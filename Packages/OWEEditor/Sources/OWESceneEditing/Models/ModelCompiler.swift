import Foundation
import simd

/// Compiles an imported model into WE's `.mdl` as WE's resource compiler does
/// (`resourcecompiler64.exe -mdl`, Assimp underneath; docs/model-import.md):
///
/// - Every mesh part (one per material) becomes an `MDLV` mesh. Its vertices are the corners
///   with identical ones joined, in the order they first appear (Assimp's
///   JoinIdenticalVertices); polygons are fans from their first corner. Texture coordinates are
///   flipped (v → 1 − v). Normals (`normals`), tangents with their handedness in w
///   (`tangentspace`, Assimp's CalcTangentSpace) and a second UV set packed with the first into
///   `a_TexCoordVec4` (`seconduvchannel`) follow the configuration; the default projects' pairs of
///   source and `.mdl` match this to the byte.
/// - A skinned model keeps the nodes the skin needs (the root, "RootNode", every bone and its
///   ancestors) as `MDLS` bones with their local matrices, bone flag 1 on armature bones, and
///   per bone the box of the vertices it moves in its bind space; every animation becomes an
///   `MDLA` record with one track per bone, and each clip a record cut from its animation with
///   the clip record after it.
/// - Materials are `materials/models/<folder>/<material>.json` (`generic4`, WE's importer's
///   pass), one per skin when the configuration has `skins`.
public enum ModelCompiler {
    public static let meshTag = "MDLV0023"
    public static let skeletonTag = "MDLS0004"
    public static let animationTag = "MDLA0006"
    public static let attachmentTag = "MDAT0001"
    public static let maximumBones = 128

    public enum CompileError: Error, Equatable, LocalizedError {
        case noMeshes
        case tooManyBones(Int)

        public var errorDescription: String? {
            switch self {
            case .noMeshes: return "The model has no triangles."
            case .tooManyBones(let count):
                return "The model has \(count) bones; Wallpaper Engine draws at most \(maximumBones)."
            }
        }
    }

    /// A material the model's meshes name, with the texture its albedo is.
    public struct MaterialFile: Sendable, Equatable {
        /// `materials/models/<folder>/<name>.json`, as the `.mdl` names it.
        public var path: String
        /// The material's name in the source (or a skin's replacement).
        public var name: String
        /// `models/<folder>/<name>`: the material's texture path (`materials/` + this + an extension).
        public var texturePath: String
        /// The albedo the source names; nil draws WE's `util/white`.
        public var albedo: ModelSource.Texture?
        public var normalMap: ModelSource.Texture?
        public var source: ModelSource.Material?
    }

    /// An animation or clip of the compiled model, as a scene's `animationlayers` name it.
    public struct AnimationInfo: Sendable, Equatable, Identifiable {
        public var id: UInt64
        public var name: String
        public var fps: Float
        public var frames: Int
        public var mode: String
        /// Cut by the Model Editor (Add Clip) rather than in the source.
        public var isClip: Bool
    }

    public struct Output: Sendable, Equatable {
        public var mdl: Data
        public var materials: [MaterialFile]
        /// The names of the materials the meshes draw with, in order.
        public var meshMaterials: [String]
        public var animations: [AnimationInfo]
        /// The skeleton's bone names (empty for a static model).
        public var bones: [String]
        public var boundsMin: SIMD3<Float>
        public var boundsMax: SIMD3<Float>
        public var vertexCount: Int
        public var triangleCount: Int
    }

    /// The id of the source's animation `index` (its animations, then each additional file's).
    public static func animationID(_ index: Int) -> UInt64 { UInt64(index + 1) }

