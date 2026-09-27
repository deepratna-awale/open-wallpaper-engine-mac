import XCTest
@testable import OpenWallpaperEngine

/// The playlist duration slider's label and steps.
final class PlaylistDurationFormatTests: XCTestCase {
    func testLabels() {
        let expected: [(Double, String)] = [
            (5, "5s"), (45, "45s"), (60, "1m"), (75, "1m15s"), (90, "1m30s"),
            (135, "2m15s"), (3599, "59m59s"), (3600, "1h"),
        ]
        for (seconds, label) in expected {
            XCTAssertEqual(PlaylistDurationFormat.label(seconds), label, "\(seconds)")
        }
    }

    func testSnapsToFiveSecondsBelowAMinuteAndFifteenFromIt() {
        XCTAssertEqual(PlaylistDurationFormat.snapped(5), 5)
        XCTAssertEqual(PlaylistDurationFormat.snapped(47), 45)
        XCTAssertEqual(PlaylistDurationFormat.snapped(58), 60)
        XCTAssertEqual(PlaylistDurationFormat.snapped(68), 75)
        XCTAssertEqual(PlaylistDurationFormat.snapped(135), 135)
        XCTAssertEqual(PlaylistDurationFormat.snapped(3599), 3600)
        XCTAssertEqual(PlaylistDurationFormat.snapped(2), 5)
    }
}
