import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// The View menu (Wallpaper Engine's editor View menu and its canvas toolbar's view buttons): its
/// entries, the options it switches and where they are kept, and the previews' framing.
@MainActor
final class EditorViewOptionsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "EditorViewOptionsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) } // Cleanup: the test's own suite.
        return defaults
    }

    func testTheMenuIsWEsViewMenu() {
        let titles = EditorViewCommand.menu.map { entry -> String in
            switch entry {
            case .command(let command): return command.title
            case .submenu(let title, let entries): return "\(title) (\(entries.count))"
            case .separator: return "—"
            }
        }
        XCTAssertEqual(titles, ["Reset Camera", "Preview Aspect Ratio (4)", "—", "Show Grid", "Show Selection Box", "Show Debug (2)",
                                "—", "Show Desktop Preview", "Show Phone Preview", "Low FPS Simulation"])
        XCTAssertEqual(EditorViewOptions.PreviewRatio.allCases.map(\.title), ["4 : 3", "16 : 10", "16 : 9", "21 : 9"])
        XCTAssertEqual(EditorViewOptions.lowFrameRate, 22)
    }

    func testTheSettingsAreKeptAndThePreviewsAreNot() throws {
        let store = try defaults()
        let options = EditorViewOptions(defaults: store)
        XCTAssertFalse(options.showsGrid)
        XCTAssertTrue(options.showsSelectionBox)
        XCTAssertEqual(options.previewRatio, .sixteenNine)
        options.showsGrid = true
        options.showsSelectionBox = false
        options.previewRatio = .twentyOneNine
        options.simulatesLowFrameRate = true
        options.toggle(.desktop)
        let again = EditorViewOptions(defaults: store)
        XCTAssertTrue(again.showsGrid)
        XCTAssertFalse(again.showsSelectionBox)
        XCTAssertEqual(again.previewRatio, .twentyOneNine)
        XCTAssertTrue(again.simulatesLowFrameRate)
        XCTAssertNil(again.preview, "a preview lasts while its window is open")
    }

    func testOnePreviewAtATimeFramedAsAScreenFillsIt() throws {
        let options = EditorViewOptions()
        options.toggle(.desktop)
        XCTAssertEqual(options.previewAspect ?? 0, 16.0 / 9.0, accuracy: 1e-12)
        options.toggle(.phone)
        XCTAssertEqual(options.preview, .phone)
        XCTAssertEqual(options.previewAspect ?? 0, 9.0 / 16.0, accuracy: 1e-12)
        options.toggle(.phone)
        XCTAssertNil(options.preview)
        let phone = EditorViewOptions.visibleRect(sceneSize: SIMD2(1920, 1080), aspect: 9.0 / 16.0)
        XCTAssertEqual(phone.minimum.y, 0)
        XCTAssertEqual(phone.maximum.y, 1080)
        XCTAssertEqual(phone.maximum.x - phone.minimum.x, 607.5, accuracy: 1e-9)
        XCTAssertEqual(phone.minimum.x, (1920 - 607.5) / 2, accuracy: 1e-9)
        let wide = EditorViewOptions.visibleRect(sceneSize: SIMD2(1920, 1080), aspect: 21.0 / 9.0)
        XCTAssertEqual(wide.maximum.x - wide.minimum.x, 1920)
        XCTAssertEqual(wide.maximum.y - wide.minimum.y, 1920 * 9 / 21, accuracy: 1e-9)
    }

    func testTheGridKeepsItsLinesApart() {
        XCTAssertEqual(EditorViewOptions.gridSpacing(pointsPerUnit: 4), 10)
        XCTAssertEqual(EditorViewOptions.gridSpacing(pointsPerUnit: 0.5), 50)
        XCTAssertEqual(EditorViewOptions.gridSpacing(pointsPerUnit: 0.001), 1000)
    }

    func testTheMenuReadsTheWindowsOptions() {
        let commands = WallpaperEditorCommands()
        XCTAssertFalse(commands.isEnabled(.showGrid), "no window yet")
        let options = EditorViewOptions()
        commands.viewOptions = options
        options.showsGrid = true
        options.previewRatio = .fourThree
        XCTAssertTrue(commands.isOn(.showGrid))
        XCTAssertTrue(commands.isOn(.previewRatio(.fourThree)))
        XCTAssertFalse(commands.isOn(.previewRatio(.sixteenNine)))
        XCTAssertFalse(commands.isEnabled(.showParticleCollision), "no particle editor")
        commands.hasParticles = true
        XCTAssertTrue(commands.isEnabled(.showParticleCollision))
    }

    func testTheCatalogHasEveryKeyTranslated() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/OWEEditor")
        let data = try Data(contentsOf: sources.appending(path: "Resources/CanvasView.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let catalog = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z])CV\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        var used = Set<String>()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
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
    }
}
