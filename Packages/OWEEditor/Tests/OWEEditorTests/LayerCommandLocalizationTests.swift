import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// The layer and effect commands' catalog (`Resources/LayerCommands.xcstrings`): every `LC("…")` key is in it,
/// translated into every language the app ships.
final class LayerCommandLocalizationTests: XCTestCase {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    func testEveryKeyIsInTheCatalogAndTranslated() throws {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/LayerCommands.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let catalog = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z])LC\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        var used = Set<String>()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                // Whole numbers are `number`, the catalog's %lld.
                used.insert(String(text[Range(match.range(at: 1), in: text)!]).replacingOccurrences(of: "\\(number)", with: "%lld"))
            }
        }
        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(used.subtracting(catalog.keys), [], "not in the catalog")
        XCTAssertEqual(Set(catalog.keys).subtracting(used), [], "in the catalog but unused")
        var problems: [String] = []
        for (key, entry) in catalog {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in EditorLocalizationTests.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                if (unit?["value"] as? String)?.isEmpty != false || unit?["state"] as? String != "translated" {
                    problems.append("\(language): “\(key)”")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
        XCTAssertEqual(LC("Rotate CW"), "Rotate CW")
    }
}
