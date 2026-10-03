import Foundation
import OWESceneEditing

extension Notification.Name {
    /// A wallpaper's editor overlay was saved; `userInfo["wallpaperDirectory"]` is its folder.
    /// Its running instances reload the scene with it (`SceneWallpaperInstance`).
    static let sceneEditOverlayDidChange = Notification.Name("SceneEditOverlayDidChange")
}

/// The Wallpaper Editor's overlays (`SceneEditOverlay`) on disk, one per wallpaper under
/// `<AppStorageLocation.supportDirectory>/editor`, named by the wallpaper's settings identity
/// (docs/editor-plan.md §3). The scene loader applies a wallpaper's overlay wherever it runs.
enum SceneEditOverlayFiles {
    static var defaultStore: SceneEditOverlayStore {
        SceneEditOverlayStore(directory: AppStorageLocation.current.supportDirectory.appending(path: "editor", directoryHint: .isDirectory))
    }

    /// The wallpaper's overlay; nil when it has none or it can't be read (logged: the wallpaper
    /// then runs as authored rather than not at all).
    static func overlay(for identity: WallpaperSettingsIdentity, store: SceneEditOverlayStore = defaultStore) -> SceneEditOverlay? {
        do {
            return try store.overlay(for: identity.rawValue)
        } catch {
            OWELog.error(.scene, "Editor overlay \(store.fileURL(for: identity.rawValue).path) can't be read; the wallpaper runs without its edits: \(error)")
            return nil
        }
    }

    /// Saves the wallpaper's overlay and has its running instances apply it.
    static func save(_ overlay: SceneEditOverlay, for identity: WallpaperSettingsIdentity, wallpaperDirectory: URL,
                     store: SceneEditOverlayStore = defaultStore) throws {
        try store.save(overlay, for: identity.rawValue)
        NotificationCenter.default.post(name: .sceneEditOverlayDidChange, object: nil,
                                        userInfo: ["wallpaperDirectory": wallpaperDirectory.standardizedFileURL])
    }
}
