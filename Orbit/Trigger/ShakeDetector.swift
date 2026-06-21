import AppKit

/// Detects left-right mouse shake while Option (⌥) or Control (⌃) is held.
/// Fires `onShake` for ⌥ and `onShakeControl` for ⌃ — separate callbacks so
/// callers can bind different actions to each modifier.
final class ShakeDetector {
    var onShake: (() -> Void)?          // ⌥ held
    var onShakeControl: (() -> Void)?   // ⌃ held

    /// 1 (hard) – 10 (easy). Higher = fewer reversals required = easier to trigger.
    var sensitivity: Int = 5 { didSet { updateThreshold() } }
    var isEnabled: Bool = true

    // MARK: - Private state

    private var mouseMonitor: Any?

    private var wasModHeld = false
    private var activeIsControl = false  // which modifier started the current shake sequence
    private var lastDirection: Int = 0   // −1 left, 0 none, +1 right
    private var reversalDates: [Date] = []
    private var lastFiredAt: Date = .distantPast
    private var lastMouseX: CGFloat?

    private var requiredReversals: Int = 3
    private let windowInterval: TimeInterval = 0.6
    private let cooldown: TimeInterval = 0.8
    private let minDelta: CGFloat = 5

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

        let flags = NSEvent.modifierFlags
        let optionHeld  = flags.contains(.option)
        let controlHeld = flags.contains(.control)
        let modHeld = optionHeld || controlHeld

        if wasModHeld, !modHeld { reset() }

        // Lock in which modifier started this sequence (ignore mid-shake switches)
        if !wasModHeld, modHeld {
            activeIsControl = controlHeld && !optionHeld
        }
        wasModHeld = modHeld
        guard modHeld else { return }

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
            reversalDates = reversalDates.filter { now.timeIntervalSince($0) <= windowInterval }

            if reversalDates.count >= requiredReversals {
                guard Date().timeIntervalSince(lastFiredAt) > cooldown else {
                    reset(); return
                }
                lastFiredAt = Date()
                let isControl = activeIsControl
                reset()
                DispatchQueue.main.async { [weak self] in
                    if isControl { self?.onShakeControl?() }
                    else         { self?.onShake?() }
                }
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
        requiredReversals = max(2, 6 - (sensitivity / 2))
    }
}
