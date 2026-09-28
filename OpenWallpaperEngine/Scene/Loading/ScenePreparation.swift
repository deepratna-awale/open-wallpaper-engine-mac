import Foundation

/// Prepares a scene wallpaper ahead of drawing and stores the result as one scene cache file
/// (`SceneCacheFile`), so the next load reads it instead of redoing the work.
///
/// Every stage runs as its own `PreparationPool` job (never on the main or render thread), so a
/// preparation can be cancelled between stages and yields to higher priority work:
/// parse → textures → shader variants → pipelines → analysis → write. Stages whose content later
/// work packages add leave their section empty until then.
enum ScenePreparation {
    /// What a preparation reads, and so what its cache key covers.
    struct Request: Sendable {
        /// The cache folder's name: the Workshop id, or the local folder's id.
        var wallpaperID: String
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

        var key: SceneCacheKey {
            SceneCacheKey(sources: SceneCacheKey.sources(of: directory), edits: edits,
                          userProperties: userProperties, displays: displays, settings: settings)
        }

        var packageURL: URL {
            directory.appending(path: (sceneFile as NSString).deletingPathExtension + ".pkg")
        }
    }

    enum Failure: Error, Equatable { case noScene }

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

    /// The scene document with the saved per-object edits applied (replaced objects, origin and
    /// scale); `data` itself when it isn't an object with an `objects` array.
    static func resolvedScene(_ data: Data, edits values: [String: String]) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var objects = root["objects"] as? [[String: Any]] else { return data }
        for index in objects.indices {
            let objectID = (objects[index]["id"] as? NSNumber)?.intValue ?? index
            guard let override = values["_owe_scene_object_\(objectID)_json"],
                  let overrideData = override.data(using: .utf8),
                  let replacement = try? JSONSerialization.jsonObject(with: overrideData) as? [String: Any] else { continue }
            objects[index] = replacement
        }
        for index in objects.indices {
            let objectID = (objects[index]["id"] as? NSNumber)?.intValue ?? index
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

    /// The parse stage: the scene file from the package (or loose), with the edits applied.
    static func parse(_ request: Request) throws -> Data {
        ThreadGuards.assertBackground("scene parse")
        let package = request.packageURL
        let data: Data?
        if FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) {
            data = try PKGParser(url: package).extractFile(named: request.sceneFile)
        } else {
            data = try Data(contentsOf: request.directory.appending(path: request.sceneFile))
        }
        guard let data else { throw Failure.noScene }
        return try resolvedScene(data, edits: request.edits)
    }

    /// Prepares `request` and writes its cache file. `scenePlan` skips the parse stage when the
    /// caller already has the resolved scene (a load that just parsed it).
    @discardableResult
    static func prepare(_ request: Request, priority: PreparationPool.Priority,
                        store: SceneCacheStore, pool: PreparationPool = .shared,
                        scenePlan: Data? = nil) async throws -> SceneCacheFile {
        let key = try await pool.run(priority: priority) { _ in request.key }
        let plan: Data
        if let scenePlan {
            plan = scenePlan
        } else {
            plan = try await pool.run(priority: priority, estimatedBytes: 64 << 20) { _ in try parse(request) }
        }
        var file = SceneCacheFile(key: key.digest, sections: [.scenePlan: plan])
        // Textures, shader variants, pipelines and analysis seeds join here as their stages land.
        file.sections = file.sections.filter { !$0.value.isEmpty }
        let finished = file
        try await pool.run(priority: priority, estimatedBytes: plan.count) { _ in
            try store.write(finished, wallpaper: request.wallpaperID, key: key)
        }
        return finished
    }

    /// Fire-and-forget form of `prepare`, for a load that missed the cache.
    @discardableResult
    static func schedule(_ request: Request, priority: PreparationPool.Priority, store: SceneCacheStore,
                         pool: PreparationPool = .shared, scenePlan: Data? = nil) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            do {
                try await prepare(request, priority: priority, store: store, pool: pool, scenePlan: scenePlan)
            } catch is CancellationError {
            } catch {
                OWELog.info(.scene, "Scene preparation for \(request.wallpaperID) failed: \(error)")
            }
        }
    }
}
