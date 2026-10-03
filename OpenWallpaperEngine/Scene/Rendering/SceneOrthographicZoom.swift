import simd

/// An orthographic scene's zoom: WE scales its orthographic projection about the screen's centre
/// by `general.zoom` × the camera's zoom (0x14017fd50; WE 2.8's capture, docs/models-plan.md
/// §5.19: at `zoom` 2 an 870 px image is drawn 1742 px wide about the centre). World matrices
/// don't change, only what the camera shows.
///
/// Scaling the projection's x and y about its centre is the same as drawing the scene scaled about
/// its centre through the unzoomed projection, and with z scaled too every distance scales alike,
/// so lighting is unchanged. The app draws everything in that *drawn space*: the layer path,
/// which keeps its own matrix, in the scene plane scaled (`plane`: layers, particle emitters and
/// their cursor), and the models, the lights (with their distances, `scaled(_:)`), the shadow
/// casters and the volumetrics in it (`space`), seen by the orthographic camera over a depth range
/// grown alike (`orthographicDepth`). What scripts see stays WE's world: their world matrices
/// are unzoomed, and the cursor's world position is the drawn point taken back through the zoom
/// (`worldPoint(drawn:)`), so a click lands on what is drawn under it.
struct SceneOrthographicZoom: Equatable {
    /// The projection's scale; 1 is none.
    let factor: Float
    /// The scene's centre, which the zoom keeps in place.
    let centre: SIMD2<Float>

    static let none = SceneOrthographicZoom(factor: 1, sceneSize: .zero)

    /// A zoom that isn't positive and finite is none.
    init(factor: Float, sceneSize: SIMD2<Float>) {
        self.factor = factor.isFinite && factor > 0 ? factor : 1
        centre = sceneSize / 2
    }

    var isNone: Bool { factor == 1 }

    /// The drawn plane: the scene scaled by `factor` about its centre.
    var plane: SceneAffineTransform {
        guard !isNone else { return .identity }
        return SceneAffineTransform(linear: simd_float2x2(diagonal: SIMD2(repeating: factor)),
                                    translation: centre - factor * centre)
    }

    /// The same in 3D, z scaled too, so every distance in it grows by `factor` alike.
    var space: simd_float4x4 {
        guard !isNone else { return matrix_identity_float4x4 }
        let shift = centre - factor * centre
        return simd_float4x4(columns: (SIMD4(factor, 0, 0, 0), SIMD4(0, factor, 0, 0), SIMD4(0, 0, factor, 0),
                                       SIMD4(shift.x, shift.y, 0, 1)))
    }

    /// The world point drawn at `drawn` (a point of the drawn plane, which is the screen's scene
    /// units): what unprojecting the cursor through the zoomed camera gives.
    func worldPoint(drawn: SIMD2<Float>) -> SIMD2<Float> {
        guard !isNone else { return drawn }
        return centre + (drawn - centre) / factor
    }

    /// A projection with its x and y scaled by `factor` about its centre: WE's zoom itself, for
    /// the temporary perspective camera of an orthographic scene's `perspective` layers and
    /// systems, whose view a scaled scene wouldn't reproduce.
    func projection(_ projection: simd_float4x4) -> simd_float4x4 {
        guard !isNone else { return projection }
        return simd_float4x4(diagonal: SIMD4(factor, factor, 1, 1)) * projection
    }

    /// The camera's depth range in the drawn space, ±`SceneCamera.orthographicDepth` × `factor`:
    /// a world z lands at the depth it has without the zoom, so models and layers keep testing
    /// against each other as they do in WE.
    var orthographicDepth: Float { SceneCamera.orthographicDepth * factor }

    /// A light's distances in the drawn space: its radius, source size and shadow cascades.
    func scaled(_ light: SceneLight) -> SceneLight {
        guard !isNone else { return light }
        var scaled = light
        scaled.radius *= factor
        scaled.lightSourceSize *= factor
        scaled.cascadeDistances *= factor
        return scaled
    }
}
