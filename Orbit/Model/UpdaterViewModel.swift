import AppKit
import Combine
import UserNotifications

// MARK: - Updater ViewModel (MVVM)

@MainActor
final class UpdaterViewModel: ObservableObject {
    static let shared = UpdaterViewModel()

    @Published private(set) var isChecking = false
    @Published var lastResultMessage: String? = nil

    private static let lastCheckKey  = "lastUpdateCheckDate"
    private static let notifActionID = "orbit.update.install"
    private static let notifID       = "orbit.update.available"

    private init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationDelegate.shared.onInstall = { [weak self] info in
            Task { @MainActor in await self?.install(info) }
        }
    }

    // MARK: - Check

    /// Called at launch (silent: true → no "up to date" alert) or manually.
    func check(silent: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            if let info = try await UpdateService.latestRelease() {
                if silent {
                    postNotification(info)
                } else {
                    showUpdateAlert(info)
                }
            } else {
                if !silent {
                    let a = NSAlert()
                    a.messageText     = L("Orbit is up to date")
                    a.informativeText = L("You're already using the latest version.")
                    a.alertStyle      = .informational
                    a.addButton(withTitle: L("OK"))
                    a.runModal()
                }
                lastResultMessage = "upToDate"
            }
        } catch {
            if !silent {
                let a = NSAlert()
                a.messageText     = L("Could not check for updates")
                a.informativeText = error.localizedDescription
                a.alertStyle      = .warning
                a.addButton(withTitle: L("OK"))
                a.runModal()
            }
        }
    }

    // MARK: - Notification banner

    private func postNotification(_ info: ReleaseInfo) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                // Fallback: show alert directly if notifications denied.
                Task { @MainActor in self.showUpdateAlert(info) }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = L("Update Available — \(info.tagName)")
            content.body  = L("A new version of Orbit is ready. Tap to install.")
            content.sound = .default
            // Store info in userInfo so the delegate can act on tap.
            content.userInfo = [
                "version":     info.version,
                "tagName":     info.tagName,
                "notes":       info.notes,
                "downloadURL": info.downloadURL.absoluteString
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            let req = UNNotificationRequest(identifier: Self.notifID,
                                            content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
        }
    }

    // MARK: - Alert (manual check or notification tap)

    func showUpdateAlert(_ info: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText     = L("Orbit \(info.tagName) is available")
        let notesPreview  = info.notes.isEmpty ? "" : "\n\n\(info.notes.prefix(300))"
        a.informativeText = L("Would you like to download and install the update?") + notesPreview
        a.alertStyle      = .informational
        a.addButton(withTitle: L("Install"))
        a.addButton(withTitle: L("Later"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Task { await install(info) }
    }

    // MARK: - Download + Install

    func install(_ info: ReleaseInfo) async {
        guard let tmpDir = try? FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: "/Applications"), create: true
        ) else { return }

        let zipPath = tmpDir.appendingPathComponent("Orbit-update.zip")

        // Download with progress indicator.
        let progress = NSProgressIndicator()
        progress.style = .bar; progress.isIndeterminate = false
        let alert = NSAlert()
        alert.messageText = L("Downloading update…")
        alert.accessoryView = progress
        alert.addButton(withTitle: L("Cancel"))
        alert.layout()
        // Show non-blocking sheet — we close it ourselves.
        NSApp.activate(ignoringOtherApps: true)

        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: info.downloadURL) { bytes, total in
                if total > 0 {
                    Task { @MainActor in progress.doubleValue = Double(bytes) / Double(total) * 100 }
                }
            }
            try FileManager.default.moveItem(at: tmpURL, to: zipPath)
        } catch {
            let ea = NSAlert(); ea.messageText = L("Download failed")
            ea.informativeText = error.localizedDescription; ea.runModal(); return
        }

        // Unzip using ditto.
        let unzipDir = tmpDir.appendingPathComponent("Orbit-unpacked")
        try? FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.launchPath = "/usr/bin/ditto"
        ditto.arguments  = ["-x", "-k", zipPath.path, unzipDir.path]
        try? ditto.run(); ditto.waitUntilExit()

        let newApp = unzipDir.appendingPathComponent("Orbit.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            let ea = NSAlert(); ea.messageText = L("Install failed")
            ea.informativeText = L("Orbit.app not found inside the downloaded archive."); ea.runModal(); return
        }

        // Replace /Applications/Orbit.app after this process exits.
        let dest   = "/Applications/Orbit.app"
        let src    = newApp.path
        let pid    = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        rm -rf '\(dest)'
        /usr/bin/ditto '\(src)' '\(dest)'
        open '\(dest)'
        """
        let scriptPath = tmpDir.appendingPathComponent("orbit_install.sh").path
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let launcher = Process()
        launcher.launchPath = "/bin/sh"
        launcher.arguments  = [scriptPath]
        try? launcher.run()

        NSApp.terminate(nil)
    }
}

// MARK: - URLSession download with progress closure

extension URLSession {
    func download(from url: URL, progress: @escaping (Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: url) { tmpURL, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let tmpURL, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse)); return
                }
                continuation.resume(returning: (tmpURL, response))
            }
            // Observe fractionCompleted for progress.
            var obs: NSKeyValueObservation? = task.observe(\.countOfBytesReceived) { t, _ in
                progress(t.countOfBytesReceived, t.countOfBytesExpectedToReceive)
            }
            task.resume()
            _ = obs   // keep alive
        }
    }
}

// MARK: - Notification Delegate (singleton, wires tap → install)

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    var onInstall: ((ReleaseInfo) -> Void)?

    private override init() { super.init() }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let ui = response.notification.request.content.userInfo
        guard
            let version     = ui["version"]     as? String,
            let tagName     = ui["tagName"]      as? String,
            let notes       = ui["notes"]        as? String,
            let urlString   = ui["downloadURL"]  as? String,
            let downloadURL = URL(string: urlString)
        else { return }

        let info = ReleaseInfo(tagName: tagName, version: version,
                               notes: notes, downloadURL: downloadURL)
        onInstall?(info)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
