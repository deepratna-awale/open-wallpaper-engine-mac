import XCTest
@testable import OpenWallpaperEngine

/// A Workshop `preset` item (5000000005) over a tiny base scene (5000000006) it names in
/// `dependency`: listed as a Preset, played from the base with the preset's values as defaults.
final class WorkshopPresetItemTests: XCTestCase {
    private var library: URL!

    override func setUpWithError() throws {
        library = FileManager.default.temporaryDirectory.appending(path: "WorkshopPresetItemTests-\(UUID().uuidString)")
        try write(folder: "5000000006", project: [
            "title": "Base", "type": "scene", "file": "scene.json", "preview": "preview.jpg", "workshopid": "5000000006",
            "general": ["properties": [
                "speed": ["type": "slider", "text": "Speed", "value": 1, "min": 0, "max": 10],
                "glow": ["type": "bool", "text": "Glow", "value": false],
                "tint": ["type": "color", "text": "Tint", "value": "1 1 1"],
            ]],
        ], scene: true)
        try write(folder: "5000000005", project: [
            "title": "Red Preset", "type": "preset", "preview": "preview.jpg", "workshopid": "5000000005",
            "dependency": "5000000006",
            "preset": ["speed": 4, "glow": true, "unknown": 3],
        ])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: library)
    }

    private func write(folder: String, project: [String: Any], scene: Bool = false) throws {
        let directory = library.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: project).write(to: directory.appending(path: "project.json"))
        if scene {
            try Data(#"{"camera":{},"general":{"orthogonalprojection":{"width":100,"height":100}},"objects":[]}"#.utf8).write(to: directory.appending(path: "scene.json"))
        }
    }

    private func listed() -> [WEWallpaper] { InstalledLibrary.wallpapers(in: library, hiding: []) }

    func testPresetIsListedAndPlaysFromItsBase() throws {
        let preset = try XCTUnwrap(listed().first { $0.isWorkshopPreset })
        XCTAssertEqual(preset.presetDirectory?.lastPathComponent, "5000000005")
        XCTAssertEqual(preset.wallpaperDirectory.lastPathComponent, "5000000006")
        XCTAssertEqual(preset.project.type, "scene")
        XCTAssertEqual(preset.project.file, "scene.json")
        XCTAssertEqual(preset.project.title, "Red Preset")
        XCTAssertEqual(preset.displayType, "preset")
        XCTAssertEqual(preset.previewURL?.deletingLastPathComponent().lastPathComponent, "5000000005")
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(preset).rawValue, "workshop-5000000005")
    }

    func testPresetValuesAreTheItemsDefaults() throws {
        let preset = try XCTUnwrap(listed().first { $0.isWorkshopPreset })
        let defaults = WorkshopPresetItem.defaultValues(for: preset)
        XCTAssertEqual(defaults, ["speed": "4", "glow": "true"])
        // The user's edit wins over the preset; untouched properties start from the preset, then the base.
        var stored = ["speed": "7"]
        stored.merge(defaults) { user, _ in user }
        let declared = (WorkshopPresetItem.projectJSON(in: preset.wallpaperDirectory)?["general"] as? [String: Any])?["properties"]
            as? [String: [String: Any]] ?? [:]
        let scene = try JSONDecoder().decode(WEScene.self, from: Data(#"{"camera":{},"general":{"orthogonalprojection":{"width":100,"height":100}},"objects":[]}"#.utf8))
        let values = SceneWallpaperViewModel.userPropertyValues(stored: stored, declared: declared, scene: scene)
        XCTAssertEqual(values["speed"], "7")
        XCTAssertEqual(values["glow"], "true")
        XCTAssertEqual(values["tint"], "1 1 1")
    }

    func testOverridesReadBothShapes() {
        let flat = WorkshopPresetItem.overrides(projectJSON: ["preset": ["a": 1]])
        let nested = WorkshopPresetItem.overrides(projectJSON: ["preset": ["a": ["value": 1]]])
        XCTAssertEqual(flat["a"] as? Int, 1)
        XCTAssertEqual(nested["a"] as? Int, 1)
    }

    func testMissingBaseStaysInItsFolderAndReportsTheDependency() throws {
        try FileManager.default.removeItem(at: library.appending(path: "5000000006"))
        let preset = try XCTUnwrap(listed().first { $0.isWorkshopPreset })
        XCTAssertEqual(preset.wallpaperDirectory, preset.presetDirectory)
        XCTAssertTrue(WorkshopDependencyResolver.projectDependencies(inItemAt: preset.wallpaperDirectory).contains("5000000006"))
        XCTAssertEqual(WorkshopPresetItem.defaultValues(for: preset), [:])
    }

    func testOrdinaryWallpaperHasNoPresetDefaults() throws {
        let base = try XCTUnwrap(listed().first { !$0.isWorkshopPreset })
        XCTAssertEqual(base.displayType, "scene")
        XCTAssertEqual(WorkshopPresetItem.defaultValues(for: base), [:])
    }

    func testPresetTypeIsFilterable() {
        XCTAssertTrue(FRType.all.contains(.preset))
        XCTAssertEqual(FRType.allOptions.last, "Preset")
    }

    func testPresetSurvivesPersistence() throws {
        let preset = try XCTUnwrap(listed().first { $0.isWorkshopPreset })
        let restored = try XCTUnwrap(WEWallpaper(rawValue: preset.rawValue))
        XCTAssertEqual(restored.presetDirectory, preset.presetDirectory)
    }
}
