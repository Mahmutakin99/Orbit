import AppKit
import SwiftUI
import Combine

// MARK: - Preview Controller

/// Manages a full-screen, mouse-transparent floating panel that shows a live
/// preview of the radial menu at the current user-selected scale. Shown while
/// the user drags the size slider in Settings; hidden when they release it.
final class RadialPreviewController {
    static let shared = RadialPreviewController()

    private var panel: NSPanel?

    private init() {}

    func show() {
        DispatchQueue.main.async {
            if self.panel == nil { self.buildPanel() }
            guard let panel = self.panel else { return }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.panel?.orderOut(nil)
        }
    }

    private func buildPanel() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovable = false
        p.hasShadow = false
        p.ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: RadialPreviewView())
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        panel = p
    }
}

// MARK: - Preview SwiftUI View

private struct RadialPreviewView: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        ZStack {
            // Semi-transparent backdrop so the user sees where the menu will sit.
            Color.black.opacity(0.18).ignoresSafeArea()

            RadialMenuView(
                items:           previewItems,
                center:          screenCenter,
                scale:           CGFloat(store.radialScale),
                isNested:        false,
                keyPublisher:    Empty().eraseToAnyPublisher(),
                scrollPublisher: Empty().eraseToAnyPublisher(),
                onSelect:        { _ in },
                onBack:          nil,
                onDismiss:       {}
            )
        }
    }

    private var previewItems: [OrbitItem] {
        let items = store.rootItems
        return items.isEmpty ? placeholders : items
    }

    private var placeholders: [OrbitItem] {
        ["Finder", "Safari", "Mail", "Terminal", "Calendar", "Messages"].map {
            OrbitItem.makeApp(path: "/Applications/\($0).app", title: $0)
        }
    }

    private var screenCenter: CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2)
    }
}
