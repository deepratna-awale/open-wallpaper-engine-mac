import Foundation
import simd

/// Geometry a script made with `thisScene.createModelData` (WE's `IModelData`, lib.sceneScript.d.ts;
/// scenescript64.dll 0x18162fd40 parses the configuration, 0x1816362d9 hands it to the engine and
/// sets `__modelDataToken`). A model layer shows it through `createLayer({model: modelData})`:
/// `_Internal.stringifyConfig` writes the token as the object's numeric `model`
/// (`WESceneModel.Source.loadedID`), which WE's object factory resolves to the loaded data.
///
/// Each shape is one mesh: interleaved floats in the order `position` (3), `normal` (3),
/// `tangentSigned` (4), `uv` (2), `color` (4), the subset the shape's `vertexFormat` enables, which
/// is `.mdl`'s own table order (`MDLVertexAttribute.all`); an optional `Uint16Array`/`Uint32Array`
/// triangle list (without one the vertices are a triangle list); a material (an `IAssetHandle`),
/// drawn like a `.mdl` mesh's.
struct SceneScriptModelData: Equatable {
    struct Shape: Equatable {
        var format: MDLVertexFormat
        /// The material's paths to try, in order (under the script's Workshop item first,
        /// `SceneScriptLayerSource.assetPaths`).
        var materialPaths: [String]
        var vertices: Data
        /// Indices as the script gave them; nil draws the vertices as a triangle list.
        var indices: Data?
        var usesUInt32Indices: Bool
        /// `isVertexBufferDynamic` / `isIndexBufferDynamic`: `applyData` may change them.
        var dynamicVertices: Bool
        var dynamicIndices: Bool

        var vertexCount: Int { format.stride == 0 ? 0 : vertices.count / format.stride }
        var indexCount: Int { indices.map { $0.count / (usesUInt32Indices ? 4 : 2) } ?? vertexCount }

        /// The triangle list the GPU draws: the script's indices, or 0…n−1 (u32 then).
        var drawnIndices: Data {
            if let indices { return indices }
            var list = Data(count: vertexCount * 4)
            list.withUnsafeMutableBytes { raw in
                for vertex in 0..<vertexCount {
                    raw.storeBytes(of: UInt32(vertex).littleEndian, toByteOffset: vertex * 4, as: UInt32.self)
                }
            }
            return list
        }

        var drawsUInt32Indices: Bool { indices == nil || usesUInt32Indices }
    }

    var shapes: [Shape]
    /// `boundingBoxMins`/`boundingBoxMaxs` ("only necessary if you are animating the model
    /// geometry"), else the box of the shapes' positions when made.
    var bounds: MDLBounds

    /// The vertex format names in their required order, with the attribute each enables.
    static let formatOrder: [(name: String, attribute: MDLVertexAttribute)] = [
        ("position", .position), ("normal", .normal), ("tangentSigned", .tangent4), ("uv", .texCoord), ("color", .color),
    ]

    /// The format of a `vertexFormat` array; nil when a name is unknown, repeated or out of order
    /// ("Vertex format in incorrect order.").
    static func format(_ names: [String]) -> MDLVertexFormat? {
        var bits: UInt32 = 0
        var last = -1
        for name in names {
            guard let index = formatOrder.firstIndex(where: { $0.name == name }), index > last else { return nil }
            last = index
            bits |= formatOrder[index].attribute.mask
        }
        return MDLVertexFormat(rawValue: bits)
    }

    /// The box of every shape's positions; `MDLBounds.unbounded` without any.
    static func positionBounds(_ shapes: [Shape]) -> MDLBounds {
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = -low
        for shape in shapes {
            guard let offset = shape.format.offset(of: .position) else { continue }
            let stride = shape.format.stride
            shape.vertices.withUnsafeBytes { raw in
                for vertex in 0..<shape.vertexCount {
                    let base = vertex * stride + offset
                    let point = SIMD3(raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                                      raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                                      raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self))
                    low = simd_min(low, point)
                    high = simd_max(high, point)
                }
            }
        }
        return low.x <= high.x ? MDLBounds(min: low, max: high) : .unbounded
    }
}

/// One shape's part of an `applyData`: only what the script passed (nil keeps the buffer).
struct SceneScriptModelDataUpdate: Equatable {
    var vertices: Data?
    var indices: Data?
    var indicesAreUInt32 = false
}

/// The model data one wallpaper instance's scripts made, by token. Scripts write it on their thread
/// (`SceneScriptObjectModel`); the loader reads it to plan a model layer and the renderer every
/// frame for the geometry `applyData` changed (`SceneModelGeometrySource`). One lock owns
/// `entries` and `nextToken`.
final class SceneScriptModelDataStore {
    /// WE's messages (scenescript64.dll 0x18162fc80's table).
    enum Failure: Error, Equatable, CustomStringConvertible {
        case invalidToken, vertexBufferGrew, indexBufferGrew, notDynamic, indexType, addsShapes, inconsistentVertices

