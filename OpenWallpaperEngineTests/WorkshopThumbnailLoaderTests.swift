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
        let pixels = try XCTUnwrap(image.representations.first)
        XCTAssertEqual(max(pixels.pixelsWide, pixels.pixelsHigh), 256)
        XCTAssertEqual(pixels.pixelsWide, 2 * pixels.pixelsHigh, "the aspect ratio stays")

        try FileManager.default.removeItem(at: file)
        let again = await loader.image(for: file)
        XCTAssertNotNil(again, "the second load comes from memory")
    }

    func testNonImageDataIsNil() {
        XCTAssertNil(WorkshopThumbnailLoader.downsample(Data("not an image".utf8), maxPixelSize: 64))
    }
}
