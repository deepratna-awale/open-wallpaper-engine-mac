import Foundation

/// WE's own UI strings (`locale/ui_<language>.json`), which translate the localisation keys
/// wallpapers and shaders use as labels (`ui_editor_properties_speed` → "Speed"). The bundled
/// assets carry WE's files in `we-assets/locale`; a WE install keeps them in `<install>/locale`,
/// beside `<install>/assets`.
struct WallpaperEngineLabels {
    private let strings: [String: String]

    init(strings: [String: String] = [:]) {
        self.strings = strings
    }

    /// English, overlaid by the first of `languages` WE ships a file for. WE's translations are
    /// partial (Lithuanian has 320 of English's 3332 keys), so a key a language lacks reads in English.
    static func load(assets: URL? = WallpaperEngineAssets.directory,
                     languages: [String] = Locale.preferredLanguages) -> WallpaperEngineLabels {
        guard let assets, let directory = localeDirectory(assets: assets) else { return WallpaperEngineLabels() }
        var strings = table(directory.appending(path: "ui_en-us.json"))
        let available = availableLanguages(in: directory)
        if let language = languages.lazy.compactMap({ weLanguage(for: $0, available: available) }).first,
           language != "en-us" {
            strings.merge(table(directory.appending(path: "ui_\(language).json"))) { _, translated in translated }
        }
        return WallpaperEngineLabels(strings: strings)
    }

    /// WE's text for a localisation key, matched case-insensitively as keys are authored with
    /// mixed case; nil for plain text and unknown keys.
    func translation(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if let exact = strings[trimmed] { return exact }
        return strings[trimmed.lowercased()]
    }

    /// WE's code (the suffix of `ui_<code>.json`: `de-de`, `pt-br`, `zh-chs`) for a BCP 47
    /// language identifier, among `available`: the language and region, else the language's first
    /// file. Chinese goes by script, as WE's files do (Traditional also for Taiwan, Hong Kong and Macau).
    static func weLanguage(for identifier: String, available: [String]) -> String? {
        let language = Locale.Language(identifier: identifier)
        guard let code = language.languageCode?.identifier.lowercased() else { return nil }
        let region = language.region?.identifier.lowercased()
        let candidate: String
        if code == "zh" {
            let traditional = language.script?.identifier == "Hant" || ["tw", "hk", "mo"].contains(region ?? "")
            candidate = traditional ? "zh-cht" : "zh-chs"
        } else if let region {
            candidate = "\(code)-\(region)"
        } else {
            candidate = ""
        }
        if available.contains(candidate) { return candidate }
        return available.sorted().first { $0.hasPrefix("\(code)-") }
    }

    /// `<assets>/locale` (the bundled tree) or `<assets>/../locale` (an install).
    private static func localeDirectory(assets: URL) -> URL? {
        [assets.appending(path: "locale"), assets.deletingLastPathComponent().appending(path: "locale")]
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "ui_en-us.json").path) }
    }

    private static func availableLanguages(in directory: URL) -> [String] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            OWELog.error(.scene, "WallpaperEngineLabels: cannot list \(directory.path): \(error)")
            return []
        }
        return names.compactMap { name in
            guard name.hasPrefix("ui_"), name.hasSuffix(".json") else { return nil }
            return String(name.dropFirst(3).dropLast(5))
        }
    }

    private static func table(_ file: URL) -> [String: String] {
        do {
            let data = try Data(contentsOf: file)
            let object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
            guard let entries = object as? [String: Any] else {
                OWELog.error(.scene, "WallpaperEngineLabels: \(file.path) isn't an object")
                return [:]
            }
            return entries.compactMapValues { $0 as? String }
        } catch {
            OWELog.error(.scene, "WallpaperEngineLabels: cannot read \(file.path): \(error)")
            return [:]
        }
    }
}
