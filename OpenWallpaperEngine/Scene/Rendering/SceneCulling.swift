import simd

/// Which layers a frame can skip without changing a pixel (docs/efficiency-plan-2d.md WP2-B):
/// layers whose drawing lands wholly outside the scene target, alpha-0 layers, and layers wholly
/// under one strictly opaque layer.
///
/// Lossless by construction and conservative throughout:
/// - a protected layer (a composite source, one that reads the scene, text, a puppet) is never culled;
/// - bounds are trusted only when the layer's output is confined to its quad (no effects, a plain
///   material); otherwise the layer counts as covering the whole scene;
/// - occlusion only counts one opaque layer that contains the whole bounds (a pixel margin
///   included), and never when anything drawn above the layer samples the frame beneath.
enum SceneCulling {
    /// Why a layer was skipped (for counters and tests).
    enum Reason: Equatable {
        case offTarget
        case transparent
        case occluded(by: Int)
    }

    /// One layer of the frame, in draw order (bottom first).
    struct Layer {
        /// The caller's index for the layer.
        var index: Int
        /// Where it can draw this frame, in scene units, clipped to the scene.
        var coverage: SceneLayerCoverage
        /// Its output stays inside `coverage` (no effect or material can move pixels outside the quad).
        var confinedToQuad: Bool
        /// Live opacity times colour alpha; nil when not known yet (an opaque coverage already
        /// proves it is 1 for an occluder).
        var opacity: Float?
        /// Never culled: a composite source, a scene reader, text, a puppet, a hidden layer that still
        /// runs for its readers.
        var protected: Bool
        /// Samples the frame beneath it (`_rt_FullFrameBuffer`, the mip-mapped frame, the snapshot).
        var readsFrameBeneath: Bool
        /// Visible this frame: only a visible layer can occlude.
        var visible: Bool
    }

    /// The layers to skip, by caller index, with why. `sceneSize` in scene units; `margin` is the
    /// scene-unit size of a pixel or more (rasterisation at the occluder's edges).
    /// `occlusionAllowed` is false when something other than a layer samples the scene (refracting
    /// particles, models, a depth-tested pass).
    static func cull(_ layers: [Layer], sceneSize: SIMD2<Float>, margin: Float, occlusionAllowed: Bool) -> [Int: Reason] {
        var culled: [Int: Reason] = [:]
        guard !layers.isEmpty else { return culled }
        // Does anything above position i sample the frame beneath?
        var readerAbove = [Bool](repeating: false, count: layers.count)
        var seen = false
        for position in layers.indices.reversed() {
            readerAbove[position] = seen
            if layers[position].readsFrameBeneath { seen = true }
        }
        let whole = SceneLayerCoverage.full(sceneSize)
        // Occluders: visible, strictly opaque, bounded.
        let occluders: [Int] = occlusionAllowed ? layers.indices.filter { position in
            let layer = layers[position]
            return layer.visible && layer.coverage.opaque && !layer.coverage.fullScene && !layer.coverage.isEmpty
                && (layer.opacity ?? 1) >= 1
        } : []
        for (position, layer) in layers.enumerated() where !layer.protected && layer.visible {
            if layer.confinedToQuad, layer.coverage.isEmpty {
                culled[layer.index] = .offTarget
                continue
            }
            if layer.confinedToQuad, let opacity = layer.opacity, opacity <= 0 {
                culled[layer.index] = .transparent
                continue
            }
            guard !readerAbove[position] else { continue }
            let bounds = layer.confinedToQuad ? layer.coverage : whole
            for occluder in occluders where occluder > position {
                if contains(layers[occluder].coverage, bounds, margin: margin, sceneSize: sceneSize) {
                    culled[layer.index] = .occluded(by: layers[occluder].index)
                    break
                }
            }
        }
        return culled
    }

    /// The layer's pixels stay inside its quad: no effect (an effect's last pass can move its
    /// vertices), a plain material, drawn in the scene's plane.
    static func confinedToQuad(_ layer: SceneMetalLayer, perspectiveScene: Bool) -> Bool {
        guard layer.weEffects.isEmpty, !layer.perspective, !perspectiveScene, !layer.fillsScene, !layer.sceneInput else {
            return false
        }
        guard let material = layer.imageMaterial else { return true }
        return material.prelighting == nil && material.materialPath.lowercased().contains("genericimage")
    }

    /// Layers whose drawing others depend on, or that keep per-frame state: never culled nor
    /// flattened. `compositeSources` holds the layers another layer or a model samples;
    /// `inScene` the layers that run their effects inside the scene pass.
    static func isProtected(_ layer: SceneMetalLayer, compositeSources: Set<String>, inScene: Set<String>) -> Bool {
        compositeSources.contains(layer.id) || inScene.contains(layer.id) || layer.readsScene
            || layer.text != nil || layer.puppet != nil
    }

    /// Whether a layer drawn at `opacity` (opacity times colour alpha) leaves every pixel as it was.
    static func isTransparent(opacity: Float, confinedToQuad: Bool, protected: Bool) -> Bool {
        !protected && confinedToQuad && opacity <= 0
    }

    /// `outer` contains `inner` with `margin` to spare on every side that isn't the scene's edge
    /// (nothing is drawn past the edge, so the edge needs no margin).
    static func contains(_ outer: SceneLayerCoverage, _ inner: SceneLayerCoverage, margin: Float,
                         sceneSize: SIMD2<Float>) -> Bool {
        let innerMin = inner.fullScene ? .zero : inner.min
        let innerMax = inner.fullScene ? sceneSize : inner.max
        func side(_ outerEdge: Float, _ innerEdge: Float, lower: Bool, sceneEdge: Float) -> Bool {
            if lower {
                return outerEdge <= 0 ? true : outerEdge + margin <= innerEdge
            }
            return outerEdge >= sceneEdge ? true : outerEdge - margin >= innerEdge
        }
        return side(outer.min.x, innerMin.x, lower: true, sceneEdge: 0)
            && side(outer.min.y, innerMin.y, lower: true, sceneEdge: 0)
            && side(outer.max.x, innerMax.x, lower: false, sceneEdge: sceneSize.x)
            && side(outer.max.y, innerMax.y, lower: false, sceneEdge: sceneSize.y)
    }
}
