import Foundation

/// One of WE's built-in particle presets (`assets/presets/<name>/preset.json`): rain, snow, fire,
/// fireworks, … each with variants that add one or more particle systems, and the files the
/// variant needs (its particle definitions and materials, in the preset's folder), which WE's
/// editor copies into the project when it adds the variant.
public struct ParticlePreset: Identifiable, Hashable, Sendable {
    public struct Variant: Identifiable, Hashable, Sendable {
        /// Its index in the preset's `variants`.
        public let id: Int
        public let title: String
        /// The scene objects it adds, each with its `particle`.
        public let objects: [SceneJSONValue]
        /// Files it needs, by their path in the preset's folder and in the project alike.
        public let dependencies: [String]
    }

    /// The preset's folder name (`rain`).
    public let id: String
    public let title: String
    /// Its description, in WE's words for the user's language; empty when it has none.
    public var summary: String = ""
    /// The scenes WE offers it in (`scene2d`, `scene3d`); empty when it doesn't say.
    public var tag: String = ""
    public let directory: URL
    public let variants: [Variant]

    /// Offered for 3D scenes (`scene3d`), whose units aren't pixels.
    public var is3D: Bool { tag.caseInsensitiveCompare("scene3d") == .orderedSame }

    public init(id: String, title: String, summary: String = "", tag: String = "", directory: URL, variants: [Variant]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.tag = tag
        self.directory = directory
        self.variants = variants
    }
}

public enum ParticlePresetCatalog {
    /// The particle presets under `presetsDirectory` (WE's `assets/presets`), sorted by title.
    /// `translate` reads WE's locale keys (`ui_editor_preset_rain_title`); a preset whose
    /// variants add anything but particle systems (text, light shafts) isn't one.
    public static func load(presetsDirectory: URL, translate: (String) -> String?) -> [ParticlePreset] {
        // No presets folder: no presets.
        let folders = (try? FileManager.default.contentsOfDirectory(at: presetsDirectory, includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { preset(in: $0, translate: translate) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The preset in `directory`; nil when it has no particle variant or its file can't be read.
    public static func preset(in directory: URL, translate: (String) -> String?) -> ParticlePreset? {
        // Optional: a folder without a readable preset file isn't a preset. WE's reader allows
        // trailing commas, which its `water` preset has.
        guard let data = try? Data(contentsOf: directory.appending(path: "preset.json")),
              let root = try? WETolerantJSON.object(from: data) as? [String: Any],
              let variants = root["variants"] as? [[String: Any]] else { return nil }
        let id = directory.lastPathComponent
        let nameKey = root["name"] as? String
        let title = nameKey.flatMap(translate) ?? id.replacingOccurrences(of: "_", with: " ").capitalized
        // The variant labels are the drop list's options, by value.
        var labels: [Int: String] = [:]
        let options = (root["options"] as? [String: Any])?["droplistOptions"] as? [[String: Any]] ?? []
        for option in options {
            guard let value = (option["value"] as? NSNumber)?.intValue, let label = option["label"] as? String else { continue }
            labels[value] = translate(label) ?? label
        }
        let particleVariants = variants.enumerated().compactMap { index, variant -> ParticlePreset.Variant? in
            let objects = (variant["objects"] as? [[String: Any]] ?? []).compactMap { SceneJSONValue(any: $0) }
            guard !objects.isEmpty, objects.allSatisfy({ $0["particle"]?.stringValue != nil }) else { return nil }
            let dependencies = (variant["dependencies"] as? [Any] ?? []).compactMap { $0 as? String }
            let fallback = variants.count == 1 ? title : "\(title) \(index + 1)"
            return ParticlePreset.Variant(id: index, title: labels[index] ?? fallback, objects: objects,
                                          dependencies: dependencies)
        }
        guard !particleVariants.isEmpty else { return nil }
        let summary = (root["description"] as? String).map { translate($0) ?? $0 } ?? ""
        return ParticlePreset(id: id, title: title, summary: summary, tag: root["tag"] as? String ?? "",
                              directory: directory, variants: particleVariants)
    }
}
