import AppKit

// MARK: - System Action

enum SystemAction: String, Codable, CaseIterable {
    case sleep, lock, screensaver, emptyTrash, screenshot

    var displayTitle: String {
        switch self {
        case .sleep:       return L("Sleep")
        case .lock:        return L("Lock Screen")
        case .screensaver: return L("Screen Saver")
        case .emptyTrash:  return L("Empty Trash")
        case .screenshot:  return L("Screenshot")
        }
    }

    var symbolName: String {
        switch self {
        case .sleep:       return "moon.fill"
        case .lock:        return "lock.fill"
        case .screensaver: return "play.rectangle.fill"
        case .emptyTrash:  return "trash.fill"
        case .screenshot:  return "camera.fill"
        }
    }

    func perform() {
        switch self {
        case .sleep:
            let proc = Process(); proc.launchPath = "/usr/bin/pmset"
            proc.arguments = ["sleepnow"]; try? proc.run()
        case .lock:
            let proc = Process(); proc.launchPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
            proc.arguments = ["-suspend"]; try? proc.run()
        case .screensaver:
            let proc = Process(); proc.launchPath = "/usr/bin/open"
            proc.arguments = ["/System/Library/CoreServices/ScreenSaverEngine.app"]; try? proc.run()
        case .emptyTrash:
            let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask)
            let items = (try? FileManager.default.contentsOfDirectory(
                at: trash.first ?? URL(fileURLWithPath: ""), includingPropertiesForKeys: nil)) ?? []
            NSWorkspace.shared.recycle(items)
        case .screenshot:
            let proc = Process(); proc.launchPath = "/usr/sbin/screencapture"
            proc.arguments = ["-i", "-c"]; try? proc.run()
        }
    }
}

// MARK: - Kind

enum OrbitItemKind {
    case app(path: String)
    case file(path: String)
    case url(urlString: String)
    case systemAction(SystemAction)
    case shortcut(name: String)
    case script(source: String, isShell: Bool, runInTerminal: Bool)
    indirect case submenu(children: [OrbitItem])
    case clipboard(text: String)
}

// MARK: - Manual Codable
//
// Hand-written to preserve the exact wire format Swift's synthesized
// Codable produced before `runInTerminal` was added, so previously saved
// items (UserDefaults JSON) keep decoding correctly. Missing `isShell`/
// `runInTerminal` keys fall back to their pre-existing defaults.
extension OrbitItemKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case app, file, url, systemAction, shortcut, script, submenu, clipboard
    }
    private enum AppKeys: String, CodingKey { case path }
    private enum FileKeys: String, CodingKey { case path }
    private enum URLKeys: String, CodingKey { case urlString }
    private enum SystemActionKeys: String, CodingKey { case _0 }
    private enum ShortcutKeys: String, CodingKey { case name }
    private enum ScriptKeys: String, CodingKey { case source, isShell, runInTerminal }
    private enum SubmenuKeys: String, CodingKey { case children }
    private enum ClipboardKeys: String, CodingKey { case text }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let c = try? container.nestedContainer(keyedBy: AppKeys.self, forKey: .app) {
            self = .app(path: try c.decode(String.self, forKey: .path)); return
        }
        if let c = try? container.nestedContainer(keyedBy: FileKeys.self, forKey: .file) {
            self = .file(path: try c.decode(String.self, forKey: .path)); return
        }
        if let c = try? container.nestedContainer(keyedBy: URLKeys.self, forKey: .url) {
            self = .url(urlString: try c.decode(String.self, forKey: .urlString)); return
        }
        if let c = try? container.nestedContainer(keyedBy: SystemActionKeys.self, forKey: .systemAction) {
            self = .systemAction(try c.decode(SystemAction.self, forKey: ._0)); return
        }
        if let c = try? container.nestedContainer(keyedBy: ShortcutKeys.self, forKey: .shortcut) {
            self = .shortcut(name: try c.decode(String.self, forKey: .name)); return
        }
        if let c = try? container.nestedContainer(keyedBy: ScriptKeys.self, forKey: .script) {
            let source = try c.decode(String.self, forKey: .source)
            let isShell = try c.decodeIfPresent(Bool.self, forKey: .isShell) ?? true
            let runInTerminal = try c.decodeIfPresent(Bool.self, forKey: .runInTerminal) ?? false
            self = .script(source: source, isShell: isShell, runInTerminal: runInTerminal); return
        }
        if let c = try? container.nestedContainer(keyedBy: SubmenuKeys.self, forKey: .submenu) {
            self = .submenu(children: try c.decode([OrbitItem].self, forKey: .children)); return
        }
        if let c = try? container.nestedContainer(keyedBy: ClipboardKeys.self, forKey: .clipboard) {
            self = .clipboard(text: try c.decode(String.self, forKey: .text)); return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown OrbitItemKind"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let path):
            var c = container.nestedContainer(keyedBy: AppKeys.self, forKey: .app)
            try c.encode(path, forKey: .path)
        case .file(let path):
            var c = container.nestedContainer(keyedBy: FileKeys.self, forKey: .file)
            try c.encode(path, forKey: .path)
        case .url(let s):
            var c = container.nestedContainer(keyedBy: URLKeys.self, forKey: .url)
            try c.encode(s, forKey: .urlString)
        case .systemAction(let a):
            var c = container.nestedContainer(keyedBy: SystemActionKeys.self, forKey: .systemAction)
            try c.encode(a, forKey: ._0)
        case .shortcut(let name):
            var c = container.nestedContainer(keyedBy: ShortcutKeys.self, forKey: .shortcut)
            try c.encode(name, forKey: .name)
        case .script(let source, let isShell, let runInTerminal):
            var c = container.nestedContainer(keyedBy: ScriptKeys.self, forKey: .script)
            try c.encode(source, forKey: .source)
            try c.encode(isShell, forKey: .isShell)
            try c.encode(runInTerminal, forKey: .runInTerminal)
        case .submenu(let children):
            var c = container.nestedContainer(keyedBy: SubmenuKeys.self, forKey: .submenu)
            try c.encode(children, forKey: .children)
        case .clipboard(let text):
            var c = container.nestedContainer(keyedBy: ClipboardKeys.self, forKey: .clipboard)
            try c.encode(text, forKey: .text)
        }
    }
}

