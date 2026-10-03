import Foundation

/// A Workshop item of `"type": "preset"`: another wallpaper (its base) plus a set of property
/// values. project.json names the base in `dependency` (the base's Workshop id, which Steam
/// downloads beside it) and carries the values in `preset`, keyed by property name the way WE's
/// Share JSON is (`WallpaperEngineShareJSON`). An item that ships its own scene (`file` present
/// in its folder) is its own base.
///
/// WE lists such an item as a Preset and plays the base with the preset's values as that item's
/// defaults: the user's own edits to the item win, and resetting goes back to the preset's values.
/// OWE plays it from the base's folder (`WEWallpaper.wallpaperDirectory`) and keeps its settings
/// and preview under the preset's folder (`WEWallpaper.presetDirectory`).
enum WorkshopPresetItem {
    static let type = "preset"

    /// Whether project.json declares a preset item.
    static func isPreset(_ root: [String: Any]) -> Bool {
        (root["type"] as? String)?.caseInsensitiveCompare(type) == .orderedSame
    }

    /// The `preset` object as key → WE value. Both shapes are read: flat values (`{"name": 1}`, as
    /// Share JSON writes them) and property-like entries (`{"name": {"value": 1}}`).
    static func overrides(projectJSON root: [String: Any]) -> [String: Any] {
        guard let preset = root["preset"] as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for (key, value) in preset {
            if let entry = value as? [String: Any] {
                if let inner = entry["value"] { result[key] = inner }
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// The folder of the preset's base wallpaper, or nil when it isn't installed. `roots` are the
    /// folders that hold Workshop items by id (the library itself).
    static func baseDirectory(forPresetAt folder: URL, projectJSON root: [String: Any], roots: [URL]) -> URL? {
        if let file = root["file"] as? String, let clean = WEProject.sanitizedFile(file), !clean.isEmpty,
           hasScene(file: clean, in: folder) {
            return folder
        }
        let resolver = WorkshopAssetResolver(roots: roots)
        for id in WorkshopDependencyResolver.projectDependencies(inItemAt: folder).sorted() {
            guard id != folder.lastPathComponent, let base = resolver.itemDirectory(for: id),
                  let baseRoot = projectJSON(in: base), !isPreset(baseRoot) else { continue }
            return base
        }
        return nil
    }

    /// The listed wallpaper for the preset item in `folder`: its own title, preview, tags and id,
    /// played from its base. Without the base it stays in its own folder, typed as the scene WE
    /// would fall back to, so the missing-dependency flow offers the base's download.
    static func wallpaper(presetAt folder: URL, projectJSON root: [String: Any], roots: [URL]) -> WEWallpaper {
        var project = (try? JSONDecoder().decode(WEProject.self, from: JSONSerialization.data(withJSONObject: withFile(root))))
            ?? WEProject(file: "", title: root["title"] as? String ?? "", type: type)
        project.applyTaggedContentRating()
        let base = baseDirectory(forPresetAt: folder, projectJSON: root, roots: roots)
        if let base, let baseRoot = projectJSON(in: base),
           let baseProject = try? JSONDecoder().decode(WEProject.self, from: JSONSerialization.data(withJSONObject: baseRoot)) {
            project.type = baseProject.type
            project.file = baseProject.file
        } else {
            project.type = "scene"
            if project.file.isEmpty { project.file = "scene.json" }
        }
        var wallpaper = WEWallpaper(using: project, where: base ?? folder)
        wallpaper.presetDirectory = folder
        return wallpaper
    }

    /// The preset's values as OWE value strings, checked against the base's property definitions
    /// (`WallpaperEngineShareJSON.values`); empty for an ordinary wallpaper.
    static func defaultValues(for wallpaper: WEWallpaper) -> [String: String] {
        guard let presetDirectory = wallpaper.presetDirectory,
              let root = projectJSON(in: presetDirectory) else { return [:] }
        let overrides = overrides(projectJSON: root)
        guard !overrides.isEmpty else { return [:] }
        return WallpaperEngineShareJSON.values(from: overrides,
                                               definitions: WallpaperEngineShareJSON.definitions(in: wallpaper.wallpaperDirectory))
    }

    static func projectJSON(in folder: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder.appending(path: "project.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// WEProject requires `file`; a preset item may leave it out.
    private static func withFile(_ root: [String: Any]) -> [String: Any] {
        var root = root
        if !(root["file"] is String) { root["file"] = "" }
        return root
    }

    private static func hasScene(file: String, in folder: URL) -> Bool {
        let fm = FileManager.default
        let pkg = folder.appending(path: (file as NSString).deletingPathExtension + ".pkg")
        return fm.fileExists(atPath: folder.appending(path: file).path(percentEncoded: false))
            || fm.fileExists(atPath: pkg.path(percentEncoded: false))
    }
}
