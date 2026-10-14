import CoreGraphics
import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// Take Snapshot and Record GIF: what the renderer is asked to draw, Use and Discard, and the
/// thumbnail's catalog (`Resources/Thumbnail.xcstrings`).
@MainActor
final class ThumbnailTests: XCTestCase {
    private static func canvas(_ size: SIMD2<Int>) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.x, height: size.y, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.x, height: size.y))
        return context.makeImage()
    }

    func testTakeSnapshotDrawsTheSceneAtItsAspectAndWaitsForUse() async throws {
        var asked: [SIMD2<Int>] = []
        let thumbnail = EditorThumbnail(sceneSize: SIMD2(1920, 1080), savesInPlace: false) { size in
            asked.append(size)
            return Self.canvas(size)
        }
        var changes = 0
        thumbnail.onChosenChange = { changes += 1 }
        await thumbnail.takeSnapshot()
        XCTAssertEqual(asked, [SIMD2<Int>(1820, 1024)])
        let pending = try XCTUnwrap(thumbnail.pending)
        XCTAssertEqual(pending.kind, .image)
        XCTAssertEqual(pending.side, 1024)
        XCTAssertNil(thumbnail.chosen, "nothing is used before Use")
        thumbnail.use()
        XCTAssertEqual(thumbnail.chosen, pending)
        XCTAssertNil(thumbnail.pending)
        XCTAssertEqual(changes, 1)
        thumbnail.keepOriginal()
        XCTAssertNil(thumbnail.chosen)
        XCTAssertEqual(changes, 2)
    }

    func testRecordGIFDrawsTheFormatsFramesAtItsRate() async throws {
        var asked = 0
        var waits: [Double] = []
        let thumbnail = EditorThumbnail(sceneSize: SIMD2(1920, 1080), savesInPlace: true,
                                        frame: { size in asked += 1; return Self.canvas(size) },
                                        sleep: { waits.append($0) })
        thumbnail.gifFormat = GIFRecordingFormat.all[1]
        await thumbnail.recordGIF()
        XCTAssertEqual(asked, 48, "12 FPS for 4 seconds")
        // The fake sleep doesn't pass time, so each wait reaches the next frame's time from the start.
        XCTAssertEqual(waits.count, 48)
        XCTAssertEqual(waits.last ?? 0, 4, accuracy: 0.5, "the last frame is due at the format's length")
        let pending = try XCTUnwrap(thumbnail.pending)
        XCTAssertEqual(pending.kind, .gif)
        XCTAssertEqual(pending.fileName, "preview.gif")
        XCTAssertEqual(pending.side, 256)
        thumbnail.discard()
        XCTAssertNil(thumbnail.pending)
        XCTAssertNil(thumbnail.chosen)
        XCTAssertEqual(thumbnail.phase, .idle)
    }

    func testACanvasWithNothingToDrawReportsAProblem() async {
        let thumbnail = EditorThumbnail(sceneSize: SIMD2(1920, 1080), savesInPlace: false) { _ in nil }
        await thumbnail.takeSnapshot()
        XCTAssertNil(thumbnail.pending)
        XCTAssertEqual(thumbnail.problem, "The thumbnail couldn’t be made.")
    }

    func testFormatsReadAsWallpaperEngineListsThem() {
        XCTAssertEqual(GIFRecordingFormat.all[0].title, "256×256, 25 FPS, 2 seconds, dithering enabled")
        XCTAssertEqual(GIFRecordingFormat.all[5].title, "128×128, 25 FPS, 8 seconds, dithering disabled")
    }

    // MARK: Catalog

    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    func testEveryKeyUsedIsInTheCatalogTranslatedIntoEveryLanguage() throws {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/Thumbnail.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let catalog = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        var used = Set<String>()
        let regex = try NSRegularExpression(pattern: #"\bTH\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                used.insert(key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression))
            }
        }
        XCTAssertEqual(used.subtracting(catalog.keys).sorted(), [], "not in the catalog")
        XCTAssertEqual(Set(catalog.keys).subtracting(used).sorted(), [], "in the catalog but unused")
        var problems: [String] = []
        for (key, entry) in catalog {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in EditorLocalizationTests.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String, !value.isEmpty, unit?["state"] as? String == "translated" else {
                    problems.append("\(language): “\(key)”")
                    continue
                }
                if value.components(separatedBy: "%@").count != key.components(separatedBy: "%@").count {
                    problems.append("\(language): “\(key)” has other arguments")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }
}
