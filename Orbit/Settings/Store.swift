import Foundation
import Combine
import ServiceManagement

// MARK: - System Monitor preference types

enum MonitorMetric: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, disk, network, ping, temperature, fan, battery
    var id: String { rawValue }

    /// English key used with `L()` for the settings list.
    var labelKey: String {
        switch self {
        case .cpu:         return "CPU"
        case .gpu:         return "GPU"
        case .ping:        return "Ping"
        case .memory:      return "Memory"
        case .disk:        return "Disk"
        case .network:     return "Network"
        case .temperature: return "Temperature"
        case .fan:         return "Fan"
        case .battery:     return "Battery"
        }
    }

    /// Compact label shown in the menu bar strip.
    var shortLabel: String {
        switch self {
        case .cpu:         return "CPU"
        case .gpu:         return "GPU"
        case .ping:        return "PING"
        case .memory:      return "MEM"
        case .disk:        return "SSD"
        case .network:     return "NET"
        case .temperature: return "TEMP"
        case .fan:         return "FAN"
        case .battery:     return "BAT"
        }
    }

    var symbol: String {
        switch self {
        case .cpu:         return "cpu"
        case .gpu:         return "cpu.fill"
        case .ping:        return "dot.radiowaves.left.and.right"
        case .memory:      return "memorychip"
        case .disk:        return "internaldrive"
        case .network:     return "arrow.up.arrow.down"
        case .temperature: return "thermometer.medium"
        case .fan:         return "fanblades"
        case .battery:     return "battery.100"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable { case celsius, fahrenheit }
enum NetworkUnit: String, Codable, CaseIterable { case bytes, bits }
enum MonitorLabelStyle: String, Codable, CaseIterable { case symbol, name }

/// The 30 most-recognized country flags offered for the menu-bar icon.
enum MenuBarFlags {
    static let all: [(flag: String, name: String)] = [
        ("🇹🇷", "Türkiye"), ("🇺🇸", "United States"), ("🇬🇧", "United Kingdom"),
        ("🇩🇪", "Germany"), ("🇫🇷", "France"), ("🇮🇹", "Italy"), ("🇪🇸", "Spain"),
        ("🇵🇹", "Portugal"), ("🇳🇱", "Netherlands"), ("🇷🇺", "Russia"), ("🇨🇳", "China"),
        ("🇯🇵", "Japan"), ("🇰🇷", "South Korea"), ("🇮🇳", "India"), ("🇧🇷", "Brazil"),
        ("🇨🇦", "Canada"), ("🇦🇺", "Australia"), ("🇲🇽", "Mexico"), ("🇦🇷", "Argentina"),
        ("🇸🇦", "Saudi Arabia"), ("🇦🇪", "UAE"), ("🇪🇬", "Egypt"), ("🇿🇦", "South Africa"),
        ("🇸🇪", "Sweden"), ("🇳🇴", "Norway"), ("🇨🇭", "Switzerland"), ("🇵🇱", "Poland"),
        ("🇬🇷", "Greece"), ("🇮🇪", "Ireland"), ("🇺🇦", "Ukraine"),
    ]
}

/// Single source of truth for all user preferences.
final class Store: ObservableObject {
    static let shared = Store()

    // MARK: - Radial Items

    @Published var rootItems: [OrbitItem] {
        didSet { saveItems() }
    }

    // MARK: - Context Sets (app bundle path → items)

    @Published var contextSets: [String: [OrbitItem]] {
        didSet { saveContextSets() }
    }

    // MARK: - Shake Trigger

    @Published var shakeEnabled: Bool {
        didSet { UserDefaults.standard.set(shakeEnabled, forKey: "shakeEnabled") }
    }

    // MARK: - Window Previews

    @Published var windowPreviews: Bool {
        didSet { UserDefaults.standard.set(windowPreviews, forKey: "windowPreviews") }
    }

    @Published var shakeSensitivity: Int {
        didSet { UserDefaults.standard.set(shakeSensitivity, forKey: "shakeSensitivity") }
    }

    // MARK: - Radial Menu Size

    @Published var radialScale: Double {
        didSet { UserDefaults.standard.set(radialScale, forKey: "radialScale") }
    }

    // MARK: - Auto Update

    @Published var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates") }
    }

    // MARK: - System Monitor

    @Published var monitorEnabled: Bool {
        didSet { UserDefaults.standard.set(monitorEnabled, forKey: "monitorEnabled") }
    }

    /// Display order of all six metrics (user-reorderable).
    @Published var metricOrder: [MonitorMetric] {
        didSet { saveMetricOrder() }
    }

    /// Metrics the user has hidden. Order is kept in `metricOrder`.
    @Published var disabledMetrics: Set<MonitorMetric> {
        didSet { saveDisabledMetrics() }
    }

    /// Visible metrics, in display order. Used by the status item & popover.
    var enabledMetrics: [MonitorMetric] {
        metricOrder.filter { !disabledMetrics.contains($0) }
    }

    @Published var temperatureUnit: TemperatureUnit {
        didSet { UserDefaults.standard.set(temperatureUnit.rawValue, forKey: "temperatureUnit") }
    }

    @Published var networkUnit: NetworkUnit {
        didSet { UserDefaults.standard.set(networkUnit.rawValue, forKey: "networkUnit") }
    }

    @Published var monitorInterval: Double {
        didSet { UserDefaults.standard.set(monitorInterval, forKey: "monitorInterval") }
    }

    @Published var monitorColorCoding: Bool {
        didSet { UserDefaults.standard.set(monitorColorCoding, forKey: "monitorColorCoding") }
    }

    @Published var monitorLabelStyle: MonitorLabelStyle {
        didSet { UserDefaults.standard.set(monitorLabelStyle.rawValue, forKey: "monitorLabelStyle") }
    }

    /// Emoji flag for the menu-bar launcher icon; "" = default ◌ symbol.
    @Published var launcherFlag: String {
        didSet { UserDefaults.standard.set(launcherFlag, forKey: "launcherFlag") }
    }

    // MARK: - Language

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() }
                else        { try SMAppService.mainApp.unregister() }
            } catch { print("[Orbit] SMAppService error:", error) }
        }
    }

    // MARK: - Init

    private init() {
        shakeEnabled       = UserDefaults.standard.object(forKey: "shakeEnabled")       as? Bool   ?? true
        shakeSensitivity   = UserDefaults.standard.object(forKey: "shakeSensitivity")   as? Int    ?? 5
        windowPreviews     = UserDefaults.standard.object(forKey: "windowPreviews")     as? Bool   ?? false
        radialScale        = UserDefaults.standard.object(forKey: "radialScale")        as? Double ?? 1.0
        autoCheckUpdates   = UserDefaults.standard.object(forKey: "autoCheckUpdates")   as? Bool   ?? true
        rootItems        = Store.loadItems()
        contextSets      = Store.loadContextSets()

        monitorEnabled    = UserDefaults.standard.object(forKey: "monitorEnabled") as? Bool ?? true
        metricOrder       = Store.loadMetricOrder()
        disabledMetrics   = Store.loadDisabledMetrics()
        monitorColorCoding = UserDefaults.standard.object(forKey: "monitorColorCoding") as? Bool ?? true
        monitorInterval   = UserDefaults.standard.object(forKey: "monitorInterval") as? Double ?? 2
        monitorLabelStyle = MonitorLabelStyle(rawValue: UserDefaults.standard.string(forKey: "monitorLabelStyle") ?? "") ?? .symbol
        temperatureUnit   = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        networkUnit       = NetworkUnit(rawValue: UserDefaults.standard.string(forKey: "networkUnit") ?? "") ?? .bytes
        launcherFlag      = UserDefaults.standard.string(forKey: "launcherFlag") ?? ""
        if let raw = UserDefaults.standard.string(forKey: "appLanguage"),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = AppLanguage.systemDefault()
        }
    }

    // MARK: - Persistence

    private static let itemsKey = "orbitItems"

    private static func loadItems() -> [OrbitItem] {
        let ud = UserDefaults.standard

        // 1. Try new JSON key
        if let data = ud.data(forKey: itemsKey),
           let items = try? JSONDecoder().decode([OrbitItem].self, from: data) {
            return items
        }

        // 2. Migrate legacy selectedAppPaths
        if let paths = ud.array(forKey: "selectedAppPaths") as? [String], !paths.isEmpty {
            let migrated = paths.map { path -> OrbitItem in
                let name = URL(fileURLWithPath: path)
                    .deletingPathExtension().lastPathComponent
                return .makeApp(path: path, title: name)
            }
            ud.removeObject(forKey: "selectedAppPaths")
            if let data = try? JSONEncoder().encode(migrated) {
                ud.set(data, forKey: itemsKey)
            }
            return migrated
        }

        return []
    }

    private func saveItems() {
        if let data = try? JSONEncoder().encode(rootItems) {
            UserDefaults.standard.set(data, forKey: Store.itemsKey)
        }
    }

    // MARK: - Monitor Persistence

    private static func loadMetricOrder() -> [MonitorMetric] {
        guard let raw = UserDefaults.standard.array(forKey: "monitorMetricOrder") as? [String] else {
            return MonitorMetric.allCases
        }
        var order = raw.compactMap { MonitorMetric(rawValue: $0) }
        // Append any metric missing from a stored order (e.g. after an update).
        for m in MonitorMetric.allCases where !order.contains(m) { order.append(m) }
        return order
    }

    private func saveMetricOrder() {
        UserDefaults.standard.set(metricOrder.map(\.rawValue), forKey: "monitorMetricOrder")
    }

    private static func loadDisabledMetrics() -> Set<MonitorMetric> {
        let raw = UserDefaults.standard.array(forKey: "monitorDisabledMetrics") as? [String] ?? []
        return Set(raw.compactMap { MonitorMetric(rawValue: $0) })
    }

    private func saveDisabledMetrics() {
        UserDefaults.standard.set(disabledMetrics.map(\.rawValue), forKey: "monitorDisabledMetrics")
    }

    // MARK: - Context Sets Persistence

    private static let contextKey = "orbitContextSets"

    private static func loadContextSets() -> [String: [OrbitItem]] {
        guard let data = UserDefaults.standard.data(forKey: contextKey),
              let sets = try? JSONDecoder().decode([String: [OrbitItem]].self, from: data)
        else { return [:] }
        return sets
    }

    private func saveContextSets() {
        if let data = try? JSONEncoder().encode(contextSets) {
            UserDefaults.standard.set(data, forKey: Store.contextKey)
        }
    }

    // MARK: - Context Set CRUD

    func contextItems(forApp path: String) -> [OrbitItem] {
        contextSets[path] ?? []
    }

    func addContextItem(_ item: OrbitItem, forApp path: String) {
        var items = contextSets[path] ?? []
        guard items.count < OrbitItem.maxItems else { return }
        items.append(item)
        contextSets[path] = items
    }

    func removeContextItem(id: UUID, forApp path: String) {
        contextSets[path]?.removeAll { $0.id == id }
    }

    func moveContextItem(forApp path: String, from source: IndexSet, to destination: Int) {
        contextSets[path]?.move(fromOffsets: source, toOffset: destination)
    }

    func removeContextSet(forApp path: String) {
        contextSets.removeValue(forKey: path)
    }

    // MARK: - Root CRUD

    func addItem(_ item: OrbitItem) {
        guard rootItems.count < OrbitItem.maxItems else { return }
        rootItems.append(item)
    }

    func removeItem(id: UUID) {
        rootItems.removeAll { $0.id == id }
    }

    func updateItem(id: UUID, title: String, kind: OrbitItemKind) {
        if let i = rootItems.firstIndex(where: { $0.id == id }) {
            rootItems[i].title = title
            rootItems[i].kind = kind
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        rootItems.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Submenu CRUD (one level deep)

    func addItem(_ item: OrbitItem, toSubmenuID submenuID: UUID) {
        mutateSubmenu(id: submenuID) { children in
            guard children.count < OrbitItem.maxItems else { return }
            children.append(item)
        }
    }

    func removeItem(id: UUID, fromSubmenuID submenuID: UUID) {
        mutateSubmenu(id: submenuID) { $0.removeAll { $0.id == id } }
    }

    func updateItem(id: UUID, inSubmenuID submenuID: UUID, title: String, kind: OrbitItemKind) {
        mutateSubmenu(id: submenuID) { children in
            if let i = children.firstIndex(where: { $0.id == id }) {
                children[i].title = title
                children[i].kind = kind
            }
        }
    }

    func moveInSubmenu(id submenuID: UUID, from source: IndexSet, to destination: Int) {
        mutateSubmenu(id: submenuID) { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func renameSubmenu(id: UUID, title: String) {
        if let idx = rootItems.firstIndex(where: { $0.id == id }) {
            rootItems[idx].title = title
        }
    }

    // Returns latest snapshot of submenu children (for reading in UI)
    func childrenOf(submenuID: UUID) -> [OrbitItem] {
        rootItems.first(where: { $0.id == submenuID })?.children ?? []
    }

    // MARK: - Private helpers

    private func mutateSubmenu(id: UUID, transform: (inout [OrbitItem]) -> Void) {
        guard let idx = rootItems.firstIndex(where: { $0.id == id }),
              case .submenu(var children) = rootItems[idx].kind else { return }
        transform(&children)
        rootItems[idx].kind = .submenu(children: children)
    }
}
