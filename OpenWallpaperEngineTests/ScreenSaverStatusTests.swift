import XCTest
@testable import OpenWallpaperEngine

final class ScreenSaverStatusTests: XCTestCase {
    private typealias Plugin = ScreenSaverPlugin

    private func wallpaper(type: String, directory: URL = URL(fileURLWithPath: "/tmp/owe-status-test")) -> WEWallpaper {
        WEWallpaper(using: WEProject(file: "scene.json", preview: "p.jpg", title: "t", type: type), where: directory)
    }

    private func key(for wallpaper: WEWallpaper) -> Plugin.StatusKey {
        Plugin.StatusKey(wallpaperKey: SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory),
                         contentKey: "c", propertyHash: "h")
    }

    // MARK: Eligibility

    func testOnlyValidScenesAreEligible() {
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "scene")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(type: "Scene")))
        XCTAssertFalse(Plugin.isEligible(wallpaper(type: "video")))
        XCTAssertFalse(Plugin.isEligible(wallpaper(type: "web")))
        XCTAssertFalse(Plugin.isEligible(wallpaper(type: "application")))
        XCTAssertFalse(Plugin.isEligible(WEWallpaper(using: .invalid, where: URL(fileURLWithPath: "/tmp/x"))))
    }

    func testTargetsFollowEligibility() {
        let screens = [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080))]
        for type in ["video", "web", "application"] {
            XCTAssertTrue(Plugin.targets(for: wallpaper(type: type), screens: screens, properties: [:]).isEmpty, type)
        }
        XCTAssertNil(Plugin.statusKey(for: wallpaper(type: "web"), properties: [:]))
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
        for type in ["video", "web", "application"] {
            XCTAssertEqual(Plugin.status(for: wallpaper(type: type), enabled: true, statuses: [:]), .notEligible, type)
        }
        XCTAssertEqual(Plugin.status(for: WEWallpaper(using: .invalid, where: URL(fileURLWithPath: "/tmp/x")),
                                     enabled: true, statuses: [:]), .notEligible)
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
                                       runner: { _, _, _ in false })
        XCTAssertFalse(plugin.isEnabled)
        XCTAssertNil(plugin.status(for: wallpaper(type: "scene")))
    }
}
