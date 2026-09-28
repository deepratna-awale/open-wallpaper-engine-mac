import SwiftUI

/// Settings › Updates: Sparkle's preferences and the beta channel.
struct UpdatesSection: View {
    @ObservedObject var updater: AppUpdater
    @AppStorage(WhatsNew.hidesReleaseNotesKey, store: .app) private var hidesReleaseNotes = false

    var body: some View {
        Section {
            if updater.isEnabled {
                Toggle("Update automatically", isOn: $updater.updatesAutomatically)
                if !updater.updatesAutomatically {
                    Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                }
                Toggle("Receive beta updates", isOn: $updater.receivesBetaUpdates)
                HStack {
                    if let date = updater.lastUpdateCheckDate {
                        Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))",
                             comment: "%@ is a date and time")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never checked")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } else {
                Text("Updates are off in this build because it has no update signing key. Builds from GitHub Releases update themselves.")
                    .foregroundStyle(.secondary)
            }
            Toggle("Don't show release notes", isOn: $hidesReleaseNotes)
        } header: {
            Label("Updates", systemImage: "arrow.down.circle")
        } footer: {
            Text("Open Wallpaper Engine checks GitHub for new versions: the update list on GitHub Pages and the downloads on GitHub Releases. No personal data is sent. Automatic updates install when you quit, when you're away from your Mac, or within a day.")
        }
    }
}
