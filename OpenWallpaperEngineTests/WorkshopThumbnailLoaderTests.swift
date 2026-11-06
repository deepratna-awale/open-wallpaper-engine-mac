import AppKit
import XCTest
@testable import OpenWallpaperEngine

/// Workshop card previews are decoded at card size and served from memory the second time.
final class WorkshopThumbnailLoaderTests: XCTestCase {
    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appending(path: "thumbnail-\(UUID().uuidString).png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 512,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file) // Test scratch; the cache test removes it itself.
    }

    func testDownsamplesAndCaches() async throws {
        let loader = WorkshopThumbnailLoader(maxPixelSize: 256)
        let loaded = await loader.image(for: file)
        let image = try XCTUnwrap(loaded)
        // The decoded bitmap, not `representations.first?.pixelsWide`: on macOS 27 an
        // NSImage(cgImage:) rep reports its point size times the main screen's backing scale.
        let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(max(pixels.width, pixels.height), 256)
        XCTAssertEqual(pixels.width, 2 * pixels.height, "the aspect ratio stays")
        XCTAssertEqual(image.size, NSSize(width: 256, height: 128), "drawn one point per decoded pixel")

        try FileManager.default.removeItem(at: file)
        let again = await loader.image(for: file)
        XCTAssertNotNil(again, "the second load comes from memory")
    }

    func testDropsTheLeastRecentlyUsedOverTheLimit() async throws {
        let copies = try (0..<3).map { index -> URL in
            let copy = file.deletingPathExtension().appendingPathExtension("\(index).png")
            try FileManager.default.copyItem(at: file, to: copy)
            return copy
        }
        defer { copies.forEach { try? FileManager.default.removeItem(at: $0) } }
        // 256 × 128 RGBA is 128 KiB (a row may be padded): room for two thumbnails, not three.
        let loader = WorkshopThumbnailLoader(maxPixelSize: 256, memoryLimit: 300 * 1024)
        _ = await loader.image(for: copies[0])
        _ = await loader.image(for: copies[1])
        XCTAssertNotNil(loader.cachedImage(for: copies[0]), "used again, so copies[1] is now the oldest")
        _ = await loader.image(for: copies[2])
        XCTAssertNotNil(loader.cachedImage(for: copies[0]))
        XCTAssertNil(loader.cachedImage(for: copies[1]))
        XCTAssertNotNil(loader.cachedImage(for: copies[2]))

        loader.removeAll()
        XCTAssertNil(loader.cachedImage(for: copies[0]))
    }

    func testNonImageDataIsNil() {
        XCTAssertNil(WorkshopThumbnailLoader.downsample(Data("not an image".utf8), maxPixelSize: 64))
    }
}
