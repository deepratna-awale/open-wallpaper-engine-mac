import Foundation

/// "Restore Defaults" for one settings tab: its global settings (`SettingsTab.fields`) and the
/// preferences it shows that are stored outside them.
@MainActor
enum SettingsTabReset {
    /// The `UserDefaults.app` preferences a tab shows, removed on reset so they read as default.
    /// (`WhatsNew.hidesReleaseNotesKey` and `AppUpdater.receivesBetaUpdatesKey` for Updates.)
    nonisolated static func preferenceKeys(of tab: SettingsTab) -> [String] {
        switch tab {
        case .optimizations: return ["ReclaimOriginalPackages"]
        case .updates: return ["HidesReleaseNotesAfterUpdate", "ReceiveBetaUpdates"]
        case .plugins: return ["TestAnimates"]
        default: return []
        }
    }

    /// Resets `tab` in `viewModel` and `defaults`. Updates also go back to updating
    /// automatically, as a new install does.
    static func reset(_ tab: SettingsTab, viewModel: GlobalSettingsViewModel, defaults: UserDefaults,
                      updater: AppUpdater?) {
        let reset = tab.resetting(viewModel.settings)
        if reset != viewModel.settings { viewModel.settings = reset }
        for key in preferenceKeys(of: tab) { defaults.removeObject(forKey: key) }
        if tab == .updates, let updater, updater.isEnabled {
            updater.automaticallyChecksForUpdates = true
            updater.updatesAutomatically = true
            updater.objectWillChange.send()
        }
    }

    /// Whether anything `tab` shows differs from its default.
    static func hasChanges(_ tab: SettingsTab, settings: GlobalSettings, defaults: UserDefaults) -> Bool {
        tab.fields.contains { $0.isChanged(settings) }
            || preferenceKeys(of: tab).contains { defaults.object(forKey: $0) != nil }
    }
}
