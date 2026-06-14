import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let panel = OverlayPanel()
    private var settingsWindow: NSWindow?
    private let shakeDetector = ShakeDetector()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkey()
        setupShakeDetector()
        checkAccessibility()
        _ = Store.shared          // pre-warm UserDefaults read
        UsageTracker.shared.start()
        ClipboardManager.shared.start()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Orbit")

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
        HotkeyManager.shared.register()
    }

    // MARK: - Shake Detector

    private func setupShakeDetector() {
        let store = Store.shared
        shakeDetector.sensitivity = store.shakeSensitivity
        shakeDetector.isEnabled   = store.shakeEnabled
        shakeDetector.onShake     = { [weak self] in
            guard let self, !self.panel.isVisible else { return }
            self.panel.show(items: self.composedItems())
        }
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
        alert.informativeText = L("Orbit needs Accessibility access to detect mouse shake while Option is held.\n\nEnable it in System Settings → Privacy & Security → Accessibility, then relaunch Orbit.")
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
