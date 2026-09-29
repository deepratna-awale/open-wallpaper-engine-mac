import XCTest
import CoreGraphics
@testable import OpenWallpaperEngine

/// The menu-bar tint snapshots: small files under a stable name per display, in OWE's own folder,
/// and the old per-launch TIFFs cleaned up.
final class DesktopSnapshotCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "DesktopSnapshotCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testSnapshotIsADownscaledJPEG() throws {
        let data = try XCTUnwrap(DesktopSnapshotCache.jpegData(try image(width: 5120, height: 2880)))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width: Int = decoded.width
        let height: Int = decoded.height
        XCTAssertEqual(width, DesktopSnapshotCache.maxPixelSize)
        XCTAssertEqual(height, 576)
        let type = CGImageSourceGetType(source) as String?
        XCTAssertEqual(type, "public.jpeg")
        XCTAssertLessThan(data.count, 1 << 20, "a tint snapshot is well under a megabyte")
    }

    func testNamesAreStablePerDisplayAndAlternate() throws {
        let cache = DesktopSnapshotCache(cachesDirectory: root)
        let a = cache.url(display: 7, slot: 0)
        let b = cache.url(display: 7, slot: 1)
        XCTAssertEqual(a, DesktopSnapshotCache(cachesDirectory: root).url(display: 7, slot: 0))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, cache.url(display: 8, slot: 0))
        let first: Int = cache.nextSlot(display: 7, showing: URL(filePath: "/Library/Desktop Pictures/x.heic"))
        let afterA: Int = cache.nextSlot(display: 7, showing: a)
        let afterB: Int = cache.nextSlot(display: 7, showing: b)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(afterA, 1)
        XCTAssertEqual(afterB, 0)
        XCTAssertTrue(cache.isSnapshot(a))
        XCTAssertTrue(cache.isSnapshot(root.appending(path: "staticWP_123.tiff")))
        XCTAssertFalse(cache.isSnapshot(URL(filePath: "/Library/Desktop Pictures/x.heic")))
    }

    /// Repeated snapshots of one display keep at most its two slots, never one file per launch.
    func testRepeatedWritesDoNotAccumulate() throws {
        let cache = DesktopSnapshotCache(cachesDirectory: root)
        let jpeg = try XCTUnwrap(DesktopSnapshotCache.jpegData(try image(width: 64, height: 64)))
        var showing: URL?
        for _ in 0..<10 {
            let written = try cache.write(jpeg, display: 3, showing: showing)
            cache.removeOtherSlot(than: written, display: 3)
            showing = written
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        let count: Int = files.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cache.existingURL(display: 3)?.lastPathComponent, showing?.lastPathComponent)
        cache.removeAll()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    /// Old `staticWP_*.tiff` files go to the Trash; nothing else in Caches is touched.
    func testLegacySnapshotsAreTrashedAndNothingElse() throws {
        let cache = DesktopSnapshotCache(cachesDirectory: root)
        for name in ["staticWP_-566.tiff", "staticWP_619.tiff", "other.tiff", "staticWP_notes.txt"] {
            try Data([1]).write(to: root.appending(path: name))
        }
        var trashed: [String] = []
        cache.trashLegacySnapshots { trashed.append($0.lastPathComponent) }
        XCTAssertEqual(trashed.sorted(), ["staticWP_-566.tiff", "staticWP_619.tiff"])
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
        XCTAssertTrue(real.isSnapshot(isolated.url(display: 2, slot: 1)))
        XCTAssertTrue(isolated.isSnapshot(real.url(display: 2, slot: 0)))
        XCTAssertFalse(real.isSnapshot(root.appending(path: "Pictures/DesktopSnapshots/x.jpg")))
    }
}
