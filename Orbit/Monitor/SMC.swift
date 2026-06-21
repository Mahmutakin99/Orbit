import Foundation
import IOKit

/// Minimal Apple SMC reader for temperature and fan sensors.
///
/// Talks to the `AppleSMC` IOKit service. Reading sensors does **not**
/// require root — only fan *control* (which we never do) would.
///
/// Sensor keys differ across Apple Silicon generations (M1/M2/M3/M4) and
/// Intel, so we probe a superset of known CPU-temperature keys and average
/// whatever reads back as valid. If nothing reads, callers get `nil` and the
/// UI simply hides that metric.
final class SMC {
    static let shared = SMC()

    private var connection: io_connect_t = 0
    private let queue = DispatchQueue(label: "com.orbit.smc")
    private var validTempKeys: [String]? = nil   // cached after first probe

    private init() { open() }
    deinit { close() }

    // MARK: - Connection

    private func open() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != kIOReturnSuccess {
            connection = 0
        }
    }

    private func close() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
    }

    var isAvailable: Bool { connection != 0 }

    // MARK: - Public sensor reads

    /// Average CPU temperature in °C, or `nil` if no sensor is readable.
    ///
    /// Tries IOHIDEventSystemClient first (reliable across Apple Silicon
    /// generations incl. M4), then falls back to SMC `Tp**` keys.
    func cpuTemperature() -> Double? {
        if let t = ThermalReader.shared.temperature() { return t }
        return smcTemperature()
    }

    private func smcTemperature() -> Double? {
        queue.sync {
            guard connection != 0 else { return nil }

            let keys = validTempKeys ?? Self.candidateTempKeys
            var readings: [Double] = []
            var working: [String] = []
            for key in keys {
                if let v = readValueLocked(key), v > 0, v < 120 {
                    readings.append(v)
                    working.append(key)
                }
            }
            // Cache the keys that actually returned data so later cycles are cheap.
            if validTempKeys == nil, !working.isEmpty { validTempKeys = working }
            guard !readings.isEmpty else { return nil }
            return readings.reduce(0, +) / Double(readings.count)
        }
    }

    /// Highest fan speed in RPM, or `nil` only on genuinely fanless Macs.
    /// Reports 0 when a fan exists but is idle (e.g. Mac mini when cool).
    func fanRPM() -> Int? {
        queue.sync {
            guard connection != 0 else { return nil }

            // Fan presence is decided by FNum (fan count) — not by RPM > 0,
            // since a present fan may idle at 0 RPM.
            let count = Int(readValueLocked("FNum") ?? 0)
            if count >= 1 {
                var speeds: [Double] = []
                for i in 0..<count {
                    if let v = readValueLocked("F\(i)Ac") { speeds.append(max(0, v)) }
                }
                guard let top = speeds.max() else { return nil }
                return Int(top.rounded())
            }

            // FNum unreadable — probe fan 0 directly as existence proof.
            if let v = readValueLocked("F0Ac") { return Int(max(0, v).rounded()) }
            return nil
        }
    }

    // MARK: - Candidate keys

    /// Superset of CPU-temperature keys across chips. We average the valid ones.
    private static let candidateTempKeys = [
        // Apple Silicon performance/efficiency core clusters (M1–M4 variants)
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T", "Tp0X",
        "Tp0b", "Tp0f", "Tp0j", "Tp0n", "Tp0r", "Tp0v",
        "Tg05", "Tg0D", "Tg0L", "Tg0T",
        // Intel
        "TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TCAD",
    ]

    // MARK: - Low-level read (caller holds `queue`)

    private func readValueLocked(_ key: String) -> Double? {
        // 1. Key info → data type + size
        var input = SMCKeyData_t()
        input.key = Self.fourCharCode(key)
        input.data8 = 9 // kSMCGetKeyInfo
        var info = SMCKeyData_t()
        guard call(&input, &info) == kIOReturnSuccess, info.result == 0 else { return nil }

        let size = info.keyInfo.dataSize
        let type = Self.typeString(info.keyInfo.dataType)

        // 2. Read value bytes
        var readInput = SMCKeyData_t()
        readInput.key = Self.fourCharCode(key)
        readInput.keyInfo.dataSize = size
        readInput.data8 = 5 // kSMCReadKey
        var output = SMCKeyData_t()
        guard call(&readInput, &output) == kIOReturnSuccess, output.result == 0 else { return nil }

        return Self.decode(type: type, size: Int(size), bytes: output.bytes)
    }

    private func call(_ input: inout SMCKeyData_t, _ output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(
            connection, 2 /* kSMCHandleYPCEvent */,
            &input, inputSize, &output, &outputSize
        )
    }

    // MARK: - Encoding helpers

    private static func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in str.utf8.prefix(4) { result = (result << 8) | UInt32(byte) }
        return result
    }

    private static func typeString(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                     UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func decode(type: String, size: Int, bytes: SMCBytes_t) -> Double? {
        let a = bytesToArray(bytes, size: size)
        switch type {
        case "flt":   // 32-bit IEEE float, little-endian
            guard a.count >= 4 else { return nil }
            let bits = UInt32(a[0]) | (UInt32(a[1]) << 8) | (UInt32(a[2]) << 16) | (UInt32(a[3]) << 24)
            return Double(Float(bitPattern: bits))
        case "fpe2":  // unsigned 14.2 fixed point, big-endian
            guard a.count >= 2 else { return nil }
            return Double((UInt16(a[0]) << 8 | UInt16(a[1])) >> 2)
        case "sp78":  // signed 7.8 fixed point, big-endian
            guard a.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(a[0]) << 8 | UInt16(a[1]))
            return Double(raw) / 256.0
        case "ui8":
            return a.isEmpty ? nil : Double(a[0])
        case "ui16":
            guard a.count >= 2 else { return nil }
            return Double(UInt16(a[0]) << 8 | UInt16(a[1]))
        case "ui32":
            guard a.count >= 4 else { return nil }
            return Double(UInt32(a[0]) << 24 | UInt32(a[1]) << 16 | UInt32(a[2]) << 8 | UInt32(a[3]))
        default:
            return nil
        }
    }

    private static func bytesToArray(_ bytes: SMCBytes_t, size: Int) -> [UInt8] {
        var b = bytes
        return withUnsafeBytes(of: &b) { Array($0.prefix(max(0, min(size, 32)))) }
    }
}

