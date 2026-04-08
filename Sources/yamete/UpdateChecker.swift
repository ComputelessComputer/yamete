import Foundation

struct UpdateInfo {
    let version: String
    let releaseURL: URL
}

enum UpdateCheckResult {
    case upToDate(String)
    case updateAvailable(UpdateInfo)
    case failed(String)
}

enum UpdateChecker {
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/ComputelessComputer/yamete/releases/latest")!

    static func check(currentVersion: String?) async -> UpdateCheckResult {
        do {
            var request = URLRequest(url: latestReleaseAPIURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Yamete", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed("Update check failed.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failed("GitHub returned \(httpResponse.statusCode) during update check.")
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.normalizedVersion

            guard let currentVersion else {
                return .updateAvailable(.init(version: latestVersion, releaseURL: release.htmlURL))
            }

            guard
                let latest = SemanticVersion(latestVersion),
                let current = SemanticVersion(currentVersion)
            else {
                if latestVersion == currentVersion {
                    return .upToDate(currentVersion)
                }

                return .updateAvailable(.init(version: latestVersion, releaseURL: release.htmlURL))
            }

            if latest > current {
                return .updateAvailable(.init(version: latestVersion, releaseURL: release.htmlURL))
            }

            return .upToDate(currentVersion)
        } catch {
            return .failed("Update check failed.")
        }
    }
}

enum AppVersion {
    static var current: String? {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !version.isEmpty {
            return version
        }

        return nil
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    var normalizedVersion: String {
        tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        let numbers = value
            .split(separator: ".")
            .map { Int($0) }

        guard numbers.allSatisfy({ $0 != nil }) else {
            return nil
        }

        components = numbers.compactMap { $0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)

        for index in 0..<count {
            let left = lhs.components.indices.contains(index) ? lhs.components[index] : 0
            let right = rhs.components.indices.contains(index) ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}
