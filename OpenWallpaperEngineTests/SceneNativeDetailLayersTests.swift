import XCTest
import simd
@testable import OpenWallpaperEngine

/// Under Render Resolution "Display" the scene is drawn at the display's points and scaled up to its
/// backing pixels; text and the media artwork whose pixels nothing after them reads or covers are
/// drawn over the output after that instead (`SceneNativeDetailLayers`), at its backing pixels.
final class SceneNativeDetailLayersTests: XCTestCase {
    private typealias Rect = SceneSnapshotTracker.Rect
    private typealias Item = SceneNativeDetailLayers.Item

    private func layer(_ index: Int, _ rect: Rect?, readsScene: Bool = false, candidate: Bool = false) -> Item {
        .layer(index: index, bounds: rect, readsScene: readsScene, candidate: candidate)
    }

    // MARK: - Eligibility

    func testATopmostCandidateIsPromoted() {
        let items = [layer(0, Rect(x: 0, y: 0, width: 100, height: 100)),
                     layer(1, Rect(x: 10, y: 10, width: 20, height: 10), candidate: true)]
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items), [1])
    }

    func testALaterLayerOverItKeepsItInTheScenePass() {
        let items = [layer(0, Rect(x: 10, y: 10, width: 20, height: 10), candidate: true),
                     layer(1, Rect(x: 25, y: 15, width: 20, height: 20))]
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items), [])
    }

    func testALaterLayerTouchingItsUpscaleFilterKeepsIt() {
        // One scene-target pixel apart: the upscale's filter mixes them.
        let items = [layer(0, Rect(x: 10, y: 10, width: 20, height: 10), candidate: true),
                     layer(1, Rect(x: 31, y: 10, width: 5, height: 5))]
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items), [])
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items, padding: 0), [0])
    }

    func testALaterLayerElsewhereDoesNotBlockIt() {
        let items = [layer(0, Rect(x: 10, y: 10, width: 20, height: 10), candidate: true),
                     layer(1, Rect(x: 200, y: 200, width: 20, height: 20))]
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items), [0])
    }

    func testALaterPromotedLayerKeepsTheOrder() {
        // Both draw after the composite, in this order: overlapping is fine.
        let items = [layer(0, Rect(x: 10, y: 10, width: 20, height: 10), candidate: true),
                     layer(1, Rect(x: 15, y: 12, width: 20, height: 10), candidate: true)]
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items), [0, 1])
    }

    func testALaterReaderOfTheSceneKeepsEverythingBeforeIt() {
        let items = [layer(0, Rect(x: 10, y: 10, width: 20, height: 10), candidate: true),
                     layer(1, Rect(x: 300, y: 300, width: 5, height: 5), readsScene: true),
                     layer(2, Rect(x: 50, y: 50, width: 5, height: 5), candidate: true)]
        XCTAssertEqual(SceneNativeDetailLayers.promoted(items), [2])
    }

    func testLaterModelsParticlesAndPlacedLayersCoverEverything() {
        let rect = Rect(x: 10, y: 10, width: 20, height: 10)
        XCTAssertEqual(SceneNativeDetailLayers.promoted([layer(0, rect, candidate: true), .unbounded]), [])
        XCTAssertEqual(SceneNativeDetailLayers.promoted([layer(0, rect, candidate: true), layer(1, nil)]), [])
        XCTAssertEqual(SceneNativeDetailLayers.promoted([.unbounded, layer(0, rect, candidate: true)]), [0])
    }

    func testOnlyDetailLayersFreeOfTheSceneAreCandidates() {
        func candidate(text: Bool = true, media: Bool = false, visible: Bool = true, source: Bool = false,
                       effects: Bool = false, reads: Bool = false, puppet: Bool = false, placed: Bool = false) -> Bool {
            SceneNativeDetailLayers.isCandidate(isText: text, isMediaImage: media, visible: visible, compositeSource: source,
                                                hasLayerEffects: effects, readsScene: reads, isPuppet: puppet, placed3D: placed)
        }
        XCTAssertTrue(candidate())
        XCTAssertTrue(candidate(text: false, media: true), "the album art")
        XCTAssertFalse(candidate(text: false), "a plain image")
        XCTAssertFalse(candidate(visible: false), "hidden (the lock picture's clock)")
        XCTAssertFalse(candidate(source: true), "sampled by a model or another layer")
        XCTAssertFalse(candidate(effects: true))
        XCTAssertFalse(candidate(reads: true))
        XCTAssertFalse(candidate(puppet: true))
        XCTAssertFalse(candidate(placed: true))
    }

    func testOnlyAnOutputWithMorePixelsGains() {
        XCTAssertTrue(SceneNativeDetailLayers.gainsDetail(scenePixelsPerUnit: 1, outputPixelsPerUnit: 2), "Display at 2×")
        XCTAssertTrue(SceneNativeDetailLayers.gainsDetail(scenePixelsPerUnit: 1.5, outputPixelsPerUnit: 2), "a render scale")
        XCTAssertFalse(SceneNativeDetailLayers.gainsDetail(scenePixelsPerUnit: 2, outputPixelsPerUnit: 2), "Retina")
        XCTAssertFalse(SceneNativeDetailLayers.gainsDetail(scenePixelsPerUnit: 2.125, outputPixelsPerUnit: 2))
    }

    func testThePlacedViewportIsTheCompositesRect() {
        let fit = SceneNativeDetailLayers.placedViewport(center: SIMD2(1000, 500), size: SIMD2(1600, 900),
                                                         outputSize: SIMD2(2000, 1000))
        XCTAssertEqual(fit.origin, SIMD2(200, 50))
        XCTAssertEqual(fit.size, SIMD2(1600, 900))
        let fill = SceneNativeDetailLayers.placedViewport(center: SIMD2(500, 500), size: SIMD2(1200, 1000),
                                                          outputSize: SIMD2(1000, 1000))
        XCTAssertEqual(fill.origin, SIMD2(-100, 0))
    }

    // MARK: - Frames

    /// Rows and columns in 1× pixels of the 480 × 272 fixtures, row 0 at the top.
    private let textBox = (x: 110..<480, y: 40..<150)
    private var directory: URL { Fixtures.url("Scenes/text-retina") }

    private func render(_ file: String, _ resolution: GSRenderResolution, promotes: Bool = true) throws -> FixtureSceneRenderer.Frame {
        var settings = SceneRenderSettings()
        settings.renderResolution = resolution
        var renderer = FixtureSceneRenderer(directory: directory, sceneFile: file, pixelsPerPoint: 2, settings: settings)
        renderer.configure = { $0.promotesDetailLayers = promotes }
        return try renderer.render()
    }

    private func inTextBox(_ x: Int, _ y: Int, scale: Int, margin: Int = 0) -> Bool {
        (textBox.x.lowerBound * scale - margin..<textBox.x.upperBound * scale + margin).contains(x)
            && (textBox.y.lowerBound * scale - margin..<textBox.y.upperBound * scale + margin).contains(y)
    }

    func testTextOnTopAtDisplayIsAsSharpAsRetinaAndTheRestIsDisplay() throws {
        _ = try Fixtures.assets()
        let display = try render("layered.json", .display)
        let retina = try render("layered.json", .retina)
        let plain = try render("layered.json", .display, promotes: false)
        try SceneRegionTransformTests.write(display, name: "native-detail-display")
        XCTAssertEqual(display.promoted, 1, "the text is drawn at the backing pixels")
        XCTAssertEqual(plain.promoted, 0)
        XCTAssertEqual(display.width, retina.width)
        XCTAssertEqual(display.height, retina.height)
        XCTAssertEqual(plain.width * 2, display.width, "the plain Display frame is the scene's points")

        // Within the text's bounds: Retina's pixels, its blend over the square beneath included. The
        // square's sides there come from the upscaled scene, a column or two of filtered edge.
        var compared = 0, differing = 0, ink = 0
        for y in textBox.y.lowerBound * 2..<textBox.y.upperBound * 2 {
            for x in textBox.x.lowerBound * 2..<min(textBox.x.upperBound * 2, display.width) {
                let a = display.pixel(x, y), b = retina.pixel(x, y)
                let delta = a &- b
                if max(abs(delta.x), abs(delta.y), abs(delta.z)) > 6 { differing += 1 }
                if a.x > 150, a.y > 150, a.z < 120 { ink += 1 }
                compared += 1
            }
        }
        XCTAssertGreaterThan(ink, 400, "the yellow text is drawn over the square")
        XCTAssertLessThan(Float(differing) / Float(compared), 0.02, "\(differing) of \(compared) differ from Retina")

        // Elsewhere: the plain Display frame, scaled up.
        compared = 0
        differing = 0
        for y in 1..<(plain.height - 1) {
            for x in 1..<(plain.width - 1) where !inTextBox(x, y, scale: 1, margin: 2) {
                let centre = plain.pixel(x, y)
                let uniform = [(-1, 0), (1, 0), (0, -1), (0, 1)].allSatisfy { plain.pixel(x + $0.0, y + $0.1) == centre }
                guard uniform else { continue }
                var sum = SIMD4<Int>(repeating: 0)
                for dy in 0..<2 { for dx in 0..<2 { sum &+= display.pixel(x * 2 + dx, y * 2 + dy) } }
                let delta = sum / 4 &- centre
                if max(abs(delta.x), abs(delta.y), abs(delta.z)) > 2 { differing += 1 }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 50_000)
        XCTAssertEqual(differing, 0, "outside the text the frame is the plain Display frame")
    }

    func testTextWithALayerAboveItStaysInTheScenePass() throws {
        _ = try Fixtures.assets()
        let display = try render("covered.json", .display)
        XCTAssertEqual(display.promoted, 0)
        let plain = try render("covered.json", .display, promotes: false)
        XCTAssertEqual(display.width, plain.width, "nothing promoted: the frame is the plain Display one")
        XCTAssertEqual(display.pixels, plain.pixels)
    }

    func testTheAlbumArtIsPromoted() throws {
        _ = try Fixtures.assets()
        let display = try render("album-art.json", .display)
        XCTAssertEqual(display.promoted, 1)
        // Without a media session it shows its own (white) image, at the same place as at Retina.
        let retina = try render("album-art.json", .retina)
        XCTAssertEqual(display.width, retina.width)
        var differing = 0
        for y in 0..<display.height { for x in 0..<display.width {
            let delta = display.pixel(x, y) &- retina.pixel(x, y)
            if max(abs(delta.x), abs(delta.y), abs(delta.z)) > 6 { differing += 1 }
        } }
        // The turned square's edges come from the upscaled scene.
        XCTAssertLessThan(differing, 600)
    }

    func testRetinaPromotesNothing() throws {
        _ = try Fixtures.assets()
        XCTAssertEqual(try render("layered.json", .retina).promoted, 0)
    }
}
