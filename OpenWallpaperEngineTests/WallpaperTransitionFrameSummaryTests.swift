import XCTest
@testable import OpenWallpaperEngine

/// The debug summary of a transition's frames: intervals, refreshes without a new frame and
/// main-thread stalls.
final class WallpaperTransitionFrameSummaryTests: XCTestCase {
    func testIntervalsAndDroppedRefreshes() {
        let refresh = 1.0 / 100
        // Four refreshes on time, then one that took three refreshes.
        let presents = [0, 0.01, 0.02, 0.03, 0.04, 0.07]
        let summary = WallpaperTransitionFrameSummary(presents: presents, stalls: [0.05, 0.02], refreshInterval: refresh)
        XCTAssertEqual(summary.frames, 6)
        XCTAssertEqual(summary.span, 0.07, accuracy: 1e-9)
        XCTAssertEqual(summary.p50, 0.01, accuracy: 1e-9)
        XCTAssertEqual(summary.maxInterval, 0.03, accuracy: 1e-9)
        XCTAssertEqual(summary.p95, 0.03, accuracy: 1e-9)
        XCTAssertEqual(summary.dropped, 2, "an interval of three refreshes drops two")
        XCTAssertEqual(summary.stallCount, 2)
        XCTAssertEqual(summary.stallMax, 0.05, accuracy: 1e-9)
        XCTAssertEqual(summary.stallTotal, 0.07, accuracy: 1e-9)
    }

    func testNothingMeasured() {
        let summary = WallpaperTransitionFrameSummary(presents: [], stalls: [], refreshInterval: 1.0 / 60)
        XCTAssertEqual(summary.frames, 0)
        XCTAssertEqual(summary.p95, 0)
        XCTAssertEqual(summary.dropped, 0)
    }

    func testNearestRankPercentile() {
        let values = (1...20).map(Double.init)
        XCTAssertEqual(WallpaperTransitionFrameSummary.percentile(values, 0.5), 10)
        XCTAssertEqual(WallpaperTransitionFrameSummary.percentile(values, 0.95), 19)
        XCTAssertEqual(WallpaperTransitionFrameSummary.percentile(values, 1), 20)
    }
}
