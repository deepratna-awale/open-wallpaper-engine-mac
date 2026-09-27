import XCTest
import CoreGraphics
import simd
@testable import OpenWallpaperEngine

/// Text drawn through a camera covers its glyphs only (`SceneTextInk`), as WE's per-glyph quads do,
/// so its empty rows write no depth over what is drawn behind them later.
final class SceneTextInkTests: XCTestCase {
    /// A 100×40 raster with ink in x 20…59, y 10…19 (from the top).
    private func raster() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 400,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        // Core Graphics' origin is the bottom-left: rows 10…19 from the top are y 20…29.
        context.fill(CGRect(x: 20, y: 20, width: 40, height: 10))
        return try XCTUnwrap(context.makeImage())
    }

    func testTheInkBoxIsTheCoveredTexelsGrownByOne() throws {
        let ink = try XCTUnwrap(SceneTextInk.bounds(of: try raster()))
        XCTAssertEqual(ink.x, 19 / 100, accuracy: 1e-6)
        XCTAssertEqual(ink.y, 9 / 40, accuracy: 1e-6)
        XCTAssertEqual(ink.z, 61 / 100, accuracy: 1e-6)
        XCTAssertEqual(ink.w, 21 / 40, accuracy: 1e-6)
        let empty = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        XCTAssertNil(SceneTextInk.bounds(of: empty))
    }

    /// The cut quad's corners are the whole quad's at the ink box's texture coordinates.
    func testTheCutQuadKeepsTheGlyphsWhereTheyWere() {
        let placement = SceneLayerPlacement(world: matrix_identity_float4x4, size: SIMD2(100, 40), offset: SIMD2(5, -3),
                                            camera: SceneFrameCamera())
        let ink = SIMD4<Float>(0.2, 0.25, 0.6, 0.5)
        let cut = SceneTextInk.crop(placement, to: ink)
        XCTAssertEqual(cut.corner(SIMD2(0, 0)), placement.corner(SIMD2(ink.x, ink.y)))
        XCTAssertEqual(cut.corner(SIMD2(1, 1)), placement.corner(SIMD2(ink.z, ink.w)))
    }
}
