import CUfbx
import Foundation
import OWESceneEditing
import simd

/// Reads an FBX or OBJ file (and an OBJ's `.mtl`) with ufbx into a `ModelSource`, as WE's
/// resource compiler reads one with Assimp: the file's own axes and units (no conversion: WE
/// keeps the FBX's node transforms, such as Blender's 100× scale and −90° turn, in the nodes),
/// each mesh node's parts split per material, polygons as fans from their first corner (a
/// concave quad from its reflex corner; larger polygons by ufbx's triangulation), and the
/// animation stacks sampled at the file's frame rate (docs/model-import.md).
public enum ModelFileLoader {
    /// The source formats WE's importer offers that ufbx reads. WE's Assimp also reads .blend,
    /// .dae, .3ds, .lxo and .gltf (`resourcecompiler64.exe`'s list); this importer doesn't.
    public static let fileExtensions: Set<String> = ["fbx", "obj"]

    public enum LoadError: Error, Equatable, LocalizedError {
        case unsupported(String)
        case unreadable(String, String)

        public var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "“\(name)” isn’t an FBX or OBJ file."
            case .unreadable(let name, let reason): return "“\(name)” can’t be read: \(reason)"
            }
        }
    }

    /// The model of the file at `url`.
    public static func load(contentsOf url: URL) throws -> ModelSource {
        let name = url.lastPathComponent
        guard fileExtensions.contains(url.pathExtension.lowercased()) else { throw LoadError.unsupported(name) }
        var options = ufbx_load_opts()
        options.load_external_files = true
        options.ignore_missing_external_files = true
        options.obj_search_mtl_by_filename = true
        // A file without normals gets flat ones from the compiler, as Assimp's GenNormals gives.
        options.generate_missing_normals = false
        options.clean_skin_weights = true
        var error = ufbx_error()
        guard let scene = url.withUnsafeFileSystemRepresentation({ path in
            path.flatMap { ufbx_load_file($0, &options, &error) }
        }) else {
            throw LoadError.unreadable(name, Self.string(error.description))
        }
        defer { ufbx_free_scene(scene) }
        var source = Reader(scene.pointee).source
        let order = url.pathExtension.lowercased() == "obj" ? materialLibraryOrder(objAt: url) : []
        reorderMaterials(&source, libraryOrder: order)
        return source
    }

    /// Materials in the order Assimp numbers them, which a static model's meshes follow: an
    /// OBJ's in its `.mtl` files' order (`newmtl`), an FBX's in the order the nodes' meshes first
    /// use them.
    static func reorderMaterials(_ source: inout ModelSource, libraryOrder: [String]) {
        var firstUse: [Int] = []
        for mesh in source.meshes {
            if let material = mesh.material, !firstUse.contains(material) { firstUse.append(material) }
        }
        let names = source.materials.map(\.name)
        let ranks = names.indices.map { index in
            (libraryOrder.firstIndex(of: names[index]) ?? Int.max, firstUse.firstIndex(of: index) ?? Int.max, index)
        }
        let order = ranks.sorted { $0 < $1 }.map(\.2)
        var newIndex: [Int: Int] = [:]
        for (new, old) in order.enumerated() { newIndex[old] = new }
        source.materials = order.map { source.materials[$0] }
        for index in source.meshes.indices {
            source.meshes[index].material = source.meshes[index].material.flatMap { newIndex[$0] }
        }
    }

    /// The `.mtl` files an OBJ's `mtllib` lines name.
    static func materialLibraries(objAt url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else { return [] }
        return text.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("mtllib") }.map {
            $0.dropFirst("mtllib".count).trimmingCharacters(in: .whitespaces)
        }
    }

    /// The `newmtl` names of the `.mtl` files an OBJ's `mtllib` lines name, in order (and of
    /// `<name>.mtl` beside it, which ufbx also reads).
    static func materialLibraryOrder(objAt url: URL) -> [String] {
        let libraries = materialLibraries(objAt: url) + [url.deletingPathExtension().lastPathComponent + ".mtl"]
        var names: [String] = []
        for library in libraries {
            let mtl = url.deletingLastPathComponent().appending(path: library)
            guard let text = try? String(contentsOf: mtl, encoding: .utf8) ?? String(contentsOf: mtl, encoding: .isoLatin1) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("newmtl") {
                    let name = trimmed.dropFirst("newmtl".count).trimmingCharacters(in: .whitespaces)
                    if !names.contains(name) { names.append(name) }
                }
            }
        }
        return names
    }

    static func string(_ s: ufbx_string) -> String {
        guard let data = s.data, s.length > 0 else { return "" }
        return data.withMemoryRebound(to: UInt8.self, capacity: s.length) {
            String(decoding: UnsafeBufferPointer(start: $0, count: s.length), as: UTF8.self)
        }
    }

    static func data(_ blob: ufbx_blob) -> Data? {
        guard let bytes = blob.data, blob.size > 0 else { return nil }
        return Data(bytes: bytes, count: blob.size)
    }
}

