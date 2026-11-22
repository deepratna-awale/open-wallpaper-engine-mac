import Foundation

/// The app's Animation Speed: WE's per-wallpaper playback `rate` (÷ 100), which `SceneClock`
/// multiplies the frame by. It is a user property of the wallpaper instance, so it lives in the
/// instance's own property store (`WallpaperPropertyScope.runtimeKey`): with properties per
/// display, two displays showing one wallpaper run it at their own speeds, as WE's per-monitor
/// wallpapers each have their own `rate`.
enum ScenePlaybackSpeed {
    /// The property the sidebar's Animation Speed slider writes.
    static let propertyKey = "_owe_speed"
    /// The User Adjustments' Pause Animation: the wallpaper pauses as when playback is paused,
    /// easing to a stop and holding its frame.
    static let pauseKey = "_owe_pause"

    /// Whether the instance whose property store is `store` has its animation paused.
    static func isPaused(ofStore store: String, services: WallpaperServices = .shared) -> Bool {
        services.userPropertyString(pauseKey, wallpaper: store)?.lowercased() == "true"
    }

    /// The speed stored for the instance whose property store is `store`; 1 when it has none or
    /// it isn't a number. Synced to music, the music amount times the audio level is added.
    static func speed(ofStore store: String, services: WallpaperServices = .shared) -> Double {
        let stored = services.userPropertyString(propertyKey, wallpaper: store)
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let value = stored.flatMap { $0.isFinite ? $0 : nil } ?? 1
        return value + musicOffset(ofStore: store, services: services)
    }

    /// `<speed>_musicAmount` × the audio level while the speed is synced to music, else 0.
    static func musicOffset(ofStore store: String, services: WallpaperServices) -> Double {
        guard services.userPropertyString("\(propertyKey)_musicSync", wallpaper: store)?.lowercased() == "true",
              let amount = services.userPropertyString("\(propertyKey)_musicAmount", wallpaper: store)
                .flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }), amount.isFinite else { return 0 }
        return amount * services.audioLevel
    }
}
