import AppKit
import AVFoundation
import CoreAudio
import Foundation

@MainActor
final class SpeechAudioEngine: NSObject, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var routedPlayer: AVAudioPlayer?
    private var renderSynthesizer: AVSpeechSynthesizer?
    private var activeRenderURL: URL?
    private var playbackToken = UUID()

    func play(response: String, amplitude: Double, masterVolume: Double, dynamicVolume: Bool) {
        let volume = dynamicVolume ? scaledVolume(for: amplitude, masterVolume: masterVolume) : masterVolume
        stopCurrentPlayback()

        if let deviceUID = PreferredAudioOutputSelector.preferredPersonalAudioDeviceUID() {
            playRenderedSpeech(response: response, volume: Float(volume), deviceUID: deviceUID)
        } else {
            speakDirectly(response: response, volume: Float(volume))
        }
    }

    private func scaledVolume(for amplitude: Double, masterVolume: Double) -> Double {
        let minAmplitude = 0.05
        let maxAmplitude = 0.8
        let clamped = min(max(amplitude, minAmplitude), maxAmplitude)
        let normalized = (clamped - minAmplitude) / (maxAmplitude - minAmplitude)
        let curved = log(1 + normalized * 99) / log(100)
        return min(max(masterVolume * (0.35 + curved * 0.65), 0), 1)
    }

    private func speakDirectly(response: String, volume: Float) {
        let utterance = AVSpeechUtterance(string: response)
        utterance.rate = 0.46
        utterance.volume = volume
        synthesizer.speak(utterance)
    }

    private func playRenderedSpeech(response: String, volume: Float, deviceUID: String) {
        let token = UUID()
        playbackToken = token

        let renderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yamete-\(token.uuidString)")
            .appendingPathExtension("caf")
        activeRenderURL = renderURL

        let renderSink = SpeechRenderSink(fileURL: renderURL)
        let renderSynthesizer = AVSpeechSynthesizer()
        self.renderSynthesizer = renderSynthesizer

        let utterance = AVSpeechUtterance(string: response)
        utterance.rate = 0.46
        utterance.volume = 1.0

        renderSynthesizer.write(utterance) { [weak self] buffer in
            guard let self else { return }

            if let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 {
                do {
                    try renderSink.append(pcmBuffer)
                } catch {
                    DispatchQueue.main.async {
                        self.finishRenderedSpeech(
                            token: token,
                            response: response,
                            volume: volume,
                            deviceUID: nil,
                            renderURL: nil
                        )
                    }
                }
                return
            }

            DispatchQueue.main.async {
                self.finishRenderedSpeech(
                    token: token,
                    response: response,
                    volume: volume,
                    deviceUID: deviceUID,
                    renderURL: renderSink.hasWrittenFrames ? renderURL : nil
                )
            }
        }
    }

    private func finishRenderedSpeech(
        token: UUID,
        response: String,
        volume: Float,
        deviceUID: String?,
        renderURL: URL?
    ) {
        guard playbackToken == token else {
            cleanupRenderFile(renderURL)
            return
        }

        renderSynthesizer = nil

        guard let renderURL else {
            speakDirectly(response: response, volume: volume)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: renderURL)
            player.delegate = self
            player.volume = volume
            player.currentDevice = deviceUID
            player.prepareToPlay()

            if player.play() {
                routedPlayer = player
                return
            }
        } catch {
            // Fall back to the current system output device if app-local routing fails.
        }

        cleanupRenderFile(renderURL)
        speakDirectly(response: response, volume: volume)
    }

    private func stopCurrentPlayback() {
        synthesizer.stopSpeaking(at: .immediate)
        renderSynthesizer?.stopSpeaking(at: .immediate)
        renderSynthesizer = nil
        routedPlayer?.stop()
        routedPlayer = nil
        cleanupRenderFile(activeRenderURL)
        activeRenderURL = nil
    }

    private func cleanupRenderFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
        if activeRenderURL == url {
            activeRenderURL = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedURL = player.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.routedPlayer?.url == finishedURL {
                self.routedPlayer = nil
                self.cleanupRenderFile(self.activeRenderURL)
            }
        }
    }
}

@MainActor
final class FlashOverlayController {
    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    func flash() {
        guard let screen = NSScreen.main else { return }

        if window == nil {
            let panel = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.isOpaque = false
            panel.backgroundColor = NSColor.white.withAlphaComponent(0.16)
            panel.level = .screenSaver
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window = panel
        }

        window?.setFrame(screen.frame, display: true)
        window?.alphaValue = 1
        window?.orderFrontRegardless()

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }
}

private final class SpeechRenderSink: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var wroteFrames = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }

        if audioFile == nil {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: buffer.format.settings)
        }

        try audioFile?.write(from: buffer)
        wroteFrames = true
    }

    var hasWrittenFrames: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wroteFrames
    }
}

private struct PreferredAudioOutputSelector {
    static func preferredPersonalAudioDeviceUID() -> String? {
        let devices = availableOutputDevices()

        if let preferredDefault = devices.first(where: { $0.isDefault && $0.isPersonalAudio }) {
            return preferredDefault.uid
        }

        if let preferred = devices.first(where: \.isPersonalAudio) {
            return preferred.uid
        }

        return nil
    }

    private static func availableOutputDevices() -> [OutputDevice] {
        let defaultOutputID = deviceIDProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )

        return deviceIDs().compactMap { deviceID in
            guard isAlive(deviceID), hasOutputStreams(deviceID) else {
                return nil
            }

            guard let uid = stringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            let name = stringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            ) else {
                return nil
            }

            let transportType = uint32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyTransportType,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? kAudioDeviceTransportTypeUnknown

            return OutputDevice(
                id: deviceID,
                uid: uid,
                name: name,
                transportType: transportType,
                isDefault: deviceID == defaultOutputID
            )
        }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func isAlive(_ deviceID: AudioDeviceID) -> Bool {
        let alive = uint32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal
        )

        return alive == 1
    }

    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        return dataSize >= UInt32(MemoryLayout<AudioObjectID>.size)
    }

    private static func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32.zero
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }

        return value
    }

    private static func deviceIDProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioDeviceID.zero
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }

        return value
    }

    private static func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr,
              let value else {
            return nil
        }

        return value.takeRetainedValue() as String
    }
}

private struct OutputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let isDefault: Bool

    var isPersonalAudio: Bool {
        let lowered = name.lowercased()
        let personalKeywords = [
            "airpods",
            "earpods",
            "earbuds",
            "headphones",
            "headset",
            "beats",
            "buds",
        ]
        let nonPersonalKeywords = [
            "speaker",
            "monitor",
            "display",
            "tv",
            "homepod",
        ]

        if personalKeywords.contains(where: lowered.contains) {
            return true
        }

        if nonPersonalKeywords.contains(where: lowered.contains) {
            return false
        }

        return transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
}
