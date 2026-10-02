import XCTest
import Metal
@testable import OpenWallpaperEngine

/// Settings → Performance → Render Resolution (`GSRenderResolution`), Upscaling and Render Scale:
/// the scene target sized for the displays' points or pixels, or the scene's authored size, drawn at the
/// render scale and scaled up (`SceneUpscaler`).
final class RenderResolutionTests: XCTestCase {
    private let retina = SceneViewport(drawableSize: SIMD2(3840, 2160), pointSize: SIMD2(1920, 1080), cursor: nil, frameRateLimit: 30)
    private let plain = SceneViewport(drawableSize: SIMD2(1920, 1080), pointSize: SIMD2(1920, 1080), cursor: nil, frameRateLimit: 30)

    private func target(_ scene: SIMD2<Float>, _ viewports: [SceneViewport], _ resolution: GSRenderResolution,
                        match: Bool, scale: Float = 1) -> SIMD2<Int> {
        let drawable = SceneRenderResolution.drawableSize(viewports, resolution: resolution, sceneSize: scene)
        let full = SceneRenderResolution.pixelsPerUnit(sceneSize: scene, drawableSize: drawable, matchDisplay: match)
        return SceneRenderResolution.targetSize(sceneSize: scene,
                                                pixelsPerUnit: SceneRenderResolution.drawnPixelsPerUnit(full, scale: scale))
    }

    func testDisplayIsThePointsAndRetinaTheBackingPixels() {
        XCTAssertEqual(SceneRenderResolution.drawableSize([retina], resolution: .display, sceneSize: SIMD2(1920, 1080)),
                       SIMD2(1920, 1080), "points, not pixels, on a 2× display")
        XCTAssertEqual(SceneRenderResolution.drawableSize([retina], resolution: .retina, sceneSize: SIMD2(1920, 1080)),
                       SIMD2(3840, 2160))
        XCTAssertEqual(SceneRenderResolution.drawableSize([plain], resolution: .display, sceneSize: SIMD2(1920, 1080)),
                       SIMD2(1920, 1080))
        XCTAssertEqual(SceneRenderResolution.drawableSize([retina, plain], resolution: .retina, sceneSize: SIMD2(1, 1)),
                       SIMD2(3840, 2160))
        let unsized = SceneViewport(drawableSize: SIMD2(800, 600), pointSize: .zero, cursor: nil, frameRateLimit: 30)
        XCTAssertEqual(SceneRenderResolution.drawableSize([unsized], resolution: .display, sceneSize: SIMD2(1, 1)),
                       SIMD2(800, 600), "a view without a size yet falls back to its drawable")
    }

    func testEachModeSizesTheTarget() {
        let scene = SIMD2<Float>(1920, 1080)
        XCTAssertEqual(target(scene, [retina], .display, match: true), SIMD2(1920, 1080), "a quarter of the pixels")
        XCTAssertEqual(target(scene, [retina], .retina, match: true), SIMD2(3840, 2160))
        XCTAssertEqual(target(scene, [plain], .display, match: true), SIMD2(1920, 1080))
        XCTAssertEqual(target(scene, [plain], .retina, match: true), SIMD2(1920, 1080))
        XCTAssertEqual(target(scene, [retina], .full, match: true), SIMD2(1920, 1080), "the authored size, placed onto the display")
        XCTAssertEqual(target(scene, [plain], .full, match: false), SIMD2(1920, 1080))
        // A 4K scene on a 1× 1080p display: Full keeps its authored size.
        XCTAssertEqual(target(SIMD2(3840, 2160), [plain], .full, match: true), SIMD2(3840, 2160))
    }

    func testAWideSceneCoversTheDisplay() {
        let wide = SIMD2<Float>(5120, 1440)
        // Covering a 3840×2160 display needs 1.5 pixels per unit (its height).
        XCTAssertEqual(target(wide, [retina], .retina, match: true), SIMD2(7680, 2160))
        XCTAssertEqual(target(wide, [retina], .display, match: true), SIMD2(3840, 1080))
        XCTAssertEqual(target(wide, [plain], .display, match: true), SIMD2(3840, 1080))
        XCTAssertEqual(target(wide, [retina], .full, match: true), SIMD2(5120, 1440))
    }

    func testMatchDisplayIsNotScaledTwice() {
        // A scene the display's shape: exactly the drawable (Retina) or the points (Display).
        for (scene, viewport) in [(SIMD2<Float>(1920, 1080), retina), (SIMD2<Float>(1920, 1080), plain),
                                  (SIMD2<Float>(3840, 2160), plain), (SIMD2<Float>(2560, 1440), retina)] {
            XCTAssertEqual(target(scene, [viewport], .retina, match: true),
                           SIMD2(Int(viewport.drawableSize.x), Int(viewport.drawableSize.y)), "\(scene) on \(viewport.drawableSize)")
            XCTAssertEqual(target(scene, [viewport], .display, match: true),
                           SIMD2(Int(viewport.pointSize.x), Int(viewport.pointSize.y)), "\(scene) on \(viewport.pointSize)")
        }
    }

