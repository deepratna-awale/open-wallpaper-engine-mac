import AppKit

/// What reading stored settings needs to carry an earlier Render Resolution over, handed to the
/// decoder in `userInfo[.settingsMigration]`, and whether it did. Without it the migration
/// assumes a 1× display.
final class GlobalSettingsMigration {
    /// The main display's backing scale when the settings are read (2 on Retina).
    let mainBackingScale: Double
    /// The settings read held the points-based Render Resolution ("display", "desktop") and were
    /// carried over (`GlobalSettings.migrateFromPoints`), or there were none and the first ones
    /// were set up for the display (`GlobalSettings.firstLaunch`): save them, so it happens once.
    var migrated = false

    init(mainBackingScale: Double) {
        self.mainBackingScale = mainBackingScale
    }

    /// For the main display now: the one with the menu bar.
    @MainActor static func current() -> GlobalSettingsMigration {
        GlobalSettingsMigration(mainBackingScale: Double(NSScreen.screens.first?.backingScaleFactor ?? 1))
    }

    /// A decoder that carries `self` over.
    func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsMigration] = self
        return decoder
    }
}

extension CodingUserInfoKey {
    /// `GlobalSettingsMigration` for `GlobalSettings.init(from:)`.
    static let settingsMigration = CodingUserInfoKey(rawValue: "app.openwallpaperengine.settingsMigration")!
}

extension GlobalSettings {
    /// The settings of a first launch, for a main display of `backingScale`: Your Display, and on
    /// a Retina display (above 1) MetalFX at 75 %, which looks native at a little over half the
    /// pixels; on a 1× display no upscaling.
    static func firstLaunch(backingScale: Double) -> GlobalSettings {
        var settings = GlobalSettings()
        if backingScale > 1 {
            settings.upscaling = .metalFX
            settings.renderScale = .percent75
        }
        return settings
    }

    /// Carries over the earlier points-based Render Resolution ("Display": one target pixel per
    /// point, scaled up), which now reads as Your Display. On a display of `backingScale` above 1
    /// Your Display draws `backingScale²` times the pixels, so the cost is held down: Upscaling, if
    /// it was off, becomes MetalFX at 67 % (under half the pixels on a 2× display, sharper than the
    /// points were), and web wallpapers keep drawing at standard resolution as Display drew them.
    /// Logged.
    mutating func migrateFromPoints(backingScale: Double) {
        renderResolution = .yourDisplay
        guard backingScale > 1 else {
            OWELog.info(.settings, "Render Resolution: Display (points) is now Your Display; on a 1× display that is the same size")
            return
        }
        var changes: [String] = []
        if upscaling == .off {
            upscaling = .metalFX
            renderScale = .percent67
            changes.append("Upscaling set to MetalFX at 67 %")
        }
        if !webStandardResolution {
            webStandardResolution = true
            changes.append("web wallpapers kept at standard resolution")
        }
        let kept = changes.isEmpty ? "Upscaling was already on" : changes.joined(separator: ", ")
        OWELog.info(.settings, "Render Resolution: Display (points) is now Your Display on a \(backingScale)× display; \(kept), to keep the GPU's work down")
    }
}
