import AppKit
import AVFoundation
import Foundation

@MainActor
final class SpeechAudioEngine {
    private let synthesizer = AVSpeechSynthesizer()

    func play(response: String, amplitude: Double, masterVolume: Double, dynamicVolume: Bool) {
        let volume = dynamicVolume ? scaledVolume(for: amplitude, masterVolume: masterVolume) : masterVolume
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: response)
        utterance.rate = 0.46
        utterance.volume = Float(volume)
        synthesizer.speak(utterance)
    }

    private func scaledVolume(for amplitude: Double, masterVolume: Double) -> Double {
        let minAmplitude = 0.05
        let maxAmplitude = 0.8
        let clamped = min(max(amplitude, minAmplitude), maxAmplitude)
        let normalized = (clamped - minAmplitude) / (maxAmplitude - minAmplitude)
        let curved = log(1 + normalized * 99) / log(100)
        return min(max(masterVolume * (0.35 + curved * 0.65), 0), 1)
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
