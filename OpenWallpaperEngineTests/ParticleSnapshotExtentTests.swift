import simd
import XCTest
@testable import OpenWallpaperEngine

final class ParticleSnapshotExtentTests: XCTestCase {
    private func record(_ position: SIMD2<Float>, size: Float, alpha: Float = 1) -> ParticleSpriteInstance {
        ParticleSpriteInstance(position: SIMD4(position.x, position.y, 0, 0), rotationSize: SIMD4(0, 0, 0, size),
                               velocityLifetime: .zero, color: SIMD4(1, 1, 1, alpha))
    }

    private func extent(_ records: [ParticleSpriteInstance], linear: simd_float2x2 = matrix_identity_float2x2,
                        aspect: Float = 1) -> ParticleSnapshotExtent? {
        records.withUnsafeBufferPointer { ParticleSnapshotExtent(records: $0, spriteLinear: linear, aspect: aspect) }
    }

    /// Every particle's quad lies inside the rect, which is padded by the refraction reach.
    func testTheRectHoldsEveryParticleAndTheRefractionReach() throws {
        let value = try XCTUnwrap(extent([record(SIMD2(100, 100), size: 10), record(SIMD2(300, 200), size: 20)]))
        // Scene 1000×1000 into 1000×1000 pixels; y flips.
        let rect = value.pixelRect(refractAmount: 0.01, sceneSize: SIMD2(1000, 1000), targetSize: SIMD2(1000, 1000))
        // Quads: x 90…320, y (up) 90…220 → pixels y 780…910. Reach: 2·0.01·1000 + 2 = 22.
        XCTAssertLessThanOrEqual(rect.x, 90 - 20)
        XCTAssertGreaterThanOrEqual(rect.maxX, 320 + 20)
        XCTAssertLessThanOrEqual(rect.y, 780 - 20)
        XCTAssertGreaterThanOrEqual(rect.maxY, 910 + 20)
        XCTAssertLessThan(rect.area, 1000 * 1000 / 4, "far smaller than the whole frame")
    }

    /// A large amount, alpha over 1 or a stretched quad only grow the rect, clamped to the target.
    func testTheReachGrowsWithAmountAlphaAndStretch() throws {
        let small = try XCTUnwrap(extent([record(SIMD2(500, 500), size: 10)]))
            .pixelRect(refractAmount: 0.01, sceneSize: SIMD2(1000, 1000), targetSize: SIMD2(1000, 1000))
        let bright = try XCTUnwrap(extent([record(SIMD2(500, 500), size: 10, alpha: 3)]))
            .pixelRect(refractAmount: 0.01, sceneSize: SIMD2(1000, 1000), targetSize: SIMD2(1000, 1000))
        let stretched = try XCTUnwrap(extent([record(SIMD2(500, 500), size: 10)], linear: simd_float2x2(diagonal: SIMD2(4, 4))))
            .pixelRect(refractAmount: 0.01, sceneSize: SIMD2(1000, 1000), targetSize: SIMD2(1000, 1000))
        XCTAssertGreaterThan(bright.area, small.area)
        XCTAssertGreaterThan(stretched.area, small.area)
        let whole = try XCTUnwrap(extent([record(SIMD2(500, 500), size: 10)]))
            .pixelRect(refractAmount: 1, sceneSize: SIMD2(1000, 1000), targetSize: SIMD2(1000, 1000))
        XCTAssertEqual(whole, SceneSnapshotTracker.Rect(x: 0, y: 0, width: 1000, height: 1000))
    }

    /// No finite particle: no extent, so the caller copies the whole scene.
    func testNoFiniteParticleHasNoExtent() {
        XCTAssertNil(extent([]))
        XCTAssertNil(extent([record(SIMD2(.nan, 0), size: 10)]))
    }
}
