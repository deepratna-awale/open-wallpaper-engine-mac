import Foundation

/// "Set as Screen Saver" from the Discover and Workshop menus: the Screen Saver mode's recording,
/// made without opening the mode.
extension ScreenSaverRecordingService {
    /// Whether the Screen Saver mode can set `wallpaper` as the screen saver: a scene it records, or
    /// a video file the saver plays (`SceneEditorModes`). Web and application wallpapers can't be.
    nonisolated static func canSet(_ wallpaper: WEWallpaper) -> Bool {
        SceneEditorModes.availability(of: .screenSaver, for: wallpaper)?.isAvailable == true
    }

    /// Sets `wallpaper` as the screen saver as the Screen Saver mode does: a video's own file
    /// (`useVideo`), or a scene recorded (`record`) from the screen saver's own values for it (else
    /// the wallpaper's) with its clock, day, date and audio-reactive layers switched off
    /// (`ScreenSaverLiveLayers`). The recording saves those values as the screen saver's choices,
    /// so the mode and the daily re-recording keep them; the desktop's values are never changed.
    /// `liveLayers` scans the scene (blocking file IO, run off the main thread). `completion` gets
    /// whether it was set.
    func setAsScreenSaver(_ wallpaper: WEWallpaper,
                          liveLayers: @escaping @Sendable (WEWallpaper) -> Set<Int> = ScreenSaverLiveLayers.objectIDs,
                          completion: @escaping @MainActor (Bool) -> Void) {
        guard !isRecording, Self.canSet(wallpaper) else {
            OWELog.info(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) can't be set now (a recording is running, or the screen saver can't play it)")
            completion(false)
            return
        }
        if ScreenSaverVideoSource.isEligible(wallpaper) {
            useVideo(wallpaper, completion: completion)
            return
        }
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: store.defaults)
        let values = store.values(for: identity)
            ?? IsolatedSceneEditSession.seed(of: wallpaper, from: [.shared], defaults: store.defaults)
        Task { [weak self] in
            let ids = await Task.detached(priority: .userInitiated) { liveLayers(wallpaper) }.value
            guard let self else { return }
            OWELog.info(.app, "Screen saver: recording \(wallpaper.wallpaperDirectory.lastPathComponent) with \(ids.count) clock or audio-reactive layers off")
            self.record(wallpaper, values: ScreenSaverLiveLayers.hiding(ids, in: values), background: false,
                        completion: completion)
        }
    }
}
