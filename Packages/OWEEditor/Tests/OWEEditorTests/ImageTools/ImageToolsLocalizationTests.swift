import XCTest
@testable import OWEEditor

/// The image tools' own catalog (`ImageTools.xcstrings`): every `IL("…")` key is in it, translated
/// into every language the app ships, with the source's format arguments.
final class ImageToolsLocalizationTests: XCTestCase {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    func testEveryKeyUsedIsTranslated() throws {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/ImageTools.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let catalog = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z])IL\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        var used = Set<String>()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                var key = String(text[Range(match.range(at: 1), in: text)!])
                key = key.replacingOccurrences(of: #"\\\(number\)"#, with: "%lld", options: .regularExpression)
                key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression)
                used.insert(key)
            }
        }
        XCTAssertGreaterThan(used.count, 10)
        XCTAssertEqual(used.filter { catalog[$0] == nil }.sorted(), [], "not in ImageTools.xcstrings")
        let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|@)"#)
        func arguments(_ text: String) -> [String] {
            specifier.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }.sorted()
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
        XCTAssertEqual(IL("Normal Map"), "Normal Map")
    }
}
