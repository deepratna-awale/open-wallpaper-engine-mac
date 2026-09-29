import simd

/// Skips an opaque model the distance fog paints over entirely, when that paint is the colour the
/// scene is cleared to, so skipping it leaves the same pixels.
///
/// `common_fog.h` ends a fogged material's colour with `mix(color, g_FogDistanceColor, z + w·f²)`,
/// `f = saturate((|eye − position| − start) / (end − start))`: at or beyond `fogdistanceend` the
/// factor is the end density, and at exactly 1 the fragment is the fog colour whatever the material
/// computed before (height fog is mixed in first, so it is overwritten too). An opaque pass writes
/// that colour; with it equal to `general.clearcolor` over a cleared target, not drawing the model
/// changes nothing.
enum SceneModelFogCulling {
    /// The fog paints anything at or beyond its end the clear colour: distance fog on, a whole
    /// density there, a range that ends past its start, and the fog colour equal to `clearColor`.
    static func coversWithClearColor(_ fog: SceneFogSettings, clearColor: SIMD3<Float>) -> Bool {
        let params = fog.distanceParams
        return fog.distance && params.y > 0 && params.z + params.w == 1 && fog.distanceColor == clearColor
    }

    /// Every point of `bounds` through `world` lies at least `fog.distanceEnd` from `eye`. The
    /// sphere encloses all eight corners (WE's cull sphere spans one diagonal only, which a
    /// sheared box can exceed), so no fragment is nearer.
    static func isBeyondFog(_ bounds: MDLBounds, world: simd_float4x4, eye: SIMD3<Float>, fog: SceneFogSettings) -> Bool {
        guard bounds != .unbounded, bounds.max.x >= bounds.min.x else { return false }
        let middle = (bounds.min + bounds.max) / 2
        let centre4 = world * SIMD4<Float>(middle, 1)
        let centre = SIMD3<Float>(centre4.x, centre4.y, centre4.z)
        var radius: Float = 0
        for corner in 0..<8 {
            let local = SIMD3<Float>(corner & 1 == 0 ? bounds.min.x : bounds.max.x,
                                     corner & 2 == 0 ? bounds.min.y : bounds.max.y,
                                     corner & 4 == 0 ? bounds.min.z : bounds.max.z)
            let point = world * SIMD4<Float>(local, 1)
            radius = max(radius, simd_distance(SIMD3<Float>(point.x, point.y, point.z), centre))
        }
        let nearest = simd_distance(centre, eye) - radius
        return nearest.isFinite && nearest >= fog.distanceEnd
    }

    /// Every mesh of `plan` ends in the distance fog and writes it opaquely: an opaque blend
    /// (not alpha-to-coverage, whose coverage shows what's behind), compiled with `FOG_DIST`
    /// and not `ADDITIVE`, and a fragment stage that never discards.
    static func fogsEveryMesh(_ plan: SceneModelPlan) -> Bool {
        !plan.meshes.isEmpty && plan.meshes.allSatisfy { mesh in
            let material = mesh.material
            guard material.isOpaque, !material.alphaToCoverage, let variant = material.pass.variant else { return false }
            return variant.combos["FOG_DIST"] == 1 && (variant.combos["ADDITIVE"] ?? 0) == 0
                && !variant.fragmentMSL.contains("discard_fragment")
        }
    }
}
