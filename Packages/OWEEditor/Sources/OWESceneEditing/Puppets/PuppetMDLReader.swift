import Foundation
import simd

/// Reads an installed puppet's `.mdl` into the editor: every version WE's runtime reads (`MDLV`
/// 4–23, `MDLS` 1–4, `MDLA` 1–6; docs/models-plan.md §1), the same layout as the app's
/// `MDLReader`. The puppet is the first mesh (the only one WE draws, 0x14020aeb9) with its
/// skeleton, weights and clips; what the editor doesn't edit is kept (`PuppetPreservedData`) or,
/// for data no library rig has (links, IK sets, morph-weight tracks), left out. Constraints are
/// Puppet Warp's blend rules (`PuppetBlendRule`).
public enum PuppetMDLReader {
    /// `imageSize`: the image's pixels (the mesh's space has no size of its own).
    public static func read(_ data: Data, imageSize: SIMD2<Float>, sourcePath: String? = nil) throws -> PuppetDocument {
        var r = PuppetMDLInput([UInt8](data))
        let tag = try r.cstring()
        guard tag.hasPrefix("MDLV") else { throw PuppetMDLError.notAModel }
        let version = Int(tag.dropFirst(4).prefix { $0.isNumber }) ?? 0
        let legacyFormat = try r.u32()
        let materialsPerMesh = Int(try r.u32())
        let meshCount = Int(try r.u32())
        guard meshCount > 0 else { throw PuppetMDLError.unsupported("no mesh") }
        var first: RawMesh?
        var channels: [PuppetPreservedData.TextureChannelMesh] = []
        for _ in 0..<meshCount {
            let start = r.offset
            let mesh = try readMesh(&r, version: version, legacyFormat: legacyFormat, materials: materialsPerMesh)
            if first == nil {
                first = mesh
            } else if mesh.flags & 2 != 0, materialsPerMesh == 1, version == 23 {
                // Texture channels, kept byte for byte for the writer's MDLV0023.
                channels.append(.init(material: mesh.material, blendRows: mesh.flagsExtra ?? 1,
                                      channelCount: channelCount(mesh), bytes: Data(r.bytes[start..<r.offset])))
            }
        }
        var document = PuppetDocument(imageSize: imageSize, material: first!.material, sourcePath: sourcePath)
        try decode(first!, into: &document)
        if !channels.isEmpty { document.preserved.textureChannels = channels }
        guard version >= 13 else { throw PuppetMDLError.unsupported("no skeleton") }
        var boneCount = 0
        var links = 0
        var constraints: [(bone: Int, rule: Int)?] = []
        while true {
            let tagBytes = try r.cstring()
            if tagBytes.isEmpty { break }
            let end = Int(try r.u32())
            guard end >= r.offset, end <= r.bytes.count else { throw PuppetMDLError.malformed("section \(tagBytes) end") }
            let sectionVersion = Int(tagBytes.dropFirst(4).prefix { $0.isNumber }) ?? 0
            let bodyStart = r.offset
            if tagBytes.hasPrefix("MDLS") {
                let counts = try readSkeleton(&r, version: sectionVersion, into: &document)
                boneCount = document.bones.count
                links = counts.links
                constraints = counts.constraints
            } else if tagBytes.hasPrefix("MDLA") {
                try readAnimations(&r, version: sectionVersion, links: links, constraints: constraints,
                                   meshes: meshCount, into: &document)
            } else if tagBytes == "MDAT0001" {
                let count = try r.u16()
                for _ in 0..<count {
                    let bone = Int(try r.u16())
                    let name = try r.cstring()
                    document.preserved.attachments.append(.init(bone: bone, name: name, matrix: try r.f32s(16)))
                }
            } else if tagBytes == "MDMP0001" {
                document.preserved.morphSection = Data(r.bytes[bodyStart..<end])
            } else if tagBytes == "MDLE0002" {
                let length = Int(try r.i32())
                if length == 64 * boneCount {
                    document.preserved.referencePose = try (0..<boneCount).map { _ in try r.f32s(16) }
                }
            }
            guard r.offset <= end else { throw PuppetMDLError.malformed("section \(tagBytes) past its end") }
            r.seek(to: end)
        }
        guard !document.bones.isEmpty else { throw PuppetMDLError.unsupported("no skeleton") }
        if document.preserved.morphSection != nil, document.preserved.morphIndices == nil { document.preserved.morphSection = nil }
        if document.preserved.morphSection == nil { document.preserved.morphIndices = nil }
        // Weights naming a bone the rig doesn't have count for nothing.
        document.weights = document.weights.map { PuppetWeight.normalized($0.filter { $0.bone < boneCount }) }
        return document
    }

