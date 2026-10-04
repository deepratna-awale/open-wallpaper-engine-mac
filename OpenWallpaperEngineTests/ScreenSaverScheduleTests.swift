import XCTest
@testable import OpenWallpaperEngine

/// The screen saver's daily re-recording: the next time it fires, catching up a missed day, the
/// daylight-saving changes and a time zone change (`ScreenSaverSchedule`), and the scheduler's
/// run, power and retry decisions (`ScreenSaverDailyScheduler`).
final class ScreenSaverScheduleTests: XCTestCase {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ text: String, _ calendar: Calendar) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: text), text)
    }

    private func schedule(at hour: Int, _ minute: Int, anchor: Date?) -> ScreenSaverSchedule {
        ScreenSaverSchedule(isEnabled: true, minuteOfDay: hour * 60 + minute, anchor: anchor)
    }

    // MARK: Next fire time

    func testNextFireIsTodayBeforeTheTimeAndTomorrowAfterIt() throws {
        let cal = try calendar("Europe/Berlin")
        let daily = schedule(at: 9, 30, anchor: nil)
        XCTAssertEqual(daily.nextFire(after: try date("2026-05-10 08:00", cal), calendar: cal), try date("2026-05-10 09:30", cal))
        XCTAssertEqual(daily.nextFire(after: try date("2026-05-10 09:30", cal), calendar: cal), try date("2026-05-11 09:30", cal))
        XCTAssertEqual(daily.nextFire(after: try date("2026-05-10 23:59", cal), calendar: cal), try date("2026-05-11 09:30", cal))
        XCTAssertEqual(schedule(at: 0, 0, anchor: nil).nextFire(after: try date("2026-05-10 23:59", cal), calendar: cal),
                       try date("2026-05-11 00:00", cal))
        var off = daily
        off.isEnabled = false
        XCTAssertNil(off.nextFire(after: try date("2026-05-10 08:00", cal), calendar: cal))
    }

    // MARK: Catch-up

    /// The Mac slept through today's time: the next check (wake or launch) runs it once, then
    /// the next run is tomorrow.
    func testMissedRunIsCaughtUpOnceAtTheNextCheck() throws {
        let cal = try calendar("Europe/Berlin")
        var daily = schedule(at: 9, 0, anchor: try date("2026-05-09 09:00", cal))
        XCTAssertFalse(daily.isDue(at: try date("2026-05-10 08:59", cal), calendar: cal))
        let wake = try date("2026-05-10 15:20", cal)
        XCTAssertTrue(daily.isDue(at: wake, calendar: cal))
        daily.anchor = wake
        XCTAssertFalse(daily.isDue(at: try date("2026-05-10 23:00", cal), calendar: cal))
        XCTAssertEqual(daily.nextFire(after: wake, calendar: cal), try date("2026-05-11 09:00", cal))
    }

    /// Several days missed (the app was quit) are one run, not one per day.
    func testSeveralMissedDaysRunOnce() throws {
        let cal = try calendar("America/New_York")
        var daily = schedule(at: 7, 15, anchor: try date("2026-05-01 07:15", cal))
        let launch = try date("2026-05-06 12:00", cal)
        XCTAssertTrue(daily.isDue(at: launch, calendar: cal))
        daily.anchor = launch
        XCTAssertFalse(daily.isDue(at: launch.addingTimeInterval(60), calendar: cal))
    }

    /// Turning it on (or moving the time) after today's time waits for tomorrow.
    func testTurningOnAfterTodaysTimeWaitsForTomorrow() throws {
        let cal = try calendar("Europe/Berlin")
        let now = try date("2026-05-10 12:00", cal)
        let daily = ScreenSaverSchedule().moved(hour: 9, minute: 0, at: now).enabled(true, at: now)
        XCTAssertFalse(daily.isDue(at: try date("2026-05-10 23:00", cal), calendar: cal))
        XCTAssertTrue(daily.isDue(at: try date("2026-05-11 09:00", cal), calendar: cal))
        XCTAssertFalse(ScreenSaverSchedule().isDue(at: now, calendar: cal), "off by default")
    }

    // MARK: Daylight saving

    /// 02:30 doesn't exist on the spring change: it fires at 03:00, the first time that does.
    func testSpringForwardSkippedTimeFiresAtTheNextTimeThatExists() throws {
        let cal = try calendar("Europe/Berlin")
        let daily = schedule(at: 2, 30, anchor: nil)
        let fire = try XCTUnwrap(daily.nextFire(after: try date("2026-03-29 00:00", cal), calendar: cal))
        XCTAssertEqual(fire, try date("2026-03-29 03:00", cal))
        XCTAssertEqual(daily.nextFire(after: fire, calendar: cal), try date("2026-03-30 02:30", cal))
    }

    /// 02:30 happens twice on the autumn change: it fires the first time only.
    func testFallBackRepeatedTimeFiresOnce() throws {
        let cal = try calendar("Europe/Berlin")
        var daily = schedule(at: 2, 30, anchor: nil)
        let fire = try XCTUnwrap(daily.nextFire(after: try date("2026-10-25 00:00", cal), calendar: cal))
        XCTAssertEqual(fire.timeIntervalSince1970, try date("2026-10-25 00:00", cal).timeIntervalSince1970 + 2.5 * 3600,
                       "the first 02:30 (summer time), 2 h 30 min after midnight")
        daily.anchor = fire
        XCTAssertFalse(daily.isDue(at: fire.addingTimeInterval(3600), calendar: cal), "the second 02:30 doesn't run again")
        XCTAssertEqual(daily.nextFire(after: fire, calendar: cal), try date("2026-10-26 02:30", cal))
    }

    /// Across a day 23 or 25 hours long, the time stays the wall-clock time.
    func testWallClockTimeHoldsAcrossTheChange() throws {
        let cal = try calendar("America/New_York")
        let daily = schedule(at: 9, 0, anchor: nil)
        let before = try XCTUnwrap(daily.nextFire(after: try date("2026-03-07 08:00", cal), calendar: cal))
        let after = try XCTUnwrap(daily.nextFire(after: before, calendar: cal))
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3600, accuracy: 1)
        XCTAssertEqual(cal.component(.hour, from: after), 9)
    }

    // MARK: Time zone change

    /// The Mac moves from Berlin to New York after today's run: it fires at 09:00 New York time
    /// and doesn't run twice for the same day.
    func testTimeZoneChangeFollowsTheLocalTime() throws {
        let berlin = try calendar("Europe/Berlin")
        let newYork = try calendar("America/New_York")
        var daily = schedule(at: 9, 0, anchor: nil)
        let ranInBerlin = try date("2026-01-10 09:00", berlin)
        daily.anchor = ranInBerlin
        let landed = try date("2026-01-10 07:00", newYork) // 13:00 in Berlin
        XCTAssertFalse(daily.isDue(at: landed, calendar: newYork))
        XCTAssertEqual(daily.nextFire(after: landed, calendar: newYork), try date("2026-01-10 09:00", newYork))
        XCTAssertTrue(daily.isDue(at: try date("2026-01-10 09:01", newYork), calendar: newYork))
        // Eastwards to Tokyo the next morning: that day's 09:00 there has passed since the run, so it runs.
        let tokyo = try calendar("Asia/Tokyo")
        XCTAssertTrue(daily.isDue(at: try date("2026-01-11 10:00", tokyo), calendar: tokyo))
    }

    func testScheduleRoundTripsThroughTheStore() throws {
        let suite = "owe-screensaver-schedule-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScreenSaverSettingsStore(defaults: defaults)
        XCTAssertEqual(store.schedule, ScreenSaverSchedule())
        XCTAssertFalse(store.schedule.isEnabled, "off by default")
        let schedule = ScreenSaverSchedule(isEnabled: true, minuteOfDay: 6 * 60 + 45, anchor: Date(timeIntervalSince1970: 1_800_000_000))
        store.schedule = schedule
        XCTAssertEqual(ScreenSaverSettingsStore(defaults: defaults).schedule, schedule)
    }

    // MARK: Scheduler

    @MainActor
    func testSchedulerRunsWhenDueAndWaitsOnLowBattery() throws {
        let suite = "owe-screensaver-scheduler-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cal = try calendar("Europe/Berlin")
        let store = ScreenSaverSettingsStore(defaults: defaults)
        store.selection = ScreenSaverSettingsStore.Selection(wallpaperDirectory: "/w", fileName: "a.mov", width: 1920,
                                                             height: 1080, recorded: try date("2026-05-09 09:00", cal))
        var now = try date("2026-05-09 08:00", cal)
        var power = PowerState(onBattery: true, batteryLevel: 0.2)
        var runs = 0
        let scheduler = ScreenSaverDailyScheduler(store: store, record: { runs += 1; return true },
                                                  now: { now }, calendar: { cal }, power: { PowerPolicy(power) })
        scheduler.setTime(hour: 9, minute: 0)
        scheduler.setEnabled(true)
        XCTAssertEqual(scheduler.nextFire, try date("2026-05-09 09:00", cal))

        // Asleep at 09:00; woken at 11:00 on a low battery: it waits.
        now = try date("2026-05-09 11:00", cal)
        scheduler.check(reason: "wake")
        XCTAssertEqual(runs, 0)
        // Plugged in: the retry runs it, once.
        power = PowerState(onBattery: false)
        scheduler.check(reason: "retry")
        XCTAssertEqual(runs, 1)
        scheduler.check(reason: "wake")
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(scheduler.nextFire, try date("2026-05-10 09:00", cal))
        // The run is remembered across launches.
        XCTAssertEqual(store.schedule.anchor, now)
        // On battery above the threshold it runs.
        power = PowerState(onBattery: true, batteryLevel: 0.8)
        now = try date("2026-05-10 09:00", cal)
        scheduler.check(reason: "timer")
        XCTAssertEqual(runs, 2)
        scheduler.stop()
    }

    func testPowerPolicyForTheScheduledRecording() {
        XCTAssertTrue(PowerPolicy(PowerState(onBattery: false)).allowsScheduledRecording)
        XCTAssertTrue(PowerPolicy(PowerState(onBattery: true, batteryLevel: 0.3)).allowsScheduledRecording)
        XCTAssertFalse(PowerPolicy(PowerState(onBattery: true, batteryLevel: 0.29)).allowsScheduledRecording)
        XCTAssertFalse(PowerPolicy(PowerState(onBattery: false, thermal: .critical)).allowsScheduledRecording)
    }
}
