import XCTest
import CoreGraphics
@testable import OpenWallpaperEngine

final class LockScreenPictureTests: XCTestCase {
    private var caches: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var picture: LockScreenPicture!

    override func setUpWithError() throws {
        caches = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        suite = "com.winddog.wallpaper-engine.isolated.tests.lockscreen.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        picture = LockScreenPicture(cache: DesktopSnapshotCache(cachesDirectory: caches), defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: caches)
    }

    private let userPicture = URL(filePath: "/System/Library/Desktop Pictures/Sonoma.heic")

    func testRecordsTheUsersPictureOncePerDisplay() {
        picture.recordOriginal(userPicture, display: 1)
        picture.recordOriginal(URL(filePath: "/Users/me/Pictures/other.jpg"), display: 1)
        XCTAssertEqual(picture.originals()[1], userPicture, "the first replaced picture is the user's")
    }

    func testNeverRecordsOWEsOwnPictures() {
        picture.recordOriginal(picture.url(display: 2, slot: 0, fileExtension: "heic"), display: 2)
        picture.recordOriginal(DesktopSnapshotCache(cachesDirectory: caches).url(display: 2, slot: 1), display: 2)
        picture.recordOriginal(nil, display: 2)
        XCTAssertNil(picture.originals()[2])
    }

    func testWriteAlternatesSlotsAndKeepsTheSnapshotsFormat() throws {
        let snapshot = caches.appending(path: "snap.heic")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: snapshot)
        let first = try picture.write(snapshot: snapshot, display: 7, showing: userPicture)
        XCTAssertEqual(first.lastPathComponent, "lock-7-a.heic")
        XCTAssertTrue(picture.isLockPicture(first))
        let second = try picture.write(snapshot: snapshot, display: 7, showing: first)
        XCTAssertEqual(second.lastPathComponent, "lock-7-b.heic", "macOS ignores the URL it already shows")
        picture.removePictures(display: 7, except: second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(try Data(contentsOf: second), Data([1, 2, 3]))
    }

    func testRestorePutsBackEachDisplaysOwnPicture() {
        let other = URL(filePath: "/Users/me/Pictures/second.jpg")
        picture.recordOriginal(userPicture, display: 1)
        picture.recordOriginal(other, display: 2)
        let lock1 = picture.url(display: 1, slot: 0, fileExtension: "heic")
        let lock2 = picture.url(display: 2, slot: 1, fileExtension: "jpg")
        let lock3 = picture.url(display: 3, slot: 0, fileExtension: "heic")
        let fallback = URL(filePath: "/Users/me/Pictures/launch.jpg")
        let plan = picture.restorePlan(showing: [1: lock1, 2: lock2, 3: lock3, 4: userPicture, 5: nil], fallback: fallback)
        XCTAssertEqual(plan, [1: userPicture, 2: other, 3: fallback],
                       "displays showing the user's own picture keep it; one with no record gets the launch picture")
        picture.forgetOriginals()
        XCTAssertTrue(picture.originals().isEmpty)
    }

    func testTintPicturesAreNotLockPictures() {
        let tint = DesktopSnapshotCache(cachesDirectory: caches).url(display: 1, slot: 0)
        XCTAssertFalse(picture.isLockPicture(tint))
        XCTAssertTrue(DesktopSnapshotCache(cachesDirectory: caches).isSnapshot(picture.url(display: 1, slot: 0, fileExtension: "jpg")))
        XCTAssertTrue(picture.restorePlan(showing: [1: tint], fallback: userPicture).isEmpty)
    }

    func testIsolatedCopiesNeverChangeTheDesktopPicture() {
        XCTAssertFalse(DesktopSnapshotCache.mayChangeDesktopPicture, "the test host is isolated")
    }

    func testSettingDefaultsOnAndDecodesWhenMissing() throws {
        XCTAssertTrue(GlobalSettings().lockScreenPicture)
        XCTAssertTrue(GlobalSettings().screenSaver)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.lockScreenPicture)
        XCTAssertTrue(decoded.screenSaver)
    }

    // MARK: A new snapshot

    private let shown = URL(filePath: "/Wallpapers/431960/shown", directoryHint: .isDirectory)
    private let other = URL(filePath: "/Wallpapers/431960/other", directoryHint: .isDirectory)

    private func refreshed(savedFor directory: URL, isOn: Bool = true, mayChange: Bool = true) -> [Int] {
        let showing: [Int: URL] = [1: shown, 2: other, 3: shown]
        return LockScreenPicture.screensToRefresh(savedFor: directory, screens: [1, 2, 3, 4],
                                                  shownDirectory: { showing[$0] }, isOn: isOn, mayChange: mayChange)
    }

    func testASnapshotOfTheShownWallpaperRefreshesTheDisplaysShowingIt() {
        XCTAssertEqual(refreshed(savedFor: shown), [1, 3])
        XCTAssertEqual(refreshed(savedFor: URL(filePath: "/Wallpapers/431960/other/../shown")), [1, 3])
    }

    func testASnapshotOfAWallpaperNoLongerShownChangesNothing() {
        XCTAssertTrue(refreshed(savedFor: URL(filePath: "/Wallpapers/431960/gone")).isEmpty)
    }

    func testNothingChangesWithTheSettingOffOrWhenIsolated() {
        XCTAssertTrue(refreshed(savedFor: shown, isOn: false).isEmpty)
        XCTAssertTrue(refreshed(savedFor: shown, mayChange: false).isEmpty)
    }

    func testEverySavedSnapshotIsReportedIncludingAfterAPropertyChange() throws {
        let wallpaper = caches.appending(path: "Library/123456", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: wallpaper, withIntermediateDirectories: true)
        try Data(#"{"type":"scene","file":"scene.json"}"#.utf8).write(to: wallpaper.appending(path: "project.json"))
        try Data("{}".utf8).write(to: wallpaper.appending(path: "scene.json"))
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let session = SceneLoadingSnapshotSession(store: SceneLoadingSnapshotStore(cachesDirectory: caches))
        let saved = expectation(description: "saved twice")
        saved.expectedFulfillmentCount = 2
        let capture = SceneLoadingSnapshotCapture(wallpaperDirectory: wallpaper, session: session, now: 0) {
            XCTAssertEqual($0, wallpaper)
            saved.fulfill()
        }
        capture.save(image)
        capture.rearm(now: 10)
        capture.save(image)
        wait(for: [saved], timeout: 10)
    }
}
