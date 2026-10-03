import Foundation

extension SceneEditOverlay {
    /// The key an effect gets in a scene applied for the editor's outline (`apply(to:markingEffectKeys:)`):
    /// the edit key it is changed by. Never written into a scene the renderer or a saved copy reads.
    static let effectKeyMarker = "__oweEditorEffectKey"

    /// scene.json with the scene edits applied; `sceneData` itself when there are none.
    public func applied(to sceneData: Data) throws -> Data {
        guard hasSceneEdits else { return sceneData }
        guard var root = try JSONSerialization.jsonObject(with: sceneData) as? [String: Any] else {
            throw SceneEditOverlayError.notAScene
        }
        try apply(to: &root)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// Applies the scene edits to a decoded scene.json. An object or effect an edit names that the
    /// scene no longer has is skipped: the wallpaper was updated under the edits.
    public func apply(to root: inout [String: Any]) throws {
        try apply(to: &root, markingEffectKeys: false)
    }

    /// `markingEffectKeys`: every effect carries its edit key (`effectKeyMarker`), for the outline.
    func apply(to root: inout [String: Any], markingEffectKeys: Bool) throws {
        guard var objects = root["objects"] as? [[String: Any]] else { throw SceneEditOverlayError.notAScene }
        if hasStructureEdits {
            // Added, deleted or moved layers would shift the index an object without an id is
            // known by: it keeps that index as its id.
            for index in objects.indices where objects[index]["id"] == nil { objects[index]["id"] = index }
            var taken = Set(objects.map(Self.objectID))
            for added in added ?? [] {
                guard case .object = added.object, var object = added.object.any as? [String: Any],
                      taken.insert(added.id).inserted else { continue }
                object["id"] = added.id
                objects.append(object)
            }
        }
        // Scripts and bindings first (added layers included): a value edit of a field they drive
        // is its start value.
        if let authoring {
            root["objects"] = objects
            authoring.applyDrivers(to: &root)
            objects = root["objects"] as? [[String: Any]] ?? objects
        }
        for index in objects.indices {
            let objectID = (objects[index]["id"] as? NSNumber)?.intValue ?? index
            let edit = self.objects[String(objectID)]
            if let edit, edit.hasSceneEdits {
                for (name, value) in edit.fields {
                    // Null drops the field (a layer taken out of its group loses `parent`).
                    if value == .null {
                        objects[index].removeValue(forKey: name)
                    } else {
                        objects[index][name] = Self.merged(objects[index][name], with: value.any)
                    }
                }
            }
            guard edit?.hasSceneEdits == true || markingEffectKeys else { continue }
            Self.applyEffects(edit ?? ObjectEdit(), to: &objects[index], markingKeys: markingEffectKeys)
        }
        if let removed, !removed.isEmpty {
            let gone = Set(removed)
            objects.removeAll { gone.contains(Self.objectID($0)) }
        }
        if let order { objects = Self.ordered(objects, by: order) }
        timelines?.apply(to: &objects)
        root["objects"] = objects
    }

    static func objectID(_ object: [String: Any]) -> Int {
        (object["id"] as? NSNumber)?.intValue ?? -1
    }

    /// `objects` in `order` (by id); an object the order doesn't name keeps its place after the
    /// object it followed (one the wallpaper gained since the edit).
    static func ordered(_ objects: [[String: Any]], by order: [Int]) -> [[String: Any]] {
        var position: [Int: Int] = [:]
        for (index, id) in order.enumerated() where position[id] == nil { position[id] = index }
        var result: [[String: Any]] = []
        var unplaced: [(after: Int?, object: [String: Any])] = []
        var previous: Int?
        for object in objects {
            let id = objectID(object)
            if position[id] == nil { unplaced.append((previous, object)) } else { previous = id }
        }
        let placed = objects.filter { position[objectID($0)] != nil }
            .sorted { position[objectID($0)]! < position[objectID($1)]! }
        for object in unplaced where object.after == nil { result.append(object.object) }
        for object in placed {
            result.append(object)
            let id = objectID(object)
            for follower in unplaced where follower.after == id { result.append(follower.object) }
        }
        return result
    }

    /// The object's effects as edited: added and removed, in their order, each with its edit.
    static func applyEffects(_ edit: ObjectEdit, to object: inout [String: Any], markingKeys: Bool) {
        let authored = object["effects"] as? [[String: Any]] ?? []
        guard !authored.isEmpty || !(edit.addedEffects ?? [:]).isEmpty || markingKeys else { return }
        var byKey: [String: [String: Any]] = [:]
        for (index, effect) in authored.enumerated() { byKey[String(index)] = effect }
        for (key, value) in edit.addedEffects ?? [:] {
            if let effect = value.any as? [String: Any] { byKey[key] = effect }
        }
        for (key, effectEdit) in edit.effects {
            guard var effect = byKey[key] else { continue }
            apply(effectEdit, to: &effect)
            byKey[key] = effect
        }
        let keys = edit.effectOrder ?? defaultEffectOrder(authoredCount: authored.count, added: edit.addedEffects)
        var effects: [[String: Any]] = []
        for key in keys {
            guard var effect = byKey[key] else { continue }
            if markingKeys { effect[effectKeyMarker] = key }
            effects.append(effect)
        }
        if effects.isEmpty && object["effects"] == nil { return }
        object["effects"] = effects
    }

    /// The authored effects in their order, then the added ones in the order they were added.
    static func defaultEffectOrder(authoredCount: Int, added: [String: SceneJSONValue]?) -> [String] {
        (0..<authoredCount).map(String.init) + addedKeysInOrder(added)
    }

    static func addedKeysInOrder(_ added: [String: SceneJSONValue]?) -> [String] {
        (added ?? [:]).keys.sorted { (Int($0.dropFirst()) ?? 0) < (Int($1.dropFirst()) ?? 0) }
    }

    /// One effect's edit: `visible`, and its first pass's constants, combos, textures and bindings.
    static func apply(_ edit: EffectEdit, to effect: inout [String: Any]) {
        if let visible = edit.visible {
            effect["visible"] = merged(effect["visible"], with: visible)
        }
        let bindings = edit.bindings ?? [:], combos = edit.combos ?? [:], textures = edit.textures ?? [:]
        guard !edit.constants.isEmpty || !bindings.isEmpty || !combos.isEmpty || !textures.isEmpty else { return }
        var passes = effect["passes"] as? [[String: Any]] ?? []
        if passes.isEmpty { passes = [[:]] }
        var pass = passes[0]
        // A scene effect's pass keeps its constants in `constantshadervalues`, the only key WE and
        // the renderer read (`WEObjectEffectPass`).
        let constantsKey = "constantshadervalues"
        var constants = pass[constantsKey] as? [String: Any] ?? [:]
        for (constant, value) in edit.constants {
            // WE's keys are matched without case (`SceneEffectPlanBuilder`); keep the authored spelling.
            let key = authoredKey(constant, in: constants)
            constants[key] = merged(constants[key], with: value.any)
        }
        for (constant, property) in bindings {
            let key = authoredKey(constant, in: constants)
            let literal = SceneFieldBinding.literal(of: SceneJSONValue(any: constants[key]))
            if property.isEmpty {
                constants[key] = literal?.any
            } else {
                var bound: [String: Any] = ["user": property]
                if let literal { bound["value"] = literal.any }
                constants[key] = bound
            }
        }
        if !constants.isEmpty || pass[constantsKey] != nil { pass[constantsKey] = constants }
        if !combos.isEmpty {
            var passCombos = pass["combos"] as? [String: Any] ?? [:]
            for (combo, value) in combos { passCombos[authoredKey(combo, in: passCombos)] = value }
            pass["combos"] = passCombos
        }
        if !textures.isEmpty {
            var slots = pass["textures"] as? [Any] ?? []
            for (slot, value) in textures {
                guard let index = Int(slot), (0..<32).contains(index) else { continue }
                while slots.count <= index { slots.append(NSNull()) }
                slots[index] = value.any
            }
            pass["textures"] = slots
        }
        passes[0] = pass
        effect["passes"] = passes
    }

    static func authoredKey(_ key: String, in dictionary: [String: Any]) -> String {
        dictionary.keys.first { $0.caseInsensitiveCompare(key) == .orderedSame } ?? key
    }

    /// An edit of a field the scene drives (a script or an animation) sets its starting `value`
    /// and keeps the driver; any other edit replaces the field. An edit that is itself a binding
    /// (`{"user": …}`, a script or an animation) replaces the field whole; one of those set to null
    /// drops it (`{"value": "x", "script": null}` takes a text layer's script away).
    static func merged(_ existing: Any?, with value: Any) -> Any {
        if let replacing = value as? [String: Any],
           replacing["user"] != nil || replacing["script"] != nil || replacing["animation"] != nil {
            return replacing.filter { !($0.value is NSNull) }
        }
        guard var object = existing as? [String: Any],
              object["script"] != nil || object["animation"] != nil || object["value"] != nil || object["user"] != nil else {
            return value
        }
        object["value"] = value
        return object
    }
}
