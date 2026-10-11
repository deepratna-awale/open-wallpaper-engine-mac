import XCTest
@testable import OpenWallpaperEngine

/// When the app draws the screen saver live: only during a screen saver session in which an Open
/// Wallpaper Engine saver says it shows.
final class ScreenSaverLiveStateTests: XCTestCase {
    func testDrawsOnceASaverShowsDuringASession() {
        var state = ScreenSaverLiveState()
        XCTAssertFalse(state.handle(.didStart, at: 0), "another screen saver may be selected")
        XCTAssertFalse(state.isDrawing)
        XCTAssertTrue(state.handle(.saverAlive, at: 1))
        XCTAssertTrue(state.isDrawing)
        XCTAssertFalse(state.handle(.saverAlive, at: 2), "already drawing")
    }

    func testASaverOutsideASessionNeverStartsIt() {
        var state = ScreenSaverLiveState()
        XCTAssertFalse(state.handle(.saverAlive, at: 0))
        XCTAssertFalse(state.isDrawing, "a stacked view that missed willstop")
    }

    func testStopsOnWillStopDidStopAndUnlock() {
        for stop in [ScreenSaverLiveState.Event.willStop, .didStop, .screenUnlocked] {
            var state = ScreenSaverLiveState()
            state.handle(.didStart, at: 0)
            state.handle(.saverAlive, at: 0.5)
            XCTAssertTrue(state.handle(stop, at: 1), "\(stop)")
            XCTAssertFalse(state.isDrawing)
            XCTAssertFalse(state.handle(.saverAlive, at: 1.5), "the session is over (\(stop))")
        }
    }

    func testLockingKeepsDrawing() {
        var state = ScreenSaverLiveState()
        state.handle(.didStart, at: 0)
        state.handle(.saverAlive, at: 0.5)
        XCTAssertFalse(state.handle(.screenLocked, at: 1))
        XCTAssertTrue(state.isDrawing)
        XCTAssertTrue(state.isLocked)
    }

    func testStopsWhenTheSaverGoesQuietAndResumesWhenItReturns() {
        var state = ScreenSaverLiveState()
        state.handle(.didStart, at: 0)
        state.handle(.saverAlive, at: 1)
        XCTAssertFalse(state.handle(.tick, at: 1 + ScreenSaverLiveState.saverTimeout))
        XCTAssertTrue(state.handle(.tick, at: 1.1 + ScreenSaverLiveState.saverTimeout))
        XCTAssertFalse(state.isDrawing)
        XCTAssertTrue(state.screenSaverRuns)
        XCTAssertTrue(state.handle(.saverAlive, at: 10), "a host that came back")
    }
}
