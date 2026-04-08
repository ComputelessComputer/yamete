import Foundation

struct DetectorSettings: Sendable {
    let minAmplitude: Double
    let cooldownMs: Int
}

struct ImpactEvent: Sendable {
    let timestamp: Date
    let amplitude: Double
    let severity: String
}

protocol ImpactDetector: AnyObject {
    var onEvent: (@Sendable (ImpactEvent) -> Void)? { get set }
    var onStatus: (@Sendable (String) -> Void)? { get set }
    func start(settings: DetectorSettings)
    func stop()
}

final class DemoDetector: ImpactDetector, @unchecked Sendable {
    var onEvent: (@Sendable (ImpactEvent) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?

    func start(settings: DetectorSettings) {
        onStatus?("Demo preview only. Install spank for real laptop hit detection. Use Preview Test Slap to verify responses.")
    }

    func stop() {
        onStatus?("Demo preview stopped")
    }
}

final class SpankBridgeDetector: ImpactDetector, @unchecked Sendable {
    var onEvent: (@Sendable (ImpactEvent) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?

    private let binaryURL: URL
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    init(binaryURL: URL) {
        self.binaryURL = binaryURL
    }

    func start(settings: DetectorSettings) {
        stop()

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "--stdio",
            "--min-amplitude", String(format: "%.4f", settings.minAmplitude),
            "--cooldown", "\(settings.cooldownMs)",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStdErr: false)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStdErr: true)
        }

        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] process in
            self?.onStatus?("spank exited with code \(process.terminationStatus). It usually needs root privileges.")
        }

        do {
            try process.run()
            self.process = process
            stdoutPipe = stdout
            stderrPipe = stderr
            onStatus?("Launching spank backend...")
        } catch {
            onStatus?("Failed to launch spank: \(error.localizedDescription)")
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
    }

    private func consume(_ data: Data, isStdErr: Bool) {
        guard !data.isEmpty else { return }

        if isStdErr {
            stderrBuffer.append(data)
            drainLines(buffer: &stderrBuffer, isStdErr: true)
        } else {
            stdoutBuffer.append(data)
            drainLines(buffer: &stdoutBuffer, isStdErr: false)
        }
    }

    private func drainLines(buffer: inout Data, isStdErr: Bool) {
        let newline = Data([0x0A])

        while let range = buffer.range(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else {
                continue
            }

            if isStdErr {
                onStatus?(line)
                continue
            }

            if line.first == "{", let event = parseEvent(line) {
                onEvent?(event)
            } else if line.contains("\"status\":\"ready\"") {
                onStatus?("spank is listening")
            } else {
                onStatus?(line)
            }
        }
    }

    private func parseEvent(_ line: String) -> ImpactEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let amplitude = json["amplitude"] as? Double else {
            return nil
        }

        let severity = json["severity"] as? String ?? "SLAP"
        return ImpactEvent(
            timestamp: Date(),
            amplitude: amplitude,
            severity: severity
        )
    }

    static func locateBinary() -> URL? {
        if let bundledPath = bundledBinaryPath(),
           FileManager.default.isExecutableFile(atPath: bundledPath.path) {
            return bundledPath
        }

        var directPaths = [
            "/opt/homebrew/bin/spank",
            "/usr/local/bin/spank",
            "/usr/bin/spank",
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            directPaths.insert("\(home)/go/bin/spank", at: 0)
        }

        for path in directPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["spank"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, !output.isEmpty else { return nil }
            return URL(fileURLWithPath: output)
        } catch {
            return nil
        }
    }

    static func isBundledBinary(_ url: URL) -> Bool {
        guard let bundledPath = bundledBinaryPath() else { return false }
        return url.standardizedFileURL == bundledPath.standardizedFileURL
    }

    private static func bundledBinaryPath() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("spank", isDirectory: false)
    }
}
