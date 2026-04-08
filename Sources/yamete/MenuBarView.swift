import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Yamete")
                    .font(.headline)
                Text("Backend: \(model.backendLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .needsRoot = model.backendState {
                backendNotice(title: "Root required", message: model.backendMessage, tint: .orange)
            } else if case .unavailable = model.backendState {
                backendNotice(title: "Live sensor unavailable", message: model.backendMessage, tint: .orange)
            } else if case .failed = model.backendState {
                backendNotice(title: "Sensor startup failed", message: model.backendMessage, tint: .red)
            } else if !model.supportsLiveImpacts {
                backendNotice(message: model.backendMessage)
            }

            HStack(spacing: 12) {
                statCard(label: "Impacts", value: "\(model.slapCount)")
                statCard(label: "Dynamic", value: String(format: "%.3fg", model.lastImpactMagnitude))
                statCard(label: "Rate", value: "\(Int(model.measuredSampleRate.rounded())) Hz")
            }

            VStack(alignment: .leading, spacing: 10) {
                metricRow(label: "Accel", value: triplet(model.liveAcceleration))
                metricRow(label: "Gyro", value: triplet(model.liveGyroscope))
                metricRow(label: "Dynamic", value: triplet(model.dynamicAcceleration))
                metricRow(label: "State", value: model.lastSeverity)
                metricRow(label: "Euler", value: orientation(model.liveOrientation))
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 8) {
                if model.supportsLiveImpacts {
                    Button(model.isListening ? "Stop Listening" : "Start Listening") {
                        model.toggleListening()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if model.canRetrySensor {
                    Button("Retry Sensor") {
                        model.retrySensor()
                    }
                    .buttonStyle(.bordered)
                }

                if model.supportsLiveImpacts {
                    Button("Preview Test Slap") {
                        model.triggerTestSlap()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Test Yamete") {
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

                Button("Whip Claude Now") {
                    model.whipClaudeNow()
                }
                .buttonStyle(.bordered)
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
        .frame(width: 340)
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

    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }

    private func backendNotice(message: String) -> some View {
        backendNotice(title: "Live motion capture is off", message: message, tint: .orange)
    }

    private func backendNotice(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func triplet(_ vector: Vector3) -> String {
        String(format: "%.3f  %.3f  %.3f", vector.x, vector.y, vector.z)
    }

    private func orientation(_ estimate: OrientationEstimate?) -> String {
        guard let estimate else {
            return "Calibrating"
        }

        return String(format: "%.1f°  %.1f°  %.1f°", estimate.roll, estimate.pitch, estimate.yaw)
    }
}
