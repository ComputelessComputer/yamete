import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenMoan")
                    .font(.headline)
                Text("Backend: \(model.backendLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.supportsLiveImpacts {
                backendNotice(message: model.backendMessage)
            }

            HStack(spacing: 12) {
                statCard(label: "Slaps", value: "\(model.slapCount)")
                statCard(label: "Amp", value: String(format: "%.3fg", model.lastAmplitude))
                statCard(label: "State", value: model.lastSeverity)
            }

            VStack(spacing: 8) {
                if model.supportsLiveImpacts {
                    Button(model.isListening ? "Stop Listening" : "Start Listening") {
                        model.toggleListening()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if model.supportsLiveImpacts {
                    Button("Test Slap") {
                        model.triggerTestSlap()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Preview Test Slap") {
                        model.triggerTestSlap()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Toggle(isOn: Binding(
                    get: { model.claudeWhipEnabled },
                    set: { model.claudeWhipEnabled = $0 }
                )) {
                    Label("Whip Claude", systemImage: "bolt.fill")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()

            Button("Settings") {
                openSettings()
            }

            Button("Reset Count") {
                model.resetCount()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func backendNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Real slap detection is off", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
