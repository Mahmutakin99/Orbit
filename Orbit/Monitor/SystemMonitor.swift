import Foundation
import Combine
import Darwin

/// Polls system metrics on a background timer and publishes them on the main
/// thread. Only runs while the menu-bar monitor is enabled.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    // MARK: - Published state

    @Published private(set) var cpuUsage: Double = 0      // 0…1
    @Published private(set) var perCoreUsage: [Double] = []
    @Published private(set) var memoryUsage: Double = 0   // 0…1
    @Published private(set) var memUsedBytes: Double = 0
    @Published private(set) var memTotalBytes: Double = 0
    @Published private(set) var diskUsage: Double = 0     // 0…1
    @Published private(set) var diskUsedBytes: Double = 0
    @Published private(set) var diskTotalBytes: Double = 0
    @Published private(set) var diskName: String = "Disk"
    @Published private(set) var netUp: Double = 0         // bytes/sec
    @Published private(set) var netDown: Double = 0       // bytes/sec
    @Published private(set) var cpuTemp: Double? = nil    // °C
    @Published private(set) var fanRPM: Int? = nil
    @Published private(set) var gpuUsage: Double? = nil   // 0…1
    @Published private(set) var pingMS: Int? = nil
    @Published private(set) var battery: BatteryInfo? = nil
    @Published private(set) var topProcesses: [ProcInfo] = []

    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var netDownHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    private let historyLimit = 40

    struct ProcInfo: Identifiable {
        let id = UUID()
        let name: String
        let cpu: Double
    }

    /// Called on the main thread after every sample (used by the status item
    /// to refresh its title without a SwiftUI host).
    var onUpdate: (() -> Void)?

    /// Set true while the detail popover is open so we also gather the (more
    /// expensive) top-process list.
    var wantTopProcesses = false

    // MARK: - Private

    private let queue = DispatchQueue(label: "com.orbit.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: Double = 2

    private var prevCoreTicks: [[UInt32]]? = nil
    private var prevNet: (up: UInt64, down: UInt64, time: Date)? = nil

    private init() {}

    // MARK: - Lifecycle

    func start(interval: Double) {
        queue.async {
            self.interval = interval
            self.startTimerLocked()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    func updateInterval(_ seconds: Double) {
        queue.async {
            self.interval = seconds
            if self.timer != nil { self.startTimerLocked() }
        }
    }

    private func startTimerLocked() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    // MARK: - Sampling

    private func tick() {
        let cpu = sampleCPU()
        let mem = sampleMemory()
        let disk = sampleDisk()
        let net = sampleNetwork()
        let temp = SMC.shared.cpuTemperature()
        let fan = SMC.shared.fanRPM()
        let gpu = GPUReader.shared.gpuUsage()
        let ping = PingReader.shared.measure()
        let bat = BatteryReader.shared.read()
        let tops = wantTopProcesses ? sampleTopProcesses() : []

        DispatchQueue.main.async {
            self.cpuUsage = cpu.overall
            self.perCoreUsage = cpu.perCore
            self.memoryUsage = mem.ratio
            self.memUsedBytes = mem.used
            self.memTotalBytes = mem.total
            self.diskUsage = disk.ratio
            self.diskUsedBytes = disk.used
            self.diskTotalBytes = disk.total
            self.diskName = disk.name
            self.netUp = net.up
            self.netDown = net.down
            self.cpuTemp = temp
            self.fanRPM = fan
            self.gpuUsage = gpu
            self.pingMS = ping
            self.battery = bat
            if self.wantTopProcesses { self.topProcesses = tops }
            self.push(&self.cpuHistory, cpu.overall)
            self.push(&self.memHistory, mem.ratio)
            self.push(&self.netDownHistory, net.down)
            if let g = gpu { self.push(&self.gpuHistory, g) }
            self.onUpdate?()
        }
    }

    private func push(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > historyLimit { buffer.removeFirst(buffer.count - historyLimit) }
    }

    // MARK: - CPU

    private func sampleCPU() -> (overall: Double, perCore: [Double]) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info = info else {
            return (cpuUsage, perCoreUsage)
        }
        defer {
            let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), bytes)
        }

        let current: [[UInt32]] = info.withMemoryRebound(
            to: processor_cpu_load_info.self, capacity: Int(cpuCount)
        ) { ptr in
            (0..<Int(cpuCount)).map { i in
                let t = ptr[i].cpu_ticks
                return [t.0, t.1, t.2, t.3]   // user, system, idle, nice
            }
        }

        var perCore: [Double] = []
        if let prev = prevCoreTicks, prev.count == current.count {
            for i in 0..<current.count {
                let userD = delta(current[i][0], prev[i][0])
                let sysD  = delta(current[i][1], prev[i][1])
                let idleD = delta(current[i][2], prev[i][2])
                let niceD = delta(current[i][3], prev[i][3])
                let busy = userD + sysD + niceD
                let total = busy + idleD
                perCore.append(total > 0 ? busy / total : 0)
            }
        }
        prevCoreTicks = current

        let overall = perCore.isEmpty ? cpuUsage : perCore.reduce(0, +) / Double(perCore.count)
        return (overall, perCore)
    }

    private func delta(_ now: UInt32, _ then: UInt32) -> Double {
        Double(Int64(now) - Int64(then))
    }

    // MARK: - Memory

    private func sampleMemory() -> (ratio: Double, used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (memoryUsage, memUsedBytes, total) }

        // Match Activity Monitor's "Memory Used":
        //   App Memory (internal − purgeable) + Wired + Compressed.
        let pageSize = Double(vm_page_size)
        let appMemory = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (appMemory + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let ratio = total > 0 ? min(1, max(0, used / total)) : 0
        return (ratio, used, total)
    }

    // MARK: - Disk

    private func sampleDisk() -> (ratio: Double, used: Double, total: Double, name: String) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return (diskUsage, diskUsedBytes, diskTotalBytes, diskName) }
        let used = Double(total) - Double(available)
        let ratio = min(1, max(0, used / Double(total)))
        return (ratio, used, Double(total), values.volumeName ?? "Disk")
    }

    // MARK: - Network

    private func sampleNetwork() -> (up: Double, down: Double) {
        var up: UInt64 = 0
        var down: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (netUp, netDown) }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard let addr = p.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let raw = p.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self)
            down += UInt64(data.pointee.ifi_ibytes)
            up   += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        var rateUp = 0.0, rateDown = 0.0
        if let prev = prevNet {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0 {
                rateUp   = up   >= prev.up   ? Double(up - prev.up) / dt     : 0
                rateDown = down >= prev.down ? Double(down - prev.down) / dt : 0
            }
        }
        prevNet = (up, down, now)
        return (rateUp, rateDown)
    }

    // MARK: - Top processes

    private func sampleTopProcesses() -> [ProcInfo] {
        let proc = Process()
        proc.launchPath = "/bin/ps"
        proc.arguments = ["-Aceo", "pcpu,comm", "-r"]
        // Force C locale so %CPU uses a "." decimal (Turkish locale emits ",",
        // which Double() can't parse → empty list).
        proc.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var result: [ProcInfo] = []
        for line in out.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let cpu = Double(parts[0]), cpu > 0 else { continue }
            let name = (parts[1] as NSString).lastPathComponent
            result.append(ProcInfo(name: name, cpu: cpu))
            if result.count >= 5 { break }
        }
        return result
    }
}

