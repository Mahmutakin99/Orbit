import AppKit
import Foundation

/// Tracks per-item usage intensity for the current day.
/// Resets at midnight. Persists via UserDefaults.
///
/// Score = foregroundSeconds (app) or opens×300 (non-app).
/// Intensity = item.score / maxScore(among visible items) → 0…1.
final class UsageTracker {
    static let shared = UsageTracker()

    // MARK: - Private state

    private var appSeconds: [String: Double] = [:]  // appPath → seconds in foreground today
    private var itemOpens:  [String: Int]    = [:]  // itemID (UUID string) → open count today
    private var usageDay: String = ""               // "yyyy-MM-dd"

    private var lastActiveApp: (path: String, since: Date)? = nil
    private var observer: Any? = nil

    // MARK: - Lifecycle

    func start() {
        loadIfSameDay()
        startForegroundTracking()
    }

    // MARK: - Record open (called when user selects an item in radial)

    func recordOpen(item: OrbitItem) {
        checkDayRollover()
        let key = item.id.uuidString
        itemOpens[key, default: 0] += 1
        save()
    }

    // MARK: - Intensity query (0…1, nil = no usage)

    /// Returns the item's intensity relative to peers, floored against an
    /// absolute "busy day" reference so a couple of early uses don't
    /// immediately read as maximum (red) just for lacking competition.
    func intensity(for item: OrbitItem, among peers: [OrbitItem]) -> Double? {
        checkDayRollover()
        let s = score(for: item)
        guard s > 0 else { return nil }
        let peerMax = peers.map { score(for: $0) }.max() ?? 0
        let reference = 3600.0   // ~12 opens or 1hr foreground = a genuinely busy item
        let denom = Swift.max(peerMax, reference)
        return min(1.0, s / denom)
    }

    // MARK: - Private: score

    private func score(for item: OrbitItem) -> Double {
        switch item.kind {
        case .app(let path):
            let secs  = appSeconds[path] ?? 0
            let opens = Double(itemOpens[item.id.uuidString] ?? 0)
            return secs + opens * 30   // each open contributes 30s
        default:
            let opens = Double(itemOpens[item.id.uuidString] ?? 0)
            return opens * 300         // each open ~5 min equivalent
        }
    }

    // MARK: - Private: foreground tracking

    private func startForegroundTracking() {
        let nc = NSWorkspace.shared.notificationCenter
        observer = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            self?.handleActivation(note)
        }
        // Capture current frontmost app as baseline
        if let app = NSWorkspace.shared.frontmostApplication,
           let url = app.bundleURL {
            lastActiveApp = (path: url.path, since: Date())
        }
    }

    private func handleActivation(_ note: Notification) {
        let now = Date()
        checkDayRollover()

        // Commit time for previously active app
        if let prev = lastActiveApp {
            let elapsed = now.timeIntervalSince(prev.since)
            if elapsed > 0 {
                let selfBundle = Bundle.main.bundleURL.path
                if prev.path != selfBundle {   // don't count Orbit itself
                    appSeconds[prev.path, default: 0] += elapsed
                }
            }
        }
        save()

        // Start tracking new app
        if let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication),
           let path = app.bundleURL?.path {
            lastActiveApp = (path: path, since: now)
        } else {
            lastActiveApp = nil
        }
    }

    // MARK: - Day rollover

    private func checkDayRollover() {
        let today = dayString(Date())
        if today != usageDay {
            appSeconds = [:]
            itemOpens  = [:]
            usageDay   = today
            save()
        }
    }

    private func dayString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    // MARK: - Persistence

    private static let udKey = "usageTrackerData"

    private struct Snapshot: Codable {
        var day: String
        var appSeconds: [String: Double]
        var itemOpens: [String: Int]
    }

    private func save() {
        let snap = Snapshot(day: usageDay, appSeconds: appSeconds, itemOpens: itemOpens)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }

    private func loadIfSameDay() {
        guard let data = UserDefaults.standard.data(forKey: Self.udKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            usageDay = dayString(Date())
            return
        }
        let today = dayString(Date())
        if snap.day == today {
            usageDay   = snap.day
            appSeconds = snap.appSeconds
            itemOpens  = snap.itemOpens
        } else {
            usageDay = today  // new day → start fresh (maps already empty)
        }
    }
}
