import AppKit
import SwiftUI
import Combine

/// One menu-bar strip element: an optional SF Symbol icon + a value, colored.
/// `secondLine` enables a stacked two-line layout (used for network up/down).
struct StripSegment {
    let symbol: String?
    let value: String
    let secondLine: String?
    let color: NSColor

    init(symbol: String?, value: String, secondLine: String? = nil, color: NSColor) {
        self.symbol = symbol
        self.value = value
        self.secondLine = secondLine
        self.color = color
    }
}

/// Display-ready card for the detail popover (BuhoCleaner-style grid).
struct MetricCardVM: Identifiable {
    let id: String
    let metric: MonitorMetric
    let icon: String
    let title: String         // e.g. "RAM (16 GB)"
    let bigValue: String      // e.g. "11.4 GB"
    let secondary: String?    // e.g. "71%" or "↓5 KB/s"
    let color: Color          // big value color (after color-coding)
    let tint: Color           // bar / sparkline tint
    let barFraction: Double?  // mem/disk
    let history: [Double]?    // cpu sparkline
    let supported: Bool
    let note: String
}

/// MVVM view model: observes the `SystemMonitor` service and `Store`, and
/// exposes presentation-ready data (formatted text, colors, units). Views and
/// the status-item controller consume only this — never the service directly.
final class MonitorViewModel: ObservableObject {
    @Published private(set) var stripSegments: [StripSegment] = []
    @Published private(set) var cards: [MetricCardVM] = []
    @Published private(set) var cores: [Double] = []
    @Published private(set) var topProcesses: [SystemMonitor.ProcInfo] = []

    private let monitor = SystemMonitor.shared
    private let store = Store.shared
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // One rebuild per sample: `cpuHistory` changes exactly once per tick,
        // and deferring to the main runloop guarantees all values are committed.
        monitor.$cpuHistory
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        // Rebuild immediately when display preferences change.
        Publishers.MergeMany(
            store.$metricOrder.map { _ in () }.eraseToAnyPublisher(),
            store.$disabledMetrics.map { _ in () }.eraseToAnyPublisher(),
            store.$temperatureUnit.map { _ in () }.eraseToAnyPublisher(),
            store.$networkUnit.map { _ in () }.eraseToAnyPublisher(),
            store.$monitorColorCoding.map { _ in () }.eraseToAnyPublisher(),
            store.$monitorLabelStyle.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.rebuild() }
        .store(in: &cancellables)

