import XCTest
@testable import OpenWallpaperEngine

/// Property changes and per-frame reads stay in memory: project.json is read once per wallpaper,
/// music-sync values once per write, and the global settings are a value snapshot.
final class MainThreadOffenderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appending(path: "owe-offenders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let project = """
        {"file": "index.html", "title": "Test", "type": "web", "general": {"properties": {
          "speed": {"type": "slider", "text": "Speed", "value": 5, "min": 0, "max": 10},
          "tint": {"type": "color", "text": "Tint", "value": "1 0 0"}}}}
        """
        try Data(project.utf8).write(to: directory.appending(path: "project.json"))
    }

    override func tearDownWithError() throws {
        WEProjectFileCache.shared.invalidate(directory)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testTenPropertyChangesReadProjectJSONNoMoreTimes() {
        // The first look loads the wallpaper.
        let declared = WebWallpaperPropertyBridge.declaredProperties(wallpaperDirectory: directory)
        XCTAssertEqual(Set(declared.keys), ["speed", "tint"])
        _ = WallpaperSettingsIdentity.resolve(directory: directory)
        let before: Int = WEProjectFileCache.shared.diskReads
        for step in 0..<10 {
            // What a property change does: the web page's payload, the edited stores' identity.
            let payload = WebWallpaperPropertyBridge.payload(
                properties: WebWallpaperPropertyBridge.declaredProperties(wallpaperDirectory: directory),
                values: ["speed": String(step)])
            XCTAssertNotNil(payload["speed"])
            _ = WallpaperSettingsIdentity.resolve(directory: directory)
            _ = projectHasCustomizableProperties(at: directory)
        }
        let after: Int = WEProjectFileCache.shared.diskReads
        XCTAssertEqual(after, before, "property changes must not read project.json")
    }

    func testAnEditedProjectJSONIsReadAgain() throws {
        XCTAssertEqual(WEProjectFileCache.shared.root(in: directory)?["title"] as? String, "Test")
        let url = directory.appending(path: "project.json")
        try Data(#"{"file": "index.html", "title": "Changed title", "type": "web"}"#.utf8).write(to: url)
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
        XCTAssertEqual(WEProjectFileCache.shared.root(in: directory)?["title"] as? String, "Changed title")
    }

    func testAMissingProjectJSONThrows() {
        let missing = directory.appending(path: "missing")
        XCTAssertNil(WEProjectFileCache.shared.root(in: missing))
        XCTAssertThrowsError(try WEProjectFileCache.shared.data(in: missing))
    }

    func testMusicSyncValuesAreReadFromDefaultsOncePerWrite() {
        let project = WEProject(file: "video.mp4", title: "Video", type: "video")
        let wallpaper = WEWallpaper(using: project, where: directory)
        VideoMusicSyncStore.shared.set(true, wallpaper, "zoomEnabled")
        VideoMusicSyncStore.shared.set(0.2, wallpaper, "zoomAmount")
        defer {
            UserDefaults.app.removeObject(forKey: VideoMusicSyncSettings.key(wallpaper, "zoomEnabled"))
            UserDefaults.app.removeObject(forKey: VideoMusicSyncSettings.key(wallpaper, "zoomAmount"))
            VideoMusicSyncSettings.invalidate()
        }
        let first: Bool = VideoMusicSyncSettings.bool(wallpaper, "zoomEnabled")
        XCTAssertTrue(first)
        let before: Int = VideoMusicSyncSettings.defaultsReads
        for _ in 0..<120 {  // two seconds of frames
            _ = VideoMusicSyncSettings.bool(wallpaper, "zoomEnabled")
            _ = VideoMusicSyncSettings.double(wallpaper, "zoomAmount", default: 0.08)
            _ = VideoMusicSyncSettings.double(wallpaper, "tiltAmount", default: 3)
        }
        let after: Int = VideoMusicSyncSettings.defaultsReads
        XCTAssertLessThanOrEqual(after, before + 2, "each value is read once, then served from memory")
        let amount: Double = VideoMusicSyncSettings.double(wallpaper, "zoomAmount", default: 0.08)
        XCTAssertEqual(amount, 0.2, accuracy: 1e-9)
        let tilt: Double = VideoMusicSyncSettings.double(wallpaper, "tiltAmount", default: 3)
        XCTAssertEqual(tilt, 3, accuracy: 1e-9, "an unset value keeps its default")
        // A write is seen at once.
        VideoMusicSyncStore.shared.set(0.5, wallpaper, "zoomAmount")
        let written: Double = VideoMusicSyncSettings.double(wallpaper, "zoomAmount", default: 0.08)
        XCTAssertEqual(written, 0.5, accuracy: 1e-9)
    }

    @MainActor
    func testGlobalSettingsSnapshotFollowsChangesAndSavesOnce() {
        let model = GlobalSettingsViewModel()
        let original = model.settings
        defer { model.settings = original; model.flushPendingSave() }
        model.setQuality(.low)
        let fps: Double = GlobalSettingsViewModel.current.fps
        XCTAssertEqual(fps, 10, "readers off the main actor see the change at once")
        model.flushPendingSave()
        let data: Data? = UserDefaults.app.data(forKey: "GlobalSettings")
        let saved: GlobalSettings? = data.flatMap { try? JSONDecoder().decode(GlobalSettings.self, from: $0) }
        XCTAssertEqual(saved?.fps, 10)
    }
}
