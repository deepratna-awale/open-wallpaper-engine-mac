import AppKit
import SwiftUI

/// The settings window's tabs, in toolbar order. The raw value is the tab's position, which
/// `UpdateRelaunchState` saves across an update relaunch.
enum SettingsTab: Int, CaseIterable, Identifiable {
    case general, performance, optimizations, assets, updates, privacy, permissions, diagnostics, plugins, about

    var id: Self { self }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue: String(describing: self))
    }

    init?(toolbarIdentifier: NSToolbarItem.Identifier) {
        guard let tab = Self.allCases.first(where: { $0.toolbarIdentifier == toolbarIdentifier }) else { return nil }
        self = tab
    }

    var title: LocalizedStringResource {
        switch self {
        case .general: return "General"
        case .performance: return "Performance"
        case .optimizations: return "Optimizations"
        case .assets: return "Assets"
        case .updates: return "Updates"
        case .privacy: return "Privacy"
        case .permissions: return "Permissions"
        case .diagnostics: return "Diagnostics"
        case .plugins: return "Plugins"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .performance: return "speedometer"
        case .optimizations: return "slider.horizontal.3"
        case .assets: return "shippingbox"
        case .updates: return "arrow.down.circle"
        case .privacy: return "hand.raised"
        case .permissions: return "lock.shield"
        case .diagnostics: return "stethoscope"
        case .plugins: return "puzzlepiece.extension"
        case .about: return "person.3"
        }
    }

    /// The global settings this tab shows, for "Restore Defaults" and the changed-from-default dots.
    /// A setting belongs to one tab. Settings stored outside `GlobalSettings` (Sparkle's, the
    /// plugins') are reset by `SettingsTabReset`.
    var fields: [SettingField] {
        switch self {
        case .general:
            return [SettingField(\.autoStart), SettingField(\.language), SettingField(\.appearance),
                    SettingField(\.adjustMenuBarTint)]
        case .performance:
            return [SettingField(\.otherApplicationFocused), SettingField(\.otherApplicationMaximized),
                    SettingField(\.otherApplicationFullscreen), SettingField(\.otherApplicationPlayingAudio),
                    SettingField(\.displayAsleep), SettingField(\.laptopOnBattery),
                    SettingField(\.antiAliasing), SettingField(\.postProcessing), SettingField(\.textureResolution),
                    SettingField(\.sceneDetail), SettingField(\.renderResolution), SettingField(\.shadows),
                    SettingField(\.volumetrics), SettingField(\.fps), SettingField(\.particleBudget),
                    SettingField(\.reflections)]
        case .optimizations:
            return [SettingField(\.syncPropertiesAcrossDisplays), SettingField(\.videoFramework),
                    SettingField(\.audioOutput), SettingField(\.reloadWhenChangingOutputDevice),
                    SettingField(\.mediaIntegration), SettingField(\.processPiority),
                    SettingField(\.pauseOnVRAMExhausted), SettingField(\.restartAfterCrashing)]
        case .diagnostics:
            return [SettingField(\.logLevel)]
        case .assets, .updates, .privacy, .permissions, .plugins, .about:
            return []
        }
    }

    /// Whether the tab has anything "Restore Defaults" can reset.
    var isResettable: Bool {
        !fields.isEmpty || !SettingsTabReset.preferenceKeys(of: self).isEmpty
    }

    /// `settings` with this tab's settings back at their defaults and every other setting kept.
    func resetting(_ settings: GlobalSettings) -> GlobalSettings {
        var reset = settings
        let defaults = GlobalSettings()
        for field in fields { field.reset(&reset, defaults) }
        return reset
    }
}

/// One setting of `GlobalSettings`: whether it differs from its default, and how to put it back.
struct SettingField {
    let isChanged: (GlobalSettings) -> Bool
    let reset: (inout GlobalSettings, GlobalSettings) -> Void

    init<Value: Equatable>(_ keyPath: WritableKeyPath<GlobalSettings, Value>) {
        isChanged = { $0[keyPath: keyPath] != GlobalSettings()[keyPath: keyPath] }
        reset = { settings, defaults in settings[keyPath: keyPath] = defaults[keyPath: keyPath] }
    }
}