/// One pass over a loaded scene.
private struct Reader {
    let scene: ufbx_scene
    /// ufbx node (by typed id) → our node index (parents first, from the root).
    var nodeIndex: [UInt32: Int] = [:]
    var nodes: [UnsafeMutablePointer<ufbx_node>] = []
    var source = ModelSource()

    init(_ scene: ufbx_scene) {
        self.scene = scene
        readNodes()
        readMaterials()
        readMeshes()
        readAnimations()
    }

    // MARK: Nodes

    mutating func readNodes() {
        guard let root = scene.root_node else { return }
        var stack = [root]
        while let node = stack.popLast() {
            nodeIndex[node.pointee.typed_id] = nodes.count
            nodes.append(node)
            let children = node.pointee.children
            // Children in file order: push them reversed.
            for index in stride(from: Int(children.count) - 1, through: 0, by: -1) {
                if let child = children.data[index] { stack.append(child) }
            }
        }
        // Depth-first order keeps parents first.
        let skinned = skinBones()
        for node in nodes {
            let n = node.pointee
            source.nodes.append(ModelSource.Node(name: ModelFileLoader.string(n.name),
                                                 parent: n.parent.flatMap { nodeIndex[$0.pointee.typed_id] },
                                                 local: Self.matrix(n.node_to_parent),
                                                 isBone: n.bone != nil || skinned.contains(n.typed_id)))
        }
    }

    /// Nodes a skin cluster deforms with, by typed id.
    func skinBones() -> Set<UInt32> {
        var bones = Set<UInt32>()
        for index in 0..<scene.skin_clusters.count {
            if let bone = scene.skin_clusters.data[index]?.pointee.bone_node { bones.insert(bone.pointee.typed_id) }
        }
        return bones
    }

    // MARK: Materials

    mutating func readMaterials() {
        for index in 0..<scene.materials.count {
            guard let material = scene.materials.data[index]?.pointee else { continue }
            var albedo = Self.texture(material.fbx.diffuse_color.texture) ?? Self.texture(material.pbr.base_color.texture)
            if albedo == nil { albedo = Self.texture(material.fbx.diffuse_factor.texture) }
            let normal = Self.texture(material.fbx.normal_map.texture) ?? Self.texture(material.pbr.normal_map.texture)
                ?? Self.texture(material.fbx.bump.texture)
            let diffuse = material.fbx.diffuse_color
            let color = diffuse.has_value ? SIMD3(Float(diffuse.value_vec4.x), Float(diffuse.value_vec4.y), Float(diffuse.value_vec4.z)) : nil
            let transparency = material.fbx.transparency_factor
            source.materials.append(ModelSource.Material(name: ModelFileLoader.string(material.name), albedo: albedo,
                                                         normalMap: normal, color: color,
                                                         opacity: transparency.has_value ? 1 - Float(transparency.value_real) : nil))
        }
    }

    static func texture(_ pointer: UnsafeMutablePointer<ufbx_texture>?) -> ModelSource.Texture? {
        guard let texture = pointer?.pointee else { return nil }
        // A layered or procedural texture names its first file texture.
        if texture.file_textures.count > 0, let file = texture.file_textures.data[0], file != pointer {
            return Self.texture(file)
        }
        let absolute = ModelFileLoader.string(texture.absolute_filename)
        let relative = ModelFileLoader.string(texture.relative_filename)
        let raw = ModelFileLoader.string(texture.filename)
        let path = [absolute, relative, raw].first { !$0.isEmpty } ?? ""
        let embedded = ModelFileLoader.data(texture.content)
        guard !path.isEmpty || embedded != nil else { return nil }
        return ModelSource.Texture(path: path, embedded: embedded)
    }

