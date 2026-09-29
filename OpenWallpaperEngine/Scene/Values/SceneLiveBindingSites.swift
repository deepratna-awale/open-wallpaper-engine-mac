/// Which user-binding sites of a scene object the renderer re-resolves every frame, so a user
/// property read only there needs no content rebuild (`SceneWallpaperViewModel.contentUserProperties`).
///
/// - Transform (`origin`, `scale`, `angles`): every object carries a `SceneObjectMotion` or a
///   layer's `SceneLayerBindings`, and children follow their live parents, in 2D and 3D. Lights
///   are left out: their out-of-plane depth (`SceneLightDepth`) is captured at build time.
/// - Colour (`color`, `alpha`, `brightness`): image layers apply them per frame
///   (`SceneLayerBindings.baseValues`). Other kinds bake them at build time, so they still rebuild.
///
/// Anything else (visibility, sizes, effect constants, `general`) is captured when the content is
/// built and keeps rebuilding it.
enum SceneLiveBindingSites {
    static let transformFields = Set([SceneObjectValueField.origin, .scale, .angles].map(\.rawValue))
    static let colourFields = Set([SceneObjectValueField.color, .alpha, .brightness].map(\.rawValue))

    /// Whether field `key` of the scene object `object` is re-resolved every frame.
    static func isLive(_ key: String, of object: [String: SceneJSON]) -> Bool {
        if transformFields.contains(key) { return object["light"] == nil }
        guard colourFields.contains(key), case .string(let image)? = object["image"] else { return false }
        return !image.isEmpty
    }
}
