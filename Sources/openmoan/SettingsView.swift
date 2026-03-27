import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
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

            Section("Detection") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Minimum Amplitude")
                        Spacer()
                        Text(String(format: "%.3fg", model.minAmplitude))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.minAmplitude, in: 0.02...0.40)
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

                Text("If `spank` is installed, OpenMoan will try to use it. Otherwise the app stays in demo mode and the Test Slap button drives the preview.")
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
}
