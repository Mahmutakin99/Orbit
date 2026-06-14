import AppKit
import Foundation

enum AppScanner {
    private static var searchDirs: [URL] {
        var dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        // ~/Applications covers Chrome PWAs, Electron apps, etc.
        if let userApps = FileManager.default.urls(
            for: .applicationDirectory, in: .userDomainMask
        ).first {
            dirs.append(userApps)
        }
        return dirs
    }

    /// Returns the first `limit` apps sorted by name.
    static func scan(limit: Int = 12) -> [AppItem] {
        Array(scanAll().prefix(limit))
    }

    /// Returns ALL .app bundles from standard directories + one level of
    /// subdirectories (Utilities, Chrome Apps.localized, etc.), sorted by name.
    static func scanAll() -> [AppItem] {
        var seen = Set<String>()
        var results: [AppItem] = []
        let fm = FileManager.default

        func collect(from dir: URL) {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for url in contents {
                if url.pathExtension == "app" {
                    let path = url.path
                    guard seen.insert(path).inserted else { continue }
                    results.append(makeItem(url: url))
                } else {
                    // One level deep: descend into non-.app directories
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir {
                        guard let sub = try? fm.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]
                        ) else { continue }
                        for subURL in sub where subURL.pathExtension == "app" {
                            let path = subURL.path
                            guard seen.insert(path).inserted else { continue }
                            results.append(makeItem(url: subURL))
                        }
                    }
                }
            }
        }

        for dir in searchDirs { collect(from: dir) }

        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Creates an AppItem from a stored file path. Returns nil if the file no longer exists.
    static func item(forPath path: String) -> AppItem? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return makeItem(url: URL(fileURLWithPath: path))
    }

    // MARK: - Private

    private static func makeItem(url: URL) -> AppItem {
        let name = url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return AppItem(name: name, url: url, icon: icon)
    }
}
