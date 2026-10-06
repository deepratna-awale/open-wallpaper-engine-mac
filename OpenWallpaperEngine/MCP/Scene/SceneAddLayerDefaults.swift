import Foundation
import OWEControlProtocol
import OWESceneEditing

/// What `add_layer` sizes and places a new layer by when the request leaves it out: the scene as
/// the renderer draws it (`SceneWallpaperViewModel.sceneSize(of:)`, WE's canvas, 0x14018b2c0) and
/// an image model's own size.
enum SceneAddLayerDefaults {
    /// The edited scene's drawn size, and where a new layer goes: its centre, a 3D scene's origin
    /// (as the editor's Add menu places it, `LayerActions.sceneCentre`).
    @MainActor
    static func canvas(sceneData: Data, overlay: SceneEditOverlay) throws -> (size: SIMD2<Double>, centre: SIMD2<Double>) {
        let scene: WEScene
        do {
            guard var root = try JSONSerialization.jsonObject(with: sceneData) as? [String: Any] else {
                throw SceneEditOverlayError.notAScene
            }
            try overlay.apply(to: &root)
            scene = try JSONDecoder().decode(WEScene.self, from: JSONSerialization.data(withJSONObject: root))
        } catch {
            OWELog.error(.app, "MCP: add_layer can't read the scene's size: \(error)")
            throw ControlError(.failed, "The scene's size can't be read: \(error.localizedDescription)")
        }
        let size = SIMD2<Double>(SceneWallpaperViewModel.sceneSize(of: scene))
        return (size, scene.general.projection == .perspective ? .zero : size / 2)
    }

    /// An image model's size as the renderer gives a layer without one: the model's `width` and
    /// `height`, else its material's first texture's image size; nil when neither can be read.
    static func imageSize(ofModel model: String, readAsset: (String) -> Data?) -> SIMD2<Double>? {
        guard let modelData = readAsset(model) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(WEModel.self, from: modelData)
            if let declared = decoded.declaredSize { return SIMD2<Double>(declared) }
            guard let materialPath = decoded.material, let materialData = readAsset(materialPath) else { return nil }
            let material = try JSONDecoder().decode(WEMaterial.self, from: materialData)
            guard let texture = material.passes?.first?.textures?.first ?? nil,
                  let data = readAsset("materials/\(texture).tex"), let header = TEXFileHeader(data),
                  header.imageWidth > 0, header.imageHeight > 0 else { return nil }
            return SIMD2(Double(header.imageWidth), Double(header.imageHeight))
        } catch {
            OWELog.debug(.app, "MCP: add_layer can't read \(model)'s size: \(error)")
            return nil
        }
    }
}
