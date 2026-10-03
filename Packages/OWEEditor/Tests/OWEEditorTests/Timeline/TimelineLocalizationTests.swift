import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// The timeline's catalog (`Resources/Timeline.xcstrings`): every `T("…")` the module uses is a
/// key of it, and every key is translated into every language the app ships with the source's
/// format arguments.
final class TimelineLocalizationTests: XCTestCase {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    private func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/Timeline.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    /// `T("…")` keys in every source of the module, interpolations as the catalog's specifiers.
    private func usedKeys() throws -> Set<String> {
        var keys = Set<String>()
        let regex = try NSRegularExpression(pattern: #"\bT\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                var key = String(text[Range(match.range(at: 1), in: text)!])
                key = key.replacingOccurrences(of: #"\\\(number\)"#, with: "%lld", options: .regularExpression)
                key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression)
                keys.insert(key)
            }
        }
        return keys
    }

    func testEveryKeyUsedIsInTheCatalogAndEveryKeyIsUsed() throws {
        let catalog = try catalog()
        let used = try usedKeys()
        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(used.subtracting(catalog.keys).sorted(), [], "not in the catalog")
        XCTAssertEqual(Set(catalog.keys).subtracting(used).sorted(), [], "in the catalog but unused")
    }

    func testEveryKeyIsTranslatedIntoEveryLanguage() throws {
        var problems: [String] = []
        let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|@)"#)
        func arguments(_ text: String) -> [String] {
            specifier.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { String(text[Range($0.range, in: text)!]) }.sorted()
        }
        for (key, entry) in try catalog() {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in EditorLocalizationTests.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String, !value.isEmpty, unit?["state"] as? String == "translated" else {
                    problems.append("\(language): “\(key)”")
                    continue
                }
                if arguments(value) != arguments(key) { problems.append("\(language): “\(key)” has \(arguments(value))") }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }

    func testEnglishTextResolvesFromItsTable() {
        XCTAssertEqual(T("Timeline"), "Timeline")
        XCTAssertEqual(T("Frame \(96)"), "Frame 96")
        XCTAssertEqual(TimelineEase.easeInOut.title, "Ease In and Out")
        XCTAssertEqual(TimelineNames.field("angles"), "Rotation")
        XCTAssertEqual(TimelineNames.time(83.25), "1:23.25")
    }

    func testTheScaleMapsTimeAcrossTheWidth() {
        let scale = TimelineScale(duration: 4, width: 424)
        XCTAssertEqual(scale.x(0), TimelineScale.inset)
        XCTAssertEqual(scale.x(4), 424 - TimelineScale.inset)
        XCTAssertEqual(scale.seconds(scale.x(1.5)), 1.5, accuracy: 1e-9)
        XCTAssertEqual(scale.pointsPerFrame(fps: 25), 4, accuracy: 1e-9)
        XCTAssertEqual(scale.tickStep(), 1, "the shortest step at least 64 points apart")
    }
}
