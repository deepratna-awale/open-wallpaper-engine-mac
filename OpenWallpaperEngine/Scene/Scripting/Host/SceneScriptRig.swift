import simd

/// A script's call on a Puppet Warp image's skeleton (`IImageLayer`'s animation-layer and bone
/// API, `IAnimationLayer`; docs/models-plan.md §2.8, §4.3 P2), handed to the renderer's
/// `ScenePuppetAnimator` in call order. Matrices are column-vector (`p′ = M · p`), which is the
/// memory of WE's row-vector `Mat4`.
enum SceneScriptRigCommand: Equatable {
    /// `createAnimationLayer`/`playSingleAnimation`'s config (the d.ts: `blendin`, `blendout`,
    /// `blendtime`, `autosort`; and the authored layer keys a JSON config may carry).
    struct LayerConfig: Equatable {
        var name: String?
        var additive = false
        var blendIn = false
        var blendOut = false
        var autosort = false
        var blendTime: Float = 0.5
        var rate: Float = 1
        var blend: Float = 1
        var visible = true
    }

    enum LayerField: Int, Equatable {
        case rate = 0, blend = 1, visible = 2
    }

    enum Playback: Equatable {
        case play, pause, stop
        case setFrame(Float)
    }

    /// A layer playing the clip named `clip`, with the key the script gave it; `singlePlay`
    /// removes it once its clip finished.
    case createLayer(key: Int, clip: String, config: LayerConfig, singlePlay: Bool)
    case destroyLayer(key: Int)
    case setLayer(key: Int, field: LayerField, value: Float)
    case playback(key: Int, Playback)
    /// `setLocalBoneTransform` (and the angles and origin setters, composed by the script side).
    case setLocal(bone: Int, matrix: simd_float4x4)
    /// `setBoneTransform`, in the rig's model space (the renderer takes the object's world off).
    case setWorld(bone: Int, matrix: simd_float4x4)
}

/// A puppet's skeleton as the renderer left it after a frame, for the next script frame.
struct SceneScriptRigFeedback: Equatable {
    struct Layer: Equatable {
        var key: Int
        var name: String
        var clip: Int
        var time: Float
        var frame: Float
        var flags: SceneTimelineClock.Flags
        var rate: Float
        var blend: Float
        var visible: Bool
    }

    var layers: [Layer] = []
    /// Each bone's local matrix.
    var locals: [simd_float4x4] = []
    /// Each bone's world matrix: the object's world times its model-space matrix (0x14020f1d0).
    var worlds: [simd_float4x4] = []
    /// Layers whose clip reached its end since the last feedback (`addEndedCallback`).
    var ended: [Int] = []
}
