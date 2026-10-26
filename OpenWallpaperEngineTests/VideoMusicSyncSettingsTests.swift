import XCTest
@testable import OpenWallpaperEngine

/// A wallpaper's music sync and scene music settings follow the wallpaper (its settings identity,
/// `WallpaperSettingsIdentity`), not its folder path.
@MainActor
final class VideoMusicSyncSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var root: URL!

    override func setUpWithError() throws {
        suite = "owe-music-sync-settings-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root) // scratch cleanup
    }

    /// A video wallpaper in a folder at `path` under the scratch root.
    private func wallpaper(_ path: String, project: String = #"{"title":"Rain","type":"video","file":"rain.mp4"}"#) throws -> WEWallpaper {
        let directory = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(project.utf8).write(to: directory.appending(path: "project.json"))
        return WEWallpaper(using: WEProject(file: "rain.mp4", preview: "preview.jpg", title: "Rain", type: "video"),
                           where: directory)
    }

    private func move(_ wallpaper: WEWallpaper, to path: String) throws -> WEWallpaper {
        let destination = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: wallpaper.wallpaperDirectory, to: destination)
        var moved = wallpaper
        moved.wallpaperDirectory = destination
        return moved
    }

    private func setEverything(on wallpaper: WEWallpaper, in store: VideoMusicSyncStore) {
        store.set(true, wallpaper, "zoomEnabled")
        store.set(0.3, wallpaper, "zoomAmount")
        store.set(true, wallpaper, "paceEnabled")
        store.setSceneMusicEnabled(false, wallpaper)
        store.setSceneMusicVolume(0.4, wallpaper)
    }

    private func assertEverythingSet(on wallpaper: WEWallpaper, in store: VideoMusicSyncStore, _ message: String,
                                     line: UInt = #line) {
        XCTAssertEqual(store.effect(for: wallpaper), VideoMusicSyncEffect(zoomAmount: 0.3, paceAmount: 0.25), message, line: line)
        XCTAssertTrue(store.isAnyEnabled(wallpaper), message, line: line)
        XCTAssertFalse(store.sceneMusicEnabled(wallpaper), message, line: line)
        XCTAssertEqual(store.sceneMusicVolume(wallpaper), 0.4, message, line: line)
    }

    func testMovingOrRenamingTheFolderKeepsTheSettings() throws {
        let store = VideoMusicSyncStore(defaults: defaults)
        let original = try wallpaper("library/Rain")
        setEverything(on: original, in: store)
        let moved = try move(original, to: "elsewhere/deeper/Rain")
        assertEverythingSet(on: moved, in: store, "same wallpaper, new place")
        let renamed = try move(moved, to: "elsewhere/Drizzle")
        assertEverythingSet(on: renamed, in: VideoMusicSyncStore(defaults: defaults), "same wallpaper, new name, read afresh")
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.contains(root.path) },
                       "no setting is keyed by a folder path")
    }

    func testAWorkshopWallpaperKeepsItsSettingsUnderItsId() throws {
        let store = VideoMusicSyncStore(defaults: defaults)
        let original = try wallpaper("library/123456")
        setEverything(on: original, in: store)
        XCTAssertNotNil(defaults.object(forKey: "VideoMusicSync.workshop-123456.zoomEnabled"))
        let renamed = try move(original, to: "other/123456")
        assertEverythingSet(on: renamed, in: VideoMusicSyncStore(defaults: defaults), "the Workshop id names it wherever it is")
    }

    func testTwoWallpapersDoNotShareTheirSettings() throws {
        let store = VideoMusicSyncStore(defaults: defaults)
        let first = try wallpaper("one/Rain")
        // The same project.json in another folder: still a wallpaper of its own.
        let second = try wallpaper("two/Rain")
        setEverything(on: first, in: store)
        XCTAssertEqual(store.effect(for: second), VideoMusicSyncEffect())
        XCTAssertFalse(store.isAnyEnabled(second))
        XCTAssertTrue(store.sceneMusicEnabled(second), "scene music is on until switched off")
        XCTAssertEqual(store.sceneMusicVolume(second), 1)
        assertEverythingSet(on: first, in: store, "the first keeps its own")
    }

    func testAChangeNamesTheWallpapersIdentity() throws {
        let store = VideoMusicSyncStore(defaults: defaults)
        let rain = try wallpaper("library/Rain")
        let expectation = expectation(forNotification: .videoMusicSyncSettingsDidChange, object: nil) { notification in
            notification.userInfo?["identity"] as? String == store.identity(of: rain).rawValue
        }
        store.set(true, rain, "tiltEnabled")
        wait(for: [expectation], timeout: 1)
        let music = self.expectation(forNotification: .sceneMusicSettingsDidChange, object: nil) { notification in
            notification.userInfo?["identity"] as? String == store.identity(of: rain).rawValue
        }
        store.setSceneMusicVolume(0.5, rain)
        wait(for: [music], timeout: 1)
    }
}
