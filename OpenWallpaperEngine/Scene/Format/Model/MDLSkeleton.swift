import simd

/// The `MDLS` section, versions 1–4 (docs/models-plan.md §1.3): the bones, then (version 2 and
/// later) links, bind matrices, constraints, u32-keyed maps, IK sets and per-bone blocks. Every
/// library file with version 2 or later has links, constraints, maps and IK sets empty.
struct MDLSkeleton: Equatable {
    /// A "link" record (0x80 bytes at model+0x78; the writer's `controllers` [I]).
    struct Link: Equatable {
        var name: String
        var bone: UInt32
        /// 0 or 1: which of WE's two bone → link maps it goes in.
        var type: UInt32
        var matrix: simd_float4x4
    }

    /// A constraint (the writer's `blendrules` [I]: a/b = target/mode, f0/f1 = amin/amax).
    struct Constraint: Equatable {
        var bone: UInt32
        var a: UInt32
        var b: UInt32
        /// Read from version 4 on, else 0. Bit 1: the two floats follow.
        var flags: UInt32
        var f0: Float?
        /// WE clamps it to at least FLT_EPSILON when it uses it; this is the file's value.
        var f1: Float?
    }

    /// One `u32 key → 12 bytes` entry of the maps WE keeps at model+0xf0 [?].
    struct MapEntry: Equatable {
        var key: UInt32
        var value: SIMD3<Float>
    }

    struct IKSet: Equatable {
        struct Joint: Equatable {
            var bone: UInt32
            /// Bit 2 sets the IK set's flag at +0x38.
            var flags: UInt32
            var f0: Float
            var f1: Float
            var bones: [UInt32]
        }

        struct Element: Equatable {
            var bone: UInt32
            var joints: [Joint]
        }

        var bone: UInt32
        /// Indices into `links`.
        var links: [UInt32]
        var elements: [Element]
    }

    /// The optional per-bone `{vec3, mat4}` block (model+0x1a0) [?].
    struct BoneVector: Equatable {
        var vector: SIMD3<Float>
        var matrix: simd_float4x4
    }

    var version: Int
    var bones: [MDLBone]
    /// Version 2 and later, else empty (as are the lists below).
    var links: [Link] = []
    /// One per bone, when the file has the optional block (model+0x48).
    var bindMatrices: [simd_float4x4]?
    /// One per link, with `bindMatrices` (model+0x90).
    var linkBindMatrices: [simd_float4x4]?
    var constraints: [Constraint] = []
    var mapIDs: [UInt32] = []
    /// One map per `mapIDs` entry, in file order.
    var maps: [[MapEntry]] = []
    var ikSets: [IKSet] = []
    var boneVectors: [BoneVector]?
    /// One bone index per bone (model+0x1d0, which WE clamps to the last bone): in Puppet Warp
    /// rigs, the bones by draw depth, the order of the mesh's `BoneRange`s.
    var boneIndices: [UInt32]?
    /// Version 3 and later: one u32 per bone (model+0x1e8), each bone's draw depth as a signed
    /// integer (`boneDepths`).
    var bonePriorities: [UInt32]?

    /// `bonePriorities` as WE's editor writes them: Puppet Warp's "Limb Depth Order", the bone's
    /// Calculated depth (default 100 per bone in order, plus its Depth offset; "Move Limb to Back"
    /// takes 100 off, WE 2.8's capture 509 B), signed (−100 is 0xFFFFFF9C). The editor already
    /// sorts the mesh's index ranges by it, lowest first, so a static depth needs nothing at run
    /// time; a clip's keyed Depth offset (`MDLAnimation.boneDepthTracks`) reorders them.
    var boneDepths: [Int32]? { bonePriorities?.map { Int32(bitPattern: $0) } }

    /// Each bone's bind pose in model space: `local · world(parent)` in WE's row-vector order,
    /// that is `world(parent) · local` for these column-vector matrices [I, consistent in the
    /// data]. Parents come before their children in every library file; a bone whose parent is
    /// out of range, or not yet computed, is taken as a root.
    var bindPoseWorldMatrices: [simd_float4x4] {
        var world: [simd_float4x4] = []
        world.reserveCapacity(bones.count)
        for (index, bone) in bones.enumerated() {
            if let parent = bone.parentIndex, parent < index {
                world.append(world[parent] * bone.matrix)
            } else {
                world.append(bone.matrix)
            }
        }
        return world
    }
}
