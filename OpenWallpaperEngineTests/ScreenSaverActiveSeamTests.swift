import XCTest
@testable import OpenWallpaperEngine

/// `ScreenSaverSeamFinder.searchActiveSeam` on synthetic luma frames (32×18, as `searchLuma`).
final class ScreenSaverActiveSeamTests: XCTestCase {
    private typealias Finder = ScreenSaverSeamFinder
    private static let pixels = 32 * 18

    /// A moving pattern at phase `phase` (radians), 0.3…0.7.
    private func pattern(_ phase: Double, brightness: Float = 1) -> [Float] {
        (0..<Self.pixels).map { pixel in
            brightness * Float(0.5 + 0.2 * sin(phase + Double(pixel) * 0.1))
        }
    }

    /// A small deterministic generator, so the noisy test is the same every run.
    private struct Noise {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24) - 0.5
        }
    }

    func testAFadeToBlackLoopsTheActivePart() throws {
        // 10 fps: 60 moving frames (period 25), a 10-frame fade, then 5 s of black.
        let active = 60, fade = 10
        var frames: [[Float]] = (0..<active).map { pattern(Double($0 % 25) * 2 * .pi / 25) }
        frames += (0..<fade).map { pattern(Double(active + $0) * 2 * .pi / 25, brightness: Float(fade - 1 - $0) / Float(fade)) }
        frames += Array(repeating: [Float](repeating: 0, count: Self.pixels), count: 50)

        let activity = Finder.activity(frames)
        let segment = try XCTUnwrap(Finder.activeSegment(activity: activity, blank: frames.map(Finder.isBlank), frameRate: 10))
        XCTAssertEqual(segment.lowerBound, 0)
        XCTAssertTrue((active...(active + fade)).contains(segment.upperBound), "the black tail is cut: \(segment)")

        let decision = try XCTUnwrap(Finder.searchActiveSeam(frames: frames, frameRate: 10, minimumSeconds: 2))
        XCTAssertEqual(decision.seam, .cut)
        XCTAssertEqual(decision.frames, 25, "the moving part's period, not the black tail")
        XCTAssertLessThanOrEqual(decision.start + decision.frames, active)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(decision.score), Finder.minimumSeamScore)
    }

    func testAShortIntroBeforeBlackDoesNotLoop() {
        // The Colorful Fluid case: ~40 moving frames at 30 fps, then black. Too short for a loop.
        var frames: [[Float]] = (0..<40).map { pattern(Double($0) * 0.37) }
        frames += Array(repeating: [Float](repeating: 0, count: Self.pixels), count: 300)
        XCTAssertNil(Finder.searchActiveSeam(frames: frames, frameRate: 30))
    }

    func testAStaticTailIsExcluded() throws {
        let active = 80
        var frames: [[Float]] = (0..<active).map { pattern(Double($0 % 20) * 2 * .pi / 20) }
        frames += Array(repeating: frames[active - 1], count: 60)
        let segment = try XCTUnwrap(Finder.activeSegment(activity: Finder.activity(frames),
                                                         blank: frames.map(Finder.isBlank), frameRate: 10))
        XCTAssertEqual(segment, 0..<active)
        let decision = try XCTUnwrap(Finder.searchActiveSeam(frames: frames, frameRate: 10, minimumSeconds: 2))
        XCTAssertLessThanOrEqual(decision.start + decision.frames, active, "the loop doesn't reach into the still tail")
        XCTAssertEqual(decision.frames, 20)
    }

    func testABriefPauseStaysInTheSegment() throws {
        // Half a second still in the middle (at 10 fps) is under `maximumDeadSeconds`.
        var frames: [[Float]] = (0..<40).map { pattern(Double($0) * 0.4) }
        frames += Array(repeating: frames[39], count: 5)
        frames += (40..<80).map { pattern(Double($0) * 0.4) }
        let segment = Finder.activeSegment(activity: Finder.activity(frames), blank: frames.map(Finder.isBlank), frameRate: 10)
        XCTAssertEqual(segment, 0..<frames.count)
    }

    func testAPeriodicSequenceFindsItsExactPeriod() throws {
        let period = 37
        let frames: [[Float]] = (0..<300).map { pattern(Double($0 % period) * 2 * .pi / Double(period)) }
        let decision = try XCTUnwrap(Finder.searchActiveSeam(frames: frames, frameRate: 30, minimumSeconds: 1))
        XCTAssertEqual(decision.frames, period)
        XCTAssertEqual(decision.start, 0)
        XCTAssertEqual(decision.seam, .cut)
        XCTAssertEqual(decision.score, .infinity)
    }

    func testANoisyAperiodicSequenceCrossfadesAboveTheThreshold() throws {
        var noise = Noise()
        // An incommensurate phase step plus grain: no frame matches another exactly.
        let frames: [[Float]] = (0..<400).map { index in
            pattern(Double(index) * 0.37).map { $0 + 0.04 * noise.next() }
        }
        let decision = try XCTUnwrap(Finder.searchActiveSeam(frames: frames, frameRate: 30, minimumSeconds: 2))
        guard case .crossfade(let fade) = decision.seam else { return XCTFail("a noisy seam fades: \(decision.seam)") }
        XCTAssertLessThanOrEqual(fade, Int(Finder.maximumCrossfadeSeconds * 30))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(decision.score), Finder.minimumSeamScore)
        XCTAssertLessThanOrEqual(decision.start + decision.frames + fade, frames.count)
    }

    func testAnAllBlackRecordingDoesNotLoop() {
        let frames = Array(repeating: [Float](repeating: 0, count: Self.pixels), count: 200)
        XCTAssertNil(Finder.searchActiveSeam(frames: frames, frameRate: 30, minimumSeconds: 1))
    }

    func testSeamScoreGrowsWithTheFade() {
        XCTAssertEqual(Finder.seamScore(psnr: 40, fade: 0), 40)
        XCTAssertEqual(Finder.seamScore(psnr: 40, fade: 9), 60, accuracy: 1e-9)
    }

    func testSearchLumaHalvesTheSignature() {
        let values = (0..<(64 * 36)).flatMap { _ in [Float(0.25), 0, 0] }
        let luma = ScreenSaverFrameSignature(values: values).searchLuma
        XCTAssertEqual(luma.count, 32 * 18)
        XCTAssertEqual(luma.first, 0.25)
    }
}
