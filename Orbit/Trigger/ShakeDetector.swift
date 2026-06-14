import AppKit

/// Detects left-right mouse shake while Option (⌥) is held.
///
/// Algorithm:
///   - Listen for `.mouseMoved` global events.
///   - On each event, read live modifier flags for Option key state.
///   - While Option is held, count direction reversals within a 600ms window.
///   - When reversals ≥ requiredReversals → fire `onShake`. Cooldown 800ms.
///
/// Note: Uses `NSEvent.modifierFlags` (no keyboard monitoring permission needed)
/// rather than a `.flagsChanged` global monitor (which requires Input Monitoring).
final class ShakeDetector {
    var onShake: (() -> Void)?

    /// 1 (hard) – 10 (easy). Higher = fewer reversals required = easier to trigger.
    var sensitivity: Int = 5 { didSet { updateThreshold() } }
    var isEnabled: Bool = true

    // MARK: - Private state

    private var mouseMonitor: Any?

    private var wasOptionHeld = false
    private var lastDirection: Int = 0   // −1 left, 0 none, +1 right
    private var reversalDates: [Date] = []
    private var lastFiredAt: Date = .distantPast
    private var lastMouseX: CGFloat?

    private var requiredReversals: Int = 3
    private let windowInterval: TimeInterval = 0.6   // rolling time window
    private let cooldown: TimeInterval = 0.8         // min time between fires
    private let minDelta: CGFloat = 5                // px threshold per event

    // MARK: - Lifecycle

    func start() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouse(event)
        }
    }

    func stop() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    // MARK: - Event Handler

    private func handleMouse(_ event: NSEvent) {
        guard isEnabled else { return }

        // Read option state live — no keyboard monitoring permission needed
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        // Reset when Option is released
        if wasOptionHeld, !optionHeld {
            reset()
        }
        wasOptionHeld = optionHeld

        guard optionHeld else { return }

        // Compute deltaX: prefer event.deltaX, fall back to mouseLocation diff
        let x = NSEvent.mouseLocation.x
        let rawDelta = event.deltaX
        let delta: CGFloat
        if abs(rawDelta) > 0 {
            delta = rawDelta
        } else if let prev = lastMouseX {
            delta = x - prev
        } else {
            delta = 0
        }
        lastMouseX = x

        guard abs(delta) >= minDelta else { return }

        let newDir = delta > 0 ? 1 : -1

        if newDir != lastDirection, lastDirection != 0 {
            let now = Date()
            reversalDates.append(now)
            // Prune entries outside the rolling window
            reversalDates = reversalDates.filter { now.timeIntervalSince($0) <= windowInterval }

            if reversalDates.count >= requiredReversals {
                guard Date().timeIntervalSince(lastFiredAt) > cooldown else {
                    reset(); return
                }
                lastFiredAt = Date()
                reset()
                DispatchQueue.main.async { [weak self] in self?.onShake?() }
                return
            }
        }

        lastDirection = newDir
    }

    // MARK: - Helpers

    private func reset() {
        lastDirection = 0
        reversalDates = []
        lastMouseX = nil
    }

    private func updateThreshold() {
        // Inverted scale: higher sensitivity = fewer reversals = easier trigger
        // sensitivity 10 → 2 reversals (very easy)
        // sensitivity 5  → 3 reversals (medium)
        // sensitivity 1  → 5 reversals (hard)
        requiredReversals = max(2, 6 - (sensitivity / 2))
    }
}