        rebuild()
    }

    // MARK: - Build

    private func rebuild() {
        cores = monitor.perCoreUsage
        topProcesses = monitor.topProcesses

        var newCards: [MetricCardVM] = []
        var segs: [StripSegment] = []
        for metric in store.enabledMetrics {
            newCards.append(makeCard(metric))
            if let seg = stripSegment(metric) { segs.append(seg) }
        }
        cards = newCards
        stripSegments = segs
    }

    // MARK: - Strip (menu bar) — icon + fixed-width value (constant strip width)

    private func stripSegment(_ metric: MonitorMetric) -> StripSegment? {
        let useName = store.monitorLabelStyle == .name
        // When showing names the label prefix replaces the SF Symbol icon.
        func namePrefix(_ label: String) -> (symbol: String?, prefix: String) {
            useName ? (nil, "\(label) ") : (metric.symbol, "")
        }

        switch metric {
        case .cpu:
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.percentFixed(monitor.cpuUsage))",
                                color: cpuColor(monitor.cpuUsage))
        case .gpu:
            guard let g = monitor.gpuUsage else { return nil }
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.percentFixed(g))",
                                color: gpuColor(g))
        case .memory:
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.percentFixed(monitor.memoryUsage))",
                                color: memColor(monitor.memoryUsage))
        case .disk:
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.percentFixed(monitor.diskUsage))",
                                color: diskColor(monitor.diskUsage))
        case .ping:
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.pingFixed(monitor.pingMS))",
                                color: pingColor(monitor.pingMS))
        case .network:
            let up = MonitorFormat.rateFixed(monitor.netUp, unit: store.networkUnit)
            let down = MonitorFormat.rateFixed(monitor.netDown, unit: store.networkUnit)
            // Stacked two-line display: upload on top, download on bottom.
            return StripSegment(symbol: nil,
                                value: "↑\(up)", secondLine: "↓\(down)", color: .labelColor)
        case .temperature:
            guard let t = monitor.cpuTemp else { return nil }
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.temperatureFixed(t, unit: store.temperatureUnit))",
                                color: tempColor(t))
        case .fan:
            guard let f = monitor.fanRPM else { return nil }
            let (sym, pre) = namePrefix(metric.shortLabel)
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.fanFixed(f))", color: .labelColor)
        case .battery:
            guard let bat = monitor.battery else { return nil }
            let icon = bat.isCharging ? "bolt.fill" : metric.symbol
            let (sym, pre) = useName ? (nil as String?, "BAT ") : (icon, "")
            return StripSegment(symbol: sym,
                                value: "\(pre)\(MonitorFormat.percentFixed(Double(bat.level) / 100))",
                                color: batteryColor(bat))
        }
    }

    // MARK: - Cards (popover)

    private func makeCard(_ metric: MonitorMetric) -> MetricCardVM {
        func card(title: String, big: String, _ color: NSColor, tint: Color,
                  secondary: String? = nil, bar: Double? = nil, history: [Double]? = nil,
                  supported: Bool = true, note: String = "") -> MetricCardVM {
            MetricCardVM(id: metric.rawValue, metric: metric, icon: metric.symbol,
                         title: title, bigValue: big, secondary: secondary,
                         color: Color(nsColor: color), tint: tint,
                         barFraction: bar, history: history, supported: supported, note: note)
        }
        switch metric {
        case .cpu:
            return card(title: L("CPU"), big: MonitorFormat.percent(monitor.cpuUsage),
                        cpuColor(monitor.cpuUsage), tint: .green, history: monitor.cpuHistory)
        case .gpu:
            if let g = monitor.gpuUsage {
                return card(title: L("GPU"), big: MonitorFormat.percent(g),
                            gpuColor(g), tint: .indigo, history: monitor.gpuHistory)
            }
            return card(title: L("GPU"), big: "—", .labelColor, tint: .indigo,
                        supported: false, note: L("Not available on this Mac"))
        case .memory:
            let total = MonitorFormat.gigabytesWhole(monitor.memTotalBytes)
            return card(title: "\(L("Memory")) (\(total))",
                        big: MonitorFormat.gigabytes(monitor.memUsedBytes),
                        memColor(monitor.memoryUsage), tint: .blue,
                        secondary: MonitorFormat.percent(monitor.memoryUsage),
                        bar: monitor.memoryUsage)
        case .disk:
            let total = MonitorFormat.gigabytesWhole(monitor.diskTotalBytes)
            return card(title: "\(monitor.diskName) (\(total))",
                        big: MonitorFormat.gigabytes(monitor.diskUsedBytes),
                        diskColor(monitor.diskUsage), tint: .purple,
                        secondary: MonitorFormat.percent(monitor.diskUsage),
                        bar: monitor.diskUsage)
        case .ping:
            let big = monitor.pingMS.map { "\($0) ms" } ?? "—"
            return card(title: L("Ping"), big: big,
                        pingColor(monitor.pingMS), tint: .teal)
        case .network:
            let up = MonitorFormat.rate(monitor.netUp, unit: store.networkUnit)
            let down = MonitorFormat.rate(monitor.netDown, unit: store.networkUnit)
            return card(title: L("Network"), big: "↑\(up)", .labelColor, tint: .teal,
                        secondary: "↓\(down)")
        case .temperature:
            if let t = monitor.cpuTemp {
                return card(title: L("Temperature"),
                            big: MonitorFormat.temperature(t, unit: store.temperatureUnit),
                            tempColor(t), tint: .orange)
            }
            return card(title: L("Temperature"), big: "—", .labelColor, tint: .orange,
                        supported: false, note: L("Not available on this Mac"))
        case .fan:
            if let f = monitor.fanRPM {
                return card(title: L("Fan"), big: "\(f) RPM", .labelColor, tint: .gray)
            }
            return card(title: L("Fan"), big: "—", .labelColor, tint: .gray,
                        supported: false, note: L("No fan sensor on this Mac"))
        case .battery:
            if let bat = monitor.battery {
                var parts: [String] = []
                if let h = bat.health { parts.append("\(h)% health") }
                if let c = bat.cycleCount { parts.append("\(c) cycles") }
                if let t = bat.timeString { parts.append(t) }
                let secondary = parts.isEmpty ? nil : parts.joined(separator: " · ")
                return card(title: L("Battery"), big: "\(bat.level)%",
                            batteryColor(bat), tint: .yellow, secondary: secondary)
            }
            return card(title: L("Battery"), big: "—", .labelColor, tint: .yellow,
                        supported: false, note: L("Not available on this Mac"))
        }
    }

    // MARK: - Color rules (single source of truth)
    // Memory/disk run high on macOS by design, so they only flag at extremes.

    private func batteryColor(_ bat: BatteryInfo) -> NSColor {
        if bat.isCharging { return .labelColor }
        guard store.monitorColorCoding else { return .labelColor }
        if bat.level <= 10 { return .systemRed }
        if bat.level <= 20 { return .systemOrange }
        return .labelColor
    }

    private func pingColor(_ ms: Int?) -> NSColor {
        guard store.monitorColorCoding, let ms else { return .labelColor }
        if ms >= 150 { return .systemRed }
        if ms >= 50  { return .systemOrange }
        return .labelColor
    }

    private func gpuColor(_ v: Double) -> NSColor {
        guard store.monitorColorCoding else { return .labelColor }
        if v >= 0.85 { return .systemRed }
        if v >= 0.60 { return .systemOrange }
        return .labelColor
    }

    private func cpuColor(_ v: Double) -> NSColor {
        guard store.monitorColorCoding else { return .labelColor }
        if v >= 0.85 { return .systemRed }
        if v >= 0.60 { return .systemOrange }
        return .labelColor
    }

    private func memColor(_ v: Double) -> NSColor {
        guard store.monitorColorCoding else { return .labelColor }
        return v >= 0.90 ? .systemRed : .labelColor
    }

    private func diskColor(_ v: Double) -> NSColor {
        guard store.monitorColorCoding else { return .labelColor }
        return v >= 0.95 ? .systemRed : .labelColor
    }

    private func tempColor(_ celsius: Double) -> NSColor {
        guard store.monitorColorCoding else { return .labelColor }
        if celsius >= 85 { return .systemRed }
        if celsius >= 70 { return .systemOrange }
        return .labelColor
    }
}
