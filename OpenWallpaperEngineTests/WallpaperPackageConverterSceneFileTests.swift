import XCTest
@testable import OpenWallpaperEngine

/// The scene file the converter unpacks is the one project.json names; a Workshop preset item
/// names none.
final class WallpaperPackageConverterSceneFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "owe-scene-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func project(_ json: String) throws {
        try Data(json.utf8).write(to: folder.appending(path: "project.json"))
    }

    func testASceneNamesItsFile() throws {
        try project(#"{"file": "scene.json", "type": "scene", "title": "A"}"#)
        XCTAssertEqual(WallpaperPackageConverter.primarySceneFile(in: folder), "scene.json")
    }

    func testAPresetItemHasNoSceneFile() throws {
        try project(#"{"dependency": "3122339805", "preset": {"alignment": 0}, "title": "Preset"}"#)
        XCTAssertNil(WallpaperPackageConverter.primarySceneFile(in: folder))
    }

    func testAVideoIsNotAScene() throws {
        try project(#"{"file": "clip.mp4", "type": "video"}"#)
        XCTAssertNil(WallpaperPackageConverter.primarySceneFile(in: folder))
    }
}
