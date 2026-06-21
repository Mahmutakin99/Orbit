import Foundation
import Network

/// Measures round-trip latency by timing a TCP handshake to 1.1.1.1:443.
/// TCP avoids ICMP firewall blocks; port 443 is almost always open.
final class PingReader {
    static let shared = PingReader()
    private init() {}

    private let queue = DispatchQueue(label: "com.orbit.ping")

    /// Synchronous measurement — call from a background thread only.
    /// Returns milliseconds, or `nil` on timeout / no connectivity.
    func measure(timeout: TimeInterval = 3) -> Int? {
        let conn = NWConnection(
            host: "1.1.1.1",
            port: 443,
            using: .tcp
        )
        let sem = DispatchSemaphore(value: 0)
        var ms: Int? = nil
        let start = Date()

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ms = Int(Date().timeIntervalSince(start) * 1000)
                conn.cancel()
                sem.signal()
            case .failed, .cancelled:
                sem.signal()
            default:
                break
            }
        }
        conn.start(queue: queue)
        _ = sem.wait(timeout: .now() + timeout)
        conn.cancel()
        return ms
    }
}
