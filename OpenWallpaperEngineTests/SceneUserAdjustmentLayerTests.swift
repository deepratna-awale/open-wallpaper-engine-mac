import XCTest
import Metal
@testable import OpenWallpaperEngine

/// The user adjustment layer (`SceneUserAdjustmentLayer`): WE's effects and WE's bloom on the
/// finished frame, planned on first use and drawing nothing at the defaults.
final class SceneUserAdjustmentLayerTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var effects: EffectGraphRenderer!
    private var layer: SceneUserAdjustmentLayer!
    private var cache: URL!

    private struct NoValues: SceneValueContext {
        func userProperty(_ name: String) -> String? { nil }
    }

    override func setUpWithError() throws {
        _ = try Fixtures.assets()
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        cache = FileManager.default.temporaryDirectory.appending(path: "owe-adjustments-\(UUID().uuidString)")
        effects = try XCTUnwrap(EffectGraphRenderer(device: device, pipelineArchiveDirectory: cache.appending(path: "archives")))
        let root = ShaderVariantTests.weAssets
        let builder = SceneEffectPlanBuilder(
            translator: ShaderVariantTranslator(compiler: InProcessShaderCompiler(), cacheDirectory: cache),
            readFile: { FileManager.default.contents(atPath: root.appending(path: $0).path) },
            loadTexture: { _, _ in nil })
        layer = SceneUserAdjustmentLayer(builder: builder)
    }

    override func tearDownWithError() throws {
        effects?.pipelineArchive?.flush()
        if let cache { try? FileManager.default.removeItem(at: cache) }
    }

    /// A 64×64 frame, black but for a white square in the middle.
    private func frame() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        for y in 0..<64 {
            for x in 0..<64 {
                let lit = (24..<40).contains(x) && (24..<40).contains(y)
                let index = (y * 64 + x) * 4
                pixels[index] = lit ? 255 : 0
                pixels[index + 1] = lit ? 255 : 0
                pixels[index + 2] = lit ? 255 : 0
                pixels[index + 3] = 255
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 64 * 4)
        return texture
    }

    /// The layer's output for `extras`, once its pipelines have compiled; nil when it draws nothing.
    private func encode(_ extras: ScenePostProcess.AppExtras, on input: MTLTexture) throws -> MTLTexture? {
        for _ in 0..<400 {
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            let output = layer.encode(on: input, extras: extras, bloomThreshold: SceneGeneralDefaults.bloomThreshold,
                                      effects: effects, builtins: BuiltinFrameContext(), values: NoValues(),
                                      referenceSize: SIMD2(64, 64), commandBuffer: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            XCTAssertNil(buffer.error)
            if output != nil || !SceneUserAdjustmentLayer.runs(extras) { return output }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    /// The red channel of `texture`'s pixel at (`x`, `y`).
    private func red(_ texture: MTLTexture, x: Int, y: Int) throws -> UInt8 {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                                  height: texture.height, mipmapped: false)
        descriptor.storageMode = .shared
        let copy = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(buffer.makeBlitCommandEncoder())
        blit.copy(from: texture, to: copy)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var pixel = [UInt8](repeating: 0, count: 4)
        copy.getBytes(&pixel, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return pixel[0]
    }

    func testTheDefaultsDrawNothing() throws {
        XCTAssertNil(try encode(.init(), on: try frame()))
        XCTAssertNil(try encode(.init(saturation: 0.5, hue: 1), on: try frame()), "hue and saturation are the composite's")
    }

    /// WE's Blur spreads the square's light into the black around it.
    func testTheBlurIsWEsBlurEffect() throws {
        let input = try frame()
        let blurred = try XCTUnwrap(try encode(.init(blur: 1), on: input))
        XCTAssertEqual(try red(input, x: 22, y: 32), 0)
        XCTAssertGreaterThan(try red(blurred, x: 22, y: 32), 0, "light spread past the square's edge")
        XCTAssertEqual(effects.failedPipelineCount, 0)
    }

    /// The bloom glows around the square on a frame whose scene has no bloom of its own.
    func testTheBloomGlowsWithoutTheScenesBloom() throws {
        let input = try frame()
        let bloomed = try XCTUnwrap(try encode(.init(bloom: 1), on: input))
        XCTAssertGreaterThan(try red(bloomed, x: 21, y: 32), 0, "glow around the square")
        XCTAssertEqual(effects.failedPipelineCount, 0)
    }

    /// Each of WE's effects the layer stacks plans, compiles and draws.
    func testEveryEffectDraws() throws {
        let input = try frame()
        let all: [(String, ScenePostProcess.AppExtras)] = [
            ("tint", .init(tint: 1, tintColor: SIMD3(0, 0, 1))), ("localcontrast", .init(localContrast: 1)),
            ("chromaticaberration", .init(chromaticAberration: 1)), ("vhs", .init(vhs: 1)), ("filmgrain", .init(filmGrain: 1))
        ]
        for (name, extras) in all {
            XCTAssertNotNil(try encode(extras, on: input), name)
            XCTAssertEqual(effects.failedPipelineCount, 0, name)
        }
        let tinted = try XCTUnwrap(try encode(.init(tint: 1, tintColor: SIMD3(0, 0, 1)), on: input))
        XCTAssertLessThan(try red(tinted, x: 32, y: 32), 128, "a blue tint takes the white square's red")
    }
}
