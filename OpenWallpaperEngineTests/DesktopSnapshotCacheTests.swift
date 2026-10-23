import XCTest
@testable import OpenWallpaperEngine

/// OWE's desktop-picture folder: its pictures told from the user's, and the old per-launch TIFFs
/// cleaned up.
final class DesktopSnapshotCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "DesktopSnapshotCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testOWEsPicturesAreRecognised() {
        let cache = DesktopSnapshotCache(cachesDirectory: root)
        XCTAssertTrue(cache.isSnapshot(cache.directory.appending(path: "lock-7-a.heic")))
        XCTAssertTrue(cache.isSnapshot(cache.directory.appending(path: "desktop-7-a.jpg")), "an earlier version's tint picture")
        XCTAssertFalse(cache.isSnapshot(URL(filePath: "/Library/Desktop Pictures/x.heic")))
    }

    /// An isolated copy leaves the user's desktop picture alone unless a test asks for it.
    func testIsolationLeavesTheDesktopPictureAlone() {
        XCTAssertFalse(DesktopSnapshotCache.mayChangeDesktopPicture, "the test host is an isolated copy")
        XCTAssertTrue(DesktopSnapshotCache.allowsDesktopPicture(isIsolated: false, environment: [:]))
        XCTAssertFalse(DesktopSnapshotCache.allowsDesktopPicture(isIsolated: true, environment: [:]))
        XCTAssertFalse(DesktopSnapshotCache.allowsDesktopPicture(isIsolated: true, environment: ["OWE_ALLOW_DESKTOP_PICTURE": "0"]))
        XCTAssertTrue(DesktopSnapshotCache.allowsDesktopPicture(isIsolated: true, environment: ["OWE_ALLOW_DESKTOP_PICTURE": "1"]))
    }

    /// Another copy's snapshot (an isolated run's) is never taken for the user's own picture.
    func testAnyCopysSnapshotCounts() {
        let real = DesktopSnapshotCache(cachesDirectory: root)
        let isolated = DesktopSnapshotCache(cachesDirectory: root.appending(path: "Open Wallpaper Engine (isolated limtest)"))
        XCTAssertTrue(real.isSnapshot(isolated.directory.appending(path: "lock-2-b.jpg")))
        XCTAssertTrue(isolated.isSnapshot(real.directory.appending(path: "lock-2-a.heic")))
        XCTAssertFalse(real.isSnapshot(root.appending(path: "Pictures/DesktopSnapshots/x.jpg")))
    }
}