        var description: String {
            switch self {
            case .invalidToken: return "Invalid model data token"
            case .vertexBufferGrew: return "Vertex buffer size cannot increase"
            case .indexBufferGrew: return "Index buffer size cannot increase"
            case .notDynamic: return "Model data not created as dynamic"
            case .indexType: return "Incorrect index buffer type"
            case .addsShapes: return "Cannot add shapes in IModelData.update"
            case .inconsistentVertices: return "Inconsistent vertex buffer size"
            }
        }
    }

    private let lock = NSLock()
    private var entries: [Int: (data: SceneScriptModelData, revision: UInt64)] = [:]
    /// How many times each token's data was replaced (`replaceData`).
    private var generations: [Int: UInt64] = [:]
    private var nextToken = 1

    /// Stores new data; returns its token.
    func create(_ data: SceneScriptModelData) -> Int {
        lock.withLock {
            let token = nextToken
            nextToken += 1
            entries[token] = (data, 1)
            return token
        }
    }

    /// `replaceData`: new, possibly incompatible data under the same token.
    func replace(_ token: Int, with data: SceneScriptModelData) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[token] else { throw Failure.invalidToken }
        entries[token] = (data, entry.revision &+ 1)
        generations[token, default: 0] &+= 1
    }

    /// `applyData`: new contents for dynamic buffers of the same or a smaller size.
    func apply(_ token: Int, _ updates: [SceneScriptModelDataUpdate]) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[token] else { throw Failure.invalidToken }
        guard updates.count <= entry.data.shapes.count else { throw Failure.addsShapes }
        for (index, update) in updates.enumerated() {
            var shape = entry.data.shapes[index]
            if let vertices = update.vertices {
                guard shape.dynamicVertices else { throw Failure.notDynamic }
                guard vertices.count <= shape.vertices.count else { throw Failure.vertexBufferGrew }
                guard shape.format.stride > 0, vertices.count % shape.format.stride == 0 else {
                    throw Failure.inconsistentVertices
                }
                shape.vertices = vertices
            }
            if let indices = update.indices {
                guard shape.dynamicIndices else { throw Failure.notDynamic }
                guard update.indicesAreUInt32 == shape.usesUInt32Indices else { throw Failure.indexType }
                guard indices.count <= (shape.indices?.count ?? 0) else { throw Failure.indexBufferGrew }
                shape.indices = indices
            }
            entry.data.shapes[index] = shape
        }
        entry.revision &+= 1
        entries[token] = entry
    }

    /// `destroyModelData`: a layer still showing it keeps what it has.
    func destroy(_ token: Int) {
        lock.withLock { _ = entries.removeValue(forKey: token) }
    }

    /// The data under `token` now, with its revision (bumped by every change).
    func snapshot(_ token: Int) -> (data: SceneScriptModelData, revision: UInt64)? {
        lock.withLock { entries[token] }
    }

    /// The data under `token` with how many times it was replaced; nil when there is none.
    func replaced(_ token: Int) -> (data: SceneScriptModelData, generation: UInt64)? {
        lock.withLock { entries[token].map { ($0.data, generations[token] ?? 0) } }
    }
}

/// A model layer's view of its model data (`SceneModelPlan.geometry`): the meshes' vertices and
/// triangle lists as the scripts last left them, and a new plan once `replaceData` replaced them.
/// The renderer asks from its render thread, which owns `plannedGeneration`.
final class SceneScriptModelGeometry: SceneModelGeometrySource {
    private let store: SceneScriptModelDataStore
    let token: Int
    /// Plans the model again from replaced data (the loader's `SceneScriptModelPlanBuilder`).
    var replan: ((SceneScriptModelData) -> SceneModelPlan?)?
    /// The replacement the current plan was made from.
    private var plannedGeneration: UInt64

    init(store: SceneScriptModelDataStore, token: Int) {
        self.store = store
        self.token = token
        plannedGeneration = store.replaced(token)?.generation ?? 0
    }

    /// WE re-creates a model whose data a script replaced, whatever its shapes now are (other
    /// counts, formats, materials or index types; scenescript64.dll hands the new data to the
    /// engine as `createModelData` does, 0x1816362d9). Nil when nothing was replaced, or when the
    /// new data plans nothing that draws (logged by the builder): the model keeps what it drew.
    func replacement(for plan: SceneModelPlan) -> SceneModelPlan? {
        guard let (data, generation) = store.replaced(token), generation != plannedGeneration else { return nil }
        plannedGeneration = generation
        return replan?(data)
    }

    func geometry(newerThan revision: UInt64) -> SceneModelGeometry? {
        guard let (data, current) = store.snapshot(token), current != revision else { return nil }
        return SceneModelGeometry(revision: current, meshes: data.shapes.map {
            .init(vertices: $0.vertices, indices: $0.drawnIndices, indexCount: $0.indexCount)
        })
    }
}
