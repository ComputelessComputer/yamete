import Foundation

struct UpdateInfo: Sendable {
    let version: String
    let downloadURL: URL
    let assetName: String
}

enum UpdateCheckResult: Sendable {
    case upToDate(String)
    case updateAvailable(UpdateInfo)
    case failed(String)
}

enum UpdatePreparationResult: Sendable {
    case readyToRelaunch(String)
    case failed(String)
}

enum UpdateChecker {
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/ComputelessComputer/yamete/releases/latest")!
    private static let appBundleName = "Yamete.app"

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
            guard let asset = release.primaryDiskImageAsset else {
                return .failed("The latest release is missing a macOS installer.")
            }

            guard let currentVersion else {
                return .updateAvailable(
                    .init(
                        version: latestVersion,
                        downloadURL: asset.browserDownloadURL,
                        assetName: asset.name
                    )
                )
            }

            guard
                let latest = SemanticVersion(latestVersion),
                let current = SemanticVersion(currentVersion)
            else {
                if latestVersion == currentVersion {
                    return .upToDate(currentVersion)
                }

                return .updateAvailable(
                    .init(
                        version: latestVersion,
                        downloadURL: asset.browserDownloadURL,
                        assetName: asset.name
                    )
                )
            }

            if latest > current {
                return .updateAvailable(
                    .init(
                        version: latestVersion,
                        downloadURL: asset.browserDownloadURL,
                        assetName: asset.name
                    )
                )
            }

            return .upToDate(currentVersion)
        } catch {
            return .failed("Update check failed.")
        }
    }

    static func prepareUpdate(_ update: UpdateInfo) async -> UpdatePreparationResult {
        let fileManager = FileManager.default
        var workspaceURL: URL?
        var mountPointURL: URL?

        do {
            let targetAppURL = try resolveInstallationTarget()
            let workspace = fileManager.temporaryDirectory
                .appendingPathComponent("yamete-update-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)

            workspaceURL = workspace

            let dmgURL = try await downloadDiskImage(for: update, in: workspace)
            let mountPoint = workspace.appendingPathComponent("mount", isDirectory: true)
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            mountPointURL = mountPoint

            try mountDiskImage(at: dmgURL, mountPointURL: mountPoint)
            let sourceAppURL = try findMountedApp(at: mountPoint)
            let scriptURL = try writeInstallerScript(in: workspace)

            try launchInstaller(
                scriptURL: scriptURL,
                sourceAppURL: sourceAppURL,
                targetAppURL: targetAppURL,
                mountPointURL: mountPoint,
                workspaceURL: workspace
            )

            return .readyToRelaunch(update.version)
        } catch let error as UpdatePreparationError {
            if let mountPointURL {
                try? detachDiskImage(at: mountPointURL)
            }
            if let workspaceURL {
                try? fileManager.removeItem(at: workspaceURL)
            }
            return .failed(error.localizedDescription)
        } catch {
            if let mountPointURL {
                try? detachDiskImage(at: mountPointURL)
            }
            if let workspaceURL {
                try? fileManager.removeItem(at: workspaceURL)
            }
            return .failed("Yamete couldn't install the update.")
        }
    }

    private static func downloadDiskImage(for update: UpdateInfo, in workspaceURL: URL) async throws -> URL {
        var request = URLRequest(url: update.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Yamete", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdatePreparationError.message("Yamete couldn't download the update.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdatePreparationError.message("GitHub returned \(httpResponse.statusCode) while downloading the update.")
        }

        let destinationURL = workspaceURL.appendingPathComponent(update.assetName)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private static func mountDiskImage(at diskImageURL: URL, mountPointURL: URL) throws {
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: [
                "attach",
                diskImageURL.path,
                "-nobrowse",
                "-readonly",
                "-mountpoint", mountPointURL.path,
                "-quiet",
            ]
        )
    }

    private static func detachDiskImage(at mountPointURL: URL) throws {
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountPointURL.path, "-quiet"]
        )
    }

    private static func findMountedApp(at mountPointURL: URL) throws -> URL {
        let expectedURL = mountPointURL.appendingPathComponent(appBundleName, isDirectory: true)
        if FileManager.default.fileExists(atPath: expectedURL.path) {
            return expectedURL
        }

        let candidates = try FileManager.default.contentsOfDirectory(
            at: mountPointURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        if let appURL = candidates.first(where: {
            guard $0.pathExtension == "app" else { return false }
            return (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }) {
            return appURL
        }

        throw UpdatePreparationError.message("The downloaded update doesn't contain Yamete.app.")
    }

    private static func resolveInstallationTarget() throws -> URL {
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(appBundleName, isDirectory: true)

        let candidates: [URL]
        if currentBundleURL.pathExtension == "app" {
            candidates = [currentBundleURL, applicationsURL]
        } else {
            candidates = [applicationsURL]
        }

        for candidate in uniqueURLs(from: candidates) where canInstall(at: candidate) {
            return candidate
        }

        throw UpdatePreparationError.message("Yamete can't write the updated app bundle. Move it into a writable Applications folder and try again.")
    }

    private static func canInstall(at appURL: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
    }

    private static func uniqueURLs(from urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        var result: [URL] = []

        for url in urls where seen.insert(url).inserted {
            result.append(url)
        }

        return result
    }

    private static func writeInstallerScript(in workspaceURL: URL) throws -> URL {
        let scriptURL = workspaceURL.appendingPathComponent("install-and-relaunch.sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail

        APP_PID="$1"
        SOURCE_APP="$2"
        TARGET_APP="$3"
        MOUNT_POINT="$4"
        WORKSPACE="$5"

        cleanup() {
          /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
        }
        trap cleanup EXIT

        while kill -0 "$APP_PID" 2>/dev/null; do
          sleep 1
        done

        /bin/mkdir -p "$(dirname "$TARGET_APP")"
        /bin/rm -rf "$TARGET_APP"
        /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
        /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
        trap - EXIT
        /usr/bin/open "$TARGET_APP"
        /bin/rm -rf "$WORKSPACE"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static func launchInstaller(
        scriptURL: URL,
        sourceAppURL: URL,
        targetAppURL: URL,
        mountPointURL: URL,
        workspaceURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            sourceAppURL.path,
            targetAppURL.path,
            mountPointURL.path,
            workspaceURL.path,
        ]

        try process.run()
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let output, !output.isEmpty {
                throw UpdatePreparationError.message(output)
            }

            throw UpdatePreparationError.message("Yamete couldn't finish the update.")
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

private enum UpdatePreparationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    var normalizedVersion: String {
        tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
    }

    var primaryDiskImageAsset: GitHubReleaseAsset? {
        assets.first(where: { $0.name.hasSuffix(".dmg") })
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct SemanticVersion: Comparable, Sendable {
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
