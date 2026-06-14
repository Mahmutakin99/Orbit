import AppKit
import SwiftUI
import Combine

final class OverlayPanel: NSPanel {
    private var keyMonitor:    Any?
    private var scrollMonitor: Any?

    let keySubject    = PassthroughSubject<NSEvent, Never>()
    let scrollSubject = PassthroughSubject<CGFloat, Never>()  // positive = up/left, negative = down/right

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        hasShadow = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Show / Hide

    func show(items: [OrbitItem]) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: false)

        let mouse = NSEvent.mouseLocation
        let swiftUICenter = CGPoint(
            x: mouse.x - screen.frame.minX,
            y: screen.frame.height - (mouse.y - screen.frame.minY)
        )
        let center = clamped(swiftUICenter, in: screen.frame.size)

        let hosting = NSHostingView(
            rootView: RadialContainerView(
                rootItems: items,
                center: center,
                keyPublisher:    keySubject.eraseToAnyPublisher(),
                scrollPublisher: scrollSubject.eraseToAnyPublisher(),
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        // Key events → SwiftUI (Esc, 1-9, arrows)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.keySubject.send(event)
            return nil
        }

        // Scroll events → SwiftUI (page flip)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let delta = event.scrollingDeltaX + event.scrollingDeltaY
            if abs(delta) > 3 { self?.scrollSubject.send(delta) }
            return nil
        }

        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        [keyMonitor, scrollMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        keyMonitor = nil; scrollMonitor = nil
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    // MARK: - Helpers

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let margin: CGFloat = 175
        return CGPoint(
            x: max(margin, min(size.width  - margin, point.x)),
            y: max(margin, min(size.height - margin, point.y))
        )
    }
}