// MARK: - C struct layout (mirrors AppleSMC)

private typealias SMCBytes_t = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers_t()
    var pLimitData = SMCKeyData_pLimitData_t()
    var keyInfo = SMCKeyData_keyInfo_t()
    var padding: UInt16 = 0   // required: the C ABI struct is 80 bytes; without
                              // this the kernel rejects every call (kIOReturnBadArgument)
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0)
}

// MARK: - IOHID thermal sensors (Apple Silicon, incl. M4)

/// Reads temperature sensors via the private `IOHIDEventSystemClient` API.
/// Symbols are resolved at runtime with `dlsym` (no entitlement, no sandbox),
/// so this degrades gracefully to `nil` if the API is unavailable.
private final class ThermalReader {
    static let shared = ThermalReader()

    private typealias CreateFn       = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn  = @convention(c) (CFTypeRef?, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (CFTypeRef?) -> Unmanaged<CFArray>?
    private typealias CopyEventFn    = @convention(c) (CFTypeRef?, Int64, Int64, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatFn     = @convention(c) (CFTypeRef?, Int64) -> Double
    private typealias CopyPropFn     = @convention(c) (CFTypeRef?, CFString?) -> Unmanaged<CFTypeRef>?

    private let copyServices: CopyServicesFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?
    private let copyProperty: CopyPropFn?
    private var client: CFTypeRef?

    private let queue = DispatchQueue(label: "com.orbit.thermal")

    // kIOHIDEventTypeTemperature = 15; field base = type << 16.
    private let eventType: Int64 = 15
    private let valueField: Int64 = 15 << 16

    private init() {
        func sym<T>(_ name: String) -> T? {
            // RTLD_DEFAULT == (void *)-2 on macOS.
            guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        let create: CreateFn?           = sym("IOHIDEventSystemClientCreate")
        let setMatching: SetMatchingFn? = sym("IOHIDEventSystemClientSetMatching")
        copyServices = sym("IOHIDEventSystemClientCopyServices")
        copyEvent    = sym("IOHIDServiceClientCopyEvent")
        getFloat     = sym("IOHIDEventGetFloatValue")
        copyProperty = sym("IOHIDServiceClientCopyProperty")

        guard let create, let setMatching,
              let c = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        // Match Apple-vendor temperature sensors (page 0xff00, usage 0x0005).
        let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005]
        setMatching(c, matching as CFDictionary)
        client = c
    }

    func temperature() -> Double? {
        queue.sync {
            guard let client, let copyServices, let copyEvent, let getFloat,
                  let services = copyServices(client)?.takeRetainedValue() as? [AnyObject]
            else { return nil }

            var cpuReadings: [Double] = []   // named CPU-cluster sensors
            var allReadings: [Double] = []   // every valid temperature sensor

            for service in services {
                guard let event = copyEvent(service as CFTypeRef, eventType, 0, 0)?.takeRetainedValue() else { continue }
                let value = getFloat(event, valueField)
                guard value > 0, value < 120 else { continue }
                allReadings.append(value)
                if let name = sensorName(service), isCPUSensor(name) {
                    cpuReadings.append(value)
                }
            }

            // Prefer the CPU core-cluster sensors for an accurate CPU die temp;
            // fall back to the overall average if names aren't exposed.
            let pool = cpuReadings.isEmpty ? allReadings : cpuReadings
            guard !pool.isEmpty else { return nil }
            return pool.reduce(0, +) / Double(pool.count)
        }
    }

    private func sensorName(_ service: AnyObject) -> String? {
        guard let copyProperty else { return nil }
        return copyProperty(service as CFTypeRef, "Product" as CFString)?.takeRetainedValue() as? String
    }

    /// Apple Silicon CPU sensors are named like "pACC MTR Temp Sensor%d"
    /// (performance cluster), "eACC MTR Temp Sensor%d" (efficiency cluster),
    /// "PMU tdie%d", or contain "CPU".
    private func isCPUSensor(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("cpu") || n.contains("acc mtr") || n.contains("pmu tdie")
    }
}
