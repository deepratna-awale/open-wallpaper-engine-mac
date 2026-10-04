import Foundation
import OWESceneEditing

/// What the Wallpaper Editor's process hands the wallpapers running in Open Wallpaper Engine
/// beside a wallpaper's overlay (`SceneEditOverlayStore`), for the messages that only name the
/// wallpaper (`AppProcessChannel`):
/// - `<identity>.preview.json`: the overlay with a gizmo drag in progress, never the saved one;
/// - `<identity>.restart.json`: the particle systems to build again.
///
/// Neither is an overlay the loader reads (`<identity>.json`); the editor removes both when its
/// window closes.
struct SceneEditLiveFiles {
    let store: SceneEditOverlayStore

    func previewURL(for identity: WallpaperSettingsIdentity) -> URL { sidecar(identity, "preview") }
    func restartURL(for identity: WallpaperSettingsIdentity) -> URL { sidecar(identity, "restart") }

    private func sidecar(_ identity: WallpaperSettingsIdentity, _ kind: String) -> URL {
        let name = store.fileURL(for: identity.rawValue).deletingPathExtension().lastPathComponent
        return store.directory.appending(path: "\(name).\(kind).json", directoryHint: .notDirectory)
    }

    func writePreview(_ overlay: SceneEditOverlay, for identity: WallpaperSettingsIdentity) throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try overlay.encoded().write(to: previewURL(for: identity), options: .atomic)
    }

    /// The drag in progress; nil when there is none (it ended, or the editor closed).
    func preview(for identity: WallpaperSettingsIdentity) throws -> SceneEditOverlay? {
        let url = previewURL(for: identity)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try SceneEditOverlay.decoded(from: Data(contentsOf: url))
    }

    func writeRestart(_ objectIDs: Set<Int>, for identity: WallpaperSettingsIdentity) throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(objectIDs.sorted()).write(to: restartURL(for: identity), options: .atomic)
    }

    func restart(for identity: WallpaperSettingsIdentity) throws -> Set<Int> {
        let url = restartURL(for: identity)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return Set(try JSONDecoder().decode([Int].self, from: Data(contentsOf: url)))
    }

    /// Removes the drag (`preview`) or both files; a missing file is fine.
    func remove(for identity: WallpaperSettingsIdentity, previewOnly: Bool = false) {
        let urls = previewOnly ? [previewURL(for: identity)] : [previewURL(for: identity), restartURL(for: identity)]
        for url in urls where FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                OWELog.error(.scene, "Can't remove the editor's live file \(url.path): \(error)")
            }
        }
    }
}
