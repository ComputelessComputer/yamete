import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            Section {
                Text("Mac smacks: \(model.macSmackCount)")
                Text("Claude whips: \(model.claudeWhipCount)")
            } header: {
                Text("Counts")
            }

            Section {
                Button(model.isCheckingForUpdates ? "Checking for Updates..." : "Check for Updates") {
                    model.checkForUpdates()
                }
                .disabled(model.isCheckingForUpdates)

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
