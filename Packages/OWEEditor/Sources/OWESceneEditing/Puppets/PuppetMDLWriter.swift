import Foundation
import simd

/// Writes a document as WE's editor writes a puppet today (docs/models-plan.md §1): `MDLV0023`
/// with one mesh in the puppet format (`0x1800009`: position, four bone indices, four weights,
/// texture coordinate; `a_PositionVec4` instead of the position while the rig keeps blend
/// shapes), then the sections `MDLS0004` (bones, their properties JSON, the rest pose when it
/// differs, the per-bone blocks the rig had), `MDLA0006` (one track per bone, `frames + 1`
/// samples of position, Euler angles and scale), and the kept `MDAT0001`, `MDMP0001` and
/// `MDLE0002`, then the empty tag. Every field is laid out as the app's `MDLReader` reads it.
public enum PuppetMDLWriter {
    /// WE's limit (0x140262501).
    public static let maximumBones = 128
    public static let meshTag = "MDLV0023"
    public static let skeletonTag = "MDLS0004"
    public static let animationTag = "MDLA0006"

    public enum WriteError: Error, Equatable, LocalizedError {
        case problems([PuppetProblem])

        public var errorDescription: String? {
            "The puppet isn't finished: it needs a mesh, at most \(maximumBones) bones, and every vertex weighted."
        }
    }

    /// The `.mdl` bytes.
    public static func write(_ document: PuppetDocument) throws -> Data {
        let problems = document.problems
        guard problems.isEmpty else { throw WriteError.problems(problems) }
        var out = PuppetMDLOutput()
        writeMesh(document, into: &out)
        out.section(skeletonTag, skeleton(document))
        if !document.clips.isEmpty { out.section(animationTag, animations(document)) }
        if !document.preserved.attachments.isEmpty { out.section("MDAT0001", attachments(document)) }
        if let morphs = document.preserved.morphSection, document.preserved.morphIndices?.count == document.mesh.vertices.count {
            out.section("MDMP0001", [UInt8](morphs))
        }
        if let pose = document.preserved.referencePose, pose.count == document.bones.count {
            var body = PuppetMDLOutput()
            body.u32(UInt32(64 * pose.count))
            for matrix in pose { body.f32s(matrix) }
            out.section("MDLE0002", body.bytes)
        }
        out.cstring("")
        return Data(out.bytes)
    }

    // MARK: MDLV

    /// Whether the mesh is written with `a_PositionVec4` (its blend shapes' morph indices).
    static func hasMorphs(_ document: PuppetDocument) -> Bool {
        document.preserved.morphSection != nil && document.preserved.morphIndices?.count == document.mesh.vertices.count
    }

    static func format(_ document: PuppetDocument) -> UInt32 {
        hasMorphs(document) ? PuppetVertexLayout.puppet & ~PuppetVertexLayout.position | PuppetVertexLayout.positionVec4
            : PuppetVertexLayout.puppet
    }

