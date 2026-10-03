import simd

/// The scene camera for one frame (WE's ctx: view at +0x38, eye at +0x68, forward at +0x160):
/// what the draws of this frame see. `SceneMetalRenderer` builds it once per frame from its
/// `SceneCameraRig` and carries it on `BuiltinFrameContext.camera` (docs/models-plan.md § Seams).
struct SceneFrameCamera: Equatable {
    var view = matrix_identity_float4x4
    var projection = matrix_identity_float4x4
    /// `g_EyePosition`.
    var eye = SIMD3<Float>(0, 0, 1)
    /// The view direction (`g_ViewForward`; the light packer's and `transparentsorting`'s key).
    var forward = SIMD3<Float>(0, 0, -1)
    var up = SIMD3<Float>(0, 1, 0)
    /// The vertical fov in degrees, when the projection is a perspective one.
    var fieldOfView: Float?
    /// The projection's depth runs 1 at the near plane to 0 at the far one, as WE's does
    /// everywhere (§2.4): a depth buffer for it clears to 0 and compares GREATER.
    var reversedDepth = true
    /// `camerafade`'s alpha this frame (`materials/util/fade.json`); 0 draws no fade.
    var fade: Float = 0

    var viewProjection: simd_float4x4 { projection * view }
    var isPerspective: Bool { fieldOfView != nil }
}

/// What a rig gets each frame.
struct SceneCameraRigInput {
    /// The scene's size in scene units.
    var sceneSize: SIMD2<Float>
    /// The scene target's width over height (WE's projection aspect, R+0x84 / R+0x88).
    var aspect: Float
    /// Seconds since the scene started, and since the last frame.
    var time: Double
    var deltaTime: Float
    /// Camera shake this frame (`SceneCameraShake`) for a camera that carries it: a perspective
    /// scene's. An orthographic scene's layers are drawn without the camera, so the renderer moves
    /// them by the shake's negative instead and this stays zero.
    var shake = SIMD3<Float>.zero
    /// A camera layer's own `visible` this frame (scripts included).
    var isVisible: (String) -> Bool = { _ in true }
    /// An object's own transform this frame where scripts or timelines set it
    /// (`SceneObjectMotion.local3D`); nil keeps the authored one. Camera layers and their parents
    /// are composed with it through `SceneSpatialContent.transforms`.
    var live: SceneTransformHierarchy3D.Live = { _ in nil }
    /// A camera layer's `fov` as a script set it.
    var layerFov: (String) -> Float? = { _ in nil }
    /// `thisScene.fov`, `nearz`, `farz` and `camerafade` as scripts or timelines set them; nil
    /// keeps the scene's.
    var fov: Float?
    var nearZ: Float?
    var farZ: Float?
    var cameraFade: Bool?
    /// The scene's default camera as `thisScene.setCameraTransforms` set it; nil keeps the
    /// `camera` block.
    var scriptCamera: SceneCameraPose?
}

/// Where a frame's camera comes from: WE's camera layers, the scene's camera paths, or the
/// `camera` block (§2.2 "View"). One rig lives per wallpaper instance and keeps its own
/// playback state (paths, queues, fades), so it is a class.
protocol SceneCameraRig: AnyObject {
    func frameCamera(_ input: SceneCameraRigInput) -> SceneFrameCamera
    /// `ILayer.setParent` on the rig's copy of the parent graph (camera layers hang from it).
    func setParent(_ id: String, to parent: String?, attachment: String?)
}

extension SceneCameraRig {
    func setParent(_ id: String, to parent: String?, attachment: String?) {}
}

enum SceneCameraRigs {
    /// The rig for a content: WE's perspective camera (`ScenePerspectiveCameraRig`) for a
    /// perspective scene, the orthographic camera otherwise. Bound values resolve against the
    /// content's user properties.
    static func make(for content: SceneMetalContent) -> any SceneCameraRig {
        guard content.spatial.camera.projection.isPerspective else {
            return SceneOrthographicCameraRig(zoom: Float(content.spatial.camera.zoom))
        }
        return ScenePerspectiveCameraRig(content.spatial, values: LiveSceneValueContext(wallpaper: content.wallpaperKey))
    }
}

/// An orthographic scene's camera (0x1401891a0 without camera paths): the view from the origin
/// down −z (identity), `ortho(0, width, 0, height)` over z −2000…2000 scaled about its centre by
/// `general.zoom` (0x14017fd50, docs/models-plan.md §5.19), and the eye WE reports afterwards,
/// (width/2, height/2, 2000) (0x140189da0). Camera shake isn't in it: the renderer moves the
/// layers and lights by its negative instead, which leaves every eye-to-object vector as WE's.
/// The layer pass draws with its own matrix (`ImageMaterialRenderer.viewProjection`) and the
/// zoom in the plane (`SceneAffineTransform.orthographicZoom`); the models and the volumetrics
/// draw with this one.
final class SceneOrthographicCameraRig: SceneCameraRig {
    /// `general.zoom`.
    let zoom: Float

    init(zoom: Float = 1) { self.zoom = zoom }

    func frameCamera(_ input: SceneCameraRigInput) -> SceneFrameCamera {
        let size = simd_max(input.sceneSize, SIMD2(1, 1))
        return SceneFrameCamera(projection: Self.projection(size: size, zoom: zoom),
                                eye: SIMD3(size.x / 2, size.y / 2, SceneCamera.orthographicDepth))
    }

    /// `ortho(0, width, 0, height)` with its x and y scaled by `zoom` about the centre.
    static func projection(size: SIMD2<Float>, zoom: Float) -> simd_float4x4 {
        let ortho = SceneCamera.orthographic(size: size)
        guard zoom != 1, zoom.isFinite, zoom > 0 else { return ortho }
        return simd_float4x4(diagonal: SIMD4(zoom, zoom, 1, 1)) * ortho
    }
}

extension SceneScriptSceneState {
    /// The default camera as `thisScene.setCameraTransforms` left it (the eye, centre, up and
    /// zoom of the scene buffer), once a script has set any of them; nil before.
    var scriptCamera: SceneCameraPose? {
        let fields: [SceneScriptSceneField] = [.cameraEye, .cameraCenter, .cameraUp, .cameraZoom]
        guard fields.contains(where: owned.contains) else { return nil }
        func vector(_ field: SceneScriptSceneField) -> SIMD3<Float> {
            SIMD3(values[field.offset], values[field.offset + 1], values[field.offset + 2])
        }
        return SceneCameraPose(eye: vector(.cameraEye), center: vector(.cameraCenter), up: vector(.cameraUp),
                               zoom: values[SceneScriptSceneField.cameraZoom.offset])
    }
}
