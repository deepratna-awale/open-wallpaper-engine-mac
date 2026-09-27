import Foundation
import XCTest
@testable import OpenWallpaperEngine

/// `Localizable.xcstrings`: every key is translated into every language the app ships, with the
/// plural forms each language needs and the same format arguments as the English.
final class LocalizationCatalogTests: XCTestCase {
    static let languages = ["de", "fr", "es", "pt-BR", "it", "ja", "ko", "zh-Hans", "zh-Hant",
                            "ru", "pl", "tr", "uk", "ar", "hi"]

    /// The CLDR cardinal categories a language's plural variations must spell out; a missing one
    /// would fall back to `other` and read wrong ("2 обоев").
    static let requiredPluralCategories: [String: Set<String>] = [
        "ja": ["other"], "ko": ["other"], "zh-Hans": ["other"], "zh-Hant": ["other"],
        "ru": ["one", "few", "many", "other"], "uk": ["one", "few", "many", "other"],
        "pl": ["one", "few", "many", "other"],
        "ar": ["zero", "one", "two", "few", "many", "other"],
    ]

    static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "OpenWallpaperEngine/Localizable.xcstrings")
    }

    private func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: Self.catalogURL)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    /// Every string unit of a localization: the plain one, plural variations, and substitutions.
    private func units(of localization: [String: Any]) -> [(path: String, state: String?, value: String)] {
        var found: [(String, String?, String)] = []
        func visit(_ node: [String: Any], path: String) {
            if let unit = node["stringUnit"] as? [String: Any] {
                found.append((path, unit["state"] as? String, unit["value"] as? String ?? ""))
            }
            if let variations = node["variations"] as? [String: [String: [String: Any]]] {
                for (kind, cases) in variations {
                    for (name, child) in cases { visit(child, path: "\(path)/\(kind).\(name)") }
                }
            }
            if let substitutions = node["substitutions"] as? [String: [String: Any]] {
                for (name, child) in substitutions { visit(child, path: "\(path)/%#@\(name)@") }
            }
        }
        visit(localization, path: "")
        return found
    }

    /// The plural categories a localization spells out, at the top level or in a substitution.
    private func pluralCategorySets(of localization: [String: Any]) -> [Set<String>] {
        var sets: [Set<String>] = []
        if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] {
            sets.append(Set(plural.keys))
        }
        for substitution in (localization["substitutions"] as? [String: [String: Any]])?.values ?? [:].values {
            if let plural = (substitution["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                sets.append(Set(plural.keys))
            }
        }
        return sets
    }

    private func isPlural(_ localization: [String: Any]?) -> Bool {
        guard let localization else { return false }
        return !pluralCategorySets(of: localization).isEmpty
    }

    func testEveryKeyIsTranslatedIntoEveryLanguage() throws {
        var problems: [String] = []
        for (key, entry) in try catalog() where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            let sourceIsPlural = isPlural(localizations["en"])
            for language in Self.languages {
                guard let localization = localizations[language] else {
                    problems.append("\(language): missing “\(key)”")
                    continue
                }
                let found = units(of: localization)
                if found.isEmpty { problems.append("\(language): no string for “\(key)”") }
                for unit in found where unit.state != "translated" || unit.value.isEmpty {
                    problems.append("\(language): “\(key)”\(unit.path) is \(unit.state ?? "without a state")")
                }
                if sourceIsPlural {
                    let required = Self.requiredPluralCategories[language] ?? ["one", "other"]
                    let sets = pluralCategorySets(of: localization)
                    if sets.isEmpty { problems.append("\(language): “\(key)” has no plural forms") }
                    for categories in sets where !required.isSubset(of: categories) {
                        problems.append("\(language): “\(key)” lacks \(required.subtracting(categories).sorted())")
                    }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "\(problems.count) gaps:\n" + problems.sorted().prefix(80).joined(separator: "\n"))
    }

    /// `%lld`, `%@`, `%1$@`… in a string, without their positions; `%%` is not an argument.
    static func formatArguments(_ string: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(ll|l|hh|h|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaA])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = string.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let length = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            let conversion = String(text[Range(match.range(at: 3), in: text)!])
            return length + conversion
        }.sorted()
    }

    /// The positions a string's arguments name (`%2$@` → 2), which must exist in the source.
    static func argumentPositions(_ string: String) -> [Int] {
        let regex = try! NSRegularExpression(pattern: #"%(\d+)\$"#)
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { match in
            Range(match.range(at: 1), in: string).flatMap { Int(string[$0]) }
        }
    }

    func testFormatArgumentsMatchTheSource() throws {
        var problems: [String] = []
        for (key, entry) in try catalog() where entry["shouldTranslate"] as? Bool != false {
            let expected = Self.formatArguments(key)
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                guard let localization = localizations[language] else { continue }
                let hasSubstitutions = localization["substitutions"] != nil
                for unit in units(of: localization) {
                    let found = Self.formatArguments(unit.value.replacingOccurrences(of: "%arg", with: "%lld"))
                    for position in Self.argumentPositions(unit.value) where position < 1 || position > expected.count {
                        problems.append("\(language): “\(key)”\(unit.path) names argument \(position)")
                    }
                    if hasSubstitutions {
                        // The count moves into the substitution; the rest must still be in the source.
                        if !Set(found).isSubset(of: Set(expected)) {
                            problems.append("\(language): “\(key)”\(unit.path) has \(found), source \(expected)")
                        }
                    } else if unit.path.contains("plural.") && !unit.path.hasSuffix("plural.other") {
                        // A form for one or two may spell the number out, but add nothing else.
                        var remaining = expected
                        for argument in found {
                            if let index = remaining.firstIndex(of: argument) {
                                remaining.remove(at: index)
                            } else {
                                problems.append("\(language): “\(key)”\(unit.path) adds \(argument)")
                            }
                        }
                    } else if found != expected {
                        problems.append("\(language): “\(key)”\(unit.path) has \(found), source \(expected)")
                    }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "\(problems.count) mismatches:\n" + problems.sorted().prefix(80).joined(separator: "\n"))
    }

    /// The built app carries every language, and plural lookups pick the language's form.
    func testTheAppResolvesTranslationsAndPlurals() {
        let bundled = Set(Bundle.main.localizations)
        for language in Self.languages {
            XCTAssertTrue(bundled.contains(language), "\(language) isn't in the app bundle")
        }
        func localized(_ value: String.LocalizationValue, _ identifier: String) -> String {
            String(localized: LocalizedStringResource(value, locale: Locale(identifier: identifier), bundle: .main))
        }
        XCTAssertNotEqual(localized("Cancel", "de"), "Cancel")
        XCTAssertEqual(localized("\(1) wallpapers", "en"), "1 wallpaper")
        XCTAssertEqual(localized("\(3) wallpapers", "en"), "3 wallpapers")
        // Russian needs a different noun form for 2 (few) and 5 (many).
        XCTAssertNotEqual(localized("Please wait \(2) seconds.", "ru"),
                          localized("Please wait \(5) seconds.", "ru").replacingOccurrences(of: "5", with: "2"))
        XCTAssertEqual(localized("Unsubscribe \(1) wallpapers: \("A")", "en"), "Unsubscribe 1 wallpaper: A")
    }
}