    // MARK: MDLV

    struct RawMesh {
        var material: String
        var flags: UInt32
        var flagsExtra: UInt32?
        var format: UInt32
        var vertices: ArraySlice<UInt8>
        var indices: ArraySlice<UInt8>
        /// The 16-byte records after the vertices (`MDLV` 21 and later), as u32s.
        var boneRanges: [SIMD4<UInt32>]?
    }

    private static func readMesh(_ r: inout PuppetMDLInput, version: Int, legacyFormat: UInt32, materials: Int) throws -> RawMesh {
        var names: [String] = []
        for _ in 0..<materials { names.append(try r.cstring()) }
        let flags = version >= 4 ? try r.u32() : 0
        let extra = flags & 2 != 0 ? try r.u32() : nil
        if version >= 17 { _ = try r.f32s(6) }
        let format = version >= 15 ? try r.u32() : legacyFormat
        guard format & ~PuppetVertexLayout.knownBits == 0 else { throw PuppetMDLError.malformed("vertex format") }
        let vertices = try r.blob("vertices")
        let indices = try r.blob("indices")
        var ranges: [SIMD4<UInt32>]?
        if version >= 21 {
            if try r.u8() != 0 {
                _ = try r.u32()
                _ = try r.blob("extra positions")
            }
            if try r.u8() != 0 {
                let block = try r.blob("vector4 block")
                guard block.count % 16 == 0 else { throw PuppetMDLError.malformed("vector4 block") }
                let values = Array(block)
                func u32(_ at: Int) -> UInt32 {
                    UInt32(values[at]) | UInt32(values[at + 1]) << 8 | UInt32(values[at + 2]) << 16 | UInt32(values[at + 3]) << 24
                }
                ranges = stride(from: 0, to: values.count, by: 16).map { SIMD4(u32($0), u32($0 + 4), u32($0 + 8), u32($0 + 12)) }
            }
        }
        if version >= 23 {
            for _ in 0..<(try r.u32()) {
                _ = try r.u64()
                _ = try r.cstring()
                _ = try r.u32()
                _ = try r.u32s(Int(try r.u32()))
                _ = try r.u32s(Int(try r.u32()))
            }
        }
        return RawMesh(material: names.first ?? "", flags: flags, flagsExtra: extra, format: format, vertices: vertices,
                       indices: indices, boneRanges: ranges)
    }

    /// The channels a texture-channel mesh's quads name: the largest `a_BlendIndices.x` + 1.
    private static func channelCount(_ mesh: RawMesh) -> Int {
        let size = PuppetVertexLayout.stride(mesh.format)
        guard size > 0, let offset = PuppetVertexLayout.offset(of: PuppetVertexLayout.blendIndices, in: mesh.format) else { return 0 }
        let bytes = Array(mesh.vertices)
        return stride(from: 0, to: bytes.count - size + 1, by: size).map { base -> Int in
            let at = base + offset
            return Int(UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24) + 1
        }.max() ?? 0
    }

