import Foundation
import simd

/// Reads an installed puppet's `.mdl` into the editor: every version WE's runtime reads (`MDLV`
/// 4–23, `MDLS` 1–4, `MDLA` 1–6; docs/models-plan.md §1), the same layout as the app's
/// `MDLReader`. The puppet is the first mesh (the only one WE draws, 0x14020aeb9) with its
/// skeleton, weights and clips; what the editor doesn't edit is kept (`PuppetPreservedData`) or,
/// for data no library rig has (links, constraints, IK sets, scalar and morph-weight tracks),
/// left out.
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
        for _ in 0..<meshCount {
            let mesh = try readMesh(&r, version: version, legacyFormat: legacyFormat, materials: materialsPerMesh)
            if first == nil { first = mesh }
        }
        var document = PuppetDocument(imageSize: imageSize, material: first!.material, sourcePath: sourcePath)
        try decode(first!, into: &document)
        guard version >= 13 else { throw PuppetMDLError.unsupported("no skeleton") }
        var boneCount = 0
        var links = 0, constraints = 0
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
        if version >= 21 {
            if try r.u8() != 0 {
                _ = try r.u32()
                _ = try r.blob("extra positions")
            }
            if try r.u8() != 0 { _ = try r.blob("vector4 block") }
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
                       indices: indices)
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
            vertices.append(PuppetVertex(position: point, uv: uv))
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
    }

    // MARK: MDLS

    private static func readSkeleton(_ r: inout PuppetMDLInput, version: Int,
                                     into document: inout PuppetDocument) throws -> (links: Int, constraints: Int) {
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
        guard version >= 2 else { return (0, 0) }
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
        let constraints = Int(try r.u32())
        for _ in 0..<constraints {
            _ = try r.u32s(3)
            let flags = version >= 4 ? try r.u32() : 0
            if flags & 2 != 0 { _ = try r.f32s(2) }
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

    private static func readAnimations(_ r: inout PuppetMDLInput, version: Int, links: Int, constraints: Int, meshes: Int,
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
                for _ in 0..<constraints {
                    _ = try r.u32()
                    _ = try r.blob("constraint track")
                }
            }
            if version >= 3 {
                for _ in 0..<(try r.u32()) {
                    _ = try r.u32()
                    _ = try r.blob("scalar track")
                }
                if try r.u8() != 0 {
                    for _ in 0..<trackCount {
                        _ = try r.u32()
                        _ = try r.blob("scalar track")
                    }
                }
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
            if version >= 6, try r.u8() != 0 {
                for _ in 0..<trackCount {
                    _ = try r.u32()
                    _ = try r.blob("scalar track")
                }
            }
            let mode = PuppetClip.Mode(rawValue: modeName) ?? .loop
            var clip = PuppetClip(id: id, name: name, mode: mode, fps: fps, frames: frames, tracks: tracks,
                                  otherFlags: flags & ~PuppetClip.RootMotion.ownedFlags)
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
