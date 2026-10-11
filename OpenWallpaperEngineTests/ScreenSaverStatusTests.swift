import XCTest
@testable import OpenWallpaperEngine

/// What the Details pane says about a wallpaper in the screen saver: scenes are drawn live, web
/// wallpapers and WebM videos through Chromium, video wallpapers play their own file once it is
/// prepared, and nothing is said while the plugin is off.
final class ScreenSaverStatusTests: XCTestCase {
    private typealias Plugin = ScreenSaverPlugin

    private func wallpaper(type: String, file: String = "scene.json",
                           directory: URL = URL(fileURLWithPath: "/tmp/owe-status-test")) -> WEWallpaper {
        WEWallpaper(using: WEProject(file: file, preview: "p.jpg", title: "t", type: type), where: directory)
    }

    private func key(for wallpaper: WEWallpaper) -> Plugin.StatusKey {
        Plugin.StatusKey(wallpaperKey: SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory),
                         contentKey: "c", propertyHash: "h")
    }

    func testScenesWebPagesVideosAndWebMVideosAreEligible() {
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "scene")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "Scene")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "web", file: "index.html")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "video", file: "clip.webm")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "video", file: "clip.mp4")))
        XCTAssertFalse(Plugin.isEligible(wallpaper(type: "application", file: "app.exe")))
        XCTAssertFalse(Plugin.isEligible(WEWallpaper(using: .invalid, where: URL(fileURLWithPath: "/tmp/x"))))
    }

    func testOnlyVideoWallpapersHaveAFileKey() {
        XCTAssertNil(Plugin.statusKey(for: wallpaper(type: "scene")))
        XCTAssertNil(Plugin.statusKey(for: wallpaper(type: "web", file: "index.html")))
        XCTAssertNil(Plugin.statusKey(for: wallpaper(type: "application", file: "app.exe")))
    }

    func testScenesAreAvailableAtOnce() {
        XCTAssertEqual(Plugin.status(for: wallpaper(type: "scene"), enabled: true, statuses: [:], chromiumInstalled: false),
                       .available, "drawn live: nothing to make first")
    }

    func testPagesNeedChromium() {
        for page in [wallpaper(type: "web", file: "index.html"), wallpaper(type: "video", file: "clip.webm")] {
            XCTAssertEqual(Plugin.status(for: page, enabled: true, statuses: [:], chromiumInstalled: false), .needsChromium)
            XCTAssertEqual(Plugin.status(for: page, enabled: true, statuses: [:], chromiumInstalled: true), .available)
        }
    }

    func testVideosFollowTheirFile() {
        let video = wallpaper(type: "video", file: "clip.mp4")
        XCTAssertNil(Plugin.status(for: video, enabled: true, statuses: [:], chromiumInstalled: true), "not checked yet")
        XCTAssertEqual(Plugin.status(for: video, enabled: true, statuses: [key(for: video): .rendering], chromiumInstalled: true),
                       .rendering)
        XCTAssertEqual(Plugin.status(for: video, enabled: true, statuses: [key(for: video): .available], chromiumInstalled: true),
                       .available)
    }

    func testNotEligibleTypesSayNotAvailable() {
        for type in ["application", "preset"] {
            XCTAssertEqual(Plugin.status(for: wallpaper(type: type), enabled: true, statuses: [:], chromiumInstalled: true),
                           .notEligible, type)
        }
        XCTAssertEqual(Plugin.status(for: wallpaper(type: "video", file: "clip.mkv"), enabled: true, statuses: [:],
                                     chromiumInstalled: true), .notEligible)
    }

    func testNoStatusWhenDisabled() {
        XCTAssertNil(Plugin.status(for: wallpaper(type: "scene"), enabled: false, statuses: [:], chromiumInstalled: true))
        XCTAssertNil(Plugin.status(for: wallpaper(type: "video"), enabled: false, statuses: [:], chromiumInstalled: true))
    }

    @MainActor
    func testANewPluginHasNoStatus() {
        let plugin = ScreenSaverPlugin(store: ScreenSaverVideoStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "owe-status-\(UUID().uuidString)")),
                                       installer: ScreenSaverInstaller(bundledSaver: nil,
                                                                       saversDirectory: URL(fileURLWithPath: "/tmp/owe-status-savers"),
                                                                       mayInstall: false))
        XCTAssertNil(plugin.status(for: wallpaper(type: "scene")), "off")
        XCTAssertTrue(plugin.statuses.isEmpty)
    }
}