    private static func decode(_ mesh: RawMesh, into document: inout PuppetDocument) throws {
        let stride = PuppetVertexLayout.stride(mesh.format)
        guard stride > 0, mesh.vertices.count % stride == 0 else { throw PuppetMDLError.malformed("vertex stride") }
        let positionOffset = PuppetVertexLayout.offset(of: PuppetVertexLayout.position, in: mesh.format)
        let vec4Offset = PuppetVertexLayout.offset(of: PuppetVertexLayout.positionVec4, in: mesh.format)
        guard let position = positionOffset ?? vec4Offset else { throw PuppetMDLError.unsupported("no positions") }
        let texCoord = [PuppetVertexLayout.texCoord, PuppetVertexLayout.texCoordVec3, PuppetVertexLayout.texCoordVec4]
            .lazy.compactMap { PuppetVertexLayout.offset(of: $0, in: mesh.format) }.first
        let blendIndices = PuppetVertexLayout.offset(of: PuppetVertexLayout.blendIndices, in: mesh.format)
        let blendWeights = PuppetVertexLayout.offset(of: PuppetVertexLayout.blendWeights, in: mesh.format)
        let count = mesh.vertices.count / stride
        let bytes = Array(mesh.vertices)
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func f32(_ at: Int) -> Float { Float(bitPattern: u32(at)) }
        var vertices: [PuppetVertex] = []
        var weights: [[PuppetWeight]] = []
        var morphs: [Float] = []
        for vertex in 0..<count {
            let base = vertex * stride
            let point = SIMD2(f32(base + position), f32(base + position + 4))
            let uv = texCoord.map { SIMD2(f32(base + $0), f32(base + $0 + 4)) } ?? document.textureCoordinate(of: point)
            let depth = f32(base + position + 8)
            vertices.append(PuppetVertex(position: point, uv: uv, depth: depth == 0 ? nil : depth))
            if positionOffset == nil, vec4Offset != nil { morphs.append(f32(base + position + 12)) }
            var entries: [PuppetWeight] = []
            if let blendIndices, let blendWeights {
                for slot in 0..<4 {
                    entries.append(PuppetWeight(bone: Int(u32(base + blendIndices + 4 * slot)),
                                                weight: f32(base + blendWeights + 4 * slot)))
                }
            }
            weights.append(PuppetWeight.normalized(entries))
        }
        let indexSize = mesh.flags & 1 != 0 ? 4 : 2
        guard mesh.indices.count % (3 * indexSize) == 0 else { throw PuppetMDLError.malformed("index count") }
        let indexBytes = Array(mesh.indices)
        var triangles: [SIMD3<UInt32>] = []
        for triangle in 0..<(indexBytes.count / (3 * indexSize)) {
            var corners = SIMD3<UInt32>.zero
            for corner in 0..<3 {
                let at = (3 * triangle + corner) * indexSize
                corners[corner] = indexSize == 4
                    ? UInt32(indexBytes[at]) | UInt32(indexBytes[at + 1]) << 8 | UInt32(indexBytes[at + 2]) << 16 | UInt32(indexBytes[at + 3]) << 24
                    : UInt32(indexBytes[at]) | UInt32(indexBytes[at + 1]) << 8
            }
            guard Int(corners.max()) < count else { throw PuppetMDLError.malformed("index past the vertices") }
            triangles.append(corners)
        }
        document.mesh = PuppetMesh(vertices: vertices, triangles: triangles)
        document.weights = weights
        document.preserved.meshFlags = mesh.flags & ~1
        document.preserved.meshFlagsExtra = mesh.flagsExtra
        if !morphs.isEmpty { document.preserved.morphIndices = morphs }
        if let ranges = mesh.boneRanges, !ranges.isEmpty, ranges.allSatisfy({ UInt64($0.z) + UInt64($0.w) <= UInt64(3 * triangles.count) }) {
            document.preserved.boneRanges = ranges
        }
    }

    // MARK: MDLS

