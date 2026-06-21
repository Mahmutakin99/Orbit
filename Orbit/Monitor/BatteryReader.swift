import Foundation
import IOKit.ps

struct BatteryInfo {
    let level: Int          // 0–100
    let isCharging: Bool
    let timeRemaining: Int? // minutes, nil = calculating
    let cycleCount: Int?
    let health: Int?        // percent of design capacity

    var timeString: String? {
        guard let t = timeRemaining, t > 0 else { return nil }
        let h = t / 60, m = t % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

final class BatteryReader {
    static let shared = BatteryReader()
    private init() {}

    func read() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        guard let ps = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
              let current = desc[kIOPSCurrentCapacityKey] as? Int,
              let max     = desc[kIOPSMaxCapacityKey]     as? Int,
              max > 0 else { return nil }

        let level      = current * 100 / max
        let charging   = desc[kIOPSIsChargingKey] as? Bool ?? false

        // Time remaining: negative = calculating
        let rawTime    = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
        let rawCharge  = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
        let timeMin: Int? = charging
            ? (rawCharge > 0 ? rawCharge : nil)
            : (rawTime   > 0 ? rawTime   : nil)

        let (cycles, health) = smartBatteryInfo()
        return BatteryInfo(level: level, isCharging: charging,
                           timeRemaining: timeMin,
                           cycleCount: cycles, health: health)
    }

    // MARK: - AppleSmartBattery registry (cycle count + health)

    private func smartBatteryInfo() -> (cycles: Int?, health: Int?) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        var cfDict: Unmanaged<CFMutableDictionary>? = nil
        guard IORegistryEntryCreateCFProperties(service, &cfDict,
                                                kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = cfDict?.takeRetainedValue() as? [String: Any] else { return (nil, nil) }

        let cycles = dict["CycleCount"] as? Int
        let design = dict["DesignCapacity"] as? Int
        let rawMax = dict["AppleRawMaxCapacity"] as? Int
                  ?? dict["MaxCapacity"] as? Int

        var health: Int? = nil
        if let d = design, let m = rawMax, d > 0 {
            health = min(100, Int((Double(m) / Double(d) * 100).rounded()))
        }
        return (cycles, health)
    }
}
