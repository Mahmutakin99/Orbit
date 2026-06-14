import AppKit

final class ClipboardManager {
    static let shared = ClipboardManager()

    private var clips: [String] = []
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let cap = 10

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func recent() -> [String] { clips }

    private func poll() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text != clips.first else { return }
        clips.removeAll { $0 == text }
        clips.insert(text, at: 0)
        if clips.count > cap { clips = Array(clips.prefix(cap)) }
    }
}
