import AppKit
import AVFoundation
import Foundation

@MainActor
final class SpeechAudioEngine: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private let soundLibrary = SoundLibrary()

    func play(amplitude: Double, masterVolume: Double, dynamicVolume: Bool) {
        let volume = dynamicVolume ? scaledVolume(for: amplitude, masterVolume: masterVolume) : masterVolume
        stopCurrentPlayback()

        guard let soundURL = soundLibrary.randomSoundURL() else { return }
        playSound(from: soundURL, volume: Float(volume))
    }

    private func scaledVolume(for amplitude: Double, masterVolume: Double) -> Double {
        let minAmplitude = 0.05
        let maxAmplitude = 0.8
        let clamped = min(max(amplitude, minAmplitude), maxAmplitude)
        let normalized = (clamped - minAmplitude) / (maxAmplitude - minAmplitude)
        let curved = log(1 + normalized * 99) / log(100)
        return min(max(masterVolume * (0.35 + curved * 0.65), 0), 1)
    }

    private func playSound(from url: URL, volume: Float) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = volume
            player.prepareToPlay()

            if player.play() {
                self.player = player
                return
            }
        } catch {
            return
        }
    }

    private func stopCurrentPlayback() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedURL = player.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.player?.url == finishedURL {
                self.player = nil
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

private struct SoundLibrary {
    private let soundURLs: [URL]

    init(bundle: Bundle = .module) {
        let candidates = [
            "yamete-kudasai",
            "haang",
            "anime-moan",
            "dame-dame",
        ]
        let bundles = [bundle, Bundle.main]

        self.soundURLs = candidates.compactMap { name in
            for bundle in bundles {
                if let url = bundle.url(forResource: name, withExtension: "mp3") {
                    return url
                }
                if let url = bundle.url(forResource: name, withExtension: "mp3", subdirectory: "Audio") {
                    return url
                }
            }

            return nil
        }
    }

    func randomSoundURL() -> URL? {
        soundURLs.randomElement()
    }
}
