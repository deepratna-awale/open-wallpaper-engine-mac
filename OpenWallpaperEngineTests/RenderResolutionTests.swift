import XCTest
@testable import OpenWallpaperEngine

/// Settings → Performance → Render Resolution (`GSRenderResolution`): the scene target sized for
/// the displays' pixels, or for their points.
final class RenderResolutionTests: XCTestCase {
    func testDesktopResolutionSizesTheTargetInPoints() {
        let retina = SceneViewport(drawableSize: SIMD2(3840, 2160), pointSize: SIMD2(1920, 1080), cursor: nil, frameRateLimit: 30)
        let plain = SceneViewport(drawableSize: SIMD2(2560, 1440), pointSize: SIMD2(2560, 1440), cursor: nil, frameRateLimit: 30)
        XCTAssertEqual(SceneRenderResolution.drawableSize([retina], resolution: .native), SIMD2(3840, 2160))
        XCTAssertEqual(SceneRenderResolution.drawableSize([retina], resolution: .desktop), SIMD2(1920, 1080))
        XCTAssertEqual(SceneRenderResolution.drawableSize([retina, plain], resolution: .desktop), SIMD2(2560, 1440))
        let unlaid = SceneViewport(drawableSize: SIMD2(800, 600), pointSize: .zero, cursor: nil, frameRateLimit: 30)
        XCTAssertEqual(SceneRenderResolution.drawableSize([unlaid], resolution: .desktop), SIMD2(800, 600))
    }

    func testTheSettingReachesTheRenderer() {
        var settings = GlobalSettings()
        XCTAssertEqual(settings.renderResolution, .native, "the display's pixels by default")
        settings.renderResolution = .desktop
        XCTAssertEqual(SceneRenderSettings(settings).renderResolution, .desktop)
        XCTAssertEqual(SceneRenderSettings().renderResolution, .native)
    }

    /// S1: a steady size draws at the display's own density (the target the drawable's size along
    /// the covering axis); while it changes, the quantised steps stand.
    func testASteadySizeIsSizedExactly() {
        let scene = SIMD2<Float>(1920, 1080)
        let macBook = SIMD2<Float>(3024, 1964)
        let quantised = SceneRenderResolution.pixelsPerUnit(sceneSize: scene, drawableSize: macBook)
        let exact = SceneRenderResolution.pixelsPerUnit(sceneSize: scene, drawableSize: macBook, exact: true)
        XCTAssertEqual(quantised, 1.875)
        XCTAssertEqual(SceneRenderResolution.targetSize(sceneSize: scene, pixelsPerUnit: exact).y, 1964)
        XCTAssertEqual(SceneRenderResolution.targetSize(sceneSize: scene, pixelsPerUnit: exact).x, 3492)
        let fiveK = SceneRenderResolution.pixelsPerUnit(sceneSize: scene, drawableSize: SIMD2(5120, 2880), exact: true)
        XCTAssertEqual(SceneRenderResolution.targetSize(sceneSize: scene, pixelsPerUnit: fiveK), SIMD2(5120, 2880))
        // Never below the authored size.
        XCTAssertEqual(SceneRenderResolution.pixelsPerUnit(sceneSize: scene, drawableSize: SIMD2(1280, 720), exact: true), 1)

        var stability = SceneRenderResolution.SizeStability()
        XCTAssertTrue(stability.isSteady(macBook), "the first size is steady")
        XCTAssertTrue(stability.isSteady(macBook))
        XCTAssertFalse(stability.isSteady(SIMD2(3000, 1900)), "a resize")
        for _ in 1..<SceneRenderResolution.SizeStability.settleFrames { XCTAssertFalse(stability.isSteady(SIMD2(3000, 1900))) }
        XCTAssertTrue(stability.isSteady(SIMD2(3000, 1900)), "settled")
    }
}
