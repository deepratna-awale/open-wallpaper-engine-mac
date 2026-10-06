import Foundation
import OWEControlProtocol
import OWEEditor
import OWESceneEditing

/// The app's headless edit sessions, one per wallpaper an MCP client edits (`HeadlessSceneDocument`),
/// kept for the app's life so `scene_undo` steps back through the client's edits.
@MainActor
final class HeadlessSceneEditService {
    struct Dependencies {
        var store: SceneEditOverlayStore = SceneEditOverlayFiles.defaultStore
        var center: NotificationCenter = .default
        /// The wallpaper's scene, files and services.
        var resources: @MainActor (ControlWallpaper) throws -> SceneEditResources
        var announce: @MainActor (URL, SceneEditOverlay, String, AppProcessChannel.OverlayStep) -> Void = { _, _, _, _ in }
        var particleSchema: () throws -> ParticleEditorSchema = { try ParticleEditorServices.bundledSchema() }
    }

    private let dependencies: Dependencies
    private var documents: [String: HeadlessSceneDocument] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// The wallpaper's document, with edits saved elsewhere since adopted.
    func document(for wallpaper: ControlWallpaper) throws -> HeadlessSceneDocument {
        let key = wallpaper.folder.standardizedFileURL.path
        if let document = documents[key] {
            try document.refresh()
            return document
        }
        let resources = try dependencies.resources(wallpaper)
        let document = try HeadlessSceneDocument(
            wallpaper: wallpaper, resources: resources,
            dependencies: .init(store: dependencies.store, center: dependencies.center, announce: dependencies.announce,
                                particleSchema: dependencies.particleSchema))
        documents[key] = document
        return document
    }
}
