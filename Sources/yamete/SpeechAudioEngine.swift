import AppKit
import AVFoundation
import CoreAudio
import Foundation

@MainActor
final class SpeechAudioEngine: NSObject, AVAudioPlayerDelegate {
    private var routedPlayer: AVAudioPlayer?
    private let soundLibrary = SoundLibrary()

    func play(amplitude: Double, masterVolume: Double, dynamicVolume: Bool) {
        let volume = dynamicVolume ? scaledVolume(for: amplitude, masterVolume: masterVolume) : masterVolume
        stopCurrentPlayback()

        guard let soundURL = soundLibrary.randomSoundURL() else { return }
        playSound(from: soundURL, volume: Float(volume), deviceUID: PreferredAudioOutputSelector.preferredPersonalAudioDeviceUID())
    }

    private func scaledVolume(for amplitude: Double, masterVolume: Double) -> Double {
        let minAmplitude = 0.05
        let maxAmplitude = 0.8
        let clamped = min(max(amplitude, minAmplitude), maxAmplitude)
        let normalized = (clamped - minAmplitude) / (maxAmplitude - minAmplitude)
        let curved = log(1 + normalized * 99) / log(100)
        return min(max(masterVolume * (0.35 + curved * 0.65), 0), 1)
    }

    private func playSound(from url: URL, volume: Float, deviceUID: String?) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = volume
            player.currentDevice = deviceUID
            player.prepareToPlay()

            if player.play() {
                routedPlayer = player
                return
            }
        } catch {
            return
        }
    }

    private func stopCurrentPlayback() {
        routedPlayer?.stop()
        routedPlayer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedURL = player.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.routedPlayer?.url == finishedURL {
                self.routedPlayer = nil
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

private struct SoundLibrary {
    private let soundURLs: [URL]

    init(bundle: Bundle = .module) {
        let candidates = [
            "yamete-kudasai",
            "haang",
            "anime-moan",
            "dame-dame",
        ]

        self.soundURLs = candidates.compactMap { name in
            bundle.url(forResource: name, withExtension: "mp3", subdirectory: "Audio")
                ?? Bundle.main.url(forResource: name, withExtension: "mp3")
                ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Audio")
        }
    }

    func randomSoundURL() -> URL? {
        soundURLs.randomElement()
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