    private static func readSkeleton(_ r: inout PuppetMDLInput, version: Int,
                                     into document: inout PuppetDocument) throws -> (links: Int, constraints: [(bone: Int, rule: Int)?]) {
        let count = Int(try r.u32())
        guard count <= PuppetMDLWriter.maximumBones else { throw PuppetMDLError.malformed("\(count) bones") }
        var bones: [PuppetBone] = []
        for index in 0..<count {
            let name = try r.cstring()
            let flags = try r.u32()
            let parent = try r.u32()
            let length = Int(try r.i32())
            guard length == 64 else { throw PuppetMDLError.malformed("bone matrix of \(length) bytes") }
            let matrix = try r.matrix()
            let properties = try r.cstring()
            var bone = PuppetBone(name: name, parent: parent == 0xFFFF_FFFF || Int(parent) >= index ? nil : Int(parent),
                                  local: PuppetTransform(matrix: matrix), flags: flags)
            if let object = Self.properties(properties) {
                bone.physics = PuppetBonePhysics(properties: object)
                bone.otherProperties = bone.physics == nil ? object : object.filter { !PuppetBonePhysics.keys.contains($0.key) }
            }
            bones.append(bone)
        }
        document.bones = bones
        guard version >= 2 else { return (0, []) }
        let links = Int(try r.u16())
        for _ in 0..<links {
            _ = try r.cstring()
            _ = try r.u32s(2)
            _ = try r.matrix()
        }
        if try r.u8() != 0 {
            for index in 0..<count {
                let rest = PuppetTransform(matrix: try r.matrix())
                if !rest.isClose(to: document.bones[index].local, tolerance: 1e-6) { document.bones[index].rest = rest }
            }
            for _ in 0..<links { _ = try r.matrix() }
        }
        // Constraints: blend rules (docs/models-plan.md §2.15), each placed on its bone; one on a
        // flag-0x2 bone hangs on a link (IK), which the editor leaves out, as one out of range.
        let constraintCount = Int(try r.u32())
        var constraints: [(bone: Int, rule: Int)?] = []
        for _ in 0..<constraintCount {
            let values = try r.u32s(3)
            let flags = version >= 4 ? try r.u32() : 0
            let floats = flags & 2 != 0 ? try r.f32s(2) : nil
            let bone = Int(values[0]), target = Int(values[2])
            guard bone < count, target < count, bone != target, document.bones[bone].flags & 2 == 0 else {
                constraints.append(nil)
                continue
            }
            var rules = document.bones[bone].blendRules ?? []
            rules.append(PuppetBlendRule(target: target, flags: flags, floats: floats.map { SIMD2($0[0], $0[1]) }))
            document.bones[bone].blendRules = rules
            constraints.append((bone, rules.count - 1))
        }
        let maps = Int(try r.u16())
        _ = try r.u32s(maps)
        for _ in 0..<maps {
            for _ in 0..<(try r.u16()) {
                _ = try r.u32()
                _ = try r.f32s(3)
            }
        }
        for _ in 0..<(try r.u16()) {
            _ = try r.u32()
            _ = try r.u32s(Int(try r.u32()))
            for _ in 0..<(try r.u16()) {
                _ = try r.u32()
                for _ in 0..<(try r.u16()) {
                    _ = try r.u32s(2)
                    _ = try r.f32s(2)
                    _ = try r.u32s(Int(try r.u16()))
                }
            }
        }
        if try r.u8() != 0 {
            document.preserved.boneBoxes = try (0..<count).map { _ in
                let vector = try r.f32s(3)
                return .init(vector: SIMD3(vector[0], vector[1], vector[2]), matrix: try r.f32s(16))
            }
        }
        if try r.u8() != 0 { document.preserved.boneIndices = try r.u32s(count) }
        if version >= 3, try r.u8() != 0 { document.preserved.bonePriorities = try r.u32s(count) }
        return (links, constraints)
    }

    /// A bone's properties JSON as an object; nil when empty or not an object.
    static func properties(_ text: String) -> [String: SceneJSONValue]? {
        guard !text.isEmpty, let data = text.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              case .object(let object)? = SceneJSONValue(any: any) else { return nil }
        return object
    }

    // MARK: MDLA

    /// One scalar track per bone track: its u32, then a sample per frame.
    private static func boneScalars(_ r: inout PuppetMDLInput, count: Int) throws -> [PuppetChannelTrack] {
        try (0..<max(count, 0)).map { _ in
            let tag = try r.u32()
            return PuppetChannelTrack(tag: tag, samples: PuppetMDLInput.floats(try r.blob("scalar track")))
        }
    }

