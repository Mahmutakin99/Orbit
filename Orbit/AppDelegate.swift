import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let panel = OverlayPanel()
    private var settingsWindow: NSWindow?
    private let shakeDetector = ShakeDetector()
    private let monitorStatus = MonitorStatusController()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkey()
        setupShakeDetector()
        setupMonitor()
        checkAccessibility()
        _ = Store.shared          // pre-warm UserDefaults read
        UsageTracker.shared.start()
        ClipboardManager.shared.start()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.autosaveName = "OrbitLauncher"
        applyLauncherIcon()

        Store.shared.$launcherFlag
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLauncherIcon() }
            .store(in: &cancellables)

        let menu = NSMenu()
        let title = NSMenuItem(title: L("Orbit Launcher"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit Orbit"), action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    /// Renders the launcher button: the chosen country flag, or the default ◌.
    private func applyLauncherIcon() {
        guard let button = statusItem?.button else { return }
        let flag = Store.shared.launcherFlag
        if flag.isEmpty {
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Orbit")
            button.title = ""
            statusItem?.length = NSStatusItem.squareLength
        } else {
            button.image = Self.flagImage(flag)
            button.title = ""
            statusItem?.length = NSStatusItem.variableLength
        }
    }

    /// Draws an emoji flag into a menu-bar-sized, full-color image.
    private static func flagImage(_ emoji: String) -> NSImage {
        let str = emoji as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15)]
        let size = str.size(withAttributes: attrs)
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)))
        image.lockFocus()
        str.draw(at: .zero, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - System Monitor

    private func setupMonitor() {
        monitorStatus.onOpenSettings = { [weak self] in self?.openSettings() }
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = L("Orbit Settings")
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        HotkeyManager.shared.onActivate = { [weak self] in self?.togglePanel() }
        HotkeyManager.shared.onActivateWindows = { [weak self] in self?.toggleWindowsPanel() }
        HotkeyManager.shared.register()
    }

    // MARK: - Shake Detector

    private func setupShakeDetector() {
        let store = Store.shared
        shakeDetector.sensitivity = store.shakeSensitivity
        shakeDetector.isEnabled   = store.shakeEnabled
        shakeDetector.onShake        = { [weak self] in self?.togglePanel() }
        shakeDetector.onShakeControl = { [weak self] in self?.toggleWindowsPanel() }
        shakeDetector.start()

        store.$shakeSensitivity
            .sink { [weak self] v in self?.shakeDetector.sensitivity = v }
            .store(in: &cancellables)

        store.$shakeEnabled
            .sink { [weak self] v in self?.shakeDetector.isEnabled = v }
            .store(in: &cancellables)
    }

    // MARK: - Accessibility

    private func checkAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false]
        guard !AXIsProcessTrustedWithOptions(options) else { return }

        // Only prompt once — don't nag on every relaunch
        let key = "hasShownAccessibilityPrompt"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = L("Accessibility Permission Required")
        alert.informativeText = L("Orbit needs Accessibility access to detect mouse shake while Option or Control is held.\n\nEnable it in System Settings → Privacy & Security → Accessibility, then relaunch Orbit.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Later"))
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Panel Toggle

    private func togglePanel() {
        if panel.isVisible {
            panel.dismiss()
        } else {
            panel.show(items: composedItems())
        }
    }

    private func toggleWindowsPanel() {
        if panel.isVisible { panel.dismiss(); return }

        // With previews on (macOS 14+), capture thumbnails via ScreenCaptureKit
        // asynchronously, then show. Otherwise show app-icon list immediately.
        if Store.shared.windowPreviews, #available(macOS 14.0, *) {
            Task { @MainActor in
                let wins = await self.captureWindowItems()
                guard !wins.isEmpty, !self.panel.isVisible else { return }
                self.panel.show(items: wins)
            }
        } else {
            let wins = openWindowItems()
            guard !wins.isEmpty else { return }
            panel.show(items: wins)
        }
    }

    private func composedItems() -> [OrbitItem] {
        var items = Store.shared.rootItems

        // Context set: prepend frontmost app's custom set if defined
        if let app = NSWorkspace.shared.frontmostApplication,
           let path = app.bundleURL?.path {
            let set = Store.shared.contextItems(forApp: path)
            if !set.isEmpty {
                let name = app.localizedName ?? "App"
                items.insert(.makeSubmenu(title: name, children: set), at: 0)
            }
        }

        // Clipboard ring: append as "Clipboard" folder if there's anything
        let clips = ClipboardManager.shared.recent()
        if !clips.isEmpty {
            let kids = clips.map { text in
                OrbitItem(title: String(text.prefix(28)), kind: .clipboard(text: text))
            }
            items.append(.makeSubmenu(title: L("Clipboard"), children: kids))
        }

        return items
    }

    /// Max windows shown in the windows panel — caps clutter when many are open.
    private let maxWindowItems = 8

    /// App-icon window list via Accessibility — no Screen Recording needed.
    /// Used as fallback and when previews are disabled.
    private func openWindowItems() -> [OrbitItem] {
        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ourPID
        }

        var result: [OrbitItem] = []
        for app in apps {
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            let axErr = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)

            if axErr == .success, let wins = value as? [AXUIElement] {
                for win in wins {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                    let title = (titleRef as? String) ?? ""
                    let appName = app.localizedName ?? ""
                    let display = title.isEmpty ? appName : "\(appName): \(title)"
                    guard !display.isEmpty else { continue }
                    // Capture CGWindowID so perform() can target this exact window
                    let windowID = axCGWindowID(win)
                    result.append(OrbitItem(title: String(display.prefix(30)),
                                            kind: .window(pid: pid, title: title.isEmpty ? appName : title, windowID: windowID)))
                    if result.count >= maxWindowItems { return result }
                }
            } else if let name = app.localizedName, !name.isEmpty {
                result.append(OrbitItem(title: name, kind: .window(pid: pid, title: name)))
                if result.count >= maxWindowItems { return result }
            }
        }
        return result
    }

    /// Window list with live thumbnails via ScreenCaptureKit (macOS 14+).
    /// CGWindowListCreateImage was obsoleted in macOS 15, so this is the only
    /// way to capture window images on current macOS. Falls back to app icons
    /// per-window if a capture fails.
    @available(macOS 14.0, *)
    private func captureWindowItems() async -> [OrbitItem] {
        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        let content: SCShareableContent
        do {
            // onScreenWindowsOnly: false so full-screen windows on other Spaces are included.
            content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: false)
        } catch {
            // Permission denied or unavailable → fall back to icon list
            return openWindowItems()
        }

        let windows = content.windows.filter { win in
            win.windowLayer == 0
                && (win.owningApplication?.processID).map { $0 != ourPID } ?? false
                && (win.title?.isEmpty == false)
        }
        guard !windows.isEmpty else { return openWindowItems() }

        // Capture all thumbnails concurrently, preserving order.
        let captured = await withTaskGroup(of: (Int, OrbitItem).self) { group in
            for (idx, win) in windows.prefix(maxWindowItems).enumerated() {
                group.addTask {
                    (idx, await self.makeWindowItem(win))
                }
            }
            var out: [(Int, OrbitItem)] = []
            for await pair in group { out.append(pair) }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return captured.isEmpty ? openWindowItems() : captured
    }

    @available(macOS 14.0, *)
    private func makeWindowItem(_ win: SCWindow) async -> OrbitItem {
        let pid = pid_t(win.owningApplication?.processID ?? 0)
        let appName = win.owningApplication?.applicationName ?? ""
        let title = win.title ?? ""
        let display = title.isEmpty ? appName : "\(appName): \(title)"
        var item = OrbitItem(title: String(display.prefix(30)),
                             kind: .window(pid: pid, title: title.isEmpty ? appName : title, windowID: win.windowID))

        let cfg = SCStreamConfiguration()
        let pw = max(win.frame.width, 1), ph = max(win.frame.height, 1)
        let scale = min(2.0, 600 / max(pw, ph))   // cap longest side ~600px
        cfg.width  = max(1, Int(pw * scale))
        cfg.height = max(1, Int(ph * scale))
        cfg.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: win)
        if let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
            item.previewImage = NSImage(cgImage: cg, size: NSSize(width: pw, height: ph))
        }
        return item
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
