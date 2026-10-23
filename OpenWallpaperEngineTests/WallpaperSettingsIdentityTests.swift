import XCTest
import OWESceneEditing
@testable import OpenWallpaperEngine

/// Risk #21: per-wallpaper settings follow the wallpaper, not its folder path.
final class WallpaperSettingsIdentityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var root: URL!

    override func setUpWithError() throws {
        suite = "owe-settings-identity-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root) // scratch cleanup
    }

    /// A wallpaper folder at `path` under the scratch root with this project.json.
    @discardableResult
    private func wallpaper(_ path: String, project: String = #"{"title":"Rain","type":"scene","file":"scene.json"}"#) throws -> URL {
        let directory = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(project.utf8).write(to: directory.appending(path: "project.json"))
        return directory
    }

    private func move(_ directory: URL, to path: String) throws -> URL {
        let destination = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory, to: destination)
        return destination
    }

    func testWorkshopIdFromProjectOrFolder() throws {
        let declared = try wallpaper("library/anything", project: #"{"workshopid":"12345","file":"scene.json"}"#)
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: declared, defaults: defaults).rawValue, "workshop-12345")
        let numeric = try wallpaper("library/67890", project: #"{"workshopid":67890}"#)
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: numeric, defaults: defaults).rawValue, "workshop-67890")
        let steamFolder = try wallpaper("library/424242")
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: steamFolder, defaults: defaults).rawValue, "workshop-424242")
    }

    func testLocalWallpapersGetTheirOwnStableIds() throws {
        let a = try wallpaper("one/Rain")
        let identity = WallpaperSettingsIdentity.resolve(directory: a, defaults: defaults)
        XCTAssertTrue(identity.rawValue.hasPrefix("local-") && !identity.isWorkshop, identity.rawValue)
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: a, defaults: defaults), identity, "resolved again")
        let moved = try move(a, to: "elsewhere/deeper/Rain")
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: moved, defaults: defaults), identity, "same wallpaper, new place")
        let renamed = try move(moved, to: "elsewhere/Drizzle")
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: renamed, defaults: defaults), identity, "same wallpaper, new name")
        let other = try wallpaper("two/Rain", project: #"{"title":"Snow","file":"scene.json"}"#)
        XCTAssertNotEqual(WallpaperSettingsIdentity.resolve(directory: other, defaults: defaults), identity, "a different project")
        let twin = try wallpaper("three/Rain")
        XCTAssertNotEqual(WallpaperSettingsIdentity.resolve(directory: twin, defaults: defaults), identity,
                          "the same project bytes and folder name in another folder is another wallpaper")
    }

    /// Title, tag and rating edits rewrite project.json; the wallpaper's properties, editor overlay
    /// and presets stay with it.
    func testEditingMetadataKeepsTheIdentityAndItsSettings() throws {
        let directory = try wallpaper("library/Rain")
        let identity = WallpaperSettingsIdentity.resolve(directory: directory, defaults: defaults)
        defaults.set(["speed": "2"], forKey: identity.key(.userProperties))
        let overlays = SceneEditOverlayStore(directory: root.appending(path: "editor"))
        var overlay = SceneEditOverlay()
        overlay.removed = [3]
        try overlays.save(overlay, for: identity.rawValue)
        let presetsDirectory = root.appending(path: "presets")
        try WallpaperPresetStore(identity: identity, directory: presetsDirectory).save(name: "Night", values: ["speed": "1"])

        try WallpaperProjectFileEdit.set(["title": "Heavy rain"], inProjectAt: directory, defaults: defaults)
        try WallpaperProjectFileEdit.set(["tags": ["Nature"]], inProjectAt: directory, defaults: defaults)
        try WallpaperProjectFileEdit.set(["contentrating": "Mature"], inProjectAt: directory, defaults: defaults)

        let after = WallpaperSettingsIdentity.resolve(directory: directory, defaults: defaults)
        XCTAssertEqual(after, identity)
        XCTAssertEqual(defaults.dictionary(forKey: after.key(.userProperties)) as? [String: String], ["speed": "2"])
        XCTAssertEqual(try overlays.overlay(for: after.rawValue)?.removed, [3])
        XCTAssertEqual(try WallpaperPresetStore(identity: after, directory: presetsDirectory).presets().map(\.name), ["Night"])
    }

    /// A copy of a wallpaper's folder (Save as New Wallpaper, a Finder copy) is a new wallpaper.
    func testACopiedFolderGetsANewId() throws {
        let original = try wallpaper("library/Rain")
        let identity = WallpaperSettingsIdentity.resolve(directory: original, defaults: defaults)
        let copy = root.appending(path: "library/Rain copy", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: original, to: copy)
        let copyIdentity = WallpaperSettingsIdentity.resolve(directory: copy, defaults: defaults)
        XCTAssertNotEqual(copyIdentity, identity)
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: original, defaults: defaults), identity, "the original keeps its id")
        let elsewhere = root.appending(path: "other/Rain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original, to: elsewhere)
        XCTAssertFalse([identity, copyIdentity].contains(WallpaperSettingsIdentity.resolve(directory: elsewhere, defaults: defaults)),
                       "same folder name and bytes elsewhere: still new")
    }

    func testWorkshopItemsAreNotRegistered() throws {
        let item = try wallpaper("library/424242", project: #"{"title":"Rain","file":"scene.json"}"#)
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: item, defaults: defaults).rawValue, "workshop-424242")
        try WallpaperProjectFileEdit.set(["title": "Snow"], inProjectAt: item, defaults: defaults)
        XCTAssertEqual(WallpaperSettingsIdentity.resolve(directory: item, defaults: defaults).rawValue, "workshop-424242")
        // This test's own store: a lookup through `defaults` also searches the process's shared domains.
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[LocalWallpaperIdentities.defaultsKey])
    }

    func testSettingsSurviveMovingTheLibrary() throws {
        let directory = try wallpaper("library/Rain")
        let key = WallpaperSettingsIdentity.resolve(directory: directory, defaults: defaults).key(.userProperties)
        defaults.set(["speed": "2"], forKey: key)
        let moved = try move(directory, to: "new-library/Rain")
        let after = WallpaperSettingsIdentity.resolve(directory: moved, defaults: defaults).key(.userProperties)
        XCTAssertEqual(defaults.dictionary(forKey: after) as? [String: String], ["speed": "2"])
    }
}
