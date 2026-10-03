import Foundation

extension SceneEditOverlay {
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
        guard var objects = root["objects"] as? [[String: Any]] else { throw SceneEditOverlayError.notAScene }
        for index in objects.indices {
            let objectID = (objects[index]["id"] as? NSNumber)?.intValue ?? index
            guard let edit = self.objects[String(objectID)], edit.hasSceneEdits else { continue }
            for (name, value) in edit.fields {
                objects[index][name] = Self.merged(objects[index][name], with: value.any)
            }
            guard !edit.effects.isEmpty, var effects = objects[index]["effects"] as? [[String: Any]] else { continue }
            for (key, effectEdit) in edit.effects {
                guard let effectIndex = Int(key), effects.indices.contains(effectIndex) else { continue }
                if let visible = effectEdit.visible {
                    effects[effectIndex]["visible"] = Self.merged(effects[effectIndex]["visible"], with: visible)
                }
                guard !effectEdit.constants.isEmpty else { continue }
                var passes = effects[effectIndex]["passes"] as? [[String: Any]] ?? []
                if passes.isEmpty { passes = [[:]] }
                var constants = passes[0]["constants"] as? [String: Any] ?? [:]
                for (constant, value) in effectEdit.constants {
                    // WE's keys are matched without case (`SceneEffectPlanBuilder`); keep the authored spelling.
                    let authoredKey = constants.keys.first { $0.caseInsensitiveCompare(constant) == .orderedSame } ?? constant
                    constants[authoredKey] = Self.merged(constants[authoredKey], with: value.any)
                }
                passes[0]["constants"] = constants
                effects[effectIndex]["passes"] = passes
            }
            objects[index]["effects"] = effects
        }
        root["objects"] = objects
    }

    /// An edit of a field the scene drives (a script or an animation) sets its starting `value`
    /// and keeps the driver; any other edit replaces the field.
    static func merged(_ existing: Any?, with value: Any) -> Any {
        guard var object = existing as? [String: Any],
              object["script"] != nil || object["animation"] != nil || object["value"] != nil || object["user"] != nil else {
            return value
        }
        object["value"] = value
        return object
    }
}
