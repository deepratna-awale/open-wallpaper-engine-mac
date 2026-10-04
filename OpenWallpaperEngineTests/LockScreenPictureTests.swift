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
        picture.recordOriginal(DesktopSnapshotCache(cachesDirectory: caches).directory.appending(path: "desktop-2-b.jpg"), display: 2)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "another Space may still show the other slot")
        XCTAssertEqual(try Data(contentsOf: second), Data([1, 2, 3]))
        let jpeg = try picture.write(Data([4]), fileExtension: "jpg", display: 7, showing: second)
        XCTAssertEqual(jpeg.lastPathComponent, "lock-7-a.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "a slot holds one file, whatever its format")
    }

    func testRestorePutsBackEachDisplaysOwnPicture() {
        let other = URL(filePath: "/Users/me/Pictures/second.jpg")
        picture.recordOriginal(userPicture, display: 1)
        picture.recordOriginal(other, display: 2)
        let lock1 = picture.url(display: 1, slot: 0, fileExtension: "heic")
        let lock2 = picture.url(display: 2, slot: 1, fileExtension: "jpg")
        let lock3 = picture.url(display: 3, slot: 0, fileExtension: "heic")
        let fallback = URL(filePath: "/Users/me/Pictures/launch.jpg")
        let plan = picture.restorePlan(showing: [1: lock1, 2: lock2, 3: lock3, 4: userPicture, 5: nil], fallback: fallback,
                                       exists: { _ in true })
        XCTAssertEqual(plan, [1: userPicture, 2: other, 3: fallback],
                       "displays showing the user's own picture keep it; one with no record gets the launch picture")
        picture.forgetOriginals()
        XCTAssertTrue(picture.originals().isEmpty)
    }

    /// A picture that is gone is never put back: the display keeps OWE's picture, which exists.
    func testRestoreNeverPointsAtAMissingFile() {
        let gone = URL(filePath: "/Users/me/Pictures/deleted.jpg")
        picture.recordOriginal(gone, display: 1)
        let lock = picture.url(display: 1, slot: 0, fileExtension: "heic")
        let oldTint = DesktopSnapshotCache(cachesDirectory: caches).directory.appending(path: "desktop-2-a.jpg")
        let exists = { (url: URL) in url != gone }
        XCTAssertEqual(picture.restorePlan(showing: [1: lock, 2: oldTint], fallback: userPicture, exists: exists),
                       [1: userPicture, 2: userPicture], "an earlier version's tint picture is OWE's too")
        XCTAssertTrue(picture.restorePlan(showing: [1: lock], fallback: gone, exists: exists).isEmpty)
        XCTAssertTrue(picture.restorePlan(showing: [4: lock], fallback: picture.url(display: 3, slot: 1, fileExtension: "jpg"),
                                          exists: { _ in true }).isEmpty, "OWE's picture is never the user's")
    }

    /// The live bug: `OSWallpaper` held `lock-1-a.heic`, a file OWE had since replaced, so quitting
    /// pointed the desktop at a missing file.
    func testTheSavedUserPictureIsNeverOWEsOrMissing() {
        let lock = picture.url(display: 1, slot: 0, fileExtension: "heic")
        let gone = URL(filePath: "/Users/me/Pictures/deleted.jpg")
        let exists = { (url: URL) in url != gone }
        XCTAssertEqual(picture.userPicture(saved: lock, showing: userPicture, exists: exists), userPicture)
        XCTAssertNil(picture.userPicture(saved: lock, showing: lock, exists: exists))
        XCTAssertEqual(picture.userPicture(saved: gone, showing: userPicture, exists: exists), userPicture)
        let saved = URL(filePath: "/Users/me/Pictures/mine.jpg")
        XCTAssertEqual(picture.userPicture(saved: saved, showing: lock, exists: exists), saved)
    }

    func testForgetsOneDisplaysPicture() {
        picture.recordOriginal(userPicture, display: 1)
        picture.recordOriginal(userPicture, display: 2)
        picture.forgetOriginals(of: [1])
        XCTAssertEqual(Array(picture.originals().keys), [2])
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
