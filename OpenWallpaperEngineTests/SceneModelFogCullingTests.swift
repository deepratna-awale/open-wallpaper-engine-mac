import simd
import XCTest
@testable import OpenWallpaperEngine

final class SceneModelFogCullingTests: XCTestCase {
    private func fog(end: Float = 10, endDensity: Float = 1, color: SIMD3<Float> = SIMD3(0.2, 0.3, 0.4)) -> SceneFogSettings {
        var fog = SceneFogSettings()
        fog.distance = true
        fog.distanceStart = 1
        fog.distanceEnd = end
        fog.distanceStartDensity = 0
        fog.distanceEndDensity = endDensity
        fog.distanceColor = color
        return fog
    }

    /// Only a whole density in the clear colour paints a model exactly the background.
    func testTheFogMustBeWholeAndTheClearColour() {
        let clear = SIMD3<Float>(0.2, 0.3, 0.4)
        XCTAssertTrue(SceneModelFogCulling.coversWithClearColor(fog(), clearColor: clear))
        XCTAssertFalse(SceneModelFogCulling.coversWithClearColor(fog(endDensity: 0.99), clearColor: clear))
        XCTAssertFalse(SceneModelFogCulling.coversWithClearColor(fog(color: SIMD3(0, 0, 0)), clearColor: clear))
        var off = fog()
        off.distance = false
        XCTAssertFalse(SceneModelFogCulling.coversWithClearColor(off, clearColor: clear))
        XCTAssertFalse(SceneModelFogCulling.coversWithClearColor(fog(end: 1), clearColor: clear), "no range")
    }

    /// A box counts as beyond the fog only when its nearest point is past the end.
    func testTheWholeBoxMustLieBeyondTheEnd() {
        let box = MDLBounds(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        func at(_ z: Float, scale: SIMD3<Float> = SIMD3(1, 1, 1)) -> simd_float4x4 {
            var world = simd_float4x4(diagonal: SIMD4(scale, 1))
            world.columns.3 = SIMD4(0, 0, z, 1)
            return world
        }
        let eye = SIMD3<Float>(0, 0, 0)
        // Corner distance √3 ≈ 1.73: the nearest point is at z − 1.73.
        XCTAssertTrue(SceneModelFogCulling.isBeyondFog(box, world: at(12), eye: eye, fog: fog()))
        XCTAssertFalse(SceneModelFogCulling.isBeyondFog(box, world: at(11), eye: eye, fog: fog()))
        XCTAssertFalse(SceneModelFogCulling.isBeyondFog(box, world: at(12, scale: SIMD3(1, 1, 3)), eye: eye, fog: fog()))
        XCTAssertFalse(SceneModelFogCulling.isBeyondFog(.unbounded, world: at(1_000_000), eye: eye, fog: fog()))
    }
}
