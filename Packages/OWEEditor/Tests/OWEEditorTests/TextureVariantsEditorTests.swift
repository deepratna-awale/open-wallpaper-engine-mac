import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// The texture variants' inspector: its own catalog (`TextureVariants.xcstrings`) complete in
/// every language the app ships, and the property a new condition makes.
final class TextureVariantsEditorTests: XCTestCase {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    func testEveryKeyUsedIsTranslated() throws {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/TextureVariants.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let catalog = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z])TVL\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        var used = Set<String>()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                used.insert(key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression))
            }
        }
        XCTAssertGreaterThan(used.count, 20)
        XCTAssertEqual(used.filter { catalog[$0] == nil }.sorted(), [], "not in TextureVariants.xcstrings")
        let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|@)"#)
        func arguments(_ text: String) -> [String] {
            specifier.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
        }
        var problems: [String] = []
        for (key, entry) in catalog {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in EditorLocalizationTests.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String, !value.isEmpty, unit?["state"] as? String == "translated" else {
                    problems.append("\(language): \(key)")
                    continue
                }
                if arguments(value) != arguments(key) { problems.append("\(language): \(key) has \(arguments(value))") }
            }
        }
        XCTAssertEqual(problems.sorted(), [])
        XCTAssertEqual(TVL("Add Variant Group"), "Add Variant Group")
    }

    func testANewConditionMakesACheckboxOrAComboForTheGroup() {
        let hat = TextureVariantDocument.Option(name: "Hat", file: "a.png")
        let coat = TextureVariantDocument.Option(name: "Coat", file: "b.png", condition: .flag("other"))
        let scarf = TextureVariantDocument.Option(name: "Scarf", file: "c.png")
        let group = TextureVariantDocument.Group(name: "Clothes", options: [hat, coat, scarf])

        let checkbox = TextureVariantConditionSheet.newProperty(.bool, label: "Clothes", group: group, option: hat.id)
        XCTAssertEqual(checkbox.draft.kind, .bool)
        XCTAssertEqual(checkbox.conditions, [hat.id: .flag("Clothes")])

        let combo = TextureVariantConditionSheet.newProperty(.combo, label: "Clothes", group: group, option: coat.id)
        XCTAssertEqual(combo.draft.kind, .combo)
        XCTAssertEqual(combo.draft.options.map(\.value), ["0", "1", "2", "3"], "the base, then one value per option")
        XCTAssertEqual(combo.draft.options.dropFirst().map(\.label), ["Hat", "Coat", "Scarf"])
        XCTAssertEqual(combo.draft.value, .string("0"), "the base shows by default")
        // The option asked for, and the group's options without a condition.
        XCTAssertEqual(combo.conditions, [hat.id: .equals("Clothes", "1"), coat.id: .equals("Clothes", "2"),
                                          scarf.id: .equals("Clothes", "3")])
        XCTAssertEqual(TextureVariantDocument.Condition.equals("Clothes", "2").rekeyed("clothes"), .equals("clothes", "2"))
    }

    func testOptionFilesNameTheirTextures() {
        XCTAssertEqual(TextureVariantsSection.textureName(of: "materials/editor/variants/hat-1.png"), "editor/variants/hat-1")
    }
}
