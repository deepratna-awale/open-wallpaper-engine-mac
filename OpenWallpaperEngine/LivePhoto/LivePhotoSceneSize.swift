import Foundation

/// The size a scene is authored at, in scene units: what the Scene Editor (Live) frames, and what
/// the iPhone & iPad Export mode's crop (`LivePhotoCrop.sceneSize`) is measured in.
enum LivePhotoSceneSize {
    /// When the scene says nothing about its size.
    static let fallback = SIMD2<Double>(1920, 1080)

    /// An orthographic scene's projection size; otherwise the extent of its objects' centres plus
    /// half their sizes, or `fallback` when no object has both.
    static func of(_ scene: WEScene) -> SIMD2<Double> {
        if case .orthographic(let width, let height) = scene.general.projection {
            return SIMD2<Double>(Double(width), Double(height))
        }
        let bounds = scene.objects.compactMap { object -> SIMD2<Double>? in
            guard let origin = object.origin?.parseVector3(), let size = object.size?.parseVector2() else { return nil }
            return SIMD2<Double>(origin.0 + size.0 / 2, origin.1 + size.1 / 2)
        }
        guard let width = bounds.map(\.x).max(), let height = bounds.map(\.y).max(), width > 0, height > 0 else {
            return fallback
        }
        return SIMD2<Double>(width, height)
    }
}
