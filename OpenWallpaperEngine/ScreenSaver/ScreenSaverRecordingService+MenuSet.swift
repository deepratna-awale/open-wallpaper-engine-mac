import Foundation

/// "Set as Screen Saver" from the Discover and Workshop menus: the Screen Saver mode's Set as
/// Screen Saver, without opening the mode.
extension ScreenSaverRecordingService {
    /// Whether the Screen Saver mode can set `wallpaper` as the screen saver: a scene drawn live,
    /// or a video file the saver plays (`SceneEditorModes`). Web and application wallpapers can't be.
    nonisolated static func canSet(_ wallpaper: WEWallpaper) -> Bool {
        SceneEditorModes.availability(of: .screenSaver, for: wallpaper)?.isAvailable == true
    }

    /// Sets `wallpaper` as the screen saver as the Screen Saver mode does: a video's own file, or
    /// a scene picked to be drawn live with the screen saver's own values for it (else the
    /// wallpaper's). Its clocks and audio-reactive layers stay as they are: drawn live, they move.
    /// `completion` gets whether it was set.
    func setAsScreenSaver(_ wallpaper: WEWallpaper, completion: @escaping @MainActor (Bool) -> Void) {
        guard !isRecording, Self.canSet(wallpaper) else {
            OWELog.info(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) can't be set now (a video is being set, or the screen saver can't show it)")
            completion(false)
            return
        }
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: store.defaults)
        let values = store.values(for: identity)
            ?? IsolatedSceneEditSession.seed(of: wallpaper, from: [.shared], defaults: store.defaults)
        set(wallpaper, values: values, completion: completion)
    }
}
