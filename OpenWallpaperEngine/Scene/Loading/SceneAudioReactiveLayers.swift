import Foundation

/// The layers that follow the system audio, by what the wallpaper's files say:
///
/// - an image, model or particle layer whose material shader, or one of its effects' pass
///   shaders, reads `g_AudioSpectrum*`. A shader that declares an `audioprocessingoptions` combo
///   (WE's "Audio response" switch, e.g. the Pulse and Shake effects) reads it only while that
///   combo is on: the layer's pass `combos`, else the material's, else the annotation's default;
/// - a particle system with an audio response: an emitter, initializer or operator whose
///   `audioprocessingmode` isn't 0, in the system or one of its children;
/// - a layer whose scripts use the SceneScript audio API (`engine.registerAudioBuffers`).
///
/// A recorded loop (the screen saver's) plays a moment of a synthetic spectrum over and over, so
/// the automatic screen saver recording leaves these layers out (`ScreenSaverLiveLayers`), as it
/// does the clock layers (`SceneClockLayers`). Only files are read: nothing is translated or built.
enum SceneAudioReactiveLayers {
    /// A file of the wallpaper by its WE path (`materials/…`, `shaders/…`): its package, its
    /// folder, a Workshop item it references, then WE's assets. Nil when there is none.
    typealias Read = (String) -> Data?

    /// The ids (`SceneObjectIdentity`: the authored `id`, else the index) of the scene's audio-reactive layers.
    static func ids(inScene sceneData: Data, read: @escaping Read) -> Set<Int> {
        guard let root = object(sceneData), let objects = root["objects"] as? [Any] else { return [] }
        var scan = Scan(read: read)
        var ids: Set<Int> = []
        for case let (index, object as [String: Any]) in objects.enumerated() {
            let id = (object["id"] as? NSNumber)?.intValue ?? index
            if scan.readsAudio(object) { ids.insert(id) }
        }
        return ids
    }

    /// Whether a script's source uses the SceneScript audio API.
    static func scriptReadsAudio(_ source: String) -> Bool {
        source.contains("registerAudioBuffers")
    }

    /// Whether a shader stage's source reads the spectrum with `combos` set (upper-cased names).
    static func shaderReadsAudio(_ source: String, combos: [String: Int]) -> Bool {
        guard source.contains("g_AudioSpectrum") else { return false }
        let switches = SceneEffectParameters.combos(in: source)
            .filter { $0.type?.caseInsensitiveCompare("audioprocessingoptions") == .orderedSame }
        guard !switches.isEmpty else { return true }
        return switches.contains { (combos[$0.combo] ?? $0.defaultValue) != 0 }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        // A file that isn't a JSON object reads nothing; the scene's own load logs it.
        (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any]
    }

    /// One scene's scan, reading each file once.
    private struct Scan {
        let read: Read
        private var documents: [String: [String: Any]?] = [:]
        private var sources: [String: String?] = [:]

        init(read: @escaping Read) {
            self.read = read
        }

        mutating func readsAudio(_ object: [String: Any]) -> Bool {
            if Self.scripts(in: object).contains(where: SceneAudioReactiveLayers.scriptReadsAudio) { return true }
            for key in ["image", "model"] {
                if let path = object[key] as? String, modelReadsAudio(path) { return true }
            }
            if let path = object["particle"] as? String {
                var visited: Set<String> = []
                if particleReadsAudio(path, visited: &visited) { return true }
            }
            for case let effect as [String: Any] in object["effects"] as? [Any] ?? [] where effectIsOn(effect) {
                if let file = effect["file"] as? String, effectReadsAudio(file, instance: effect) { return true }
            }
            return false
        }

        /// Every inline `script` in the object, its effects' and properties' alike.
        private static func scripts(in value: Any) -> [String] {
            switch value {
            case let object as [String: Any]:
                var found: [String] = []
                for (key, child) in object {
                    if key == "script", let source = child as? String { found.append(source) } else { found += scripts(in: child) }
                }
                return found
            case let array as [Any]:
                return array.flatMap { scripts(in: $0) }
            default:
                return []
            }
        }