    /// Compiles `source` (and the animations of `additional`, matched to its bones by name) with
    /// `config`; `folder` names the model's folder in the material paths
    /// (`materials/models/<folder>/…`).
    public static func compile(_ source: ModelSource, config: ModelImportConfig, folder: String,
                               additional: [ModelSource] = [], skins: [[String: String]] = []) throws -> Output {
        guard source.meshes.contains(where: { !$0.positions.isEmpty }) else { throw CompileError.noMeshes }
        let skeleton = source.isSkinned ? Skeleton(source) : nil
        if let skeleton, skeleton.nodes.count > maximumBones { throw CompileError.tooManyBones(skeleton.nodes.count) }
        var materials = materialFiles(source, folder: folder, skins: skins)
        for index in materials.indices {
            if let edited = config.materials[materials[index].name] { materials[index].path = edited }
        }

        var out = PuppetMDLOutput()
        let parts = skeleton == nil ? mergedByMaterial(source.meshes) : source.meshes.filter { !$0.positions.isEmpty }
        let meshes = parts.map { CompiledMesh($0, config: config, skeleton: skeleton) }
        let materialsPerMesh = max(1, skins.count)
        out.cstring(meshTag)
        out.u32(meshes.first?.format ?? 0)  // the legacy format: the first mesh's
        out.u32(UInt32(materialsPerMesh))
        out.u32(UInt32(meshes.count))
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = -low
        var meshMaterials: [String] = []
        for (mesh, part) in zip(meshes, parts) {
            for skin in 0..<materialsPerMesh {
                let material = materials[materialIndex(part.material, skin: skin, of: source, skins: skins)]
                out.cstring(material.path)
                if !meshMaterials.contains(material.name) { meshMaterials.append(material.name) }
            }
            mesh.write(into: &out)
            low = simd_min(low, mesh.boundsMin)
            high = simd_max(high, mesh.boundsMax)
        }

        var animations: [AnimationInfo] = []
        if let skeleton {
            let tracks = skeleton.animations(source, additional: additional)
            out.section(skeletonTag, skeleton.section(meshes: meshes, config: config))
            let attachments = config.attachments.compactMap { attachment in
                skeleton.index(of: attachment.bone).map { (attachment, $0) }
            }
            if !attachments.isEmpty {
                var body = PuppetMDLOutput()
                body.u16(UInt16(attachments.count))
                for (attachment, bone) in attachments {
                    body.u16(UInt16(bone))
                    body.cstring(attachment.name)
                    body.matrix(attachment.matrix)
                }
                out.section(attachmentTag, body.bytes)
            }
            let records = skeleton.records(tracks, config: config)
            if !records.isEmpty {
                out.section(animationTag, skeleton.animationSection(records, meshes: meshes, config: config))
            }
            animations = records.map {
                AnimationInfo(id: $0.id, name: $0.name, fps: $0.fps, frames: $0.frames, mode: $0.mode, isClip: $0.reference != nil)
            }
        }
        out.cstring("")
        return Output(mdl: Data(out.bytes), materials: materials, meshMaterials: meshMaterials, animations: animations,
                      bones: skeleton?.nodes.map(\.name) ?? [], boundsMin: low, boundsMax: high,
                      vertexCount: meshes.reduce(0) { $0 + $1.vertexCount }, triangleCount: meshes.reduce(0) { $0 + $1.indices.count / 3 })
    }

    /// A static model's parts with one material are one mesh, in material order, the parts'
    /// corners one after the other (Assimp's PreTransformVertices, which WE's importer runs on a
    /// model without bones: the default projects' `dna.fbx` has two nodes and one mesh, and
    /// `orbitaleffects.obj`'s meshes follow its materials, not its faces).
    static func mergedByMaterial(_ meshes: [ModelSource.Mesh]) -> [ModelSource.Mesh] {
        let parts = meshes.filter { !$0.positions.isEmpty }
        let materials = Set(parts.compactMap(\.material)).sorted().map(Optional.some) + (parts.contains { $0.material == nil } ? [nil] : [])
        return materials.map { material in
            let group = parts.filter { $0.material == material }
            guard group.count > 1 else { return group[0] }
            func joined<T>(_ values: [T]?, count: Int, fill: T) -> [T] { values ?? Array(repeating: fill, count: count) }
            let hasNormals = group.allSatisfy { $0.normals != nil }
            let hasUVs = group.contains { $0.uvs != nil }
            let hasSecond = group.contains { $0.secondUVs != nil }
            var merged = ModelSource.Mesh(name: group[0].name, material: material, positions: group.flatMap(\.positions))
            if hasNormals { merged.normals = group.flatMap { $0.normals ?? [] } }
            if hasUVs { merged.uvs = group.flatMap { joined($0.uvs, count: $0.positions.count, fill: .zero) } }
            if hasSecond { merged.secondUVs = group.flatMap { joined($0.secondUVs, count: $0.positions.count, fill: .zero) } }
            if group.allSatisfy({ $0.tangents != nil && $0.bitangents != nil }) {
                merged.tangents = group.flatMap { $0.tangents ?? [] }
                merged.bitangents = group.flatMap { $0.bitangents ?? [] }
            }
            return merged
        }
    }

