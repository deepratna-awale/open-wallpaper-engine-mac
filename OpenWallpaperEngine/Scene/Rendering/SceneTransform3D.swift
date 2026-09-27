import simd

/// An object's own 3D transform relative to its parent: `origin` in world units (pixels in an
/// orthographic scene, scene units in a perspective one), `scale` per axis and `angles` in radians
/// (docs/models-plan.md §2.3). SceneScript's `angles` are degrees at the API, but the object table
/// keeps radians, so every value here is radians.
struct SceneLocalTransform3D: Equatable {
    var origin: SIMD3<Float>
    var scale: SIMD3<Float>
    var angles: SIMD3<Float>

    static let identity = SceneLocalTransform3D(origin: .zero, scale: SIMD3(repeating: 1), angles: .zero)

    init(origin: SIMD3<Float>, scale: SIMD3<Float>, angles: SIMD3<Float>) {
        self.origin = origin
        self.scale = scale
        self.angles = angles
    }

    /// The authored transform. WE's object constructor defaults `origin` to 0, `scale` to 1 and
    /// `angles` to 0 (+0x128, +0x134, +0x140). `rootOrigin` is where a root object without an
    /// `origin` sits: 0 in WE; the orthographic 2D path centres it in the scene
    /// (`SceneLocalTransform(object:sceneSize:)`), and passing that centre keeps the two paths
    /// equal. A vector with fewer than three numbers keeps the field's default for the rest [I].
    init(object: WESceneObject, rootOrigin: SIMD3<Float> = .zero) {
        let defaultOrigin = object.parent == nil ? rootOrigin : .zero
        origin = Self.vector(object.origin, default: defaultOrigin)
        scale = Self.vector(object.scale, default: SIMD3(repeating: 1))
        angles = Self.vector(object.angles, default: .zero)
    }

    /// The 2D transform with a depth: `origin.z` and `scale.z` added to the 2D path's values.
    init(_ local: SceneLocalTransform, originZ: Float = 0, scaleZ: Float = 1) {
        origin = SIMD3(local.origin, originZ)
        scale = SIMD3(local.scale, scaleZ)
        angles = SIMD3(local.tilt, local.angle)
    }

    /// The 2D path's view of this transform (`origin.z` and `scale.z` dropped).
    var planar: SceneLocalTransform {
        SceneLocalTransform(origin: SIMD2(origin.x, origin.y), scale: SIMD2(scale.x, scale.y), angle: angles.z,
                            tilt: SIMD2(angles.x, angles.y))
    }

    /// WE's own matrix for this transform (`SceneWorldMatrix.local`).
    var matrix: simd_float4x4 { SceneWorldMatrix.local(self) }

    private static func vector(_ text: String?, default fallback: SIMD3<Float>) -> SIMD3<Float> {
        guard let text else { return fallback }
        let numbers = text.split(separator: " ").compactMap { Float($0) }
        var value = fallback
        for index in 0..<min(numbers.count, 3) { value[index] = numbers[index] }
        return value
    }
}

/// WE's object matrices (docs/models-plan.md §2.3), in simd's column-vector convention: a point
/// maps as `world * SIMD4(p, 1)` and a parent's world applies after its child's, `parent * child`.
///
/// WE keeps row-vector matrices whose rows are the basis vectors (0x1401dd630 stores them at
/// +0x14c…+0x16c) and the origin in row 3 (0x1401850a0). A `simd_float4x4`'s columns are those
/// rows, so its memory is exactly WE's matrix (and glm's column-major one): column i is WE's
/// row i. Upload it as is wherever WE uploads its matrix (`g_ModelMatrix`).
enum SceneWorldMatrix {
    /// 0x1401dd630: `R = Rz·Ry·Rx` of `angles` (radians), as its three basis rows:
    /// - row0 = (cy·cz, cy·sz, −sy)
    /// - row1 = (sx·sy·cz − cx·sz, sx·sy·sz + cx·cz, sx·cy)
    /// - row2 = (cx·sy·cz + sx·sz, cx·sy·sz − sx·cz, cx·cy)
    ///
    /// Row i is where the object's local axis i points in its parent's space.
    static func rows(_ angles: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let cx = cos(angles.x), sx = sin(angles.x)
        let cy = cos(angles.y), sy = sin(angles.y)
        let cz = cos(angles.z), sz = sin(angles.z)
        return (SIMD3(cy * cz, cy * sz, -sy),
                SIMD3(sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy),
                SIMD3(cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy))
    }

