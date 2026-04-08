import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            Section {
                Text("Mac smacks: \(model.macSmackCount)")
                Text("Claude whips: \(model.claudeWhipCount)")
                Text(model.statusMessage)
            } header: {
                Text("Counts")
            }

            Section {
                if model.supportsLiveImpacts {
                    Button(model.isListening ? "Stop Listening" : "Start Listening") {
                        model.toggleListening()
                    }
                }

                if model.canRetrySensor {
                    Button("Retry Sensor") {
                        model.retrySensor()
                    }
                }

                Button(model.supportsLiveImpacts ? "Test Smack" : "Test Yamete") {
                    model.triggerTestSlap()
                }

                Toggle(isOn: Binding(
                    get: { model.claudeWhipEnabled },
                    set: { model.claudeWhipEnabled = $0 }
                )) {
                    Text("Auto-whip Claude")
                }

                Button("Whip Claude Now") {
                    model.whipClaudeNow()
                }
            } header: {
                Text("Actions")
            }

            Section {
                Button("Reset Counts") {
                    model.resetCounts()
                }

                Button("Quit Yamete") {
                    NSApplication.shared.terminate(nil)
                }
            } header: {
                Text("App")
            }
        }
    }
}
