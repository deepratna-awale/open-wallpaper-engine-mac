import Foundation

/// One mesh's morph targets (blend shapes) from the `MDMP0001` section (docs/models-plan.md
/// §1.5). No library file has the section; the layout is the reader's and the writer's, and WE's
/// editor wrote one for docs/test-risks.md MG5.
struct MDLMorphTargets: Equatable {
    struct Target: Equatable {
        /// The writer's `modifierbone`, `modifiermode`, `modifierstartdistance` and
        /// `modifierenddistance` (mesh flag 0x2000, `MORPHING_MODIFIERS`).
        struct Modifier: Equatable {
            var bone: UInt32
            var mode: UInt32
            var startDistance: Float
            var endDistance: Float
        }

        var id: UInt64
        var name: String
        /// A float3 per vertex, the position deltas over the mesh's `weight`: 16-bit signed
        /// normalised values, which WE copies as they are into its RGBA16 SNORM morph texture
        /// (format 0x13 → DXGI 13, 0x1400d2a4d; the editor's MG5 shape: 0x7FB1 · 126.47 / 32767 is
        /// its +126.168 x).
        var positions: [Float]
        /// Mesh flag 0x400: normal deltas, like `positions` [I].
        var normals: [Float]?
        /// Mesh flag 0x800: tangent deltas, like `positions` [I].
        var tangents: [Float]?
        /// Mesh flag 0x1000: a 16-bit value per morph vertex, the texel's fourth (alpha) channel
        /// on puppets (the editor's mask alpha [I]).
        var extra: Data?
        var modifier: Modifier?
    }

    /// The mesh's index.
    var mesh: Int
    /// With targets: WE's `g_MorphWeights[0]` (mesh+0x60), the scale the normalised deltas are
    /// multiplied by: the editor writes the largest delta's length (MG5: 126.47 for a shape moving
    /// one vertex by (126.168, 0, 8.7)).
    var weight: Float?
    /// With targets: the vertices each target covers, clamped by WE to what the smallest position
    /// blob holds (0x14026578f).
    var vertexCount: UInt32?
    var targets: [Target]
}

extension MDLMorphTargets {
    /// A 16-bit signed normalised value as the GPU reads it: `max(v / 32767, −1)`.
    static func float(snormBits bits: UInt16) -> Float {
        max(Float(Int16(bitPattern: bits)) / 32767, -1)
    }

    /// `value` as 16-bit signed normalised bits, rounded to nearest and clamped to ±1: exact for
    /// the `.mdl`'s values, which `float(snormBits:)` read.
    static func snormBits(_ value: Float) -> UInt16 {
        let scaled = (min(max(value, -1), 1) * 32767).rounded()
        return UInt16(bitPattern: Int16(scaled))
    }
}
