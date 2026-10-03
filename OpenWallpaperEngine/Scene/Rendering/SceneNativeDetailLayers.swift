import simd

/// Which "detail" layers draw at the output's backing pixels instead of in the scene pass.
///
/// Under Render Resolution "Display" (or a MetalFX render scale below 1) the scene target has
/// fewer pixels than the output and is scaled up onto it, which stretches text and the media
/// artwork 2×. A detail layer (text, or an image whose texture is the now-playing artwork) whose
/// pixels nothing after it reads or covers can instead be drawn onto the output once the scene is
/// placed there: the same quad, opacity, colour and blend over the same pixels beneath it, so the
/// frame layers exactly as before, only sharper. Everything else stays in the scene pass.
enum SceneNativeDetailLayers {
    /// One object of the scene pass, in WE's draw order.
    enum Item: Equatable {
        /// A layer drawn this frame: its index, its pixels in the scene target (nil for a layer
        /// whose footprint isn't known, such as one placed through a 3D camera), whether it reads
        /// the scene drawn before it, and whether it may be promoted on its own (`isCandidate`).
        case layer(index: Int, bounds: SceneSnapshotTracker.Rect?, readsScene: Bool, candidate: Bool)
        /// A model or particle system: its footprint isn't tracked, so it covers everything.
        case unbounded
    }

    /// A layer may leave the scene pass when it is a detail layer (text or the media artwork),
    /// drawn and visible, not sampled by a model or another layer, without effects of its own
    /// (its text's font effects are in its raster), not reading the scene, not a puppet and drawn
    /// in the scene's plane (no 3D placement, which tests the scene's depth).
    static func isCandidate(isText: Bool, isMediaImage: Bool, visible: Bool, compositeSource: Bool,
                            hasLayerEffects: Bool, readsScene: Bool, isPuppet: Bool, placed3D: Bool) -> Bool {
        (isText || isMediaImage) && visible && !compositeSource && !hasLayerEffects && !readsScene
            && !isPuppet && !placed3D
    }

    /// Whether drawing at the output gains any pixels: the output has more of them per scene unit
    /// than the scene pass (Display on a Retina panel, or a render scale below 1). Not at Retina
    /// with no render scale, where the two match.
    static func gainsDetail(scenePixelsPerUnit: Float, outputPixelsPerUnit: Float) -> Bool {
        scenePixelsPerUnit > 0 && outputPixelsPerUnit.isFinite && outputPixelsPerUnit > scenePixelsPerUnit * 1.01
    }

    /// The layers of `items` promoted to the native pass. Walking from the last object drawn back,
    /// a candidate is promoted when nothing kept in the scene pass after it reads the scene or
    /// touches its pixels (`padding` scene-target pixels around it, for the upscale's filter). A
    /// later promoted layer doesn't block it: the native pass keeps their order.
    static func promoted(_ items: [Item], padding: Int = 1) -> Set<Int> {
        var promoted = Set<Int>()
        var covered: [SceneSnapshotTracker.Rect] = []
        var blocked = false
        for item in items.reversed() {
            switch item {
            case .unbounded:
                blocked = true
            case let .layer(index, bounds, readsScene, candidate):
                if candidate, !blocked, let bounds {
                    let grown = SceneSnapshotTracker.Rect(x: bounds.x - padding, y: bounds.y - padding,
                                                          width: bounds.width + 2 * padding,
                                                          height: bounds.height + 2 * padding)
                    if !covered.contains(where: { $0.intersection(grown) != nil }) {
                        promoted.insert(index)
                        continue
                    }
                }
                if readsScene { blocked = true }
                if let bounds { covered.append(bounds) } else { blocked = true }
            }
        }
        return promoted
    }

    /// Where the composite puts the scene on the output: its rect in output pixels (origin at the
    /// top left, as a Metal viewport takes it), from the composite's quad (`layerUniform` of the
    /// whole scene, centred on the output for every placement).
    static func placedViewport(center: SIMD2<Float>, size: SIMD2<Float>, outputSize: SIMD2<Float>)
        -> (origin: SIMD2<Float>, size: SIMD2<Float>) {
        (SIMD2(center.x - size.x / 2, outputSize.y - center.y - size.y / 2), size)
    }
}
