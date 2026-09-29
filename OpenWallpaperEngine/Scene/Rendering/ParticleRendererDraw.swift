import simd

/// One entry of a particle system's `renderers`: what it draws the system's particles as. WE draws
/// every renderer of a system, in authored order, from the one simulation; the system's own fields
/// (`SceneMetalParticleSystem.rendererName` and the rest) are the first's, and
/// `SceneMetalParticleSystem.additionalRenderers` holds the others.
/// `ParticleSystemBuilder.rendererDraw` makes it from the json with WE's defaults.
struct ParticleRendererDraw {
    /// `sprite`, `spritetrail`, `rope` or `ropetrail`.
    var name: String
    /// `SceneMetalParticleSystem.trailLength`.
    var trailLength: Float
    /// `spritetrail`'s `maxlength` and `minlength`.
    var trailLengthLimits: SIMD2<Float>
    /// `ropetrail`'s `segments`.
    var trailSegments: Int
    /// `subdivision` (`TRAILSUBDIVISION`).
    var ropeSubdivision: Int
    var fadeTrailAlpha: Bool
    var fadeTrailSize: Bool
    var orientation: ParticleOrientation
    var ropeUV: ParticleRopeUV
    /// The system's material with this renderer's combos; nil keeps the built-in particle draw.
    var material: ParticleMaterialPlan? = nil
}

/// The trail history the simulation keeps for a `ropetrail` renderer: a sample every
/// `length / segments` seconds, `segments` of them per particle.
struct ParticleTrailHistory: Equatable {
    /// A renderer of the system is a `ropetrail`.
    var kept: Bool
    /// That renderer's `length` (seconds of history) and `segments`.
    var length: Float
    var segments: Int
}
