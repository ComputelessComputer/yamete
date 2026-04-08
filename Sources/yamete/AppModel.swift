import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isCheckingForUpdates = false
    @Published var statusMessage = "Checking Apple SPU sensor..."
    @Published private(set) var macSmackCount: Int {
        didSet { defaults.set(macSmackCount, forKey: Keys.macSmackCount) }
    }
    @Published private(set) var claudeWhipCount: Int {
        didSet { defaults.set(claudeWhipCount, forKey: Keys.claudeWhipCount) }
    }
    @Published var claudeWhipEnabled: Bool {
        didSet { defaults.set(claudeWhipEnabled, forKey: Keys.claudeWhipEnabled) }
    }
    @Published private(set) var backendState: MotionBackendState = .stopped("Checking Apple SPU sensor...")
    @Published private(set) var lastSeverity = "IDLE"

    private enum Keys {
        static let macSmackCount = "macSmackCount"
        static let claudeWhipCount = "claudeWhipCount"
        static let claudeWhipEnabled = "claudeWhipEnabled"
    }

    private static let defaultDetectionSettings = DetectionSettings(
        impactThreshold: 0.18,
        cooldown: 0.75,
        sampleRate: 100
    )
    private static let masterVolume = 0.9
    private static let dynamicVolume = true
    private static let flashScreen = true

    private let defaults: UserDefaults
    private let audioEngine = SpeechAudioEngine()
    private let flashController = FlashOverlayController()
    private let motionMonitor: MotionMonitor
    private var comboState = ComboState()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        macSmackCount = defaults.object(forKey: Keys.macSmackCount) as? Int ?? 0
        claudeWhipCount = defaults.object(forKey: Keys.claudeWhipCount) as? Int ?? 0
        claudeWhipEnabled = defaults.object(forKey: Keys.claudeWhipEnabled) as? Bool ?? false

        motionMonitor = MotionMonitor(settings: Self.defaultDetectionSettings)

        motionMonitor.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.applyBackendState(state)
            }
        }
        motionMonitor.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.applySnapshot(snapshot)
            }
        }
        motionMonitor.onImpact = { [weak self] event in
            Task { @MainActor in
                self?.handleImpact(event)
            }
        }

        restartMotionMonitor()
    }

    var menuBarTitle: String {
        "Yamete"
    }

    var backendMessage: String {
        backendState.description
    }

    var supportsLiveImpacts: Bool {
        backendState.supportsLiveCapture
    }

    var canRetrySensor: Bool {
        switch backendState {
        case .needsRoot, .failed:
            return true
        case .running, .stopped, .unavailable:
            return false
        }
    }

    func toggleListening() {
        isListening ? stopListening() : restartMotionMonitor()
    }

    func stopListening() {
        motionMonitor.stop()
    }

    func triggerTestSlap() {
        handleImpact(.init(timestamp: Date(), amplitude: 0.33, severity: "TEST"))
    }

    func resetCounts() {
        macSmackCount = 0
        claudeWhipCount = 0
        comboState = ComboState()
        statusMessage = "Counters reset."
    }

    func retrySensor() {
        restartMotionMonitor()
    }

    func whipClaudeNow() {
        applyClaudeWhipResult(ClaudeWhip.whip())
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        statusMessage = "Checking for updates..."

        let currentVersion = AppVersion.current

        Task {
            let result = await UpdateChecker.check(currentVersion: currentVersion)
            await MainActor.run {
                isCheckingForUpdates = false
                applyUpdateCheckResult(result)
            }
        }
    }

    private func restartMotionMonitor() {
        motionMonitor.update(settings: Self.defaultDetectionSettings)
        motionMonitor.start()
    }

    private func handleImpact(_ event: ImpactEvent) {
        macSmackCount += 1
        lastSeverity = event.severity
        statusMessage = "\(event.severity) impact at \(String(format: "%.3f", event.amplitude))g"

        _ = comboState.record(event.timestamp)
        if Self.flashScreen {
            flashController.flash()
        }

        audioEngine.play(
            amplitude: event.amplitude,
            masterVolume: Self.masterVolume,
            dynamicVolume: Self.dynamicVolume
        )

        if claudeWhipEnabled {
            applyClaudeWhipResult(ClaudeWhip.whip())
        }
    }

    private func applyBackendState(_ state: MotionBackendState) {
        backendState = state
        isListening = state.isRunning

        switch state {
        case .running:
            if macSmackCount == 0 {
                statusMessage = state.description
            }
        case .stopped, .needsRoot, .unavailable, .failed:
            statusMessage = state.description
        }
    }

    private func applySnapshot(_ snapshot: MotionSnapshot) {
        lastSeverity = snapshot.dynamicMagnitude >= Self.defaultDetectionSettings.impactThreshold ? "LIVE" : lastSeverity
    }

    private func applyClaudeWhipResult(_ result: ClaudeWhip.Result) {
        statusMessage = result.statusMessage

        switch result {
        case .whipped, .launched:
            claudeWhipCount += 1
        case .failed:
            break
        }
    }

    private func applyUpdateCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate(let version):
            statusMessage = "Yamete \(version) is up to date."
        case .updateAvailable(let update):
            statusMessage = "Update available: \(update.version)"
            NSWorkspace.shared.open(update.releaseURL)
        case .failed(let message):
            statusMessage = message
        }
    }
}

private struct ComboState {
    private let halfLife: TimeInterval = 30
    private var score: Double = 0
    private var lastImpact: Date?

    mutating func record(_ time: Date) -> Int {
        if let lastImpact {
            let elapsed = time.timeIntervalSince(lastImpact)
            score *= pow(0.5, elapsed / halfLife)
        }
        score += 1
        lastImpact = time

        switch score {
        case ..<2:
            return 0
        case ..<4:
            return 1
        case ..<7:
            return 2
        default:
            return 3
        }
    }
}
