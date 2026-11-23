import XCTest
import simd
@testable import OpenWallpaperEngine

/// Parallax on or off applies from the next frame without rebuilding the content: a user property
/// bound to `general.cameraparallax…` moves the scene's binding revision only (the content
/// revision, `metalRevision`, stays), and the parallax eases in and out instead of jumping.
final class LiveParallaxTests: XCTestCase {
    private let size = SIMD2<Float>(1920, 1080)

    private func update(_ general: String, _ keys: [String]) throws -> SceneBindingUpdate {
        let document = try JSONDecoder().decode(SceneJSON.self, from: Data(#"{"general": {\#(general)}, "objects": []}"#.utf8))
        let table = UserPropertyBindingTable()
        table.record(.scene, json: document)
        return SceneBindingUpdate(keys: keys, table: table)
    }

    func testBoundParallaxDoesNotRebuildTheContent() throws {
        let toggle = try update(#""cameraparallax": {"user": "parallax", "value": false}"#, ["parallax"])
        XCTAssertEqual(toggle.impact, .none, "no content rebuild, so metalRevision stays")
        XCTAssertEqual(toggle.owners, [.scene], "the renderer resolves the camera again")
        for field in ["cameraparallaxamount", "cameraparallaxdelay", "cameraparallaxmouseinfluence"] {
            XCTAssertEqual(try update(#""\#(field)": {"user": "p", "value": 0.5}"#, ["p"]).impact, .none, field)
        }
        // Other scene-wide bindings are still built into the content.
        XCTAssertEqual(try update(#""bloom": {"user": "b", "value": true}"#, ["b"]).impact, .rebuildContent)
    }

    func testAppParallaxKeysDoNotRebuildTheContent() {
        XCTAssertEqual(SceneChangeImpact.aggregate(["_owe_effect_enabled_parallax", "_owe_effect_parallax_amount"]), .none)
    }

    func testParallaxEasesInOnTheNextFrame() {
        var parallax = SceneCameraParallax(sceneSize: size, enabled: false)
        parallax.update(cursor: SIMD2(1, 1), eye: .zero, sceneSize: size, influence: 1, delay: 0, deltaTime: 1 / 60)
        XCTAssertFalse(parallax.isActive)
        XCTAssertEqual(parallax.offset(rootOrigin: .zero, rootDepth: SIMD2(1, 1), amount: 1), .zero)
        XCTAssertEqual(parallax.shaderPosition(sceneSize: size), SIMD2(0.5, 0.5))

        parallax.ease(enabled: true, deltaTime: 1 / 60)
        XCTAssertTrue(parallax.isActive, "applies on the next frame")
        let first = parallax.offset(rootOrigin: .zero, rootDepth: SIMD2(1, 1), amount: 1)
        let full = -size
        XCTAssertLessThan(simd_length(first), simd_length(full), "eases in rather than jumping")
        XCTAssertGreaterThan(simd_length(first), 0)

        for _ in 0..<120 { parallax.ease(enabled: true, deltaTime: 1 / 60) }
        XCTAssertEqual(parallax.weight, 1, "fully on is WE's parallax exactly")
        XCTAssertEqual(parallax.offset(rootOrigin: .zero, rootDepth: SIMD2(1, 1), amount: 1), full)
        XCTAssertEqual(parallax.shaderPosition(sceneSize: size), SIMD2(1, 1))
    }

    func testParallaxEasesOutAndStops() {
        var parallax = SceneCameraParallax(sceneSize: size)
        parallax.update(cursor: SIMD2(1, 1), eye: .zero, sceneSize: size, influence: 1, delay: 0, deltaTime: 1 / 60)
        parallax.ease(enabled: false, deltaTime: 1 / 60)
        XCTAssertTrue(parallax.isActive)
        XCTAssertGreaterThan(parallax.weight, 0.5, "eases out rather than snapping back")
        for _ in 0..<120 { parallax.ease(enabled: false, deltaTime: 1 / 60) }
        XCTAssertFalse(parallax.isActive, "stops once eased out")
        XCTAssertEqual(parallax.offset(rootOrigin: .zero, rootDepth: SIMD2(1, 1), amount: 1), .zero)
    }

    /// Parallax the scene doesn't have of its own (User Adjustments) zooms the scene just enough
    /// that a scene-sized layer still covers the screen with the cursor in any corner.
    func testAddedParallaxZoomsToHideTheEdges() {
        let amount: Float = 0.5, influence: Float = 0.5
        let factor = SceneCameraParallax.coverZoom(reach: amount * influence, authoredReach: 0)
        XCTAssertEqual(factor, 1 / (1 - amount * influence), accuracy: 1e-6)
        let zoom = SceneOrthographicZoom(factor: factor, sceneSize: size)
        var parallax = SceneCameraParallax(sceneSize: size)
        for corner in [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)] {
            parallax.update(cursor: corner, eye: .zero, sceneSize: size, influence: influence, delay: 0, deltaTime: 1 / 60)
            let offset = zoom.plane.linear * parallax.offset(rootOrigin: size / 2, rootDepth: SIMD2(1, 1), amount: amount)
            let low = zoom.plane.apply(.zero) + offset, high = zoom.plane.apply(size) + offset
            XCTAssertLessThanOrEqual(low.x, 1e-2, "\(corner)")
            XCTAssertLessThanOrEqual(low.y, 1e-2, "\(corner)")
            XCTAssertGreaterThanOrEqual(high.x, size.x - 1e-2, "\(corner)")
            XCTAssertGreaterThanOrEqual(high.y, size.y - 1e-2, "\(corner)")
            XCTAssertNotEqual(offset.x, 0, "moves sideways")
            XCTAssertNotEqual(offset.y, 0, "moves up and down")
        }
    }

    /// A scene's own parallax is drawn as WE draws it; only the app's amount above 1 zooms.
    func testOwnParallaxZoomsOnlyForTheExtraAmount() {
        XCTAssertEqual(SceneCameraParallax.coverZoom(reach: 0.25, authoredReach: 0.25), 1)
        XCTAssertEqual(SceneCameraParallax.coverZoom(reach: 0.1, authoredReach: 0.25), 1)
        XCTAssertEqual(SceneCameraParallax.coverZoom(reach: 0.5, authoredReach: 0.25), 1 / 0.75, accuracy: 1e-6)
        XCTAssertEqual(SceneCameraParallax.coverZoom(reach: 0, authoredReach: 0), 1, "off or eased out")
        XCTAssertEqual(SceneCameraParallax.coverZoom(reach: 5, authoredReach: 0), SceneCameraParallax.maximumCoverZoom)
    }

    func testCameraRigCarriesTheCoverZoom() {
        var input = SceneCameraRigInput(sceneSize: size, aspect: size.x / size.y, time: 0, deltaTime: 0)
        input.parallaxCoverZoom = 1.25
        XCTAssertEqual(SceneOrthographicCameraRig(zoom: 2).frameCamera(input).drawnSpace.factor, 2.5, accuracy: 1e-6)
    }
}