    private static func readAnimations(_ r: inout PuppetMDLInput, version: Int, links: Int,
                                       constraints: [(bone: Int, rule: Int)?], meshes: Int,
                                       into document: inout PuppetDocument) throws {
        let count = Int(try r.i32())
        let rest = document.restLocals
        for index in 0..<max(count, 0) {
            let id = try r.u64()
            let name = try r.cstring()
            let modeName = try r.cstring()
            let fps = try r.f32()
            let frames = Int(try r.u32())
            let flags = try r.u32()
            let samples = frames + 1
            let trackCount = Int(try r.i32())
            var tracks: [PuppetTrack] = []
            for track in 0..<max(trackCount, 0) {
                let trackFlags = try r.u32()
                let blob = try r.blob("bone track")
                guard blob.count == 36 * samples else { throw PuppetMDLError.malformed("bone track of \(blob.count) bytes") }
                guard track < document.bones.count else { continue }
                if trackFlags & 1 != 0 {
                    tracks.append(PuppetTrack())
                    continue
                }
                let values = PuppetMDLInput.floats(blob)
                let transforms = (0..<samples).map { PuppetTransform(samples: values[(9 * $0)..<(9 * $0 + 9)]) }
                tracks.append(PuppetTrack(keys: PuppetClipBaker.keys(from: transforms)))
            }
            while tracks.count < document.bones.count { tracks.append(PuppetTrack()) }
            if version >= 2 {
                for _ in 0..<links {
                    _ = try r.u32()
                    _ = try r.blob("link track")
                }
                for placement in constraints {
                    let tag = try r.u32()
                    let samples = PuppetMDLInput.floats(try r.blob("constraint track"))
                    guard let placement, tag & 1 == 0, !samples.isEmpty else { continue }
                    document.bones[placement.bone].blendRules?[placement.rule].weights[id] = PuppetBlendRule.keys(from: samples)
                }
            }
            var channelTracks: [PuppetChannelTrack] = []
            var boneAlpha: [PuppetChannelTrack]?, boneDepth: [PuppetChannelTrack]?
            if version >= 3 {
                for _ in 0..<(try r.u32()) {
                    let tag = try r.u32()
                    channelTracks.append(PuppetChannelTrack(tag: tag, samples: PuppetMDLInput.floats(try r.blob("scalar track"))))
                }
                if try r.u8() != 0 { boneAlpha = try boneScalars(&r, count: trackCount) }
            }
            if version >= 4, try r.u8() != 0 {
                for _ in 0..<meshes {
                    if try r.u32() & 1 != 0 {
                        _ = try r.f32()
                        for _ in 0..<(try r.u16()) {
                            _ = try r.u16()
                            _ = try r.blob("morph weight track")
                        }
                    }
                }
            }
            if version >= 5 { _ = try r.f32s(6) }
            if version >= 6, try r.u8() != 0 { boneDepth = try boneScalars(&r, count: trackCount) }
            let mode = PuppetClip.Mode(rawValue: modeName) ?? .loop
            var clip = PuppetClip(id: id, name: name, mode: mode, fps: fps, frames: frames, tracks: tracks,
                                  otherFlags: flags & ~PuppetClip.RootMotion.ownedFlags)
            if !channelTracks.isEmpty { clip.channelTracks = channelTracks }
            // One per bone the document kept; a bone past the file's tracks at rest.
            let boneCount = document.bones.count
            func perBone(_ tracks: [PuppetChannelTrack]?, rest: Float) -> [PuppetChannelTrack]? {
                tracks.map { tracks in
                    (0..<boneCount).map { tracks.indices.contains($0) ? tracks[$0] : PuppetChannelTrack(tag: 0, samples: [rest]) }
                }
            }
            clip.boneAlphaTracks = perBone(boneAlpha, rest: 1)
            clip.boneDepthTracks = perBone(boneDepth, rest: 0)
            if PuppetClip.Mode(rawValue: modeName) == nil { clip.modeName = modeName }
            if flags & PuppetClip.RootMotion.ownedFlags != 0 {
                var motion = PuppetClip.RootMotion(matchLoop: flags & PuppetClip.RootMotion.matchLoopFlag != 0,
                                                   positionX: flags & PuppetClip.RootMotion.positionXFlag != 0,
                                                   positionY: flags & PuppetClip.RootMotion.positionYFlag != 0,
                                                   positionZ: flags & PuppetClip.RootMotion.positionZFlag != 0,
                                                   rotationY: flags & PuppetClip.RootMotion.rotationYFlag != 0)
                if flags & PuppetClip.RootMotion.referenceFlag != 0 {
                    let source = Int(try r.u16())
                    let values = try r.u32s(4)
                    guard source < index else { throw PuppetMDLError.malformed("clip \(index) cut from clip \(source)") }
                    motion.sourceClip = source
                    motion.startFrame = Int(values[0])
                    motion.endFrame = Int(values[1])
                    motion.frameOffset = Int(values[2])
                    let root = Int32(bitPattern: values[3])
                    motion.rootBone = root >= 0 && Int(root) < document.bones.count ? Int(root) : nil
                }
                clip.rootMotion = motion
            }
            let events = Int(try r.i32())
            for _ in 0..<max(events, 0) {
                let frame = try r.f32()
                clip.events.append(PuppetClipEvent(frame: frame, name: try r.cstring()))
            }
            _ = rest
            document.clips.append(clip)
        }
    }
}