    /// 0x1401850a0's local matrix: row i = rotation row i × `scale[i]`, row 3 = `origin`.
    static func local(_ transform: SceneLocalTransform3D) -> simd_float4x4 {
        let (row0, row1, row2) = rows(transform.angles)
        return simd_float4x4(columns: (SIMD4(row0 * transform.scale.x, 0), SIMD4(row1 * transform.scale.y, 0),
                                       SIMD4(row2 * transform.scale.z, 0), SIMD4(transform.origin, 1)))
    }

    /// The angles whose rows are `row0`…`row2`: WE's extraction after a camera layer's path
    /// sets its eye, centre and up (0x1401f31f7–0x1401f3306, into 0x1401dd630):
    /// z = atan2(row0.y, row0.x), y = atan2(−row0.z, |(row1.z, row2.z)|),
    /// x = atan2(row2.x·sz − row2.y·cz, row1.y·cz − row1.x·sz). It inverts `rows` for |y| < π/2.
    static func angles(row0: SIMD3<Float>, row1: SIMD3<Float>, row2: SIMD3<Float>) -> SIMD3<Float> {
        let z = atan2(row0.y, row0.x)
        let y = atan2(-row0.z, (row1.z * row1.z + row2.z * row2.z).squareRoot())
        let sz = sin(z), cz = cos(z)
        let x = atan2(row2.x * sz - row2.y * cz, row1.y * cz - row1.x * sz)
        return SIMD3(x, y, z)
    }

    /// The angles of an object at `eye` looking at `center` with `up`: `lookAtRH`'s basis
    /// (0x14019d920: f = normalize(center − eye), s = normalize(f × up), u = s × f) as rows
    /// (s, u, −f), then `angles(row0:row1:row2:)`, as a camera layer's path writes back its
    /// `angles` (0x1401f31f2). Its forward, −row2, is then f.
    static func lookAtAngles(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> SIMD3<Float> {
        let forward = simd_normalize(center - eye)
        let side = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(side, forward)
        return angles(row0: side, row1: trueUp, row2: -forward)
    }

    /// Where an object with this world matrix looks: its local −Z, WE's camera convention
    /// (docs/models-plan.md §2.3), i.e. −row2, normalised (scale removed).
    static func forward(_ world: simd_float4x4) -> SIMD3<Float> {
        let back = SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z)
        return simd_length(back) > 0 ? -simd_normalize(back) : SIMD3(0, 0, -1)
    }

    /// Its local +Y (row 1), normalised.
    static func up(_ world: simd_float4x4) -> SIMD3<Float> {
        let up = SIMD3(world.columns.1.x, world.columns.1.y, world.columns.1.z)
        return simd_length(up) > 0 ? simd_normalize(up) : SIMD3(0, 1, 0)
    }

    /// Its origin (row 3).
    static func translation(_ world: simd_float4x4) -> SIMD3<Float> {
        SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }

    /// What an orthographic view along −Z shows of the z = 0 plane under `world`: its x and y
    /// rows without their z, and its origin's x and y. For a chain whose tilts are all on the
    /// leaf (every library ortho scene, `SceneTransform3DLibraryTests`) this is exactly the 2D
    /// path's `SceneAffineTransform`.
    static func orthographic(_ world: simd_float4x4) -> SceneAffineTransform {
        SceneAffineTransform(linear: simd_float2x2(columns: (SIMD2(world.columns.0.x, world.columns.0.y),
                                                            SIMD2(world.columns.1.x, world.columns.1.y))),
                             translation: SIMD2(world.columns.3.x, world.columns.3.y))
    }
}

/// An object hanging from a bone of its parent's model through `attachment` (docs/models-plan.md
/// §2.6): what the attachment hook is asked about.
struct SceneAttachedObject: Equatable {
    let id: String
    let parentID: String
    /// The exact name in the parent model's MDAT attachment list.
    let attachment: String
}

/// The bone-attachment hook of the 3D hierarchy (M6 implements it with the parent's skeleton).
protocol SceneAttachmentProviding {
    /// `boneWorld[bone] · attachment.matrix` of the parent's attachment named `object.attachment`,
    /// in the parent's model space, this frame (0x1402248c0). WE puts it between the parent's
    /// world and the child's local (0x1401850a0: world = parentWorld · attachment · local). Nil
    /// when the parent has no such attachment or no posed skeleton; the object then hangs from
    /// its parent's origin, as WE's index −1 does.
    func attachmentWorld(_ object: SceneAttachedObject) -> simd_float4x4?
}