        /// An effect switched off as authored (`"visible": false`) draws nothing.
        private func effectIsOn(_ effect: [String: Any]) -> Bool {
            switch effect["visible"] {
            case let visible as Bool: return visible
            case let bound as [String: Any]: return (bound["value"] as? Bool) ?? true
            default: return true
            }
        }

        private mutating func modelReadsAudio(_ path: String) -> Bool {
            guard let model = document(path), let material = model["material"] as? String else { return false }
            return materialReadsAudio(material, directory: "", instanceCombos: [:])
        }

        private mutating func effectReadsAudio(_ file: String, instance: [String: Any]) -> Bool {
            guard let effect = document(file) else { return false }
            // A Workshop effect keeps its files under its own folder (`SceneEffectPlanBuilder.readWallpaperFile`).
            let directory = (file as NSString).deletingLastPathComponent
            let instancePasses = instance["passes"] as? [Any] ?? []
            for case let (index, pass as [String: Any]) in (effect["passes"] as? [Any] ?? []).enumerated() {
                guard let material = pass["material"] as? String else { continue }
                let instancePass = index < instancePasses.count ? instancePasses[index] as? [String: Any] : nil
                if materialReadsAudio(material, directory: directory, instanceCombos: Self.combos(instancePass?["combos"])) {
                    return true
                }
            }
            return false
        }

        private mutating func materialReadsAudio(_ path: String, directory: String, instanceCombos: [String: Int]) -> Bool {
            guard let material = scopedDocument(path, directory: directory),
                  let pass = (material["passes"] as? [Any])?.first as? [String: Any],
                  let shader = pass["shader"] as? String else { return false }
            let combos = Self.combos(pass["combos"]).merging(instanceCombos) { $1 }
            return ["vert", "frag"].contains { stage in
                guard let source = scopedSource("shaders/\(shader).\(stage)", directory: directory) else { return false }
                return SceneAudioReactiveLayers.shaderReadsAudio(source, combos: combos)
            }
        }

        private mutating func particleReadsAudio(_ path: String, visited: inout Set<String>) -> Bool {
            guard visited.insert(path).inserted, let system = document(path) else { return false }
            for key in ["emitter", "initializer", "operator"] {
                for case let element as [String: Any] in system[key] as? [Any] ?? [] {
                    if let mode = Self.number(element["audioprocessingmode"]), mode != 0 { return true }
                }
            }
            if let material = system["material"] as? String,
               materialReadsAudio(material, directory: "", instanceCombos: [:]) { return true }
            for case let child as [String: Any] in system["children"] as? [Any] ?? [] {
                if let name = child["name"] as? String, particleReadsAudio(name, visited: &visited) { return true }
            }
            return false
        }

        /// `combos` as upper-cased names and their values (a bound value's `value`).
        private static func combos(_ raw: Any?) -> [String: Int] {
            var result: [String: Int] = [:]
            for (name, value) in raw as? [String: Any] ?? [:] {
                if let number = number(value) { result[name.uppercased()] = number }
            }
            return result
        }

        /// A number, a numeric string, or a user-bound value's `value`.
        private static func number(_ raw: Any?) -> Int? {
            switch raw {
            case let number as NSNumber: return number.intValue
            case let text as String: return Int(text) ?? Double(text).map { Int($0) }
            case let bound as [String: Any]: return number(bound["value"])
            default: return nil
            }
        }

        private mutating func scopedDocument(_ path: String, directory: String) -> [String: Any]? {
            if !directory.isEmpty, let own = document("\(directory)/\(path)") { return own }
            return document(path)
        }

        private mutating func scopedSource(_ path: String, directory: String) -> String? {
            if !directory.isEmpty, let own = source("\(directory)/\(path)") { return own }
            return source(path)
        }

        private mutating func document(_ path: String) -> [String: Any]? {
            if let known = documents[path] { return known }
            let parsed = read(path).flatMap(SceneAudioReactiveLayers.object)
            documents[path] = parsed
            return parsed
        }

        private mutating func source(_ path: String) -> String? {
            if let known = sources[path] { return known }
            let text = read(path).map { String(decoding: $0, as: UTF8.self) }
            sources[path] = text
            return text
        }
    }
}
