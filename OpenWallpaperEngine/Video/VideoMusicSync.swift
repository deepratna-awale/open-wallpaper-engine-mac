import Cocoa
import SwiftUI
import AVKit

/// A video wallpaper's music-sync switches and amounts, per wallpaper: `VideoMusicSync.<identity>.<name>`
/// in `UserDefaults.app`, keyed by the wallpaper's settings identity (`WallpaperSettingsIdentity`)
/// like its user properties, so moving or renaming its folder keeps them and two wallpapers never
/// share them.
enum VideoMusicSyncSettings {
    static func key(_ identity: WallpaperSettingsIdentity, _ name: String) -> String {
        "VideoMusicSync.\(identity.rawValue).\(name)"
    }

    static func bool(_ identity: WallpaperSettingsIdentity, _ name: String, defaults: UserDefaults = .app) -> Bool {
        defaults.bool(forKey: key(identity, name))
    }

    /// The music-sync switches; any of them on makes the wallpaper follow the system audio.
    static let switches = ["zoomEnabled", "tiltEnabled", "saturationEnabled", "paceEnabled"]

    /// Whether any music sync is on for the wallpaper, so it needs system audio capture.
    static func isAnyEnabled(_ identity: WallpaperSettingsIdentity, defaults: UserDefaults = .app) -> Bool {
        switches.contains { bool(identity, $0, defaults: defaults) }
    }

    static func double(_ identity: WallpaperSettingsIdentity, _ name: String, default defaultValue: Double = 0,
                       defaults: UserDefaults = .app) -> Double {
        let key = key(identity, name)
        return defaults.object(forKey: key) == nil ? defaultValue : defaults.double(forKey: key)
    }
}

/// UserDefaults is invisible to SwiftUI and to the Metal renderer, which bakes the zoom/tilt/
/// saturation amounts into a layer at build time. Routing writes through here gives both a change
/// signal, so the controls redraw and the wallpaper picks the new values up immediately. The
/// notifications carry the changed wallpaper's settings identity (`"identity"`).
@MainActor
final class VideoMusicSyncStore: ObservableObject {
    static let shared = VideoMusicSyncStore()

    @Published private(set) var revision = 0

    private let defaults: UserDefaults
    /// Each wallpaper folder's settings identity, resolved once (resolving reads its project.json).
    private var identities: [String: WallpaperSettingsIdentity] = [:]

    /// The app's store writes `UserDefaults.app`; tests pass their own suite.
    init(defaults: UserDefaults = .app) {
        self.defaults = defaults
    }

    /// The identity `wallpaper`'s music settings are kept under.
    func identity(of wallpaper: WEWallpaper) -> WallpaperSettingsIdentity {
        let path = wallpaper.settingsDirectory.standardizedFileURL.path
        if let identity = identities[path] { return identity }
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)
        identities[path] = identity
        return identity
    }

    func bool(_ wallpaper: WEWallpaper, _ name: String) -> Bool {
        VideoMusicSyncSettings.bool(identity(of: wallpaper), name, defaults: defaults)
    }

    func double(_ wallpaper: WEWallpaper, _ name: String, default defaultValue: Double = 0) -> Double {
        VideoMusicSyncSettings.double(identity(of: wallpaper), name, default: defaultValue, defaults: defaults)
    }

    func isAnyEnabled(_ wallpaper: WEWallpaper) -> Bool {
        VideoMusicSyncSettings.isAnyEnabled(identity(of: wallpaper), defaults: defaults)
    }

    /// The music-sync amounts set for `wallpaper`.
    func effect(for wallpaper: WEWallpaper) -> VideoMusicSyncEffect {
        VideoMusicSyncEffect(identity(of: wallpaper), defaults: defaults)
    }

    func set(_ value: Bool, _ wallpaper: WEWallpaper, _ name: String) {
        let identity = identity(of: wallpaper)
        defaults.set(value, forKey: VideoMusicSyncSettings.key(identity, name))
        didChange(identity, .videoMusicSyncSettingsDidChange)
    }

    func set(_ value: Double, _ wallpaper: WEWallpaper, _ name: String) {
        let identity = identity(of: wallpaper)
        defaults.set(value, forKey: VideoMusicSyncSettings.key(identity, name))
        didChange(identity, .videoMusicSyncSettingsDidChange)
    }

    // MARK: Scene music

    /// Whether `wallpaper`'s own sound layers play (`SceneMusicSettings`).
    func sceneMusicEnabled(_ wallpaper: WEWallpaper) -> Bool {
        SceneMusicSettings.enabled(identity(of: wallpaper), defaults: defaults)
    }

    func sceneMusicVolume(_ wallpaper: WEWallpaper) -> Double {
        SceneMusicSettings.volume(identity(of: wallpaper), defaults: defaults)
    }

    func setSceneMusicEnabled(_ enabled: Bool, _ wallpaper: WEWallpaper) {
        let identity = identity(of: wallpaper)
        defaults.set(enabled, forKey: SceneMusicSettings.enabledKey(identity))
        didChange(identity, .sceneMusicSettingsDidChange)
    }

    func setSceneMusicVolume(_ volume: Double, _ wallpaper: WEWallpaper) {
        let identity = identity(of: wallpaper)
        defaults.set(volume, forKey: SceneMusicSettings.volumeKey(identity))
        didChange(identity, .sceneMusicSettingsDidChange)
    }

    private func didChange(_ identity: WallpaperSettingsIdentity, _ name: Notification.Name) {
        revision &+= 1
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["identity": identity.rawValue])
    }
}
