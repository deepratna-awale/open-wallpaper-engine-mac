import XCTest
import Metal
@testable import OpenWallpaperEngine

/// A block-compressed `.tex` uploads every mipmap it stores from the loaded one on
/// (`SceneTextureUpload.blockCompressedTexture`).
final class BlockTextureMipmapTests: XCTestCase {
    func testABlockTextureCarriesEveryStoredMipmap() throws {
        let data = TextureReductionTests.tex(format: 7, image: SIMD2(8, 8), mipmaps: [
            (SIMD2(8, 8), [UInt8](repeating: 1, count: 4 * 8)),
            (SIMD2(4, 4), [UInt8](repeating: 2, count: 8)),
            (SIMD2(2, 2), [UInt8](repeating: 3, count: 8)),
            (SIMD2(1, 1), [UInt8](repeating: 4, count: 8)),
        ])
        let full = try XCTUnwrap(TEXParser(data: data).extractCompressedTexture())
        XCTAssertEqual(full.levels.count, 4)
        XCTAssertEqual(full.levels.map { $0.first ?? 0 }, [1, 2, 3, 4])
        let reduced = try XCTUnwrap(TEXParser(data: data).extractCompressedTexture(reduction: 2))
        XCTAssertEqual(reduced.levels.count, 3, "a reduced load starts at the second")
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        try XCTSkipUnless(device.supportsBCTextureCompression)
        let texture = try XCTUnwrap(SceneTextureUpload.blockCompressedTexture(full, device: device))
        XCTAssertEqual(texture.mipmapLevelCount, 4)
    }

    func testAChainThatSkipsALevelStopsThere() throws {
        let data = TextureReductionTests.tex(format: 7, image: SIMD2(8, 8), mipmaps: [
            (SIMD2(8, 8), [UInt8](repeating: 1, count: 4 * 8)),
            (SIMD2(2, 2), [UInt8](repeating: 3, count: 8)),
        ])
        let texture = try XCTUnwrap(TEXParser(data: data).extractCompressedTexture())
        XCTAssertEqual(texture.levels.count, 1)
    }
}
