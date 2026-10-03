import XCTest
@testable import OpenWallpaperEngine

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

    // MARK: Eligibility

    func testScenesWebPagesAndWebMVideosAreEligible() {
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "scene")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "Scene")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "web", file: "index.html")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "video", file: "clip.webm")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "video", file: "clip.mp4")))
        XCTAssertFalse(Plugin.isEligible(wallpaper(type: "application", file: "app.exe")))
        XCTAssertFalse(Plugin.isEligible(WEWallpaper(using: .invalid, where: URL(fileURLWithPath: "/tmp/x"))))
    }

    func testTargetsFollowEligibility() {
        let screens = [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080))]
        for type in ["video", "application"] {
            XCTAssertTrue(Plugin.targets(for: wallpaper(type: type), screens: screens, properties: [:]).isEmpty, type)
        }
        XCTAssertNil(Plugin.statusKey(for: wallpaper(type: "application"), properties: [:]))
    }

    func testWebTargetsCarryTheirProperties() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "owe-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("<html></html>".utf8).write(to: directory.appending(path: "index.html"))
        let web = wallpaper(type: "web", file: "index.html", directory: directory)
        let screens = [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080))]
        let target = try XCTUnwrap(Plugin.targets(for: web, screens: screens, properties: ["a": "1"]).first)
        XCTAssertEqual(target.pixelSize, SIMD2(1920, 1080), "Render Resolution Display records the points")
        XCTAssertEqual(target.properties, ["a": "1"])
        XCTAssertEqual(Plugin.decodeProperties(Plugin.encodeProperties(["a": "1", "b": "x y"])), ["a": "1", "b": "x y"])
        XCTAssertEqual(Plugin.decodeProperties("not json"), [:])
    }

    func testStatusKeyMatchesTheStoreName() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "owe-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appending(path: "scene.json"))
        let scene = wallpaper(type: "scene", directory: directory)
        let key = try XCTUnwrap(Plugin.statusKey(for: scene, properties: ["a": "1"]))
        let screens = [(pixels: SIMD2(2560, 1440), points: SIMD2(2560, 1440))]
        let target = try XCTUnwrap(Plugin.targets(for: scene, screens: screens, properties: ["a": "1"]).first)
        XCTAssertEqual(target.fileName, ScreenSaverVideoStore.fileName(
            wallpaperKey: key.wallpaperKey, contentKey: key.contentKey, propertyHash: key.propertyHash,
            pixelSize: SIMD2(2560, 1440)))
    }

    // MARK: Status

    func testAvailableAndRendering() {
        let scene = wallpaper(type: "scene")
        XCTAssertEqual(Plugin.status(for: scene, enabled: true, statuses: [key(for: scene): .available]), .available)
        XCTAssertEqual(Plugin.status(for: scene, enabled: true, statuses: [key(for: scene): .rendering]), .rendering)
    }

    func testNotEligibleTypesSayNotAvailable() {
        for type in ["video", "application"] {
            XCTAssertEqual(Plugin.status(for: wallpaper(type: type), enabled: true, statuses: [:]), .notEligible, type)
        }
        XCTAssertEqual(Plugin.status(for: WEWallpaper(using: .invalid, where: URL(fileURLWithPath: "/tmp/x")),
                                     enabled: true, statuses: [:]), .notEligible)
    }

    func testFinishedJobStatus() {
        XCTAssertEqual(Plugin.finishedStatus(allRendered: true, pageDidNotLoad: false), .available)
        XCTAssertEqual(Plugin.finishedStatus(allRendered: false, pageDidNotLoad: true), .notAvailable(.pageDidNotLoad))
        XCTAssertNil(Plugin.finishedStatus(allRendered: false, pageDidNotLoad: false), "another failure shows nothing")
    }

    func testRenderingThenNotAvailableForAPageThatDidNotLoad() {
        let web = wallpaper(type: "web", file: "index.html")
        XCTAssertEqual(Plugin.status(for: web, enabled: true, statuses: [key(for: web): .rendering]), .rendering)
        let failed = Plugin.finishedStatus(allRendered: false, pageDidNotLoad: true).map { [key(for: web): $0] } ?? [:]
        XCTAssertEqual(Plugin.status(for: web, enabled: true, statuses: failed), .notAvailable(.pageDidNotLoad))
        let done = Plugin.finishedStatus(allRendered: true, pageDidNotLoad: false).map { [key(for: web): $0] } ?? [:]
        XCTAssertEqual(Plugin.status(for: web, enabled: true, statuses: done), .available)
    }

    func testNoStatusWhenDisabled() {
        let scene = wallpaper(type: "scene")
        XCTAssertNil(Plugin.status(for: scene, enabled: false, statuses: [key(for: scene): .available]))
        XCTAssertNil(Plugin.status(for: wallpaper(type: "video"), enabled: false, statuses: [:]))
    }

    func testNoStatusForASceneNotYetRendered() {
        let scene = wallpaper(type: "scene")
        let other = wallpaper(type: "scene", directory: URL(fileURLWithPath: "/tmp/owe-other"))
        XCTAssertNil(Plugin.status(for: scene, enabled: true, statuses: [:]))
        XCTAssertNil(Plugin.status(for: scene, enabled: true, statuses: [key(for: other): .available]),
                     "another wallpaper's loop says nothing about this one")
    }

    @MainActor
    func testANewPluginHasNoStatus() {
        let plugin = ScreenSaverPlugin(pool: PreparationPool(maxWorkers: 1),
                                       store: ScreenSaverVideoStore(directory: FileManager.default.temporaryDirectory),
                                       runner: { _, _, _ in .failed })
        XCTAssertFalse(plugin.isEnabled)
        XCTAssertNil(plugin.status(for: wallpaper(type: "scene")))
    }
}