    // MARK: Meshes

    mutating func readMeshes() {
        for node in nodes {
            guard let meshPointer = node.pointee.mesh else { continue }
            readMesh(meshPointer.pointee, node: node.pointee)
        }
    }

    mutating func readMesh(_ mesh: ufbx_mesh, node: ufbx_node) {
        let name = ModelFileLoader.string(node.name)
        let materials = node.materials.count > 0 ? node.materials : mesh.materials
        let skin: ufbx_skin_deformer? = mesh.skin_deformers.count > 0 ? mesh.skin_deformers.data[0]?.pointee : nil
        let geometryToWorld = node.geometry_to_world
        let normalMatrix = ufbx_matrix_for_normals([geometryToWorld])
        // Per cluster: the bone's rest world times the geometry's inverse bind (geometry → model space).
        var clusterMatrices: [ufbx_matrix] = []
        var clusterNodes: [Int] = []
        if let skin {
            for index in 0..<skin.clusters.count {
                guard let cluster = skin.clusters.data[index]?.pointee else { continue }
                if let bone = cluster.bone_node {
                    clusterMatrices.append(ufbx_matrix_mul([bone.pointee.node_to_world], [cluster.geometry_to_bone]))
                    clusterNodes.append(nodeIndex[bone.pointee.typed_id] ?? 0)
                } else {
                    clusterMatrices.append(geometryToWorld)
                    clusterNodes.append(nodeIndex[node.typed_id] ?? 0)
                }
            }
        }
        let partCount = max(Int(mesh.material_parts.count), 1)
        var triangle = [UInt32](repeating: 0, count: Int(max(mesh.max_face_triangles, 1)) * 3)
        for part in 0..<partCount {
            let faces: [UInt32]
            if mesh.material_parts.count > 0 {
                let list = mesh.material_parts.data[part].face_indices
                faces = (0..<list.count).map { list.data[$0] }
            } else {
                faces = (0..<UInt32(mesh.faces.count)).map { $0 }
            }
            guard !faces.isEmpty else { continue }
            var material: Int?
            if part < materials.count, let pointer = materials.data[part] { material = Int(pointer.pointee.typed_id) }
            var out = ModelSource.Mesh(name: name, material: material, positions: [])
            var normals: [SIMD3<Float>] = []
            var uvs: [SIMD2<Float>] = []
            var secondUVs: [SIMD2<Float>] = []
            var influences: [ModelSource.Influences] = []
            var tangents: [SIMD3<Float>] = []
            var bitangents: [SIMD3<Float>] = []
            let hasTangents = mesh.vertex_tangent.exists && mesh.vertex_bitangent.exists
            let hasSecondUV = mesh.uv_sets.count > 1
            for faceIndex in faces {
                let face = mesh.faces.data[Int(faceIndex)]
                guard face.num_indices >= 3 else { continue }
                let corners = Self.triangulate(face, mesh: mesh, scratch: &triangle)
                for corner in corners {
                    let index = Int(corner)
                    let p = ufbx_get_vertex_vec3([mesh.vertex_position], index)
                    let n = mesh.vertex_normal.exists ? ufbx_get_vertex_vec3([mesh.vertex_normal], index) : nil
                    let t = hasTangents ? ufbx_get_vertex_vec3([mesh.vertex_tangent], index) : nil
                    let b = hasTangents ? ufbx_get_vertex_vec3([mesh.vertex_bitangent], index) : nil
                    var weightsOfCorner: [(Int, Float, Int)] = []  // (node, weight, cluster)
                    if let skin {
                        let vertex = Int(mesh.vertex_indices.data[index])
                        if vertex < skin.vertices.count {
                            let entry = skin.vertices.data[vertex]
                            for w in 0..<Int(entry.num_weights) {
                                let weight = skin.weights.data[Int(entry.weight_begin) + w]
                                let cluster = Int(weight.cluster_index)
                                guard cluster < clusterNodes.count, weight.weight > 0 else { continue }
                                weightsOfCorner.append((clusterNodes[cluster], Float(weight.weight), cluster))
                            }
                        }
                    }
                    if skin != nil {
                        // WE keeps four influences (Assimp's LimitBoneWeights): the largest, renormalised.
                        weightsOfCorner.sort { $0.1 > $1.1 }
                        let kept = Array(weightsOfCorner.prefix(4))
                        let total = kept.reduce(Float(0)) { $0 + $1.1 }
                        var position = SIMD3<Double>.zero, normal = SIMD3<Double>.zero
                        var tangent = SIMD3<Double>.zero, bitangent = SIMD3<Double>.zero
                        if total > 0 {
                            for (_, weight, cluster) in kept {
                                let m = clusterMatrices[cluster]
                                let share = Double(weight / total)
                                position += Self.vector(ufbx_transform_position([m], p)) * share
                                if let n {
                                    normal += Self.vector(ufbx_transform_direction([ufbx_matrix_for_normals([m])], n)) * share
                                }
                                if let t, let b {
                                    tangent += Self.vector(ufbx_transform_direction([m], t)) * share
                                    bitangent += Self.vector(ufbx_transform_direction([m], b)) * share
                                }
                            }
                        } else {
                            position = Self.vector(ufbx_transform_position([geometryToWorld], p))
                            if let n { normal = Self.vector(ufbx_transform_direction([normalMatrix], n)) }
                            if let t, let b {
                                tangent = Self.vector(ufbx_transform_direction([geometryToWorld], t))
                                bitangent = Self.vector(ufbx_transform_direction([geometryToWorld], b))
                            }
                        }
                        if t != nil {
                            tangents.append(Self.normalized(SIMD3<Float>(tangent)))
                            bitangents.append(Self.normalized(SIMD3<Float>(bitangent)))
                        }
                        out.positions.append(SIMD3<Float>(position))
                        if n != nil { normals.append(Self.normalized(SIMD3<Float>(normal))) }
                        var nodesOf = SIMD4<UInt32>.zero, weightsOf = SIMD4<Float>.zero
                        if total > 0 {
                            for (slot, entry) in kept.enumerated() {
                                nodesOf[slot] = UInt32(entry.0)
                                weightsOf[slot] = entry.1 / total
                            }
                        } else {
                            nodesOf[0] = UInt32(nodeIndex[node.typed_id] ?? 0)
                            weightsOf[0] = 1
                        }
                        influences.append(ModelSource.Influences(nodes: nodesOf, weights: weightsOf))
                    } else {
                        out.positions.append(SIMD3<Float>(Self.vector(ufbx_transform_position([geometryToWorld], p))))
                        if let n { normals.append(Self.normalized(SIMD3<Float>(Self.vector(ufbx_transform_direction([normalMatrix], n))))) }
                        if let t, let b {
                            tangents.append(Self.normalized(SIMD3<Float>(Self.vector(ufbx_transform_direction([geometryToWorld], t)))))
                            bitangents.append(Self.normalized(SIMD3<Float>(Self.vector(ufbx_transform_direction([geometryToWorld], b)))))
                        }
                    }
                    if mesh.vertex_uv.exists {
                        let uv = ufbx_get_vertex_vec2([mesh.vertex_uv], index)
                        uvs.append(SIMD2(Float(uv.x), Float(uv.y)))
                    }
                    if hasSecondUV {
                        let set = mesh.uv_sets.data[1].vertex_uv
                        let uv = set.exists ? ufbx_get_vertex_vec2([set], index) : ufbx_vec2()
                        secondUVs.append(SIMD2(Float(uv.x), Float(uv.y)))
                    }
                }
            }
            guard !out.positions.isEmpty else { continue }
            if normals.count == out.positions.count { out.normals = normals }
            if uvs.count == out.positions.count { out.uvs = uvs }
            if secondUVs.count == out.positions.count { out.secondUVs = secondUVs }
            if tangents.count == out.positions.count, bitangents.count == out.positions.count {
                out.tangents = tangents
                out.bitangents = bitangents
            }
            if skin != nil { out.influences = influences }
            source.meshes.append(out)
        }
    }

