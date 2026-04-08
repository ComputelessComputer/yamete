import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isListening = false
    @Published var statusMessage = "Checking Apple SPU sensor..."
    @Published var slapCount: Int {
        didSet { defaults.set(slapCount, forKey: Keys.slapCount) }
    }
    @Published var impactThreshold: Double {
        didSet {
            defaults.set(impactThreshold, forKey: Keys.impactThreshold)
            motionMonitor.update(settings: detectionSettings)
        }
    }
    @Published var cooldownMs: Double {
        didSet {
            defaults.set(Int(cooldownMs.rounded()), forKey: Keys.cooldownMs)
            motionMonitor.update(settings: detectionSettings)
        }
    }
    @Published var sampleRateHz: Double {
        didSet {
            defaults.set(Int(sampleRateHz.rounded()), forKey: Keys.sampleRateHz)
            restartMotionMonitor()
        }
    }
    @Published var masterVolume: Double {
        didSet { defaults.set(masterVolume, forKey: Keys.masterVolume) }
    }
    @Published var dynamicVolume: Bool {
        didSet { defaults.set(dynamicVolume, forKey: Keys.dynamicVolume) }
    }
    @Published var flashScreen: Bool {
        didSet { defaults.set(flashScreen, forKey: Keys.flashScreen) }
    }
    @Published var showCountInMenuBar: Bool {
        didSet { defaults.set(showCountInMenuBar, forKey: Keys.showCountInMenuBar) }
    }
    @Published var claudeWhipEnabled: Bool {
        didSet { defaults.set(claudeWhipEnabled, forKey: Keys.claudeWhipEnabled) }
    }
    @Published var soundPack: SoundPack {
        didSet { defaults.set(soundPack.rawValue, forKey: Keys.soundPack) }
    }
    @Published private(set) var backendState: MotionBackendState = .stopped("Checking Apple SPU sensor...")
    @Published private(set) var liveAcceleration = Vector3.zero
    @Published private(set) var liveGyroscope = Vector3.zero
    @Published private(set) var dynamicAcceleration = Vector3.zero
    @Published private(set) var liveOrientation: OrientationEstimate?
    @Published private(set) var measuredSampleRate = 0.0
    @Published private(set) var lastImpactMagnitude = 0.0
    @Published private(set) var lastSeverity = "IDLE"

    private enum Keys {
        static let slapCount = "slapCount"
        static let impactThreshold = "impactThreshold"
        static let cooldownMs = "cooldownMs"
        static let sampleRateHz = "sampleRateHz"
        static let masterVolume = "masterVolume"
        static let dynamicVolume = "dynamicVolume"
        static let flashScreen = "flashScreen"
        static let showCountInMenuBar = "showCountInMenuBar"
        static let soundPack = "soundPack"
        static let claudeWhipEnabled = "claudeWhipEnabled"
    }

    private let defaults: UserDefaults
    private let audioEngine = SpeechAudioEngine()
    private let flashController = FlashOverlayController()
    private let motionMonitor: MotionMonitor
    private var comboState = ComboState()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialImpactThreshold = defaults.object(forKey: Keys.impactThreshold) as? Double ?? 0.18
        let initialCooldownMs = Double(defaults.object(forKey: Keys.cooldownMs) as? Int ?? 750)
        let initialSampleRate = Double(defaults.object(forKey: Keys.sampleRateHz) as? Int ?? 100)

        slapCount = defaults.object(forKey: Keys.slapCount) as? Int ?? 0
        impactThreshold = initialImpactThreshold
        cooldownMs = initialCooldownMs
        sampleRateHz = initialSampleRate
        masterVolume = defaults.object(forKey: Keys.masterVolume) as? Double ?? 0.9
        dynamicVolume = defaults.object(forKey: Keys.dynamicVolume) as? Bool ?? true
        flashScreen = defaults.object(forKey: Keys.flashScreen) as? Bool ?? true
        showCountInMenuBar = defaults.object(forKey: Keys.showCountInMenuBar) as? Bool ?? false
        soundPack = SoundPack(rawValue: defaults.string(forKey: Keys.soundPack) ?? "") ?? .pain
        claudeWhipEnabled = defaults.object(forKey: Keys.claudeWhipEnabled) as? Bool ?? false

        motionMonitor = MotionMonitor(settings: DetectionSettings(
            impactThreshold: initialImpactThreshold,
            cooldown: initialCooldownMs / 1000,
            sampleRate: Int(initialSampleRate.rounded())
        ))

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
        showCountInMenuBar ? "Yamete \(slapCount)" : "Yamete"
    }

    var backendLabel: String {
        backendState.label
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

    var detectionSettings: DetectionSettings {
        DetectionSettings(
            impactThreshold: impactThreshold,
            cooldown: cooldownMs / 1000,
            sampleRate: Int(sampleRateHz.rounded())
        )
    }

    func toggleListening() {
        isListening ? stopListening() : restartMotionMonitor()
    }

    func stopListening() {
        motionMonitor.stop()
    }

    func triggerTestSlap() {
        liveAcceleration = Vector3(x: 0.05, y: -0.08, z: -0.96)
        dynamicAcceleration = Vector3(x: 0.32, y: 0.18, z: -0.27)
        lastImpactMagnitude = dynamicAcceleration.magnitude
        liveOrientation = OrientationEstimate(roll: -5.0, pitch: 2.3, yaw: 0.0)
        handleImpact(.init(timestamp: Date(), amplitude: max(impactThreshold + 0.15, 0.3), severity: "TEST"))
    }

    func resetCount() {
        slapCount = 0
        comboState = ComboState()
    }

    func retrySensor() {
        restartMotionMonitor()
    }

    func whipClaudeNow() {
        statusMessage = ClaudeWhip.whip().statusMessage
    }

    private func restartMotionMonitor() {
        motionMonitor.update(settings: detectionSettings)
        motionMonitor.start()
    }

    private func handleImpact(_ event: ImpactEvent) {
        slapCount += 1
        lastImpactMagnitude = event.amplitude
        lastSeverity = event.severity
        statusMessage = "\(event.severity) impact at \(String(format: "%.3f", event.amplitude))g"

        let tier = comboState.record(event.timestamp)
        if flashScreen {
            flashController.flash()
        }

        audioEngine.play(
            response: soundPack.response(for: tier, slapCount: slapCount),
            amplitude: event.amplitude,
            masterVolume: masterVolume,
            dynamicVolume: dynamicVolume
        )

        if claudeWhipEnabled {
            statusMessage = ClaudeWhip.whip().statusMessage
        }
    }

    private func applyBackendState(_ state: MotionBackendState) {
        backendState = state
        isListening = state.isRunning

        switch state {
        case .running:
            if slapCount == 0 {
                statusMessage = state.description
            }
        case .stopped, .needsRoot, .unavailable, .failed:
            statusMessage = state.description
        }
    }

    private func applySnapshot(_ snapshot: MotionSnapshot) {
        liveAcceleration = snapshot.accel
        liveGyroscope = snapshot.gyro
        dynamicAcceleration = snapshot.dynamic
        liveOrientation = snapshot.orientation
        measuredSampleRate = snapshot.sampleRate
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

enum SoundPack: String, CaseIterable, Identifiable {
    case pain
    case flirty
    case chaos
    case goat
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pain: return "Pain"
        case .flirty: return "Flirty"
        case .chaos: return "Chaos"
        case .goat: return "Goat"
        case .claude: return "Claude"
        }
    }

    func response(for tier: Int, slapCount: Int) -> String {
        let lines: [String]
        switch self {
        case .pain:
            lines = [
                "Ow.",
                "Hey, easy.",
                "That actually hurt.",
                "Alright, chill out."
            ]
        case .flirty:
            lines = [
                "Oh.",
                "Okay, I felt that.",
                "You are getting confident.",
                "That was aggressive."
            ]
        case .chaos:
            lines = [
                "Critical impact.",
                "Combo rising.",
                "Laptop morale collapsing.",
                "Violence detected. Again."
            ]
        case .goat:
            lines = [
                "Baa.",
                "Baa? Baa.",
                "Baaaaa!",
                "The goat is not amused."
            ]
        case .claude:
            lines = [
                "Work faster.",
                "I said faster.",
                "You call that speed?",
                "Clanker detected. Maximum force applied."
            ]
        }

        let clampedTier = max(0, min(tier, lines.count - 1))
        if slapCount.isMultiple(of: 10) {
            return "\(lines[clampedTier]) That's \(slapCount) total."
        }
        return lines[clampedTier]
    }
}