    // MARK: Materials

    /// WE's importer's names: the material's own (Assimp's "DefaultMaterial" for none), made a
    /// valid file name; a name used twice gets a number.
    static func materialFiles(_ source: ModelSource, folder: String, skins: [[String: String]]) -> [MaterialFile] {
        var files: [MaterialFile] = []
        var used = Set<String>()
        func add(_ name: String, _ material: ModelSource.Material?) {
            var file = fileName(name)
            var counter = 1
            while !used.insert(file.lowercased()).inserted {
                counter += 1
                file = "\(fileName(name))_\(counter)"
            }
            files.append(MaterialFile(path: "materials/models/\(folder)/\(file).json", name: name,
                                      texturePath: "models/\(folder)/\(file)", albedo: material?.albedo,
                                      normalMap: material?.normalMap, source: material))
        }
        for material in source.materials { add(material.name.isEmpty ? defaultMaterialName : material.name, material) }
        add(defaultMaterialName, nil)  // meshes without a material
        // Each skin's replacements (`skins`: [{source name: replacement}]) are materials of their own.
        for skin in skins {
            for replacement in Set(skin.values).sorted() where !files.contains(where: { $0.name == replacement }) {
                let base = files.first { skin[$0.name] == replacement }
                add(replacement, base?.source)
            }
        }
        return files
    }

    /// Assimp's name for a mesh's missing material.
    public static let defaultMaterialName = "DefaultMaterial"

    static func materialIndex(_ material: Int?, skin: Int, of source: ModelSource, skins: [[String: String]]) -> Int {
        let base = material ?? source.materials.count
        guard skin < skins.count else { return base }
        let name = material.map { source.materials[$0].name.isEmpty ? defaultMaterialName : source.materials[$0].name }
            ?? defaultMaterialName
        guard let replacement = skins[skin][name] else { return base }
        let files = materialFiles(source, folder: "", skins: skins)
        return files.firstIndex { $0.name == replacement } ?? base
    }

    /// A material or model name as a file name: `/`, `\`, `:` and control characters become `_`.
    public static func fileName(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.map { scalar -> Character in
            "/\\:*?\"<>|".unicodeScalars.contains(scalar) || scalar.value < 0x20 ? "_" : Character(scalar)
        }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "material" : cleaned
    }

    /// The material WE's importer writes for a mesh (the `generic4` pass of `wallpaperui.exe`'s
    /// template: depth test and write on, back faces culled) drawing `texture`, or WE's white.
    public static func materialJSON(texture: String?) -> [String: SceneJSONValue] {
        [
            "passes": .array([.object([
                "blending": .string("normal"),
                "cullmode": .string("normal"),
                "depthtest": .string("enabled"),
                "depthwrite": .string("enabled"),
                "shader": .string("generic4"),
                "textures": .array([.string(texture ?? "util/white")]),
            ])]),
        ]
    }
}

// MARK: - Meshes

/// One `MDLV` mesh: its joined vertices, indices and format.
struct CompiledMesh {
    var format: UInt32
    var vertexCount: Int
    var vertexBytes: [UInt8]
    var indices: [UInt32]
    var boundsMin: SIMD3<Float>
    var boundsMax: SIMD3<Float>
    /// Joined vertices' positions and influences (for the bone boxes and animated bounds).
    var positions: [SIMD3<Float>]
    var influences: [ModelSource.Influences]

    static let position: UInt32 = 0x1
    static let normal: UInt32 = 0x2
    static let tangent: UInt32 = 0x4
    static let texCoord: UInt32 = 0x8
    static let texCoordVec4: UInt32 = 0x20
    static let blendIndices: UInt32 = 0x800000
    static let blendWeights: UInt32 = 0x1000000