    private static func writeMesh(_ document: PuppetDocument, into out: inout PuppetMDLOutput) {
        let format = format(document)
        let morphs = hasMorphs(document) ? document.preserved.morphIndices : nil
        let vertexCount = document.mesh.vertices.count
        let wide = vertexCount > Int(UInt16.max)
        let channels = document.preserved.textureChannels ?? []
        out.cstring(meshTag)
        out.u32(PuppetVertexLayout.puppet) // the legacy format WE's editor still fills in
        out.u32(1)
        out.u32(UInt32(1 + channels.count))
        out.cstring(document.material)
        var flags = document.preserved.meshFlags & ~1
        if wide { flags |= 1 }
        if document.preserved.meshFlagsExtra == nil { flags &= ~2 }
        out.u32(flags)
        if flags & 2 != 0, let extra = document.preserved.meshFlagsExtra { out.u32(extra) }
        let bounds = boundsOf(document.mesh.vertices.map(\.position))
        let depths = document.mesh.vertices.map { $0.depth ?? 0 }
        out.f32s([bounds.min.x, bounds.min.y, depths.min() ?? 0, bounds.max.x, bounds.max.y, depths.max() ?? 0])
        out.u32(format)
        var vertices = PuppetMDLOutput()
        for (index, vertex) in document.mesh.vertices.enumerated() {
            vertices.f32s([vertex.position.x, vertex.position.y, vertex.depth ?? 0])
            if let morphs { vertices.f32(morphs[index]) }
            let entries = index < document.weights.count ? document.weights[index] : []
            for slot in 0..<4 { vertices.u32(slot < entries.count ? UInt32(entries[slot].bone) : 0) }
            for slot in 0..<4 { vertices.f32(slot < entries.count ? entries[slot].weight : 0) }
            vertices.f32s([vertex.uv.x, vertex.uv.y])
        }
        out.blob(vertices.bytes)
        var indices = PuppetMDLOutput()
        for triangle in document.mesh.triangles {
            for index in [triangle.x, triangle.y, triangle.z] {
                if wide { indices.u32(index) } else { indices.u16(UInt16(index)) }
            }
        }
        out.blob(indices.bytes)
        out.u8(0) // no second position set
        out.u8(0) // no vector4 block
        out.u32(0) // no groups
        // The texture channels' meshes as they were: their quads are in the image's pixels, not the puppet's mesh.
        for channel in channels { out.raw([UInt8](channel.bytes)) }
    }

    static func boundsOf(_ points: [SIMD2<Float>]) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        guard var low = points.first else { return (.zero, .zero) }
        var high = low
        for point in points {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        return (low, high)
    }

    // MARK: MDLS

    /// Each bone's properties: its physics compiled as WE's compiler writes them over the keys
    /// the editor doesn't edit.
    public static func boneProperties(_ document: PuppetDocument) -> [[String: SceneJSONValue]] {
        let worlds = document.bindWorlds
        return document.bones.indices.map { index in
            let bone = document.bones[index]
            var properties = bone.otherProperties
            if let physics = bone.physics {
                let child = document.children(of: index).first
                let distance = child.map { simd_distance(PuppetMath.origin(of: worlds[$0]), PuppetMath.origin(of: worlds[index])) }
                for (key, value) in physics.properties(childDistance: distance) { properties[key] = value }
            }
            return properties
        }
    }