    func testRenderScaleSizes() {
        let scene = SIMD2<Float>(1920, 1080)
        XCTAssertEqual(target(scene, [retina], .retina, match: true, scale: GSRenderScale.percent50.factor), SIMD2(1920, 1080))
        XCTAssertEqual(target(scene, [retina], .retina, match: true, scale: GSRenderScale.percent67.factor), SIMD2(2560, 1440))
        XCTAssertEqual(target(scene, [retina], .retina, match: true, scale: GSRenderScale.percent75.factor), SIMD2(2880, 1620))
        XCTAssertEqual(target(scene, [retina], .display, match: true, scale: GSRenderScale.percent50.factor), SIMD2(960, 540),
                       "MetalFX draws below the chosen target")
        XCTAssertEqual(target(scene, [plain], .full, match: true, scale: 0.5), SIMD2(960, 540))
        XCTAssertEqual(SceneRenderResolution.drawnPixelsPerUnit(2, scale: 1), 2)
        var settings = SceneRenderSettings()
        XCTAssertEqual(settings.drawnScale, 1, "upscaling off draws the full target")
        settings.upscaling = .metalFX
        settings.renderScale = .percent67
        XCTAssertEqual(settings.drawnScale, 2.0 / 3)
    }

    func testUpscalingPathFallsBackToBilinear() {
        var settings = SceneRenderSettings()
        XCTAssertEqual(SceneUpscaler.path(settings: settings, format: .bgra8Unorm, deviceSupportsMetalFX: true), .none)
        settings.upscaling = .metalFX
        settings.renderScale = .percent50
        XCTAssertEqual(SceneUpscaler.path(settings: settings, format: .bgra8Unorm, deviceSupportsMetalFX: true), .metalFX)
        XCTAssertEqual(SceneUpscaler.path(settings: settings, format: .bgra8Unorm, deviceSupportsMetalFX: false), .bilinear,
                       "a GPU without MetalFX")
        XCTAssertEqual(SceneUpscaler.path(settings: settings, format: .rgba16Float, deviceSupportsMetalFX: true), .bilinear,
                       "HDR and EDR frames")
    }

    func testMetalFXUpscalesToTheFullTarget() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        try XCTSkipUnless(SceneUpscaler.supportsMetalFX(device), "this GPU has no MetalFX spatial scaler")
        let upscaler = SceneUpscaler(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 36, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        let input = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        // The scaler is made off the calling thread: the first frames fall back.
        var output: MTLTexture?
        let deadline = Date().addingTimeInterval(10)
        while output == nil, Date() < deadline {
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            output = upscaler.upscale(input, to: SIMD2(128, 72), commandBuffer: commandBuffer)
            commandBuffer.commit()
            if output == nil { Thread.sleep(forTimeInterval: 0.02) }
        }
        let upscaled = try XCTUnwrap(output)
        XCTAssertEqual(SIMD2(upscaled.width, upscaled.height), SIMD2(128, 72))
        let hdr = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 36, mipmapped: false)
        hdr.usage = [.shaderRead]
        hdr.storageMode = .private
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertNil(upscaler.upscale(try XCTUnwrap(device.makeTexture(descriptor: hdr)), to: SIMD2(128, 72),
                                      commandBuffer: commandBuffer), "RGBA16F is scaled bilinearly by the composite")
    }

    func testTheSettingReachesTheRenderer() {
        var settings = GlobalSettings()
        XCTAssertEqual(settings.renderResolution, .display, "the display's points by default")
        XCTAssertEqual(settings.upscaling, .off)
        settings.renderResolution = .full
        settings.upscaling = .metalFX
        settings.renderScale = .percent50
        let render = SceneRenderSettings(settings)
        XCTAssertEqual(render.renderResolution, .full)
        XCTAssertEqual(render.upscaling, .metalFX)
        XCTAssertEqual(render.renderScale, .percent50)
        XCTAssertEqual(SceneRenderSettings().renderResolution, .retina, "a settings-less renderer draws as WE does")
    }

    func testSavedAndExportedSettingsMigrate() throws {
        func decoded(_ value: String) throws -> GlobalSettings {
            try JSONDecoder().decode(GlobalSettings.self, from: Data("{\"renderResolution\":\"\(value)\"}".utf8))
        }
        XCTAssertEqual(try decoded("desktop").renderResolution, .display, "the points-based Desktop becomes Display")
        XCTAssertEqual(try decoded("native").renderResolution, .retina, "the backing-pixel Native becomes Retina")
        XCTAssertEqual(try decoded("retina").renderResolution, .retina)
        XCTAssertEqual(try decoded("full").renderResolution, .full)
        XCTAssertEqual(try decoded("display").renderResolution, .display, "the earlier backing-pixel Display moves to points")
        XCTAssertEqual(try decoded("bogus").renderResolution, .display, "an unknown value keeps the default")
        var settings = GlobalSettings()
        settings.renderResolution = .full
        settings.upscaling = .metalFX
        settings.renderScale = .percent67
        let roundTrip = try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(roundTrip.renderResolution, .full)
        XCTAssertEqual(roundTrip.upscaling, .metalFX)
        XCTAssertEqual(roundTrip.renderScale, .percent67)
    }

    func testPresets() {
        var settings = GlobalSettings()
        settings.renderResolution = .full
        settings.applyResolutionPreset(.low)
        XCTAssertEqual(settings.upscaling, .metalFX)
        XCTAssertEqual(settings.renderScale, .percent50)
        // The user's own choice stands until a preset is applied again.
        settings.renderScale = .percent75
        XCTAssertEqual(settings.renderScale, .percent75)
        for quality in [GSQuality.medium, .high, .ultra] {
            settings.applyResolutionPreset(.low)
            settings.applyResolutionPreset(quality)
            XCTAssertEqual(settings.upscaling, .off, "\(quality)")
            XCTAssertEqual(settings.renderResolution, .display, "\(quality)")
        }
        settings.applyResolutionPreset(.low)
        XCTAssertEqual(settings.renderScale, .percent50, "applying Low again overrides the user's scale")
    }
}
