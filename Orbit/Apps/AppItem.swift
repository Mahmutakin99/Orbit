import AppKit
import Foundation

struct AppItem: Identifiable {
    /// Stable ID — the app bundle's absolute path.
    var id: String { url.path }
    let name: String
    let url: URL
    let icon: NSImage
}
