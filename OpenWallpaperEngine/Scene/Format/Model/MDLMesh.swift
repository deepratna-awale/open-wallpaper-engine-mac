import Foundation

/// One mesh of an `MDLV` part (docs/models-plan.md §1.2): its materials, interleaved vertices and
/// a triangle list. The bytes are kept as the file has them, ready for a vertex and index buffer;
/// the accessors decode single attributes.
struct MDLMesh: Equatable {
    /// A group record of `MDLV` 23: a Puppet Warp clipping mask (`MDLClippingMask`, which reads
    /// it). Its lists index the mesh's `vector4Block`.
    struct Group: Equatable {
        var id: UInt64
        /// The mask's texture.
        var name: String
        /// `MDLClippingMask.Flags`.
        var flags: UInt32
        var listA: [UInt32]
        var listB: [UInt32]
    }

    /// The optional blob of `MDLV` 21 and later after a `u32` WE discards: one float3 per vertex,
    /// the vertices where the texture lays them out, `(uv − ½) · imageSize` with v flipped
    /// (docs/models-plan.md §1.2). WE's Puppet Warp editor writes it once a rig's mesh no longer
    /// is its texture's layout: "Lock Geometry for Vertex Editing" with Edit Deformation, or a
    /// stored Reference Pose (WE 2.8's capture 509 A and C; the `u32` was 1 both times). The
    /// vertices' `a_Position` then hold the moved or reference-posed mesh, which WE draws.
    struct ExtraPositions: Equatable {
        var discarded: UInt32
        var data: Data
    }

    /// One `vector4Block` record: four `u32`s, `(bone, 0, firstIndex, indexCount)`, the triangles
    /// of one bone's part (WE 2.8's capture 509 B). The records follow the bones' draw depth
    /// (`MDLSkeleton.boneDepths`), lowest first, and split the index buffer between them.
    struct BoneRange: Equatable {
        var bone: Int
        var firstIndex: Int
        var indexCount: Int
    }

    /// One material path per skin; a model object's `skin` picks one (§2.6).
    var materials: [String]
    /// Bit 0: u32 indices; 0x2: a Puppet Warp texture-channel mesh, `flagsExtra` follows;
    /// 0x4: `SKINNING_ALPHA`, which WE's Puppet Warp editor sets once a clip keys a bone's
    /// Opacity; 0x8: set once a clip keys a bone's Depth offset (`keyedDrawOrder`; WE 2.8's
    /// capture 509 F and B); 0x400/0x800/0x1000/0x2000: extra `MDMP` blobs per morph target,
    /// 0x2000 `MORPHING_MODIFIERS`.
    var flags: UInt32
    /// The `u32` after the flags when flags & 0x2: the channel material's `BLENDROWCOUNT`, the
    /// `vec4` rows of `g_BlendMap` (mesh+0x1c, read at 0x140209f28 and 0x1402079e5).
    var flagsExtra: UInt32?
    /// The authored box (`MDLV` 17 and later).
    var bounds: MDLBounds?
    var format: MDLVertexFormat
    /// `vertexCount` vertices of `format.stride` bytes.
    var vertexData: Data
    /// A triangle list of u16 or u32 (`usesUInt32Indices`) indices.
    var indexData: Data
    var extraPositions: ExtraPositions?
    /// 16-byte entries (`MDLV` 21 and later), kept as the file's bits: one `BoneRange` per bone
    /// in every Puppet Warp rig (`boneRanges`).
    var vector4Block: [SIMD4<Float>]?
    /// `MDLV` 23 and later.
    var groups: [Group]?

    var usesUInt32Indices: Bool { flags & 1 != 0 }
    var indexSize: Int { usesUInt32Indices ? 4 : 2 }
    var vertexCount: Int { format.stride == 0 ? 0 : vertexData.count / format.stride }
    var indexCount: Int { indexData.count / indexSize }
    /// Mesh flag 0x4.
    var usesSkinningAlpha: Bool { flags & 0x4 != 0 }
    /// Mesh flag 0x8: the parts' order is keyed in a clip (`ScenePuppetDrawOrder`).
    var keyedDrawOrder: Bool { flags & 0x8 != 0 }
    var isSkinned: Bool { format.contains(.blendIndices) }
    /// Mesh flag 0x2: the texture channels' quads of a puppet (`ScenePuppetChannelPlan`), whose
    /// `a_BlendIndices.x` names a channel's `g_BlendMap` entry, not a bone.
    var isTextureChannelMesh: Bool { flags & 0x2 != 0 }

    /// `vector4Block` read as `BoneRange`s; nil without the block or when a record's bone or
    /// triangles fall outside the skeleton's `boneCount` or the index buffer.
    func boneRanges(boneCount: Int) -> [BoneRange]? {
        guard let block = vector4Block, !block.isEmpty else { return nil }
        var ranges: [BoneRange] = []
        for entry in block {
            let bone = Int(entry.x.bitPattern), first = Int(entry.z.bitPattern), count = Int(entry.w.bitPattern)
            guard bone < boneCount, first % 3 == 0, count % 3 == 0, first + count <= indexCount else { return nil }
            ranges.append(BoneRange(bone: bone, firstIndex: first, indexCount: count))
        }
        return ranges
    }

    /// `extraPositions` as one point per vertex; nil without it or when its size isn't
    /// 12 · `vertexCount`.
    var textureLayoutPositions: [SIMD3<Float>]? {
        guard let blob = extraPositions?.data, blob.count == 12 * vertexCount else { return nil }
        return blob.withUnsafeBytes { raw in
            func float(_ at: Int) -> Float { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))) }
            return (0..<vertexCount).map { SIMD3(float(12 * $0), float(12 * $0 + 4), float(12 * $0 + 8)) }
        }
    }

    /// The indices, widened to u32.
    var indices: [UInt32] {
        indexData.withUnsafeBytes { raw in
            (0..<indexCount).map { index in
                usesUInt32Indices ? raw.loadUnaligned(fromByteOffset: 4 * index, as: UInt32.self).littleEndian
                    : UInt32(raw.loadUnaligned(fromByteOffset: 2 * index, as: UInt16.self).littleEndian)
            }
        }
    }

    /// Every vertex's `attribute`, flattened (`components` values per vertex); nil when the
    /// format lacks it. `a_BlendIndices` reads as floats of the integers: use `unsignedValues`.
    func floatValues(_ attribute: MDLVertexAttribute) -> [Float]? {
        values(attribute).map { $0.map(Float.init(bitPattern:)) }
    }

    /// Every vertex's `attribute` as raw little-endian u32s (the integer `a_BlendIndices`, or a
    /// float's bit pattern); nil when the format lacks it.
    func unsignedValues(_ attribute: MDLVertexAttribute) -> [UInt32]? { values(attribute) }

    private func values(_ attribute: MDLVertexAttribute) -> [UInt32]? {
        guard let offset = format.offset(of: attribute) else { return nil }
        let stride = format.stride
        let count = vertexCount
        return vertexData.withUnsafeBytes { raw in
            var out: [UInt32] = []
            out.reserveCapacity(count * attribute.components)
            for vertex in 0..<count {
                for component in 0..<attribute.components {
                    out.append(raw.loadUnaligned(fromByteOffset: vertex * stride + offset + 4 * component, as: UInt32.self).littleEndian)
                }
            }
            return out
        }
    }
}
