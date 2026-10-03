import Foundation
import OWESceneEditing

extension Notification.Name {
    /// A wallpaper's editor overlay was saved; `userInfo["wallpaperDirectory"]` is its folder.
    /// Its running instances reload the scene with it (`SceneWallpaperInstance`).
    static let sceneEditOverlayDidChange = Notification.Name("SceneEditOverlayDidChange")
    /// The particle editor changed only documents particle systems read, or restarts a system:
    /// `userInfo["wallpaperDirectory"]` is the wallpaper's folder, `["assets"]` the overlay's
    /// documents by path (`[String: Data]`), `["paths"]` the changed ones and `["objectIDs"]`
    /// systems to build again in any case. Running instances build again only those systems
    /// (`SceneWallpaperInstance`); the rest of the scene keeps running.
    static let sceneEditParticlesDidChange = Notification.Name("SceneEditParticlesDidChange")
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

    /// Saves the wallpaper's overlay and has its running instances apply it: they read the scene
    /// again, or, when only particle documents changed (`change`), build those systems again.
    static func save(_ overlay: SceneEditOverlay, for identity: WallpaperSettingsIdentity, wallpaperDirectory: URL,
                     change: SceneEditOverlay.LiveChange = .scene, store: SceneEditOverlayStore = defaultStore) throws {
        try store.save(overlay, for: identity.rawValue)
        switch change {
        case .scene:
            NotificationCenter.default.post(name: .sceneEditOverlayDidChange, object: nil,
                                            userInfo: ["wallpaperDirectory": wallpaperDirectory.standardizedFileURL])
        case .particleAssets(let paths):
            postParticles(overlay, wallpaperDirectory: wallpaperDirectory, paths: paths)
        }
    }

    /// Has the running instances read the overlay's particle documents again and build the
    /// systems that read `paths`, and the systems `objectIDs` (a restart), again.
    static func postParticles(_ overlay: SceneEditOverlay, wallpaperDirectory: URL, paths: Set<String> = [],
                              objectIDs: Set<Int> = []) {
        NotificationCenter.default.post(name: .sceneEditParticlesDidChange, object: nil, userInfo: [
            "wallpaperDirectory": wallpaperDirectory.standardizedFileURL,
            "assets": overlay.particles?.assetData() ?? [:],
            "paths": Array(paths),
            "objectIDs": Array(objectIDs),
        ])
    }
}