// MARK: - Item

struct OrbitItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var kind: OrbitItemKind

    init(id: UUID = UUID(), title: String, kind: OrbitItemKind) {
        self.id = id; self.title = title; self.kind = kind
    }

    static let maxItems    = 48   // total cap per level
    static let itemsPerPage = 12  // visible per radial page

    // MARK: - Factory

    static func makeApp(path: String, title: String) -> OrbitItem {
        OrbitItem(title: title, kind: .app(path: path))
    }
    static func makeSubmenu(title: String, children: [OrbitItem] = []) -> OrbitItem {
        OrbitItem(title: title, kind: .submenu(children: children))
    }
    static func makeFile(path: String, title: String) -> OrbitItem {
        OrbitItem(title: title, kind: .file(path: path))
    }
    static func makeURL(urlString: String, title: String) -> OrbitItem {
        OrbitItem(title: title, kind: .url(urlString: urlString))
    }

    // MARK: - Runtime properties (not Codable)

    var icon: NSImage {
        switch kind {
        case .app(let p), .file(let p):
            return NSWorkspace.shared.icon(forFile: p)
        case .url:
            return sym("globe") ?? NSImage(named: NSImage.networkName)!
        case .systemAction(let a):
            return sym(a.symbolName) ?? NSImage(named: NSImage.actionTemplateName)!
        case .shortcut:
            return sym("bolt.fill") ?? NSImage(named: NSImage.actionTemplateName)!
        case .script:
            return sym("terminal.fill") ?? NSImage(named: NSImage.actionTemplateName)!
        case .submenu:
            return sym("folder.fill") ?? NSImage(named: NSImage.folderName)!
        case .clipboard:
            return sym("doc.on.clipboard") ?? NSImage(named: NSImage.actionTemplateName)!
        }
    }

    var typeLabel: String {
        switch kind {
        case .app:          return L("App")
        case .file:         return L("File")
        case .url:          return L("Link")
        case .systemAction: return L("System")
        case .shortcut:     return L("Shortcut")
        case .script:       return L("Script")
        case .submenu:      return L("Folder")
        case .clipboard:    return L("Clipboard")
        }
    }

    var isSubmenu: Bool {
        if case .submenu = kind { return true }; return false
    }

    var children: [OrbitItem]? {
        if case .submenu(let c) = kind { return c }; return nil
    }

    // MARK: - Perform

    func perform() {
        switch kind {
        case .app(let p):
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        case .file(let p):
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        case .url(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .systemAction(let a):
            a.perform()
        case .shortcut(let name):
            let p = Process(); p.launchPath = "/usr/bin/shortcuts"
            p.arguments = ["run", name]; try? p.run()
        case .script(let src, let isShell, let runInTerminal):
            guard isShell else { break }
            if runInTerminal {
                let tmp = NSTemporaryDirectory() + "orbit-\(UUID().uuidString).sh"
                try? src.write(toFile: tmp, atomically: true, encoding: .utf8)
                let osa = "tell application \"Terminal\"\nactivate\ndo script \"bash '\(tmp)'\"\nend tell"
                let p = Process(); p.launchPath = "/usr/bin/osascript"
                p.arguments = ["-e", osa]; try? p.run()
            } else {
                let p = Process(); p.launchPath = "/bin/zsh"
                p.arguments = ["-c", src]; try? p.run()
            }
        case .submenu:
            break // navigation handled by caller
        case .clipboard(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

// MARK: - Helpers

private func sym(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)
}
