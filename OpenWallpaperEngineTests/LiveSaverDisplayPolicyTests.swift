import XCTest
@testable import OpenWallpaperEngine

/// The savers' choice between live frames and the video, and how fast a view ticks.
final class LiveSaverDisplayPolicyTests: XCTestCase {
    func testGoesLiveAfterSteadyFramesAndFallsBackWhenTheyStop() {
        var fallback = LiveFrameFallback()
        fallback.frameArrived(at: 0)
        fallback.frameArrived(at: 0.03)
        XCTAssertEqual(fallback.update(at: 0.04), .fallback)
        fallback.frameArrived(at: 0.06)
        XCTAssertEqual(fallback.update(at: 0.07), .live)
        XCTAssertEqual(fallback.update(at: 0.06 + LiveFrameFallback.staleAfter), .live)
        XCTAssertEqual(fallback.update(at: 0.07 + LiveFrameFallback.staleAfter), .fallback)
    }

    func testAFrameAfterAGapStartsTheCountAgain() {
        var fallback = LiveFrameFallback()
        fallback.frameArrived(at: 0)
        fallback.frameArrived(at: 0.1)
        fallback.frameArrived(at: 1)
        XCTAssertEqual(fallback.update(at: 1), .fallback)
        fallback.frameArrived(at: 1.1)
        fallback.frameArrived(at: 1.2)
        XCTAssertEqual(fallback.update(at: 1.2), .live)
    }

    func testAParkedViewTicksSlowerWithoutFallingBack() {
        var fallback = LiveFrameFallback()
        fallback.tickInterval = 1
        for time in [0.0, 1, 2] { fallback.frameArrived(at: time) }
        XCTAssertEqual(fallback.update(at: 2.9), .live, "frames a second apart are fresh at one tick a second")
        XCTAssertEqual(fallback.update(at: 4.1), .fallback)
    }

    func testResetFallsBackAtOnce() {
        var fallback = LiveFrameFallback()
        for time in [0.0, 0.01, 0.02] { fallback.frameArrived(at: time) }
        XCTAssertEqual(fallback.update(at: 0.02), .live)
        fallback.reset()
        XCTAssertEqual(fallback.mode, .fallback)
    }

    func testParksWithoutPresentedFrames() {
        var park = SaverParkPolicy(startedAt: 10)
        XCTAssertFalse(park.isParked(at: 10 + SaverParkPolicy.startGrace), "full rate while starting")
        XCTAssertTrue(park.isParked(at: 10.1 + SaverParkPolicy.startGrace), "never presented: a hidden host")
        XCTAssertEqual(park.rate(at: 20, fullRate: 60), SaverParkPolicy.parkedRate)
        park.presented(at: 20)
        XCTAssertEqual(park.rate(at: 21, fullRate: 60), 60)
        XCTAssertTrue(park.isParked(at: 20.1 + SaverParkPolicy.presentedGrace))
    }

    func testSmallViewsArePreviewsWhateverTheirFlag() {
        XCTAssertTrue(SaverParkPolicy.isPreview(flag: true, size: CGSize(width: 1920, height: 1080)))
        XCTAssertTrue(SaverParkPolicy.isPreview(flag: false, size: CGSize(width: 296, height: 184)))
        XCTAssertFalse(SaverParkPolicy.isPreview(flag: false, size: CGSize(width: 1512, height: 982)))
    }
}
