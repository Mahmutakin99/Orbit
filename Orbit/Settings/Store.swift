import Foundation
import Combine
import ServiceManagement

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

    @Published var shakeSensitivity: Int {
        didSet { UserDefaults.standard.set(shakeSensitivity, forKey: "shakeSensitivity") }
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
        shakeEnabled     = UserDefaults.standard.object(forKey: "shakeEnabled")     as? Bool ?? true
        shakeSensitivity = UserDefaults.standard.object(forKey: "shakeSensitivity") as? Int  ?? 5
        rootItems        = Store.loadItems()
        contextSets      = Store.loadContextSets()
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