// MARK: - Formatting helpers (shared by status item & popover)

enum MonitorFormat {
    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:    return "\(Int(celsius.rounded()))°C"
        case .fahrenheit: return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
    }

    static func rate(_ bytesPerSec: Double, unit: NetworkUnit) -> String {
        switch unit {
        case .bytes: return scaled(bytesPerSec, units: ["B", "K", "M", "G"])
        case .bits:  return scaled(bytesPerSec * 8, units: ["b", "Kb", "Mb", "Gb"])
        }
    }

    private static func scaled(_ value: Double, units: [String]) -> String {
        var v = value
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(Int(v))\(units[i])" }
        return v >= 100 ? "\(Int(v))\(units[i])" : String(format: "%.1f%@", v, units[i])
    }

    /// Gigabytes with one decimal, e.g. "11.4 GB".
    static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }

    /// Whole gigabytes, e.g. "245 GB" (for capacity labels).
    static func gigabytesWhole(_ bytes: Double) -> String {
        "\(Int((bytes / 1_073_741_824).rounded())) GB"
    }

    // MARK: - Fixed-width variants (menu bar strip → constant width → no drift)
    // Values are LEFT-aligned (padded on the right) so the value sits flush
    // against its symbol/arrow; short values like "0B" no longer float away.

    private static func padRight(_ s: String, to n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }

    static func percentFixed(_ v: Double) -> String {
        padRight("\(Int((v * 100).rounded()))%", to: 4)
    }

    static func temperatureFixed(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:    return padRight("\(Int(celsius.rounded()))°C", to: 4)
        case .fahrenheit: return padRight("\(Int((celsius * 9 / 5 + 32).rounded()))°F", to: 4)
        }
    }

    static func fanFixed(_ rpm: Int) -> String { padRight("\(rpm)", to: 4) }

    /// Ping latency left-aligned to a constant 5-character field, e.g. "12ms ".
    static func pingFixed(_ ms: Int?) -> String {
        let s = ms.map { "\($0)ms" } ?? "—"
        return padRight(s, to: 5)
    }

    /// Network rate left-aligned to a constant 5-character field.
    static func rateFixed(_ bytesPerSec: Double, unit: NetworkUnit) -> String {
        let s = rate(bytesPerSec, unit: unit)
        return s.count >= 5 ? s : s + String(repeating: " ", count: 5 - s.count)
    }
}
