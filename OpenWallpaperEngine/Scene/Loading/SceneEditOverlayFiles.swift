import Foundation
import OWESceneEditing

extension Notification.Name {
    /// A wallpaper's editor overlay changed; `userInfo["wallpaperDirectory"]` is its folder,
    /// `["overlay"]` the overlay and `["base"]` the scene with its structural edits
    /// (`SceneEditSession.baseOutline`), when the editor sent them; `["transient"]` is true for a
    /// drag in progress, which isn't saved. Its running instances draw the change live when they
    /// can (`SceneEditLiveValues`), else reload the scene with it (`SceneWallpaperInstance`).
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
/// (docs/editor-plan.md §3), with the files the editor added beside each (`<identity>.assets`).
/// The scene loader applies a wallpaper's overlay wherever it runs and finds its files.
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
    /// again (`base` lets them draw a value-only change live), or, when only particle documents
    /// changed (`change`), build those systems again.
    static func save(_ overlay: SceneEditOverlay, for identity: WallpaperSettingsIdentity, wallpaperDirectory: URL,
                     base: SceneOutline? = nil, change: SceneEditOverlay.LiveChange = .scene,
                     store: SceneEditOverlayStore = defaultStore) throws {
        try store.save(overlay, for: identity.rawValue)
        switch change {
        case .scene:
            post(overlay, base: base, wallpaperDirectory: wallpaperDirectory, transient: false)
        case .particleAssets(let paths):
            postParticles(overlay, wallpaperDirectory: wallpaperDirectory, paths: paths)
        }
    }

    /// A change the running instances draw while it lasts (a gizmo drag), not saved.
    static func preview(_ overlay: SceneEditOverlay, base: SceneOutline, wallpaperDirectory: URL) {
        post(overlay, base: base, wallpaperDirectory: wallpaperDirectory, transient: true)
    }

    private static func post(_ overlay: SceneEditOverlay, base: SceneOutline?, wallpaperDirectory: URL, transient: Bool) {
        var userInfo: [String: Any] = ["wallpaperDirectory": wallpaperDirectory.standardizedFileURL,
                                       "overlay": overlay, "transient": transient]
        if let base { userInfo["base"] = base }
        NotificationCenter.default.post(name: .sceneEditOverlayDidChange, object: nil, userInfo: userInfo)
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

    // MARK: Files the editor added

    /// Where the editor keeps the files it added for the wallpaper.
    static func assets(for identity: WallpaperSettingsIdentity, store: SceneEditOverlayStore = defaultStore) -> EditorAssetStore {
        EditorAssetStore(directory: store.assetsDirectory(for: identity.rawValue))
    }

    /// The editor's file at scene path `path` for the wallpaper (read after the wallpaper's own):
    /// an imported file, or a built-in effect's material or shader the editor copied into the
    /// project as WE's editor does; nil when it has none there.
    static func assetData(_ path: String, for identity: WallpaperSettingsIdentity,
                          store: SceneEditOverlayStore = defaultStore) -> Data? {
        guard let url = assets(for: identity, store: store).url(for: path) else { return nil }
        return try? AssetPathResolver.readRegularFile(at: url)
    }
}
