import Foundation
import OWESceneEditing

/// What a scene load reads (`Request`, whose `key` identifies the parse) and how the scene
/// file's stored edits are applied.
enum ScenePreparation {
    /// What a scene load reads, and so what its key covers.
    struct Request: Sendable {
        var directory: URL
        /// The project's scene file, e.g. `scene.json`.
        var sceneFile: String
        /// The saved Inspector edits (`_owe_scene_object_*`).
        var edits: [String: String]
        /// Stored user property values that can change the content.
        var userProperties: [String: String]
        /// The settings that affect preparation.
        var settings: String
        var displays: [SceneCacheKey.Display]
        /// The Wallpaper Editor's edits (`SceneEditOverlay`), applied under the Inspector's.
        var overlay: SceneEditOverlay? = nil

        var key: SceneCacheKey {
            SceneCacheKey(sources: SceneCacheKey.sources(of: directory), edits: keyedEdits,
                          userProperties: userProperties, displays: displays, settings: settings)
        }

        /// The edits the key covers: the Inspector's, and the overlay's by its digest.
        var keyedEdits: [String: String] {
            guard let overlay, overlay.hasSceneEdits else { return edits }
            var keyed = edits
            keyed[ScenePreparation.overlayKey] = overlay.digest
            return keyed
        }
    }

    /// Names the editor overlay among the cache key's edits; no stored edit has it (they all start
    /// with `_owe_scene_object_`).
    static let overlayKey = "editorOverlay"

    /// Splits stored values into the Inspector edits and the user properties that feed the key.
    static func split(storedValues values: [String: String]) -> (edits: [String: String], properties: [String: String]) {
        var edits: [String: String] = [:]
        var properties: [String: String] = [:]
        for (key, value) in values {
            if key.hasPrefix("_owe_scene_object_") { edits[key] = value }
            else if !key.hasPrefix("_owe_") { properties[key] = value }
        }
        return (edits, properties)
    }

    /// The scene document with the Wallpaper Editor's overlay applied, then the saved per-object
    /// Inspector edits (replaced objects, origin and scale), which stay the user's own on top of
    /// the scene as edited; `data` itself when it isn't an object with an `objects` array.
    static func resolvedScene(_ data: Data, edits values: [String: String],
                              overlay: SceneEditOverlay? = nil) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["objects"] is [[String: Any]] else { return data }
        if let overlay, overlay.hasSceneEdits { try overlay.apply(to: &root) }
        guard var objects = root["objects"] as? [[String: Any]] else { return data }
        for index in objects.indices {
            let objectID = SceneObjects.objectID(objects[index], index: index)
            guard let override = values["_owe_scene_object_\(objectID)_json"],
                  let overrideData = override.data(using: .utf8),
                  let replacement = try? JSONSerialization.jsonObject(with: overrideData) as? [String: Any] else { continue }
            objects[index] = replacement
        }
        for index in objects.indices {
            let objectID = SceneObjects.objectID(objects[index], index: index)
            if let origin = values["_owe_scene_object_\(objectID)_origin"] {
                objects[index]["origin"] = origin
            }
            if let scale = values["_owe_scene_object_\(objectID)_scale"] {
                objects[index]["scale"] = scale
            }
        }
        root["objects"] = objects
        return try JSONSerialization.data(withJSONObject: root)
    }
}
