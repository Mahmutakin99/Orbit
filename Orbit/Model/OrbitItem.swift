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
            proc.arguments = ["-a", "ScreenSaverEngine"]; try? proc.run()
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

enum OrbitItemKind: Codable {
    case app(path: String)
    case file(path: String)
    case url(urlString: String)
    case systemAction(SystemAction)
    case shortcut(name: String)
    case script(source: String, isShell: Bool)
    indirect case submenu(children: [OrbitItem])
    case clipboard(text: String)
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
        case .script(let src, let isShell):
            if isShell {
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
