import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum UpdateStatus {
    case upToDate
    case available(version: String, downloadURL: URL?, releaseURL: URL)
    case failed(String)
}

enum Updater {
    static let repoOwner = "xiaohe529"
    static let repoName = "FocusGuard"
    static let apiURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func checkForUpdates() async -> UpdateStatus {
        guard let url = URL(string: apiURL) else { return .failed("无效的更新检查地址") }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FocusGuard/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("无法连接 GitHub，请检查网络后重试")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            if compareVersions(currentVersion, latestVersion) == .orderedAscending {
                let asset = release.assets.first { $0.name.hasSuffix(".dmg") }
                    ?? release.assets.first { $0.name.hasSuffix(".zip") }
                return .available(version: latestVersion, downloadURL: asset?.browserDownloadURL, releaseURL: release.htmlURL)
            } else {
                return .upToDate
            }
        } catch {
            return .failed("检查更新失败：\(error.localizedDescription)")
        }
    }

    static func download(_ url: URL, to destination: URL) async throws {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(pa.count, pb.count)
        for i in 0..<count {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }
}