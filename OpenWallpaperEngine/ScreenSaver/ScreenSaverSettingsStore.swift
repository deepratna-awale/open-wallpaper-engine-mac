import Foundation

/// Scene Edit / Export's Screen Saver mode's saved state, in the app's defaults
/// (`UserDefaults.app`, so tests and isolated copies keep their own):
/// - **Per wallpaper** (`ScreenSaverValues.<identity>`, `WallpaperSettingsIdentity`): the values the
///   screen saver's version of a wallpaper is drawn with (its user properties and Scene Edit /
///   Export's layer edits, as `IsolatedSceneEditSession.values` holds them). They are the screen
///   saver's own, apart from the wallpaper's: the desktop never reads them, and editing the
///   wallpaper doesn't change them.
/// - **The live pick** (`ScreenSaverLivePick`): the wallpaper set as the screen saver, which the
///   live screen saver draws with these values instead of the desktop's wallpapers.
struct ScreenSaverSettingsStore {
    static let valuesPrefix = "ScreenSaverValues."
    static let livePickKey = "ScreenSaverLivePick"

    /// The wallpaper set as the screen saver, drawn live.
    struct LivePick: Codable, Equatable, Sendable {
        /// The wallpaper's folder.
        var wallpaperDirectory: String
        /// When it was picked.
        var picked: Date
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .app) { self.defaults = defaults }

    // MARK: Per wallpaper

    static func valuesKey(_ identity: WallpaperSettingsIdentity) -> String { valuesPrefix + identity.rawValue }

    /// The screen saver's saved values for the wallpaper, nil when it has none (it is then drawn
    /// with the wallpaper's own).
    func values(for identity: WallpaperSettingsIdentity) -> [String: String]? {
        defaults.dictionary(forKey: Self.valuesKey(identity)) as? [String: String]
    }

    func setValues(_ values: [String: String], for identity: WallpaperSettingsIdentity) {
        defaults.set(values, forKey: Self.valuesKey(identity))
    }

    // MARK: Pick

    var livePick: LivePick? {
        get { decode(LivePick.self, forKey: Self.livePickKey) }
        nonmutating set { encode(newValue, forKey: Self.livePickKey) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            OWELog.error(.app, "Screen saver: can't read \(key), ignoring it: \(error)")
            return nil
        }
    }

    private func encode<Value: Encodable>(_ value: Value?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            OWELog.error(.app, "Screen saver: can't save \(key): \(error)")
        }
    }
}
