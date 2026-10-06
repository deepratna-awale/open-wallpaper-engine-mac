import Foundation
import OWESceneEditing

/// The size a scene wallpaper is drawn at, in scene units: WE's canvas
/// (`SceneWallpaperViewModel.sceneSize(of:)`, 0x14018b2c0) of its scene.json with the Wallpaper
/// Editor's overlay and the per-object edits applied, as the renderer loads it. What anything
/// framing the drawn scene (the Scene Editor (Live), the iPhone & iPad and Android exports)
/// measures in.
enum SceneDrawnSize {
    /// `sceneData`'s drawn size with `overlay` and `edits` (stored `_owe_scene_object_…` values)
    /// applied (`ScenePreparation.resolvedScene`).
    static func of(sceneData: Data, overlay: SceneEditOverlay?, edits: [String: String] = [:]) throws -> SIMD2<Double> {
        let resolved = try ScenePreparation.resolvedScene(sceneData, edits: edits, overlay: overlay)
        return SIMD2<Double>(SceneWallpaperViewModel.sceneSize(of: try JSONDecoder().decode(WEScene.self, from: resolved)))
    }

    /// The overlay the renderer applies to `wallpaper`: the one saved for its settings identity.
    static func savedOverlay(of wallpaper: WEWallpaper) -> SceneEditOverlay? {
        SceneEditOverlayFiles.overlay(for: WallpaperSettingsIdentity.resolve(directory: wallpaper.settingsDirectory))
    }
}
