import Foundation

/// Scene Edit / Export's Screen Saver mode's saved state, in the app's defaults
/// (`UserDefaults.app`, so tests and isolated copies keep their own):
/// - **Per wallpaper** (`ScreenSaverValues.<identity>`, `WallpaperSettingsIdentity`): the values the
///   screen saver's version of a wallpaper is recorded with (its user properties and Scene Edit /
///   Export's layer edits, as `IsolatedSceneEditSession.values` holds them). They are the screen
///   saver's own, apart from the wallpaper's: the desktop never reads them, and editing the
///   wallpaper doesn't change them. Every recording of that wallpaper, by hand or on the daily
///   schedule, uses them.
/// - **The selection** (`ScreenSaverSelection`): the recording set as the screen saver, while one
///   is. The screen saver plugin then plays it instead of making a loop of the desktop's wallpaper.
/// - **The daily schedule** (`ScreenSaverSchedule`).
struct ScreenSaverSettingsStore {
    static let valuesPrefix = "ScreenSaverValues."
    static let selectionKey = "ScreenSaverSelection"
    static let scheduleKey = "ScreenSaverSchedule"

    /// The recording set as the screen saver.
    struct Selection: Codable, Equatable, Sendable {
        /// The recorded wallpaper's folder.
        var wallpaperDirectory: String
        /// The video's name in the screen saver's folder (`ScreenSaverVideoStore`).
        var fileName: String
        var width: Int
        var height: Int
        /// When it was recorded.
        var recorded: Date
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .app) { self.defaults = defaults }

    // MARK: Per wallpaper

    static func valuesKey(_ identity: WallpaperSettingsIdentity) -> String { valuesPrefix + identity.rawValue }

    /// The screen saver's saved values for the wallpaper, nil when it has none (a recording then
    /// starts from the wallpaper's own).
    func values(for identity: WallpaperSettingsIdentity) -> [String: String]? {
        defaults.dictionary(forKey: Self.valuesKey(identity)) as? [String: String]
    }

    func setValues(_ values: [String: String], for identity: WallpaperSettingsIdentity) {
        defaults.set(values, forKey: Self.valuesKey(identity))
    }

    // MARK: Selection and schedule

    var selection: Selection? {
        get { decode(Selection.self, forKey: Self.selectionKey) }
        nonmutating set { encode(newValue, forKey: Self.selectionKey) }
    }

    var schedule: ScreenSaverSchedule {
        get { decode(ScreenSaverSchedule.self, forKey: Self.scheduleKey) ?? ScreenSaverSchedule() }
        nonmutating set { encode(newValue, forKey: Self.scheduleKey) }
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