    /// A face's triangles as corner indices: a fan from its first corner (Assimp's
    /// triangulation of a convex polygon; a concave quad fans from its reflex corner); ufbx's
    /// triangulation past four corners.
    static func triangulate(_ face: ufbx_face, mesh: ufbx_mesh, scratch: inout [UInt32]) -> [UInt32] {
        let first = face.index_begin, count = face.num_indices
        if count == 3 { return [first, first + 1, first + 2] }
        if count == 4 {
            // Assimp's TriangulateProcess: a quad is split from its first corner whose two
            // angles to the opposite corner add up past π (the concave one), else from corner 0.
            let p = (0..<4).map { SIMD3<Float>(Self.vector(ufbx_get_vertex_vec3([mesh.vertex_position], Int(first) + $0))) }
            var start = 0
            for i in 0..<4 {
                let v = p[i]
                let left = AssimpVector.normalized(p[(i + 3) % 4] - v)
                let diagonal = AssimpVector.normalized(p[(i + 2) % 4] - v)
                let right = AssimpVector.normalized(p[(i + 1) % 4] - v)
                let angle = acos(AssimpVector.dot(left, diagonal)) + acos(AssimpVector.dot(right, diagonal))
                if angle > Float.pi {
                    start = i
                    break
                }
            }
            let c = (0..<4).map { first + UInt32(($0 + start) % 4) }
            return [c[0], c[1], c[2], c[0], c[2], c[3]]
        }
        let triangles = scratch.withUnsafeMutableBufferPointer { buffer in
            ufbx_triangulate_face(buffer.baseAddress, buffer.count, [mesh], face)
        }
        return Array(scratch.prefix(Int(triangles) * 3))
    }