    static func propertiesJSON(_ properties: [String: SceneJSONValue]) -> String {
        guard !properties.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(properties) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func skeleton(_ document: PuppetDocument) -> [UInt8] {
        var out = PuppetMDLOutput()
        let properties = boneProperties(document)
        out.u32(UInt32(document.bones.count))
        for (index, bone) in document.bones.enumerated() {
            out.cstring(bone.name)
            out.u32(bone.flags)
            out.u32(bone.parent.map { UInt32($0) } ?? 0xFFFF_FFFF)
            out.u32(64)
            out.matrix(bone.local.matrix)
            out.cstring(propertiesJSON(properties[index]))
        }
        out.u16(0) // links
        let hasRest = document.bones.contains { $0.rest != nil }
        out.u8(hasRest ? 1 : 0)
        if hasRest {
            for bone in document.bones { out.matrix((bone.rest ?? bone.local).matrix) }
        }
        out.u32(0) // constraints
        out.u16(0) // maps
        out.u16(0) // IK sets
        let count = document.bones.count
        if let boxes = document.preserved.boneBoxes, boxes.count == count {
            out.u8(1)
            for box in boxes {
                out.f32s([box.vector.x, box.vector.y, box.vector.z])
                out.f32s(box.matrix)
            }
        } else {
            out.u8(0)
        }
        if let indices = document.preserved.boneIndices, indices.count == count {
            out.u8(1)
            for index in indices { out.u32(min(index, UInt32(count - 1))) }
        } else {
            out.u8(0)
        }
        if let priorities = document.preserved.bonePriorities, priorities.count == count {
            out.u8(1)
            for priority in priorities { out.u32(priority) }
        } else {
            out.u8(0)
        }
        return out.bytes
    }

    // MARK: MDLA

    private static func animations(_ document: PuppetDocument) -> [UInt8] {
        var out = PuppetMDLOutput()
        let rest = document.restLocals
        let rig = PuppetRig(document)
        out.i32(Int32(document.clips.count))
        for (index, clip) in document.clips.enumerated() {
            let frames = max(clip.frames, 1)
            var flags = clip.flags
            var record: PuppetClip.RootMotion?
            if let motion = clip.rootMotion, let source = motion.sourceClip, source < index {
                record = motion
            } else {
                flags &= ~PuppetClip.RootMotion.referenceFlag
            }
            out.u64(clip.id)
            out.cstring(clip.name)
            out.cstring(clip.modeName ?? clip.mode.rawValue)
            out.f32(clip.fps)
            out.u32(UInt32(frames))
            out.u32(flags)
            out.i32(Int32(document.bones.count))
            for bone in document.bones.indices {
                let samples = PuppetClipBaker.samples(of: clip, bone: bone, rest: rest[bone])
                out.u32(samples == nil ? 1 : 0)
                var blob = PuppetMDLOutput()
                for frame in 0...frames {
                    blob.f32s((samples.map { $0[min(frame, $0.count - 1)] } ?? rest[bone]).samples)
                }
                out.blob(blob.bytes)
            }
            // A3: the texture channels' tracks, one sample a frame (the last held past its end).
            let channelTracks = clip.channelTracks ?? []
            out.u32(UInt32(channelTracks.count))
            for track in channelTracks {
                out.u32(track.tag)
                var blob = PuppetMDLOutput()
                for frame in 0...frames { blob.f32(track.sample(frame)) }
                out.blob(blob.bytes)
            }
            out.u8(0)  // A3: no per-bone scalar tracks
            out.u8(0)  // A4: no morph-weight tracks
            let bounds = animatedBounds(document, rig: rig, clip: index)
            out.f32s([bounds.min.x, bounds.min.y, 0, bounds.max.x, bounds.max.y, 0])
            out.u8(0)  // A6: no third scalar list
            if let record, let source = record.sourceClip {
                // 0x140265232: with root motion and without Match loop the frames must lie in the clip.
                let limit = frames
                let start = record.matchLoop ? record.startFrame : min(max(record.startFrame, 0), limit)
                let end = record.matchLoop ? record.endFrame : min(max(record.endFrame, 0), limit)
                out.u16(UInt16(source))
                out.u32(UInt32(max(start, 0)))
                out.u32(UInt32(max(end, 0)))
                out.u32(UInt32(max(record.frameOffset, 0)))
                out.i32(record.rootBone.map { Int32($0) } ?? -1)
            }
            out.i32(Int32(clip.events.count))
            for event in clip.events {
                out.f32(event.frame)
                out.cstring(event.name)
            }
        }
        return out.bytes
    }

    /// The posed mesh's box over every frame of the clip (`MDLA` 5's animated box).
    static func animatedBounds(_ document: PuppetDocument, rig: PuppetRig, clip: Int) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var points: [SIMD2<Float>] = []
        let frames = max(document.clips[clip].frames, 1)
        for frame in 0...frames {
            let palette = rig.palette(worlds: rig.worlds(rig.pose(clip: clip, frame: Float(frame))))
            let skinned = PuppetRig.skin(document, palette: palette)
            let box = boundsOf(skinned)
            points += [box.min, box.max]
        }
        return boundsOf(points)
    }

    // MARK: MDAT

    private static func attachments(_ document: PuppetDocument) -> [UInt8] {
        var out = PuppetMDLOutput()
        out.u16(UInt16(document.preserved.attachments.count))
        for attachment in document.preserved.attachments {
            out.u16(UInt16(attachment.bone))
            out.cstring(attachment.name)
            out.f32s(attachment.matrix)
        }
        return out.bytes
    }
}
