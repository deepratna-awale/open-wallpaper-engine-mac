import XCTest
@testable import OpenWallpaperEngine

/// `DisplayPlaybackMonitor` over injected windows and displays: it evaluates the rules per display,
/// hands on only changes, and looks at the desktop on a timer only while a rule needs it.
@MainActor
final class DisplayPlaybackMonitorTests: XCTestCase {
    private final class Desktop {
        var windows: [DesktopWindow] = []
        var frontmost: pid_t?
        var audio = false
        var battery = false
        var windowReads = 0
        var evaluations = 0
        let displays = [
            DesktopDisplay(id: "1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                           visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055)),
            DesktopDisplay(id: "2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                           visibleFrame: CGRect(x: 1920, y: 25, width: 1920, height: 1055)),
        ]
    }

    private var desktop = Desktop()
    private var applied: [[String: DisplayPlayback]] = []
    private var monitor: DisplayPlaybackMonitor!

    override func setUp() {
        super.setUp()
        desktop = Desktop()
        applied = []
        let desktop = desktop
        let sources = DisplayPlaybackSources(
            windows: { desktop.windowReads += 1; return desktop.windows },
            displays: { desktop.evaluations += 1; return desktop.displays },
            frontmostPID: { desktop.frontmost },
            ownPID: 1,
            otherApplicationPlayingAudio: { desktop.audio },
            onBattery: { desktop.battery })
        monitor = DisplayPlaybackMonitor(sources: sources) { [weak self] in self?.applied.append($0) }
    }

    override func tearDown() {
        monitor.stop()
        monitor = nil
        super.tearDown()
    }

    func testAFocusedAppOnTheRightDisplayPausesOnlyThatDisplay() {
        monitor.setRules(PlaybackRules(focused: .pause))
        XCTAssertEqual(applied.last, ["1": .run, "2": .run])
        desktop.frontmost = 100
        desktop.windows = [DesktopWindow(ownerPID: 100, bounds: CGRect(x: 2200, y: 200, width: 800, height: 600))]
        monitor.evaluate()
        XCTAssertEqual(applied.last, ["1": .run, "2": .pause])
        // The window moves to the left display.
        desktop.windows[0].bounds.origin.x = 200
        monitor.evaluate()
        XCTAssertEqual(applied.last, ["1": .pause, "2": .run])
    }

    func testUnchangedStatesAreNotHandedOnAgain() {
        monitor.setRules(PlaybackRules(focused: .pause))
        monitor.evaluate()
        monitor.evaluate()
        XCTAssertEqual(applied.count, 1)
    }

    func testWindowsAreReadOnlyWhileAWindowRuleIsOn() {
        monitor.setRules(PlaybackRules(onBattery: .pause))
        XCTAssertEqual(desktop.windowReads, 0)
        XCTAssertFalse(monitor.isPolling, "the battery rule follows IOKit's notification, not a timer")
        monitor.setRules(PlaybackRules(fullscreen: .stop))
        XCTAssertGreaterThan(desktop.windowReads, 0)
        XCTAssertTrue(monitor.isPolling)
        monitor.setRules(PlaybackRules())
        XCTAssertFalse(monitor.isPolling)
    }

    func testNoPollingWhileTheDisplaysSleep() {
        monitor.setRules(PlaybackRules(playingAudio: .mute, displayAsleep: .stop))
        XCTAssertTrue(monitor.isPolling)
        monitor.setDisplaysAsleep(true)
        XCTAssertFalse(monitor.isPolling)
        XCTAssertEqual(applied.last, ["1": .stop, "2": .stop])
        monitor.setDisplaysAsleep(false)
        XCTAssertTrue(monitor.isPolling)
        XCTAssertEqual(applied.last, ["1": .run, "2": .run])
    }

    func testAudioAndBatteryActOnEveryDisplay() {
        desktop.audio = true
        desktop.battery = true
        monitor.setRules(PlaybackRules(playingAudio: .mute))
        XCTAssertEqual(applied.last, ["1": .mute, "2": .mute])
        monitor.setRules(PlaybackRules(onBattery: .pause))
        XCTAssertEqual(applied.last, ["1": .pause, "2": .pause])
    }

    func testBurstsOfEventsEvaluateOnce() {
        monitor.setRules(PlaybackRules(onBattery: .pause))  // no polling to interfere
        let evaluations = desktop.evaluations
        for _ in 0..<20 { monitor.setNeedsEvaluation() }
        let done = expectation(description: "evaluated")
        DispatchQueue.main.asyncAfter(deadline: .now() + DisplayPlaybackMonitor.throttle * 3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(desktop.evaluations, evaluations + 1)
    }
}
