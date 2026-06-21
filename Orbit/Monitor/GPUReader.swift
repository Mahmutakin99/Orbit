import Foundation
import IOKit

/// Reads instantaneous GPU utilisation from the IOAccelerator registry entry.
/// Works on Apple Silicon and Intel without any entitlements or root.
///
/// Keys probed (first non-nil wins):
///   "Device Utilization %"  — Apple Silicon (M1+)
///   "GPU Core Utilization"  — some Intel variants
///   "GPU Activity"          — older Intel/AMD
final class GPUReader {
    static let shared = GPUReader()
    private init() {}

    /// Returns 0…1, or `nil` if no accelerator entry is found.
    func gpuUsage() -> Double? {
        let matching = IOServiceMatching("IOAccelerator")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var best: Double? = nil

        var service: io_object_t = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }

            var cfDict: Unmanaged<CFMutableDictionary>? = nil
            guard IORegistryEntryCreateCFProperties(service, &cfDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = cfDict?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }

            for key in ["Device Utilization %", "GPU Core Utilization", "GPU Activity"] {
                let raw: Double?
                if let v = stats[key] as? Double { raw = v }
                else if let v = stats[key] as? Int { raw = Double(v) }
                else { raw = nil }

                if let v = raw {
                    best = max(best ?? 0, min(max(v, 0), 100) / 100)
                    break
                }
            }
        }
        return best
    }
}
