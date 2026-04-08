import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isListening = false
    @Published var statusMessage = "Starting detector..."
    @Published var slapCount: Int {
        didSet { defaults.set(slapCount, forKey: Keys.slapCount) }
    }
    @Published var minAmplitude: Double {
        didSet {
            defaults.set(minAmplitude, forKey: Keys.minAmplitude)
            restartDetector()
        }
    }
    @Published var cooldownMs: Double {
        didSet {
            defaults.set(Int(cooldownMs.rounded()), forKey: Keys.cooldownMs)
            restartDetector()
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
    @Published private(set) var backendLabel = "Demo Preview"
    @Published private(set) var backendMessage = "Checking detector..."
    @Published private(set) var supportsLiveImpacts = false
    @Published var lastAmplitude: Double = 0
    @Published var lastSeverity = "idle"

    private enum Keys {
        static let slapCount = "slapCount"
        static let minAmplitude = "minAmplitude"
        static let cooldownMs = "cooldownMs"
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
    private var detector: ImpactDetector?
    private var comboState = ComboState()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        slapCount = defaults.object(forKey: Keys.slapCount) as? Int ?? 0
        minAmplitude = defaults.object(forKey: Keys.minAmplitude) as? Double ?? 0.05
        cooldownMs = Double(defaults.object(forKey: Keys.cooldownMs) as? Int ?? 750)
        masterVolume = defaults.object(forKey: Keys.masterVolume) as? Double ?? 0.9
        dynamicVolume = defaults.object(forKey: Keys.dynamicVolume) as? Bool ?? true
        flashScreen = defaults.object(forKey: Keys.flashScreen) as? Bool ?? true
        showCountInMenuBar = defaults.object(forKey: Keys.showCountInMenuBar) as? Bool ?? false
        soundPack = SoundPack(rawValue: defaults.string(forKey: Keys.soundPack) ?? "") ?? .pain
        claudeWhipEnabled = defaults.object(forKey: Keys.claudeWhipEnabled) as? Bool ?? false

        configureDetector()
        restartDetector()
    }

    var menuBarTitle: String {
        showCountInMenuBar ? "Yamete \(slapCount)" : "Yamete"
    }

    var detectorSettings: DetectorSettings {
        DetectorSettings(
            minAmplitude: minAmplitude,
            cooldownMs: Int(cooldownMs.rounded())
        )
    }

    func toggleListening() {
        isListening ? stopListening() : restartDetector()
    }

    func stopListening() {
        detector?.stop()
        isListening = false
        statusMessage = "Detector stopped"
    }

    func triggerTestSlap() {
        handleImpact(.init(timestamp: Date(), amplitude: max(minAmplitude + 0.15, 0.2), severity: "TEST"))
    }

    func resetCount() {
        slapCount = 0
        comboState = ComboState()
    }

    private func configureDetector() {
        if let binary = SpankBridgeDetector.locateBinary() {
            let bridge = SpankBridgeDetector(binaryURL: binary)
            bridge.onEvent = { [weak self] event in
                Task { @MainActor in
                    self?.handleImpact(event)
                }
            }
            bridge.onStatus = { [weak self] message in
                Task { @MainActor in
                    self?.statusMessage = message
                }
            }
            detector = bridge
            backendLabel = "spank"
            if SpankBridgeDetector.isBundledBinary(binary) {
                backendMessage = "Using the bundled spank detector for real laptop hits."
            } else {
                backendMessage = "Using the installed spank detector for real laptop hits."
            }
            supportsLiveImpacts = true
            return
        }

        let demo = DemoDetector()
        demo.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleImpact(event)
            }
        }
        demo.onStatus = { [weak self] message in
            Task { @MainActor in
                self?.statusMessage = message
            }
        }
        detector = demo
        backendLabel = "Demo Preview"
        backendMessage = "Install spank to react to real laptop hits. Until then, only Preview Test Slap works."
        supportsLiveImpacts = false
    }

    private func restartDetector() {
        detector?.stop()
        detector?.start(settings: detectorSettings)
        isListening = true
    }

    private func handleImpact(_ event: ImpactEvent) {
        slapCount += 1
        lastAmplitude = event.amplitude
        lastSeverity = event.severity
        statusMessage = "\(event.severity) at \(String(format: "%.3f", event.amplitude))g"

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
            ClaudeWhip.whip()
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
