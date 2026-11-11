import CoreAudio
import XCTest
@testable import OpenWallpaperEngine

@MainActor
final class AudioCapturePolicyTests: XCTestCase {
    // MARK: Permission gate

    func testMissingPermissionAlertsOncePerLaunch() {
        let gate = AudioCapturePermissionGate(preflight: { false }, isAlertDismissed: { false })
        XCTAssertTrue(gate.shouldAlertMissingPermission())
        XCTAssertFalse(gate.shouldAlertMissingPermission())
        XCTAssertFalse(gate.shouldAlertMissingPermission())
    }

    func testDismissedOrGrantedPermissionNeverAlerts() {
        XCTAssertFalse(AudioCapturePermissionGate(preflight: { false }, isAlertDismissed: { true })
            .shouldAlertMissingPermission())
        XCTAssertFalse(AudioCapturePermissionGate(preflight: { true }, isAlertDismissed: { false })
            .shouldAlertMissingPermission())
    }

    func testGrantChangeIsReportedOnce() {
        var granted = false
        let gate = AudioCapturePermissionGate(preflight: { granted }, isAlertDismissed: { false })
        XCTAssertFalse(gate.canCapture())
        XCTAssertFalse(gate.becameGranted())
        granted = true
        XCTAssertTrue(gate.becameGranted())
        XCTAssertFalse(gate.becameGranted())
    }

    // MARK: Restart scheduler

    private final class FakeTimers {
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
        @MainActor func fireAll() {
            let due = pending
            pending = []
            due.forEach { $0.work() }
        }
    }

    /// The scheduler's clock; tests move it by hand.
    private var uptime: TimeInterval = 0

    private func makeScheduler(maxFailures: Int = 3) -> (CaptureRestartScheduler, FakeTimers, () -> Int) {
        let timers = FakeTimers()
        var starts = 0
        let scheduler = CaptureRestartScheduler(
            debounce: 1.5, baseBackoff: 2, maxFailures: maxFailures,
            stableInterval: 10, rapidTolerance: 2, maxRapidDelay: 60,
            now: { [unowned self] in self.uptime },
            schedule: { delay, work in timers.pending.append((delay, work)) },
            start: { starts += 1 })
        return (scheduler, timers, { starts })
    }

    func testBurstOfRequestsIsDebouncedIntoOneStart() {
        let (scheduler, timers, starts) = makeScheduler()
        for _ in 0..<5 { scheduler.requestRestart() }
        XCTAssertEqual(timers.pending.map(\.delay), Array(repeating: 1.5, count: 5))
        timers.fireAll()
        XCTAssertEqual(starts(), 1)
    }

    func testRequestWhileInFlightRunsOnceAfterward() {
        let (scheduler, timers, starts) = makeScheduler()
        scheduler.requestRestart()
        timers.fireAll()
        scheduler.requestRestart()
        scheduler.requestRestart()
        timers.fireAll()
        XCTAssertEqual(starts(), 1, "never more than one start in flight")
        scheduler.finished(success: true)
        timers.fireAll()
        XCTAssertEqual(starts(), 2)
    }

    func testFailuresBackOffExponentiallyThenGiveUpOnce() {
        let (scheduler, timers, starts) = makeScheduler(maxFailures: 3)
        scheduler.requestRestart()
        timers.fireAll()
        XCTAssertFalse(scheduler.finished(success: false))
        XCTAssertEqual(timers.pending.map(\.delay), [2])
        timers.fireAll()
        XCTAssertFalse(scheduler.finished(success: false))
        XCTAssertEqual(timers.pending.map(\.delay), [4])
        timers.fireAll()
        XCTAssertTrue(scheduler.finished(success: false))
        XCTAssertTrue(timers.pending.isEmpty)
        XCTAssertEqual(starts(), 3)

        scheduler.requestRestart()
        timers.fireAll()
        XCTAssertEqual(starts(), 3, "no restarts after giving up")

        scheduler.reset()
        scheduler.requestRestart()
        timers.fireAll()
        XCTAssertEqual(starts(), 4)
    }

    func testSuccessClearsFailureCount() {
        let (scheduler, timers, _) = makeScheduler()
        scheduler.requestRestart()
        timers.fireAll()
        scheduler.finished(success: false)
        timers.fireAll()
        scheduler.finished(success: true)
        XCTAssertEqual(scheduler.consecutiveFailures, 0)
        XCTAssertTrue(timers.pending.isEmpty)
    }

    // MARK: Rapid restarts

    /// One capture: a restart request `afterRunning` seconds after the last start, then a start
    /// that succeeds. Returns the delay the restart was scheduled with and what the request returned.
    private func restart(_ scheduler: CaptureRestartScheduler, _ timers: FakeTimers,
                         afterRunning seconds: TimeInterval) -> (delay: TimeInterval?, slowed: TimeInterval?) {
        uptime += seconds
        let slowed = scheduler.requestRestart()
        let delay = timers.pending.last?.delay
        timers.fireAll()
        scheduler.finished(success: true)
        return (delay, slowed)
    }

