import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater: UpdaterService

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)

                HStack {
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