    // MARK: Animations

    mutating func readAnimations() {
        var fps = Float(scene.settings.frames_per_second)
        if !(fps > 0) || !fps.isFinite { fps = 30 }
        for index in 0..<scene.anim_stacks.count {
            guard let stack = scene.anim_stacks.data[index]?.pointee, let anim = stack.anim else { continue }
            let duration = max(stack.time_end - stack.time_begin, 0)
            let frames = max(Int((duration * Double(fps)).rounded()), 1)
            var samples: [[PuppetTransform]] = []
            samples.reserveCapacity(nodes.count)
            for node in nodes {
                var track: [PuppetTransform] = []
                track.reserveCapacity(frames + 1)
                for frame in 0...frames {
                    var transform = ufbx_evaluate_transform(anim, node, stack.time_begin + Double(frame) / Double(fps))
                    let matrix = Self.matrix(ufbx_transform_to_matrix(&transform))
                    track.append(PuppetTransform(matrix: matrix))
                }
                samples.append(track)
            }
            source.animations.append(ModelSource.Animation(name: ModelFileLoader.string(stack.name), fps: fps, frames: frames,
                                                           samples: samples))
        }
    }

    // MARK: Conversions

    static func matrix(_ m: ufbx_matrix) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(Float(m.m00), Float(m.m10), Float(m.m20), 0),
                                SIMD4(Float(m.m01), Float(m.m11), Float(m.m21), 0),
                                SIMD4(Float(m.m02), Float(m.m12), Float(m.m22), 0),
                                SIMD4(Float(m.m03), Float(m.m13), Float(m.m23), 1)))
    }

    static func vector(_ v: ufbx_vec3) -> SIMD3<Double> { SIMD3(Double(v.x), Double(v.y), Double(v.z)) }

    static func normalized(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(v)
        return length > 0 ? v / length : v
    }
}

/// Assimp's vector arithmetic (single precision, normalising by the length's reciprocal).
enum AssimpVector {
    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let xy: Float = a.x * b.x + a.y * b.y
        return xy + a.z * b.z
    }

    static func normalized(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let length = dot(v, v).squareRoot()
        guard length != 0 else { return v }
        let inverse: Float = 1 / length
        return SIMD3(v.x * inverse, v.y * inverse, v.z * inverse)
    }
}
