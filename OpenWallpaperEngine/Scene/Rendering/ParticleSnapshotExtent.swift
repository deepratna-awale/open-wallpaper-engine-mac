import simd

/// Where a refracting particle system's draw can read the scene snapshot (`_rt_FullFrameBuffer`),
/// so only that part of the scene is copied for it.
///
/// `genericparticle.frag` samples the snapshot at the fragment's screen position plus
/// `v_ScreenTangents · normal.xy · normal.a · v_Color.a`, where the tangents are unit axes dotted
/// with unit view axes times `g_RefractAmount` (`ComputeScreenRefractionTangents`). Each component
/// of that offset is at most `2·|g_RefractAmount|·alpha` in texture coordinates, so the rect is the
/// particles' screen box padded by that much of the target on each side.
///
/// Built from the CPU sprite records of a plain `sprite` renderer drawn through the orthographic
/// scene view; anything else (GPU records, trails, ropes, a 3D placement, a bound or scripted
/// refraction amount) has no known extent and copies the whole scene.
struct ParticleSnapshotExtent: Equatable {
    /// The particles' quads, scene units (y up).
    var low: SIMD2<Float>
    var high: SIMD2<Float>
    /// The largest record alpha, which scales the refraction offset.
    var alpha: Float

    /// The box around `records`' quads, or nil when none has a finite position and size.
    /// `spriteLinear` is the quad axes' transform (`ParticleSystemRuntime.spriteLinear`) and
    /// `aspect` texture 0's height over width, which a sprite-sheet frame or the texture's shape
    /// stretches the quad's height by.
    init?(records: UnsafeBufferPointer<ParticleSpriteInstance>, spriteLinear: simd_float2x2, aspect: Float) {
        // The quad's half-diagonal is at most its width times the larger of 1 and the aspect,
        // through the axes' largest stretch (bounded by the Frobenius norm).
        let stretch = sqrt(simd_length_squared(spriteLinear.columns.0) + simd_length_squared(spriteLinear.columns.1))
        let shape = aspect.isFinite && aspect > 0 ? max(1, aspect, 1 / aspect) : 1
        var low = SIMD2<Float>(repeating: .infinity)
        var high = SIMD2<Float>(repeating: -.infinity)
        var alpha: Float = 0
        for record in records {
            let centre = SIMD2(record.position.x, record.position.y)
            let radius = abs(record.rotationSize.w) * stretch * shape
            guard centre.x.isFinite, centre.y.isFinite, radius.isFinite else { continue }
            low = simd_min(low, centre - radius)
            high = simd_max(high, centre + radius)
            if record.color.w.isFinite { alpha = max(alpha, abs(record.color.w)) }
        }
        guard low.x <= high.x, low.y <= high.y else { return nil }
        self.low = low
        self.high = high
        self.alpha = alpha
    }

    /// The target pixels the draw may read with refraction `amount`, clamped to the target
    /// (`SceneSnapshotTracker.Rect`, y down); `.empty` when none.
    func pixelRect(refractAmount amount: Float, sceneSize: SIMD2<Float>, targetSize: SIMD2<Int>) -> SceneSnapshotTracker.Rect {
        let target = SIMD2<Float>(Float(targetSize.x), Float(targetSize.y))
        let scale = target / simd_max(sceneSize, SIMD2<Float>(1, 1))
        // Refraction offset (texture coordinates) in pixels, plus the tracker's filtering padding.
        let reach = 2 * abs(amount) * max(alpha, 1) * target + Float(SceneSnapshotTracker.padding)
        let left = low.x * scale.x - reach.x, right = high.x * scale.x + reach.x
        let top = target.y - high.y * scale.y - reach.y, bottom = target.y - low.y * scale.y + reach.y
        guard left.isFinite, right.isFinite, top.isFinite, bottom.isFinite else {
            return SceneSnapshotTracker.Rect(x: 0, y: 0, width: targetSize.x, height: targetSize.y)
        }
        let x0 = Int(min(max(left.rounded(.down), 0), target.x)), x1 = Int(min(max(right.rounded(.up), 0), target.x))
        let y0 = Int(min(max(top.rounded(.down), 0), target.y)), y1 = Int(min(max(bottom.rounded(.up), 0), target.y))
        guard x1 > x0, y1 > y0 else { return .empty }
        return SceneSnapshotTracker.Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
