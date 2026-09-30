/// Which user-binding sites of a scene object the renderer applies without rebuilding the content,
/// so a user property read only there needs no rebuild (`SceneWallpaperViewModel.contentUserProperties`).
///
/// Always:
/// - Transform (`origin`, `scale`, `angles`): every object carries a `SceneObjectMotion` or a
///   layer's `SceneLayerBindings`, and children follow their live parents, in 2D and 3D. Lights
///   are left out: their out-of-plane depth (`SceneLightDepth`) is captured at build time.
/// - Colour (`color`, `alpha`, `brightness`) of image layers, applied per frame
///   (`SceneLayerBindings.baseValues`).
///
/// While the user edits properties (`ScenePropertyEditing`), also:
/// - Colour of text layers: rasterised white and coloured when drawn, or rasterised again in
///   their fill, from the same bindings.
/// - Visibility (`visible` of an object and of its effects): hidden objects and effects are built
///   too, and the renderer takes the user's visibility again on each change (`SceneUserVisibility`).
/// - Effect constants (an effect pass's `constantshadervalues`): a user-bound constant is a dynamic
///   source, resolved every frame (`ShaderConstantResolver.ResolvedConstants`).
/// - A particle system's `instanceoverride` but `count`: bound fields resolve every frame
///   (`ParticleFrameInputs`); the particle budget is estimated from `count` at build.
/// The wallpaper is rebuilt once when editing ends, so it is exactly what a fresh load draws.
///
/// Anything else (sizes, combos, materials, `general`) is captured when the content is built and
/// keeps rebuilding it.
enum SceneLiveBindingSites {
    static let transformFields = Set([SceneObjectValueField.origin, .scale, .angles].map(\.rawValue))
    static let colourFields = Set([SceneObjectValueField.color, .alpha, .brightness].map(\.rawValue))

    /// Whether field `key` of the scene object `object` is applied without a rebuild; `editing`
    /// adds the sites live while the user edits properties. `effects` and `instanceoverride` are
    /// live in part while editing (`liveEffectFields`, `livePassFields`, `isLiveInstanceOverride`).
    static func isLive(_ key: String, of object: [String: SceneJSON], editing: Bool = false) -> Bool {
        if transformFields.contains(key) { return object["light"] == nil }
        if editing, key == "visible" { return true }
        guard colourFields.contains(key) else { return false }
        if editing, object["text"] != nil { return true }
        guard case .string(let image)? = object["image"] else { return false }
        return !image.isEmpty
    }

    /// Fields of an entry of an object's `effects` applied without a rebuild while editing.
    static let liveEffectFields: Set<String> = ["visible"]
    /// Fields of an effect pass (an entry of an effect's `passes`) applied without a rebuild while editing.
    static let livePassFields: Set<String> = ["constantshadervalues"]

    /// Whether field `key` of a particle object's `instanceoverride` is applied without a rebuild
    /// while editing.
    static func isLiveInstanceOverride(_ key: String) -> Bool {
        key != SceneInstanceOverrideField.count.rawValue
    }
}
