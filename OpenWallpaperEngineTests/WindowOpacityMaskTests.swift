import CoreGraphics
import XCTest
@testable import OpenWallpaperEngine

/// `WindowOpacityMask`: a window snapshot reduced to where it is opaque.
final class WindowOpacityMaskTests: XCTestCase {
    /// An RGBA image `width` × `height` whose left `seeThroughColumns` columns have `alpha` and
    /// the rest are opaque.
    private func image(width: Int, height: Int, seeThroughColumns: Int, alpha: UInt8) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let a = column < seeThroughColumns ? alpha : 255
                let index = (row * width + column) * 4
                // Premultiplied: colour no brighter than alpha.
                pixels[index] = a / 2
                pixels[index + 1] = a / 3
                pixels[index + 2] = a / 4
                pixels[index + 3] = a
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    func testOnlyTheAlphaDecidesOpacity() throws {
        // A terminal at 55% opacity on the left half.
        let mask = try XCTUnwrap(WindowOpacityMask(image: image(width: 8, height: 4, seeThroughColumns: 4, alpha: 140),
                                                   columns: 8, rows: 4))
        XCTAssertEqual(mask.opaque.filter { $0 }.count, 16)
        XCTAssertFalse(mask.isOpaque(atUnit: CGPoint(x: 0.1, y: 0.5)))
        XCTAssertTrue(mask.isOpaque(atUnit: CGPoint(x: 0.9, y: 0.5)))
    }

    func testNearlyOpaquePixelsCountAsOpaque() throws {
        let mask = try XCTUnwrap(WindowOpacityMask(image: image(width: 4, height: 4, seeThroughColumns: 4, alpha: 250),
                                                   columns: 4, rows: 4))
        XCTAssertTrue(mask.opaque.allSatisfy { $0 })
    }

    func testPointsOutsideTheFrameClampToItsEdge() {
        let mask = WindowOpacityMask(columns: 2, rows: 1, opaque: [false, true])
        XCTAssertFalse(mask.isOpaque(atUnit: CGPoint(x: -1, y: 0)))
        XCTAssertTrue(mask.isOpaque(atUnit: CGPoint(x: 2, y: 9)))
    }

    func testTheGridKeepsTheWindowsShape() {
        let wide = WindowOpacityMask.gridSize(for: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(wide.columns, WindowOpacityMask.longSide)
        XCTAssertEqual(wide.rows, 27)
        let tall = WindowOpacityMask.gridSize(for: CGSize(width: 400, height: 1600))
        XCTAssertEqual(tall.rows, WindowOpacityMask.longSide)
        XCTAssertEqual(tall.columns, 12)
        XCTAssertEqual(WindowOpacityMask.gridSize(for: .zero).columns, 1)
    }
}
