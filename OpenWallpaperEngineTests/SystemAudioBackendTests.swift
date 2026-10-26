import CoreAudio
import XCTest
@testable import OpenWallpaperEngine

/// Choosing between the Core Audio process tap and the ScreenCaptureKit fallback.
final class SystemAudioBackendTests: XCTestCase {
    private func candidates(tapSupported: Bool = true,
                            tap: SystemAudioRecordingPermission.Status,
                            screenRecording: Bool) -> [SystemAudioBackend] {
        SystemAudioBackend.candidates(tapSupported: tapSupported, tapPermission: tap,
                                      screenRecordingGranted: screenRecording)
    }

    func testGrantedTapIsTriedFirstWithScreenCaptureAsFallback() {
        XCTAssertEqual(candidates(tap: .authorized, screenRecording: true), [.processTap, .screenCapture])
        XCTAssertEqual(candidates(tap: .authorized, screenRecording: false), [.processTap])
    }

    func testTapNeverStartsWithoutItsPermission() {
        // Starting it then would show the prompt (not asked yet) or deliver silence (denied).
        XCTAssertEqual(candidates(tap: .notDetermined, screenRecording: false), [])
        XCTAssertEqual(candidates(tap: .denied, screenRecording: false), [])
        XCTAssertEqual(candidates(tap: .denied, screenRecording: true), [.screenCapture])
        XCTAssertEqual(candidates(tap: .notDetermined, screenRecording: true), [.screenCapture])
    }

    func testUnreadableTapPermissionStillTriesTheTap() {
        XCTAssertEqual(candidates(tap: .unknown, screenRecording: false), [.processTap])
        XCTAssertEqual(candidates(tap: .unknown, screenRecording: true), [.processTap, .screenCapture])
    }

    func testBeforeMacOS14_2OnlyScreenCaptureIsUsed() {
        XCTAssertEqual(candidates(tapSupported: false, tap: .authorized, screenRecording: true), [.screenCapture])
        XCTAssertEqual(candidates(tapSupported: false, tap: .authorized, screenRecording: false), [])
    }

    func testRequestedPermissionFollowsTheBackend() {
        XCTAssertEqual(SystemAudioBackend.requestedPermission(tapSupported: true), .processTap)
        XCTAssertEqual(SystemAudioBackend.requestedPermission(tapSupported: false), .screenCapture)
    }

    func testPreflightResultsMapToStatuses() {
        XCTAssertEqual(SystemAudioRecordingPermission.status(preflightResult: 0), .authorized)
        XCTAssertEqual(SystemAudioRecordingPermission.status(preflightResult: 1), .denied)
        XCTAssertEqual(SystemAudioRecordingPermission.status(preflightResult: 2), .notDetermined)
    }

    // MARK: Aggregate device

    func testAggregateDeviceIsPrivateAndCarriesTheTap() {
        let description = ProcessTapAudioCapture.aggregateDescription(tapUID: "tap-uid")
        XCTAssertEqual(description[kAudioAggregateDeviceIsPrivateKey] as? Bool, true)
        XCTAssertEqual(description[kAudioAggregateDeviceTapAutoStartKey] as? Bool, true)
        let taps = description[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        XCTAssertEqual(taps?.count, 1)
        XCTAssertEqual(taps?.first?[kAudioSubTapUIDKey] as? String, "tap-uid")
        let unique = ProcessTapAudioCapture.aggregateDescription(tapUID: "tap-uid")
        XCTAssertNotEqual(description[kAudioAggregateDeviceUIDKey] as? String,
                          unique[kAudioAggregateDeviceUIDKey] as? String, "each capture gets its own device")
    }
}
