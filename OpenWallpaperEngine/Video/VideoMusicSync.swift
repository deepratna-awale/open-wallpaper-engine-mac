import Cocoa
import SwiftUI
import AVKit

enum VideoMusicSyncSettings {
    static func key(_ wallpaper: WEWallpaper, _ name: String) -> String {
        "VideoMusicSync.\(wallpaper.wallpaperDirectory.path).\(name)"
    }

    /// The music-sync values are read every frame by the video paths, so each is read from
    /// UserDefaults once and then served from memory. `VideoMusicSyncStore`, their only writer,
    /// drops the cache on every write.
    static func bool(_ wallpaper: WEWallpaper, _ name: String) -> Bool {
        cache.value(key(wallpaper, name)) { defaults, key in defaults.bool(forKey: key) as Any } as? Bool ?? false
    }

    static func double(_ wallpaper: WEWallpaper, _ name: String, default defaultValue: Double = 0) -> Double {
        let value = cache.value(key(wallpaper, name)) { defaults, key in
            defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key) as Any
        }
        return value as? Double ?? defaultValue
    }

    /// Drops the cached values; the next reads go to UserDefaults again.
    static func invalidate() { cache.invalidate() }

    /// How many values were read from UserDefaults (for tests).
    static var defaultsReads: Int { cache.reads }

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        /// A key whose value is absent from UserDefaults maps to `.some(nil)`.
        private var values: [String: Any?] = [:]
        private(set) var reads = 0

        func invalidate() {
            lock.lock(); values.removeAll(); lock.unlock()
        }

        func value(_ key: String, read: (UserDefaults, String) -> Any?) -> Any? {
            lock.lock(); defer { lock.unlock() }
            if let cached = values[key] { return cached }
            let value = read(UserDefaults.app, key)
            values[key] = .some(value)
            reads += 1
            return value
        }
    }
}

/// UserDefaults is invisible to SwiftUI and to the Metal renderer, which bakes the zoom/tilt/
/// saturation amounts into a layer at build time. Routing writes through here gives both a change
/// signal, so the controls redraw and the wallpaper picks the new values up immediately.
final class VideoMusicSyncStore: ObservableObject {
    static let shared = VideoMusicSyncStore()

    @Published private(set) var revision = 0

    private init() {}

    func set(_ value: Bool, _ wallpaper: WEWallpaper, _ name: String) {
        UserDefaults.app.set(value, forKey: VideoMusicSyncSettings.key(wallpaper, name))
        didChange(wallpaper)
    }

    func set(_ value: Double, _ wallpaper: WEWallpaper, _ name: String) {
        UserDefaults.app.set(value, forKey: VideoMusicSyncSettings.key(wallpaper, name))
        didChange(wallpaper)
    }

    private func didChange(_ wallpaper: WEWallpaper) {
        VideoMusicSyncSettings.invalidate()
        revision &+= 1
        NotificationCenter.default.post(name: .videoMusicSyncSettingsDidChange, object: nil,
                                        userInfo: ["path": wallpaper.wallpaperDirectory.path])
    }
}