/// The scene's parent graph in 3D: every object's authored `SceneLocalTransform3D`, its parent and
/// its bone attachment. A world matrix composes an object's ancestors root first, as WE's
/// 0x1401850a0 recurses: world = parentWorld · [attachment ·] local. Every object has a node,
/// groups and camera layers included, so children follow any parent.
struct SceneTransformHierarchy3D: Equatable {
    struct Node: Equatable {
        let parentID: String?
        let local: SceneLocalTransform3D
        /// The `attachment` name, when the object hangs from a bone of its parent.
        let attachment: String?

        init(parentID: String?, local: SceneLocalTransform3D, attachment: String? = nil) {
            self.parentID = parentID
            self.local = local
            self.attachment = attachment
        }
    }

    /// This frame's own transform of an object, when it differs from the authored one (scripts,
    /// timelines, user bindings: `SceneObjectMotion.local3D`); nil keeps the authored one.
    typealias Live = (String) -> SceneLocalTransform3D?

    private(set) var nodes: [String: Node]

    static let empty = SceneTransformHierarchy3D(nodes: [:])

    init(nodes: [String: Node]) { self.nodes = nodes }

    /// Every object of `objects`, keyed like the 2D hierarchy (`id`, else its index). The
    /// `attachment` is every object's (`WESceneObject.attachment`).
    init(objects: [WESceneObject], rootOrigin: SIMD3<Float> = .zero) {
        var nodes: [String: Node] = [:]
        for (index, object) in objects.enumerated() {
            nodes[String(object.id ?? index)] = Node(parentID: object.parent.map(String.init),
                                                     local: SceneLocalTransform3D(object: object, rootOrigin: rootOrigin),
                                                     attachment: object.attachment ?? object.model?.attachment)
        }
        self.nodes = nodes
    }

    /// `id`'s ancestors, nearest first. A missing parent ends the chain (the object is a root, as
    /// in the 2D hierarchy); a cycle stops the walk.
    func ancestors(of id: String) -> [String] {
        var chain: [String] = []
        var visited: Set<String> = [id]
        var next = nodes[id]?.parentID
        while let parentID = next, visited.insert(parentID).inserted, let node = nodes[parentID] {
            chain.append(parentID)
            next = node.parentID
        }
        return chain
    }

    /// The composed world matrix of `id`'s parent (identity for a root). `live` supplies this
    /// frame's local transforms; `attachments` resolves bone attachments along the chain.
    func parentWorld(of id: String, live: Live = { _ in nil },
                     attachments: SceneAttachmentProviding? = nil) -> simd_float4x4 {
        ancestors(of: id).reversed().reduce(matrix_identity_float4x4) { world, ancestor in
            world * ownMatrix(ancestor, local: live(ancestor), attachments: attachments)
        }
    }

    /// `id`'s world matrix: its parent's world times its own (attachment, then local). `local`
    /// overrides its own transform; otherwise `live`, then the authored one.
    func world(of id: String, local: SceneLocalTransform3D? = nil, live: Live = { _ in nil },
               attachments: SceneAttachmentProviding? = nil) -> simd_float4x4 {
        guard nodes[id] != nil || local != nil else { return matrix_identity_float4x4 }
        return parentWorld(of: id, live: live, attachments: attachments)
            * ownMatrix(id, local: local ?? live(id), attachments: attachments)
    }

    /// Every node's world matrix: a frame's model matrices for all objects at once. `live` is
    /// asked once per node per chain it is in; the renderer caches its per-frame locals.
    func worlds(live: Live = { _ in nil }, attachments: SceneAttachmentProviding? = nil) -> [String: simd_float4x4] {
        var worlds: [String: simd_float4x4] = [:]
        worlds.reserveCapacity(nodes.count)
        for id in nodes.keys { worlds[id] = world(of: id, live: live, attachments: attachments) }
        return worlds
    }

    /// `[attachment ·] local` of one node. The attachment applies only to an object with a parent
    /// in the hierarchy (WE's +0x180 set).
    private func ownMatrix(_ id: String, local: SceneLocalTransform3D?,
                           attachments: SceneAttachmentProviding?) -> simd_float4x4 {
        let node = nodes[id]
        let own = (local ?? node?.local ?? .identity).matrix
        guard let attachments, let node, let name = node.attachment, let parentID = node.parentID,
              nodes[parentID] != nil,
              let attachment = attachments.attachmentWorld(SceneAttachedObject(id: id, parentID: parentID,
                                                                              attachment: name)) else { return own }
        return attachment * own
    }
}
