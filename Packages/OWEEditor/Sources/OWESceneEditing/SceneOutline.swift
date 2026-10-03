import Foundation

/// scene.json's objects as the editor shows them: their order, kinds, parents and effects, and the
/// scene's size when it is a 2D (orthographic) scene.
public struct SceneOutline: Sendable {
    public let layers: [SceneLayer]
    /// The orthographic scene's size in scene units; nil for a 3D (perspective) scene.
    public let size: SIMD2<Double>?
    private let byID: [Int: Int]

    public init(sceneData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: sceneData) as? [String: Any] else {
            throw SceneEditOverlayError.notAScene
        }
        try self.init(root: root)
    }

    public init(root: [String: Any]) throws {
        guard let objects = root["objects"] as? [[String: Any]] else { throw SceneEditOverlayError.notAScene }
        let parents = Set(objects.compactMap { ($0["parent"] as? NSNumber)?.intValue })
        var layers: [SceneLayer] = []
        for (index, object) in objects.enumerated() {
            let id = (object["id"] as? NSNumber)?.intValue ?? index
            var fields: [String: SceneJSONValue] = [:]
            for (key, value) in object where key != "effects" {
                if let value = SceneJSONValue(any: value) { fields[key] = value }
            }
            let effects = (object["effects"] as? [[String: Any]] ?? []).enumerated().map { effectIndex, effect in
                SceneLayerEffect(id: effectIndex, file: effect["file"] as? String ?? "",
                                 name: effect["name"] as? String,
                                 visible: SceneJSONValue(any: effect["visible"]).flatMap { $0 == .null ? nil : $0 })
            }
            layers.append(SceneLayer(id: id, index: index, name: object["name"] as? String,
                                     kind: Self.kind(of: object, isParent: parents.contains(id)),
                                     parentID: (object["parent"] as? NSNumber)?.intValue,
                                     fields: fields, effects: effects))
        }
        self.layers = layers
        var byID: [Int: Int] = [:]
        for (position, layer) in layers.enumerated() where byID[layer.id] == nil { byID[layer.id] = position }
        self.byID = byID
        size = Self.orthographicSize(root, layers: layers)
    }

    /// An outline of `layers` as they are (the editor's added and deleted objects applied).
    init(layers: [SceneLayer], size: SIMD2<Double>?) {
        self.layers = layers
        self.size = size
        var byID: [Int: Int] = [:]
        for (position, layer) in layers.enumerated() where byID[layer.id] == nil { byID[layer.id] = position }
        self.byID = byID
    }

    public func layer(_ id: Int) -> SceneLayer? { byID[id].map { layers[$0] } }

    /// The layers whose parent is `id` (the scene's top level for nil), in draw order. A layer
    /// whose parent isn't in the scene is at the top level.
    public func children(of id: Int?) -> [SceneLayer] {
        layers.filter { layer in
            guard let parent = layer.parentID, parent != layer.id, self.layer(parent) != nil else { return id == nil }
            return parent == id
        }
    }

    /// Parent first, up to the top level; a cycle stops the walk.
    public func ancestors(of id: Int) -> [SceneLayer] {
        var chain: [SceneLayer] = []
        var seen: Set<Int> = [id]
        var current = layer(id)?.parentID
        while let parentID = current, seen.insert(parentID).inserted, let parent = layer(parentID) {
            chain.append(parent)
            current = parent.parentID
        }
        return chain
    }

    static func kind(of object: [String: Any], isParent: Bool) -> SceneLayer.Kind {
        if object["image"] is String { return .image }
        if object["text"] != nil { return .text }
        if object["particle"] is String { return .particle }
        if object["sound"] != nil { return .sound }
        if object["light"] != nil { return .light }
        if object["model"] != nil { return .model }
        return isParent ? .group : .other
    }

    /// `orthogonalprojection` as WE reads it: its width and height, or with `auto` the first image
    /// layer's size (WE sizes the scene to it).
    static func orthographicSize(_ root: [String: Any], layers: [SceneLayer]) -> SIMD2<Double>? {
        guard let projection = (root["general"] as? [String: Any])?["orthogonalprojection"] as? [String: Any] else {
            return nil
        }
        if let auto = projection["auto"] as? NSNumber, CFGetTypeID(auto) == CFBooleanGetTypeID(), auto.boolValue {
            let size = layers.first { $0.kind == .image }.map { SceneVector.components(SceneFieldBinding.literal(of: $0.fields["size"])) }
            guard let size, size.count >= 2, size[0] > 0, size[1] > 0 else { return nil }
            return SIMD2(size[0], size[1])
        }
        guard let width = (projection["width"] as? NSNumber)?.doubleValue,
              let height = (projection["height"] as? NSNumber)?.doubleValue,
              width.rounded(.towardZero) != 0, height.rounded(.towardZero) != 0 else { return nil }
        return SIMD2(width.rounded(.towardZero), height.rounded(.towardZero))
    }
}
