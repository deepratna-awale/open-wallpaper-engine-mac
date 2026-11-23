import Foundation

/// Sets every wallpaper's saved Blur adjustment back to its default once: Blur became Wallpaper
/// Engine's Blur effect (#627), whose scale differs, so values saved before it blur differently.
enum UserAdjustmentBlurReset {
    static let doneKey = "UserAdjustmentBlurReset.v1"
    static let propertyKeys: Set<String> = ["_owe_blur", "_owe_blur_musicSync", "_owe_blur_musicAmount"]

    static func runOnce(defaults: UserDefaults = .app) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let prefix = WallpaperSettingsIdentity.Family.userProperties.rawValue
        var reset = 0
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            guard var values = value as? [String: String],
                  !propertyKeys.isDisjoint(with: values.keys) else { continue }
            for property in propertyKeys { values.removeValue(forKey: property) }
            defaults.set(values, forKey: key)
            reset += 1
        }
        defaults.set(true, forKey: doneKey)
        OWELog.info(.settings, "Reset the Blur adjustment in \(reset) saved wallpaper settings")
    }
}
