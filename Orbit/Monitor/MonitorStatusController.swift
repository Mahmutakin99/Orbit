import AppKit
import SwiftUI
import Combine

/// Owns the dedicated system-monitor status-bar item: a text strip rendered as
/// the button's attributed title, plus a detail popover on click. Reads only
/// from `MonitorViewModel` (MVVM).
final class MonitorStatusController: NSObject, NSPopoverDelegate {
    /// Wired by AppDelegate so the popover's "Settings…" button works.
    var onOpenSettings: (() -> Void)?

    private let viewModel = MonitorViewModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.delegate = self

        let store = Store.shared

        store.$monitorEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.apply(enabled: enabled) }
            .store(in: &cancellables)

        store.$monitorInterval
            .dropFirst()
            .sink { SystemMonitor.shared.updateInterval($0) }
            .store(in: &cancellables)

        // The view model already merges sampling + preference changes.
        viewModel.$stripSegments
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildTitle() }
            .store(in: &cancellables)
    }

    // MARK: - Enable / disable
    // The status item is created once and toggled via `isVisible` — never
    // removed/re-added — so the menu bar never reshuffles or hides the launcher.

    private func apply(enabled: Bool) {
        ensureItem()
        statusItem?.isVisible = enabled
        if enabled {
            SystemMonitor.shared.start(interval: Store.shared.monitorInterval)
        } else {
            if popover.isShown { popover.performClose(nil) }
            SystemMonitor.shared.stop()
        }
    }

    private func ensureItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "OrbitSystemMonitor"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        rebuildTitle()
    }

    // MARK: - Title rendering

    private func rebuildTitle() {
        guard let button = statusItem?.button else { return }
        // Fully monospaced (not just digits): every glyph — letters, °, %, arrows,
        // spaces — has the same advance, so fixed-character values give a constant
        // pixel width → the status item never resizes → the popover never shifts.
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let title = NSMutableAttributedString()
        let segments = viewModel.stripSegments

        if segments.isEmpty {
            title.append(NSAttributedString(string: "Orbit",
                                            attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            button.attributedTitle = title
            return
        }

        for (i, seg) in segments.enumerated() {
            if i > 0 {
                title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            if let second = seg.secondLine,
               let attachment = stackedTextAttachment(top: seg.value, bottom: second,
                                                      color: seg.color, mainFont: font) {
                title.append(NSAttributedString(attachment: attachment))
            } else {
                if let symbol = seg.symbol,
                   let attachment = iconAttachment(symbol, color: seg.color, font: font) {
                    title.append(NSAttributedString(attachment: attachment))
                }
                title.append(NSAttributedString(string: seg.value,
                                                attributes: [.font: font, .foregroundColor: seg.color]))
            }
        }
        button.attributedTitle = title
    }

    /// Two lines of text stacked vertically, rendered into an image attachment.
    /// Used for network up/down so they sit directly above/below each other.
    private func stackedTextAttachment(top: String, bottom: String,
                                       color: NSColor, mainFont: NSFont) -> NSTextAttachment? {
        let smallFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: color]
        let topStr = NSAttributedString(string: top, attributes: attrs)
        let botStr = NSAttributedString(string: bottom, attributes: attrs)

        let lineH: CGFloat = ceil(smallFont.ascender - smallFont.descender) + 1
        let imgW = ceil(max(topStr.size().width, botStr.size().width))
        let imgH = lineH * 2

        let image = NSImage(size: CGSize(width: imgW, height: imgH), flipped: false) { _ in
            // Non-flipped: y=0 at bottom. Draw bottom string first, then top.
            botStr.draw(at: CGPoint(x: 0, y: -smallFont.descender))
            topStr.draw(at: CGPoint(x: 0, y: lineH - smallFont.descender))
            return true
        }
        image.isTemplate = false

        let attachment = NSTextAttachment()
        attachment.image = image
        // Center the stacked block on the main font's cap-height midpoint.
        let y = (mainFont.capHeight - imgH) / 2
        attachment.bounds = CGRect(x: 0, y: y, width: imgW, height: imgH)
        return attachment
    }

    /// SF Symbol rendered as a baseline-aligned, tinted text attachment.
    private func iconAttachment(_ symbol: String, color: NSColor, font: NSFont) -> NSTextAttachment? {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        let size = image.size
        // Vertically center the glyph on the text's cap height.
        let y = (font.capHeight - size.height) / 2
        attachment.bounds = CGRect(x: 0, y: y, width: size.width, height: size.height)
        return attachment
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            onOpenSettings?()
            return
        }

        SystemMonitor.shared.wantTopProcesses = true
        let host = NSHostingController(
            rootView: MonitorPopoverView(vm: viewModel, onOpenSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.onOpenSettings?()
            })
        )
        // Make the popover size to the SwiftUI content's ideal size (fixes the
        // right-edge clipping where values were cut off).
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Belt-and-suspenders: an accessory app's transient popover can miss the
        // first outside click, so also close on any click in another app.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        SystemMonitor.shared.wantTopProcesses = false
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }
}
