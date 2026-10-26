import Foundation

/// A scene's own music (its sound layers) per wallpaper: on or off (on when unset) and its volume
/// (1 when unset), `SceneMusicEnabled.<identity>` and `SceneMusicVolume.<identity>` in
/// `UserDefaults.app`, keyed by the wallpaper's settings identity like its music sync
/// (`VideoMusicSyncSettings`). Written through `VideoMusicSyncStore`.
enum SceneMusicSettings {
    static func enabledKey(_ identity: WallpaperSettingsIdentity) -> String { "SceneMusicEnabled.\(identity.rawValue)" }

    static func volumeKey(_ identity: WallpaperSettingsIdentity) -> String { "SceneMusicVolume.\(identity.rawValue)" }

    static func enabled(_ identity: WallpaperSettingsIdentity, defaults: UserDefaults = .app) -> Bool {
        let key = enabledKey(identity)
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    static func volume(_ identity: WallpaperSettingsIdentity, defaults: UserDefaults = .app) -> Double {
        let key = volumeKey(identity)
        return defaults.object(forKey: key) == nil ? 1 : defaults.double(forKey: key)
    }
}
