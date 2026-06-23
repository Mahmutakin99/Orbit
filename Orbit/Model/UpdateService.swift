import Foundation

// MARK: - Release Info

struct ReleaseInfo {
    let tagName: String     // e.g. "v1.3.0"
    let version: String     // tagName with leading "v" stripped
    let notes: String       // release body / changelog
    let downloadURL: URL    // direct URL for Orbit.app.zip asset
}

// MARK: - Service

enum UpdateService {
    private static let apiURL = URL(string: "https://api.github.com/repos/Mahmutakin99/Orbit/releases/latest")!

    /// Fetches the latest GitHub release. Returns nil if already up-to-date.
    static func latestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

        // Compare against current bundle version using numeric ordering.
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard version.compare(current, options: .numeric) == .orderedDescending else {
            return nil   // already up-to-date
        }

        let notes = json["body"] as? String ?? ""

        // Find the .zip asset URL.
        guard let assets = json["assets"] as? [[String: Any]],
              let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let urlString = zipAsset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString) else {
            throw URLError(.resourceUnavailable)
        }

        return ReleaseInfo(tagName: tag, version: version, notes: notes, downloadURL: downloadURL)
    }
}
