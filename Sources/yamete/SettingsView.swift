import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Live Motion") {
                VStack(alignment: .leading, spacing: 6) {
                    statusLabel

                    Text(model.backendMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Sample Rate", selection: $model.sampleRateHz) {
                    Text("50 Hz").tag(50.0)
                    Text("100 Hz").tag(100.0)
                    Text("200 Hz").tag(200.0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Impact Threshold")
                        Spacer()
                        Text(String(format: "%.3fg", model.impactThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.impactThreshold, in: 0.08...0.80)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cooldown")
                        Spacer()
                        Text("\(Int(model.cooldownMs)) ms")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.cooldownMs, in: 150...1500, step: 50)
                }
            }

            Section("Sound") {
                Picker("Pack", selection: $model.soundPack) {
                    ForEach(SoundPack.allCases) { pack in
                        Text(pack.title).tag(pack)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Master Volume")
                        Spacer()
                        Text("\(Int(model.masterVolume * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.masterVolume, in: 0.1...1.0)
                }

                Toggle("Scale volume by impact", isOn: $model.dynamicVolume)
                Toggle("Flash the screen on impact", isOn: $model.flashScreen)
            }

            Section("Claude Code") {
                Toggle("Whip Claude Code on impact", isOn: $model.claudeWhipEnabled)
                Text("Sends Ctrl+C and an encouraging message to Claude Code when you slap your laptop. If Claude Code isn't running, opens Ghostty and launches it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Menu Bar") {
                Toggle("Show slap count in menu bar title", isOn: $model.showCountInMenuBar)
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }

    private var statusLabel: some View {
        let systemImage: String
        let tint: Color
        let title: String

        switch model.backendState {
        case .running:
            systemImage = "waveform.path.ecg"
            tint = .green
            title = "Apple SPU stream is live."
        case .stopped:
            systemImage = "pause.circle.fill"
            tint = .secondary
            title = "Apple SPU stream is stopped."
        case .needsRoot:
            systemImage = "lock.fill"
            tint = .orange
            title = "Root access is required for live capture."
        case .unavailable:
            systemImage = "xmark.circle.fill"
            tint = .orange
            title = "This Mac does not expose the Apple SPU IMU."
        case .failed:
            systemImage = "exclamationmark.triangle.fill"
            tint = .red
            title = "The sensor backend failed to start."
        }

        return Label(title, systemImage: systemImage)
            .foregroundStyle(tint)
    }
}
