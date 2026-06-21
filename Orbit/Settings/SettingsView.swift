import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        TabView {
            ItemsTab()
                .tabItem { Label(L("Items"), systemImage: "circle.grid.3x3") }
            ContextTab()
                .tabItem { Label(L("Context"), systemImage: "app.badge") }
            MonitorTab()
                .tabItem { Label(L("Monitor"), systemImage: "gauge.with.dots.needle.bottom.50percent") }
            GeneralTab()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
        }
        .padding(16)
        .frame(width: 460, height: 560)
    }
}

// MARK: - Shared overlay kind

private enum OverlayKind: Identifiable {
    case submenuName, url, script
    var id: String { "\(self)" }
}

// MARK: - Items Tab

private struct ItemsTab: View {
    @ObservedObject private var store = Store.shared
    @State private var editingSubmenu: OrbitItem? = nil

    // Sheet/overlay triggers
    @State private var showingAppPicker    = false
    @State private var showingShortcuts    = false
    @State private var addingToSubmenuID: UUID? = nil

    @State private var overlay: OverlayKind? = nil

    // Overlay field state
    @State private var overlayTitle  = ""
    @State private var overlayValue  = ""   // URL string or script source
    @State private var overlayRunInTerminal = false
    @State private var editingItemID: UUID? = nil   // non-nil while editing an existing item