    func testCapturesRestartedRightAfterStartingBackOff() {
        let (scheduler, timers, starts) = makeScheduler()
        XCTAssertEqual(restart(scheduler, timers, afterRunning: 0).delay, 1.5, "the first start")
        // Two rapid restarts are tolerated (a device switch right after a start), then each waits
        // twice as long, up to the cap.
        var delays: [TimeInterval?] = []
        var slowed: [TimeInterval?] = []
        for _ in 0..<9 {
            let result = restart(scheduler, timers, afterRunning: 0.3)
            delays.append(result.delay)
            slowed.append(result.slowed)
        }
        XCTAssertEqual(delays, [1.5, 1.5, 3, 6, 12, 24, 48, 60, 60])
        XCTAssertEqual(slowed, [nil, nil, 3, 6, 12, 24, 48, 60, 60])
        XCTAssertEqual(starts(), 10)
    }

    func testBurstOfRequestsCountsOneRapidRestart() {
        let (scheduler, timers, _) = makeScheduler()
        _ = restart(scheduler, timers, afterRunning: 0)
        for _ in 0..<5 { scheduler.requestRestart() }
        XCTAssertEqual(scheduler.rapidRestarts, 1)
        XCTAssertEqual(timers.pending.map(\.delay), Array(repeating: 1.5, count: 5))
    }

    func testCaptureThatRunsLongEnoughClearsRapidRestarts() {
        let (scheduler, timers, _) = makeScheduler()
        _ = restart(scheduler, timers, afterRunning: 0)
        for _ in 0..<4 { _ = restart(scheduler, timers, afterRunning: 0.3) }
        XCTAssertEqual(scheduler.rapidRestarts, 4)
        XCTAssertEqual(scheduler.restartDelay, 6)
        let result = restart(scheduler, timers, afterRunning: 10)
        XCTAssertEqual(result.delay, 1.5)
        XCTAssertNil(result.slowed)
        XCTAssertEqual(scheduler.rapidRestarts, 0)
    }

    func testResetClearsRapidRestarts() {
        let (scheduler, timers, _) = makeScheduler()
        _ = restart(scheduler, timers, afterRunning: 0)
        for _ in 0..<4 { _ = restart(scheduler, timers, afterRunning: 0.3) }
        scheduler.reset()
        XCTAssertEqual(scheduler.rapidRestarts, 0)
        XCTAssertEqual(restart(scheduler, timers, afterRunning: 0.3).delay, 1.5)
        XCTAssertEqual(scheduler.rapidRestarts, 0, "the stopped capture isn't counted")
    }

    func testFailedStartIsNotARapidRestart() {
        let (scheduler, timers, _) = makeScheduler()
        scheduler.requestRestart()
        timers.fireAll()
        scheduler.finished(success: false)
        timers.fireAll()
        scheduler.finished(success: false)
        scheduler.requestRestart()
        XCTAssertEqual(scheduler.rapidRestarts, 0)
    }

    // MARK: Process tap notifications

    func testTapNotificationWithoutAChangeIsNotAnInterruption() {
        XCTAssertFalse(ProcessTapAudioCapture.isInterruption(atStart: AudioObjectID(77), now: AudioObjectID(77)))
        XCTAssertTrue(ProcessTapAudioCapture.isInterruption(atStart: AudioObjectID(77), now: AudioObjectID(91)))
        XCTAssertFalse(ProcessTapAudioCapture.isInterruption(atStart: Float64(48_000), now: Float64(48_000)))
        XCTAssertTrue(ProcessTapAudioCapture.isInterruption(atStart: Float64(48_000), now: Float64(44_100)))
        // The object is gone: its value can't be read any more.
        XCTAssertTrue(ProcessTapAudioCapture.isInterruption(atStart: UInt32(1), now: nil))
        XCTAssertFalse(ProcessTapAudioCapture.isInterruption(atStart: UInt32?.none, now: nil))
    }

    func testTapFormatComparesWhatTheConverterUses() {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
            mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let atStart = ProcessTapAudioCapture.StreamFormat(description)
        XCTAssertFalse(ProcessTapAudioCapture.isInterruption(atStart: atStart, now: ProcessTapAudioCapture.StreamFormat(description)))
        description.mSampleRate = 24_000
        XCTAssertTrue(ProcessTapAudioCapture.isInterruption(atStart: atStart, now: ProcessTapAudioCapture.StreamFormat(description)))
        description.mSampleRate = 48_000
        description.mChannelsPerFrame = 1
        XCTAssertTrue(ProcessTapAudioCapture.isInterruption(atStart: atStart, now: ProcessTapAudioCapture.StreamFormat(description)))
    }
}