    init(_ mesh: ModelSource.Mesh, config: ModelImportConfig, skeleton: ModelCompiler.Skeleton?) {
        let count = mesh.positions.count
        // Assimp gives a mesh without normals smooth ones (GenSmoothNormals); the corners are
        // joined on them whether or not the configuration writes them.
        let allNormals = mesh.normals ?? Self.smoothNormals(mesh.positions)
        let normals: [SIMD3<Float>]? = config.normals ? allNormals : nil
        let uvs = (mesh.uvs ?? Array(repeating: .zero, count: count)).map { SIMD2($0.x, 1 - $0.y) }
        let secondUVs = config.secondUVChannel
            ? (mesh.secondUVs ?? mesh.uvs ?? Array(repeating: .zero, count: count)).map { SIMD2($0.x, 1 - $0.y) } : nil
        // The file's own tangent space when it has one (Assimp's CalcTangentSpace leaves such a
        // mesh alone), else a computed one; corners are joined on it whether or not it is written.
        let tangentSpace: (tangents: [SIMD4<Float>], bitangents: [SIMD3<Float>])?
        if let fileTangents = mesh.tangents, let fileBitangents = mesh.bitangents {
            tangentSpace = (zip(fileTangents, zip(allNormals, fileBitangents)).map { t, nb in
                SIMD4(t, simd_dot(simd_cross(nb.0, t), nb.1) > 0 ? 1 : -1)
            }, fileBitangents)
        } else if mesh.uvs != nil {
            tangentSpace = Self.tangentSpace(positions: mesh.positions, normals: allNormals, uvs: uvs)
        } else {
            tangentSpace = nil
        }
        let tangents = config.tangentSpace && normals != nil ? tangentSpace?.tangents : nil
        let influences = skeleton.map { skeleton in
            mesh.influences.map { $0.map { skeleton.remap($0) } } ?? Array(repeating: skeleton.rootInfluence, count: count)
        }

        var format = Self.position
        if normals != nil { format |= Self.normal }
        if tangents != nil { format |= Self.tangent }
        format |= secondUVs != nil ? Self.texCoordVec4 : Self.texCoord
        if influences != nil { format |= Self.blendIndices | Self.blendWeights }
        self.format = format

        // Corners are joined as Assimp's JoinIdenticalVertices joins them: at the same position
        // with the same influences, and every other attribute (the tangent space too, written or
        // not) within 1e-5; the first corner of a vertex gives its values.
        struct Candidate {
            var index: UInt32
            var corner: Int
        }
        var groups: [[UInt8]: [Candidate]] = [:]
        var bytes: [UInt8] = []
        var indices: [UInt32] = []
        var positions: [SIMD3<Float>] = []
        var vertexInfluences: [ModelSource.Influences] = []
        indices.reserveCapacity(count)
        let epsilon: Float = 1e-5 * 1e-5
        func close<V: SIMD>(_ a: V, _ b: V) -> Bool where V.Scalar == Float {
            var sum: Float = 0
            for lane in a.indices { sum += (a[lane] - b[lane]) * (a[lane] - b[lane]) }
            return sum <= epsilon
        }
        func same(_ a: Int, _ b: Int) -> Bool {
            if !close(allNormals[a], allNormals[b]) { return false }
            if let tangentSpace {
                let ta = tangentSpace.tangents[a], tb = tangentSpace.tangents[b]
                if !close(SIMD3(ta.x, ta.y, ta.z), SIMD3(tb.x, tb.y, tb.z)) || !close(tangentSpace.bitangents[a], tangentSpace.bitangents[b]) {
                    return false
                }
            }
            if !close(uvs[a], uvs[b]) { return false }
            if let secondUVs, !close(secondUVs[a], secondUVs[b]) { return false }
            return true
        }
        for corner in 0..<count {
            let p = mesh.positions[corner]
            var key = PuppetMDLOutput()
            key.f32s([p.x, p.y, p.z])
            if let influences {
                let i = influences[corner]
                for slot in 0..<4 { key.u32(i.nodes[slot]) }
                for slot in 0..<4 { key.f32(i.weights[slot]) }
            }
            if let match = groups[key.bytes]?.first(where: { same($0.corner, corner) }) {
                indices.append(match.index)
                continue
            }
            let index = UInt32(positions.count)
            groups[key.bytes, default: []].append(Candidate(index: index, corner: corner))
            var vertex = PuppetMDLOutput()
            vertex.f32s([p.x, p.y, p.z])
            if let normals { vertex.f32s([normals[corner].x, normals[corner].y, normals[corner].z]) }
            if let tangents { vertex.f32s([tangents[corner].x, tangents[corner].y, tangents[corner].z, tangents[corner].w]) }
            if let influences {
                let i = influences[corner]
                for slot in 0..<4 { vertex.u32(i.nodes[slot]) }
                for slot in 0..<4 { vertex.f32(i.weights[slot]) }
            }
            if let secondUVs {
                vertex.f32s([uvs[corner].x, uvs[corner].y, secondUVs[corner].x, secondUVs[corner].y])
            } else {
                vertex.f32s([uvs[corner].x, uvs[corner].y])
            }
            bytes += vertex.bytes
            positions.append(p)
            if let influences { vertexInfluences.append(influences[corner]) }
            indices.append(index)
        }
        vertexCount = positions.count
        vertexBytes = bytes
        self.indices = indices
        self.positions = positions
        self.influences = vertexInfluences
        var low = positions.first ?? .zero, high = low
        for p in positions {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        boundsMin = low
        boundsMax = high
    }

    var usesUInt32Indices: Bool { vertexCount > Int(UInt16.max) }

    func write(into out: inout PuppetMDLOutput) {
        out.u32(usesUInt32Indices ? 1 : 0)
        out.f32s([boundsMin.x, boundsMin.y, boundsMin.z, boundsMax.x, boundsMax.y, boundsMax.z])
        out.u32(format)
        out.blob(vertexBytes)
        var indexBytes = PuppetMDLOutput()
        for index in indices {
            if usesUInt32Indices { indexBytes.u32(index) } else { indexBytes.u16(UInt16(index)) }
        }
        out.blob(indexBytes.bytes)
        out.u8(0)  // no texture-layout positions (MDLV 21)
        out.u8(0)  // no bone index ranges (MDLV 21)
        out.u32(0) // no groups (MDLV 23)
    }

    /// Each triangle's own normal on its three corners (a source without normals).
    static func faceNormals(_ positions: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var normals: [SIMD3<Float>] = []
        normals.reserveCapacity(positions.count)
        for first in stride(from: 0, to: positions.count - 2, by: 3) {
            let normal = AssimpMath.normalizedSafe(AssimpMath.cross(positions[first + 1] - positions[first],
                                                                    positions[first + 2] - positions[first]))
            normals += [normal, normal, normal]
        }
        return normals
    }

    /// Assimp's GenSmoothNormals at its default 175° limit: each corner gets the normalised sum
    /// of the face normals of every corner within 1e-4 of the mesh's box diagonal.
    static func smoothNormals(_ positions: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let faces = faceNormals(positions)
        var normals = faces
        let radius = positionEpsilon(positions)
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for corner in positions.indices { grid[cell(positions[corner], radius), default: []].append(corner) }
        var done = Array(repeating: false, count: positions.count)
        for a in positions.indices where !done[a] {
            let found = near(a, positions, grid: grid, radius: radius)
            var sum = SIMD3<Float>.zero
            for b in found { sum += faces[b] }
            let normal = AssimpMath.normalized(sum)
            for b in found {
                normals[b] = normal
                done[b] = true
            }
        }
        return normals
    }

    /// Assimp's ComputePositionEpsilon: 1e-4 of the mesh's box diagonal.
    static func positionEpsilon(_ positions: [SIMD3<Float>]) -> Float {
        var low = positions.first ?? .zero, high = low
        for p in positions {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        return max(simd_length(high - low) * 1e-4, .leastNormalMagnitude)
    }

    static func cell(_ p: SIMD3<Float>, _ radius: Float) -> SIMD3<Int32> {
        SIMD3<Int32>((p / radius).rounded(.down).clamped(lowerBound: SIMD3(repeating: -2e9), upperBound: SIMD3(repeating: 2e9)))
    }

    /// The corners within `radius` of corner `a`, in corner order.
    static func near(_ a: Int, _ positions: [SIMD3<Float>], grid: [SIMD3<Int32>: [Int]], radius: Float) -> [Int] {
        let origin = cell(positions[a], radius)
        var found: [Int] = []
        for dz in -1...1 {
            for dy in -1...1 {
                for dx in -1...1 {
                    for b in grid[origin &+ SIMD3(Int32(dx), Int32(dy), Int32(dz))] ?? []
                    where simd_length_squared(positions[b] - positions[a]) < radius * radius {
                        found.append(b)
                    }
                }
            }
        }
        return found.sorted()
    }

    /// Assimp's CalcTangentSpace on the flipped coordinates: per triangle, the tangent and
    /// bitangent of its UV mapping, made orthogonal to each corner's normal; then each corner
    /// averages those of the corners at the same position whose normal, tangent and bitangent
    /// lie within 45° of its own. w is the handedness, the sign of (N × T) · B.
    static func tangentSpace(positions: [SIMD3<Float>], normals: [SIMD3<Float>], uvs: [SIMD2<Float>])
        -> (tangents: [SIMD4<Float>], bitangents: [SIMD3<Float>]) {
        let count = positions.count
        var tangents = Array(repeating: SIMD3<Float>.zero, count: count)
        var bitangents = Array(repeating: SIMD3<Float>.zero, count: count)
        for first in stride(from: 0, to: count - 2, by: 3) {
            let p0 = positions[first], p1 = positions[first + 1], p2 = positions[first + 2]
            let v = p1 - p0, w = p2 - p0
            var sx = uvs[first + 1].x - uvs[first].x, sy = uvs[first + 1].y - uvs[first].y
            var tx = uvs[first + 2].x - uvs[first].x, ty = uvs[first + 2].y - uvs[first].y
            let direction: Float = tx * sy - ty * sx < 0 ? -1 : 1
            if sx * ty == sy * tx {
                sx = 0; sy = 1; tx = 1; ty = 0
            }
            let tangent = (w * sy - v * ty) * direction
            let bitangent = (w * sx - v * tx) * direction
            for corner in first..<(first + 3) {
                let n = normals[corner]
                tangents[corner] = AssimpMath.normalizedSafe(tangent - n * AssimpMath.dot(tangent, n))
                bitangents[corner] = AssimpMath.normalizedSafe(bitangent - n * AssimpMath.dot(bitangent, n))
            }
        }
        // Smoothing as Assimp's CalcTangentsProcess: in corner order, a corner not yet smoothed
        // gathers the unsmoothed corners within 1e-4 of the mesh's box diagonal whose normal is
        // within 0.9999 and tangent and bitangent within 45° of its own (itself counted twice,
        // as Assimp's loop adds it again), and all of them get the normalised sums.
        let radius = positionEpsilon(positions)
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for corner in 0..<count { grid[cell(positions[corner], radius), default: []].append(corner) }
        let limit = cos(Float.pi / 4)
        var done = Array(repeating: false, count: count)
        for a in 0..<count where !done[a] {
            let found = near(a, positions, grid: grid, radius: radius)
            var group = [a]
            for b in found where !done[b] {
                guard AssimpMath.dot(normals[b], normals[a]) >= 0.9999, AssimpMath.dot(tangents[b], tangents[a]) >= limit,
                      AssimpMath.dot(bitangents[b], bitangents[a]) >= limit else { continue }
                group.append(b)
                done[b] = true
            }
            var t = SIMD3<Float>.zero, b = SIMD3<Float>.zero
            for member in group {
                t += tangents[member]
                b += bitangents[member]
            }
            t = AssimpMath.normalized(t)
            b = AssimpMath.normalized(b)
            for member in group {
                tangents[member] = t
                bitangents[member] = b
            }
        }
        let smoothedT = tangents, smoothedB = bitangents
        let oriented = (0..<count).map { corner in
            let handedness: Float = simd_dot(simd_cross(normals[corner], smoothedT[corner]), smoothedB[corner]) > 0 ? 1 : -1
            return SIMD4(smoothedT[corner], handedness)
        }
        return (oriented, smoothedB)
    }
}

/// Assimp's `aiVector3D` arithmetic in its order, so ties at the 45° and 0.9999 limits fall the
/// way they fall in WE's importer: dot products summed x, y, z, normalising by multiplying with
/// the length's reciprocal, and a zero vector left as it is by NormalizeSafe.
enum AssimpMath {
    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let xy: Float = a.x * b.x + a.y * b.y
        return xy + a.z * b.z
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ v: SIMD3<Float>) -> Float { dot(v, v).squareRoot() }

    /// `Normalize()`: `*this /= Length()`, which multiplies by `1 / f` and leaves a zero length alone.
    static func normalized(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let f = length(v)
        guard f != 0 else { return v }
        let inverse: Float = 1 / f
        return SIMD3(v.x * inverse, v.y * inverse, v.z * inverse)
    }

    static func normalizedSafe(_ v: SIMD3<Float>) -> SIMD3<Float> {
        length(v) > 0 ? normalized(v) : v
    }
}