    private var currentItems: [OrbitItem] {
        if let s = editingSubmenu { return store.childrenOf(submenuID: s.id) }
        return store.rootItems
    }
    private var isFull: Bool { currentItems.count >= OrbitItem.maxItems }
    private var isRoot: Bool { editingSubmenu == nil }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            if currentItems.isEmpty { emptyState } else { itemsList }
        }
        // App picker
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(submenuID: addingToSubmenuID, onDone: { showingAppPicker = false })
                .frame(width: 360, height: 460)
        }
        // Shortcuts picker
        .sheet(isPresented: $showingShortcuts) {
            ShortcutPickerSheet(submenuID: addingToSubmenuID, onDone: { showingShortcuts = false })
                .frame(width: 340, height: 420)
        }
        // Inline overlays (submenu name, URL, script)
        .overlay {
            if let kind = overlay {
                overlayView(for: kind)
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            if !isRoot {
                Button {
                    editingSubmenu = nil
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.backward").font(.caption.weight(.semibold))
                        Text(L("Items"))
                    }.foregroundStyle(Color.accentColor)
                }.buttonStyle(.plain)
                Image(systemName: "chevron.forward").font(.caption2).foregroundStyle(.secondary)
                Text(editingSubmenu?.title ?? "").fontWeight(.medium)
            } else {
                Text(L("Radial Items")).fontWeight(.medium)
            }
            Spacer()
            Text("\(currentItems.count)/\(OrbitItem.maxItems)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isFull ? Color.orange : Color.secondary)

            addMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var addMenu: some View {
        Menu {
            // App
            Button(L("Add App…")) {
                addingToSubmenuID = editingSubmenu?.id
                showingAppPicker = true
            }
            // File/Folder
            Button(L("Add File or Folder…")) { pickFile() }

            Divider()

            // Link
            Button(L("Add Link…")) {
                addingToSubmenuID = editingSubmenu?.id
                editingItemID = nil
                overlayTitle = ""; overlayValue = "https://"
                overlay = .url
            }

            // System actions submenu
            Menu(L("Add System Action")) {
                ForEach(SystemAction.allCases, id: \.self) { action in
                    Button(action.displayTitle) { addSystemAction(action) }
                }
            }

            // Shortcut
            Button(L("Add Shortcut…")) {
                addingToSubmenuID = editingSubmenu?.id
                showingShortcuts = true
            }

            // Script
            Button(L("Add Script…")) {
                addingToSubmenuID = editingSubmenu?.id
                editingItemID = nil
                overlayTitle = ""; overlayValue = "#!/bin/zsh\n"; overlayRunInTerminal = false
                overlay = .script
            }

            if isRoot {
                Divider()
                Button(L("Add Folder…")) {
                    editingItemID = nil
                    overlayTitle = "New Folder"
                    overlay = .submenuName
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(isFull ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(isFull)
    }

    // MARK: - List

    @State private var dropTargeted = false

    private var itemsList: some View {
        List {
            ForEach(currentItems) { item in
                ItemRow(
                    item: item,
                    onDrillIn: item.isSubmenu ? { editingSubmenu = item } : nil,
                    onEdit: editAction(for: item),
                    onRemove: {
                        if let sid = editingSubmenu?.id {
                            store.removeItem(id: item.id, fromSubmenuID: sid)
                            editingSubmenu = store.rootItems.first { $0.id == sid }
                        } else {
                            store.removeItem(id: item.id)
                        }
                    }
                )
            }
            .onMove { src, dst in
                if let sid = editingSubmenu?.id {
                    store.moveInSubmenu(id: sid, from: src, to: dst)
                    editingSubmenu = store.rootItems.first { $0.id == sid }
                } else {
                    store.move(from: src, to: dst)
                }
            }
        }
        .listStyle(.inset)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(dropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: dropTargeted ? "arrow.down.circle" : "plus.circle.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                .animation(.spring(response: 0.2), value: dropTargeted)
            Text(isRoot ? L("No items yet") : L("Folder is empty")).font(.headline)
            Text(dropTargeted ? L("Release to add files") : L("Use the + button or drag files here."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            addFileURLs(urls)
        }
        return true
    }

    // MARK: - Overlay factory

    @ViewBuilder
    private func overlayView(for kind: OverlayKind) -> some View {
        switch kind {
        case .submenuName:
            SubmenuNameOverlay(title: $overlayTitle, isEditing: editingItemID != nil) {
                if let id = editingItemID {
                    store.renameSubmenu(id: id, title: overlayTitle)
                    editingItemID = nil
                } else {
                    store.addItem(.makeSubmenu(title: overlayTitle))
                }
                overlay = nil
            } onCancel: { overlay = nil; editingItemID = nil }

        case .url:
            URLInputOverlay(itemTitle: $overlayTitle, urlString: $overlayValue, isEditing: editingItemID != nil) {
                var raw = overlayValue.trimmingCharacters(in: .whitespaces)
                if !raw.contains("://") { raw = "https://" + raw }
                let title = overlayTitle.isEmpty
                    ? (URL(string: raw)?.host ?? "Link")
                    : overlayTitle
                let kind = OrbitItemKind.url(urlString: raw)
                commitItem(title: title, kind: kind, makeNew: { OrbitItem.makeURL(urlString: raw, title: title) })
                overlay = nil
            } onCancel: { overlay = nil; editingItemID = nil }

        case .script:
            ScriptInputOverlay(itemTitle: $overlayTitle, source: $overlayValue, runInTerminal: $overlayRunInTerminal, isEditing: editingItemID != nil) {
                let title = overlayTitle.isEmpty ? "Script" : overlayTitle
                let kind = OrbitItemKind.script(source: overlayValue, isShell: true, runInTerminal: overlayRunInTerminal)
                commitItem(title: title, kind: kind, makeNew: { OrbitItem(title: title, kind: kind) })
                overlay = nil
            } onCancel: { overlay = nil; editingItemID = nil }
        }
    }

    /// Either updates the item currently being edited (`editingItemID`), or
    /// adds a freshly built one — mirroring the add/edit overlay duality.
    private func commitItem(title: String, kind: OrbitItemKind, makeNew: () -> OrbitItem) {
        if let id = editingItemID {
            if let sid = addingToSubmenuID {
                store.updateItem(id: id, inSubmenuID: sid, title: title, kind: kind)
                editingSubmenu = store.rootItems.first { $0.id == sid }
            } else {
                store.updateItem(id: id, title: title, kind: kind)
            }
            editingItemID = nil
        } else {
            let item = makeNew()
            if let sid = addingToSubmenuID { store.addItem(item, toSubmenuID: sid) }
            else { store.addItem(item) }
        }
    }

    /// Returns an edit closure for items whose overlay form supports editing
    /// (link, script), or nil otherwise.
    private func editAction(for item: OrbitItem) -> (() -> Void)? {
        switch item.kind {
        case .url(let s):
            return {
                addingToSubmenuID = editingSubmenu?.id
                editingItemID = item.id
                overlayTitle = item.title; overlayValue = s
                overlay = .url
            }
        case .script(let source, _, let runInTerminal):
            return {
                addingToSubmenuID = editingSubmenu?.id
                editingItemID = item.id
                overlayTitle = item.title; overlayValue = source; overlayRunInTerminal = runInTerminal
                overlay = .script
            }
        case .submenu:
            return {
                editingItemID = item.id
                overlayTitle = item.title
                overlay = .submenuName
            }
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            addFileURLs(panel.urls)
        }
    }

    private func addFileURLs(_ urls: [URL]) {
        for url in urls {
            let item = OrbitItem.makeFile(
                path: url.path,
                title: url.deletingPathExtension().lastPathComponent
            )
            if let sid = editingSubmenu?.id {
                store.addItem(item, toSubmenuID: sid)
            } else {
                store.addItem(item)
            }
        }
        if let sid = editingSubmenu?.id {
            editingSubmenu = store.rootItems.first { $0.id == sid }
        }
    }

    private func addSystemAction(_ action: SystemAction) {
        let item = OrbitItem(title: action.displayTitle, kind: .systemAction(action))
        if let sid = editingSubmenu?.id {
            store.addItem(item, toSubmenuID: sid)
            editingSubmenu = store.rootItems.first { $0.id == sid }
        } else { store.addItem(item) }
    }
}

// MARK: - Item Row

private struct ItemRow: View {
    let item: OrbitItem
    var onDrillIn: (() -> Void)?
    var onEdit: (() -> Void)?
    let onRemove: () -> Void

    private var subtitle: String? {
        switch item.kind {
        case .url(let s): return URL(string: s)?.host ?? s
        case .app(let p): return URL(fileURLWithPath: p).deletingLastPathComponent().path == "/Applications" ? nil : URL(fileURLWithPath: p).deletingLastPathComponent().lastPathComponent
        case .systemAction(let a): return a.displayTitle == item.title ? nil : a.displayTitle
        case .submenu(let c): return "\(c.count) item\(c.count == 1 ? "" : "s")"
        case .script(_, _, let runInTerminal): return runInTerminal ? "Shell script · Terminal" : "Shell script"
        case .shortcut: return "Shortcut"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable().interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                if let sub = subtitle {
                    Text(sub).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.typeLabel)
                .font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color(nsColor: .quaternaryLabelColor))
                .clipShape(Capsule())
            if let drill = onDrillIn {
                Button(action: drill) {
                    Image(systemName: "chevron.forward").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            if let edit = onEdit {
                Button(action: edit) {
                    Image(systemName: "pencil.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - App Picker Sheet

private struct AppPickerSheet: View {
    @ObservedObject private var store = Store.shared
    let submenuID: UUID?
    let onDone: () -> Void
    var onAdd: ((OrbitItem) -> Void)? = nil  // if set, overrides store.addItem

    @State private var allApps: [AppItem] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var staged: [AppItem] = []

    private var filtered: [AppItem] {
        searchText.isEmpty ? allApps : allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    private var currentItems: [OrbitItem] {
        submenuID.map { store.childrenOf(submenuID: $0) } ?? store.rootItems
    }
    private var available: Int {
        OrbitItem.maxItems - currentItems.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search apps…"), text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 12)
            Divider().padding(.top, 8)

            if isLoading {
                Spacer(); ProgressView(L("Scanning apps…")); Spacer()
            } else {
                List(filtered) { app in
                    let alreadyIn = currentItems.contains {
                        if case .app(let p) = $0.kind { return p == app.url.path }
                        return false
                    }
                    let isSt = staged.contains { $0.id == app.id }
                    Button {
                        guard !alreadyIn else { return }
                        if isSt { staged.removeAll { $0.id == app.id } }
                        else if staged.count < available { staged.append(app) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon).resizable().interpolation(.high)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(app.name).foregroundStyle(alreadyIn ? .secondary : .primary)
                            Spacer()
                            Image(systemName: alreadyIn ? "checkmark.circle.fill" : isSt ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(alreadyIn ? .secondary : isSt ? Color.accentColor : .secondary)
                                .font(.system(size: 18))
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(alreadyIn).opacity(alreadyIn ? 0.5 : 1)
                }
                .listStyle(.plain)
            }
            Divider()
            HStack {
                Text("\(staged.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel")) { onDone() }.keyboardShortcut(.cancelAction)
                Button(L("Add")) {
                    for app in staged {
                        let item = OrbitItem.makeApp(path: app.url.path, title: app.name)
                        if let custom = onAdd { custom(item) }
                        else if let sid = submenuID { store.addItem(item, toSubmenuID: sid) }
                        else { store.addItem(item) }
                    }
                    onDone()
                }
                .keyboardShortcut(.defaultAction).disabled(staged.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .onAppear {
            guard allApps.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let a = AppScanner.scanAll()
                DispatchQueue.main.async { allApps = a; isLoading = false }
            }
        }
    }
}

// MARK: - Shortcut Picker Sheet

private struct ShortcutPickerSheet: View {
    @ObservedObject private var store = Store.shared
    let submenuID: UUID?
    let onDone: () -> Void
    var onAdd: ((OrbitItem) -> Void)? = nil

    @State private var shortcuts: [String] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var filtered: [String] {
        searchText.isEmpty ? shortcuts : shortcuts.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    private var currentItems: [OrbitItem] {
        submenuID.map { store.childrenOf(submenuID: $0) } ?? store.rootItems
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search shortcuts…"), text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 12)
            Divider().padding(.top, 8)

            if isLoading {
                Spacer(); ProgressView(L("Loading shortcuts…")); Spacer()
            } else if shortcuts.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(L("No shortcuts found")).font(.headline)
                    Text("Create shortcuts in the Shortcuts app.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filtered, id: \.self) { name in
                    let alreadyIn = currentItems.contains {
                        if case .shortcut(let n) = $0.kind { return n == name }
                        return false
                    }
                    Button {
                        guard !alreadyIn else { return }
                        let item = OrbitItem(title: name, kind: .shortcut(name: name))
                        if let custom = onAdd { custom(item) }
                        else if let sid = submenuID { store.addItem(item, toSubmenuID: sid) }
                        else { store.addItem(item) }
                        onDone()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill").foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            Text(name).foregroundStyle(alreadyIn ? .secondary : .primary)
                            Spacer()
                            if alreadyIn {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(alreadyIn).opacity(alreadyIn ? 0.5 : 1)
                }
                .listStyle(.plain)
            }
            Divider()
            HStack {
                Spacer()
                Button(L("Cancel")) { onDone() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .onAppear {
            guard shortcuts.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let names = fetchShortcuts()
                DispatchQueue.main.async { shortcuts = names; isLoading = false }
            }
        }
    }

    private func fetchShortcuts() -> [String] {
        let proc = Process()
        proc.launchPath = "/usr/bin/shortcuts"
        proc.arguments = ["list"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }
}

// MARK: - Overlay: Submenu Name

private struct SubmenuNameOverlay: View {
    @Binding var title: String
    var isEditing: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        overlayBase {
            Text(isEditing ? L("Rename Folder") : L("New Folder")).font(.headline)
            TextField(L("Folder name"), text: $title)
                .textFieldStyle(.roundedBorder).frame(width: 220)
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                Button(isEditing ? L("Save") : L("Create"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Overlay: URL Input

private struct URLInputOverlay: View {
    @Binding var itemTitle: String
    @Binding var urlString: String
    var isEditing: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        overlayBase {
            Text(isEditing ? L("Edit Link") : L("Add Link")).font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Title (optional)")).font(.caption).foregroundStyle(.secondary)
                TextField("e.g. GitHub", text: $itemTitle)
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("URL")).font(.caption).foregroundStyle(.secondary)
                TextField("https://…", text: $urlString)
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                Button(isEditing ? L("Save") : L("Add"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Overlay: Script Input

private struct ScriptInputOverlay: View {
    @Binding var itemTitle: String
    @Binding var source: String
    @Binding var runInTerminal: Bool
    var isEditing: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        overlayBase {
            Text(isEditing ? L("Edit Shell Script") : L("Add Shell Script")).font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Title")).font(.caption).foregroundStyle(.secondary)
                TextField(L("Script name"), text: $itemTitle)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Script")).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 300, height: 100)
                    .border(Color(nsColor: .separatorColor))
            }
            Toggle(L("Run in Terminal"), isOn: $runInTerminal)
                .frame(width: 300, alignment: .leading)
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                Button(isEditing ? L("Save") : L("Add"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(itemTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Overlay base

private func overlayBase<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Color.black.opacity(0.4).ignoresSafeArea()
        VStack(spacing: 14) { content() }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject private var store = Store.shared

    @ViewBuilder
    private func shortcutRow(label: String, badge: String) -> some View {
        HStack {
            Text(label); Spacer()
            Text(badge)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    var body: some View {
        Form {
            Section(L("Language")) {
                Picker(L("Language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
            }
            Section(L("Startup")) {
                Toggle(L("Start at Login"), isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }
                ))
            }
            Section(L("Menu Bar Icon")) {
                Picker(L("Menu Bar Icon"), selection: $store.launcherFlag) {
                    Text("◌  \(L("Default"))").tag("")
                    ForEach(MenuBarFlags.all, id: \.flag) { item in
                        Text("\(item.flag)  \(item.name)").tag(item.flag)
                    }
                }
                .labelsHidden()
            }
            Section(L("Trigger")) {
                Toggle(L("Mouse shake (hold ⌥/⌃ + shake)"), isOn: $store.shakeEnabled)
                if store.shakeEnabled {
                    HStack {
                        Text(L("Sensitivity"))
                        Slider(
                            value: Binding(
                                get: { Double(store.shakeSensitivity) },
                                set: { store.shakeSensitivity = Int($0.rounded()) }
                            ),
                            in: 1...10, step: 1
                        )
                        Text("\(store.shakeSensitivity)").monospacedDigit().frame(width: 20, alignment: .trailing)
                    }
                }
            }
            Section(L("Keyboard Shortcut")) {
                shortcutRow(label: L("Toggle radial menu"), badge: "⌘⇧D")
                shortcutRow(label: L("Open windows"), badge: "⌘⇧W")
            }
            Section(L("Windows")) {
                Toggle(L("Window previews (needs Screen Recording)"), isOn: $store.windowPreviews)
                    .onChange(of: store.windowPreviews) { newValue in
                        if newValue { CGRequestScreenCaptureAccess() }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Monitor Tab

private struct MonitorTab: View {
    @ObservedObject private var store = Store.shared
    @State private var draggedMetric: MonitorMetric?

    var body: some View {
        Form {
            Section {
                Toggle(L("Show system monitor"), isOn: $store.monitorEnabled)
            }

            Section {
                ForEach(store.metricOrder) { metric in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        Image(systemName: metric.symbol)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Toggle(L(metric.labelKey), isOn: binding(for: metric))
                    }
                    .contentShape(Rectangle())
                    .opacity(draggedMetric == metric ? 0.4 : 1)
                    .onDrag {
                        draggedMetric = metric
                        return NSItemProvider(object: metric.rawValue as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: MetricDropDelegate(
                        item: metric, dragged: $draggedMetric, store: store))
                }
            } header: {
                Text(L("Metrics"))
            } footer: {
                Text(L("Drag to reorder. Temperature and fan appear only on supported Macs."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section(L("Units")) {
                Picker(L("Temperature unit"), selection: $store.temperatureUnit) {
                    Text("°C").tag(TemperatureUnit.celsius)
                    Text("°F").tag(TemperatureUnit.fahrenheit)
                }
                Picker(L("Network unit"), selection: $store.networkUnit) {
                    Text(L("Bytes (KB/s)")).tag(NetworkUnit.bytes)
                    Text(L("Bits (Kbps)")).tag(NetworkUnit.bits)
                }
            }

            Section(L("Display")) {
                Picker(L("Label style"), selection: $store.monitorLabelStyle) {
                    Text(L("Symbol")).tag(MonitorLabelStyle.symbol)
                    Text(L("Name")).tag(MonitorLabelStyle.name)
                }
                Picker(L("Update interval"), selection: $store.monitorInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                }
                Toggle(L("Color high values"), isOn: $store.monitorColorCoding)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for metric: MonitorMetric) -> Binding<Bool> {
        Binding(
            get: { !store.disabledMetrics.contains(metric) },
            set: { on in
                if on { store.disabledMetrics.remove(metric) }
                else  { store.disabledMetrics.insert(metric) }
            }
        )
    }
}

/// Live drag-to-reorder for the metrics list: as the dragged row hovers over
/// another, the two swap positions in `store.metricOrder`.
private struct MetricDropDelegate: DropDelegate {
    let item: MonitorMetric
    @Binding var dragged: MonitorMetric?
    let store: Store

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != item,
              let from = store.metricOrder.firstIndex(of: dragged),
              let to = store.metricOrder.firstIndex(of: item) else { return }
        withAnimation {
            store.metricOrder.move(fromOffsets: IndexSet(integer: from),
                                   toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}

// MARK: - Context Tab

private struct ContextTab: View {
    @ObservedObject private var store = Store.shared

    @State private var selectedAppPath: String? = nil
    @State private var showingAppPicker  = false
    @State private var showingShortcuts  = false
    @State private var overlay: OverlayKind? = nil
    @State private var overlayTitle = ""
    @State private var overlayValue = ""
    @State private var overlayRunInTerminal = false

    private var allApps: [AppItem] { AppScanner.scanAll() }

    private var configuredPaths: [String] {
        store.contextSets.keys.sorted()
    }

    private var displayedPaths: [String] {
        var paths = configuredPaths
        if let sel = selectedAppPath, !paths.contains(sel) {
            paths.insert(sel, at: 0)
        }
        return paths
    }

    private var currentItems: [OrbitItem] {
        guard let path = selectedAppPath else { return [] }
        return store.contextItems(forApp: path)
    }

    private var isFull: Bool { currentItems.count >= OrbitItem.maxItems }

    var body: some View {
        VStack(spacing: 0) {
            appSelectorBar
            Divider()
            if selectedAppPath == nil {
                emptyPrompt
            } else if currentItems.isEmpty {
                emptySetState
            } else {
                contextList
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            if let path = selectedAppPath {
                AppPickerSheet(submenuID: nil, onDone: { showingAppPicker = false },
                               onAdd: { item in store.addContextItem(item, forApp: path) })
                    .frame(width: 360, height: 460)
            }
        }
        .sheet(isPresented: $showingShortcuts) {
            if let path = selectedAppPath {
                ShortcutPickerSheet(submenuID: nil, onDone: { showingShortcuts = false },
                                    onAdd: { item in store.addContextItem(item, forApp: path) })
                    .frame(width: 340, height: 420)
            }
        }
        .overlay {
            if let kind = overlay {
                contextOverlay(for: kind)
            }
        }
    }

    private var appSelectorBar: some View {
        HStack(spacing: 8) {
            Text(L("App:")).foregroundStyle(.secondary)
            Picker("", selection: $selectedAppPath) {
                Text(L("Choose…")).tag(Optional<String>.none)
                ForEach(allApps, id: \.url.path) { app in
                    Text(app.name).tag(Optional(app.url.path))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)

            Spacer()

            if selectedAppPath != nil {
                if !isFull { contextAddMenu }
                if !currentItems.isEmpty {
                    Button(role: .destructive) {
                        if let p = selectedAppPath { store.removeContextSet(forApp: p) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var contextAddMenu: some View {
        Menu {
            Button(L("Add App…")) { showingAppPicker = true }
            Button(L("Add File or Folder…")) { pickFileForContext() }
            Divider()
            Button(L("Add Link…")) {
                overlayTitle = ""; overlayValue = "https://"; overlay = .url
            }
            Menu(L("Add System Action")) {
                ForEach(SystemAction.allCases, id: \.self) { action in
                    Button(action.displayTitle) { addContextSystemAction(action) }
                }
            }
            Button(L("Add Shortcut…")) { showingShortcuts = true }
            Button(L("Add Script…")) {
                overlayTitle = ""; overlayValue = "#!/bin/zsh\n"; overlayRunInTerminal = false
                overlay = .script
            }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color.accentColor)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var contextList: some View {
        List {
            ForEach(currentItems) { item in
                HStack {
                    Image(nsImage: item.icon).resizable().frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(item.title)
                    Spacer()
                    Text(item.typeLabel).font(.caption).foregroundStyle(.secondary)
                    Button { if let p = selectedAppPath { store.removeContextItem(id: item.id, forApp: p) } }
                    label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                    .buttonStyle(.plain)
                }
            }
            .onMove { src, dst in
                if let p = selectedAppPath { store.moveContextItem(forApp: p, from: src, to: dst) }
            }
        }
        .listStyle(.inset)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "app.badge").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text(L("Context Sets")).font(.headline)
            Text(L("Select an app above to create a custom item set\nthat appears when that app is in front."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var emptySetState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "plus.circle.dashed").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text(L("No items for this app")).font(.headline)
            Text(L("Use the + button to add items to this context set."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func pickFileForContext() {
        guard let path = selectedAppPath else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                let item = OrbitItem.makeFile(
                    path: url.path,
                    title: url.deletingPathExtension().lastPathComponent
                )
                store.addContextItem(item, forApp: path)
            }
        }
    }

    private func addContextSystemAction(_ action: SystemAction) {
        guard let path = selectedAppPath else { return }
        store.addContextItem(
            OrbitItem(title: action.displayTitle, kind: .systemAction(action)),
            forApp: path
        )
    }

    @ViewBuilder
    private func contextOverlay(for kind: OverlayKind) -> some View {
        switch kind {
        case .submenuName:
            EmptyView()
        case .url:
            URLInputOverlay(itemTitle: $overlayTitle, urlString: $overlayValue) {
                guard let path = selectedAppPath else { overlay = nil; return }
                var raw = overlayValue.trimmingCharacters(in: .whitespaces)
                if !raw.contains("://") { raw = "https://" + raw }
                let title = overlayTitle.isEmpty ? (URL(string: raw)?.host ?? "Link") : overlayTitle
                store.addContextItem(.makeURL(urlString: raw, title: title), forApp: path)
                overlay = nil
            } onCancel: { overlay = nil }
        case .script:
            ScriptInputOverlay(itemTitle: $overlayTitle, source: $overlayValue, runInTerminal: $overlayRunInTerminal) {
                guard let path = selectedAppPath else { overlay = nil; return }
                let title = overlayTitle.isEmpty ? "Script" : overlayTitle
                store.addContextItem(
                    OrbitItem(title: title, kind: .script(source: overlayValue, isShell: true, runInTerminal: overlayRunInTerminal)),
                    forApp: path
                )
                overlay = nil
            } onCancel: { overlay = nil }
        }
    }
}
