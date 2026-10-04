import Foundation

/// "Re-record every day at [time]" for the screen saver (off by default): the times it fires and
/// whether a run is due. Pure calendar arithmetic, so the rules are testable; the scheduler
/// (`ScreenSaverDailyScheduler`) asks it at launch, at wake, on a clock or time zone change and
/// when its timer fires.
///
/// - The time is a wall-clock time in the Mac's current time zone, read with the calendar passed
///   in: after a time zone change it fires at that time where the Mac is now.
/// - A time the clocks skip (the spring change) fires at the first time after it that exists; a
///   time that happens twice (the autumn change) fires the first time only.
/// - `anchor` is when the schedule last ran, or was turned on or moved to another time. A run is
///   due when a scheduled time has passed since then, so a day missed while the Mac slept or the
///   app was quit runs once at the next check, however many days were missed, and turning the
///   schedule on after today's time waits for tomorrow.
struct ScreenSaverSchedule: Codable, Equatable, Sendable {
    var isEnabled = false
    /// The time of day, in minutes after midnight.
    var minuteOfDay = 9 * 60
    var anchor: Date?

    var hour: Int { minuteOfDay / 60 }
    var minute: Int { minuteOfDay % 60 }

    /// The schedule turned on or off at `now`.
    func enabled(_ isEnabled: Bool, at now: Date) -> ScreenSaverSchedule {
        var schedule = self
        schedule.isEnabled = isEnabled
        schedule.anchor = now
        return schedule
    }

    /// The schedule moved to `hour`:`minute` at `now`; a time already passed today waits for tomorrow.
    func moved(hour: Int, minute: Int, at now: Date) -> ScreenSaverSchedule {
        var schedule = self
        schedule.minuteOfDay = min(max(hour, 0), 23) * 60 + min(max(minute, 0), 59)
        schedule.anchor = now
        return schedule
    }

    /// The scheduled time on the calendar day that contains `day`.
    func occurrence(onDayOf day: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        return calendar.nextDate(after: start.addingTimeInterval(-1),
                                 matching: DateComponents(hour: hour, minute: minute, second: 0),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    /// The first scheduled time after `date`; nil while off.
    func nextFire(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled else { return nil }
        var day = date
        for _ in 0..<3 {
            if let time = occurrence(onDayOf: day, calendar: calendar), time > date { return time }
            guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return nil }
            day = next
        }
        return nil
    }

    /// The last scheduled time at or before `date`.
    func latestOccurrence(atOrBefore date: Date, calendar: Calendar) -> Date? {
        var day = date
        for _ in 0..<3 {
            if let time = occurrence(onDayOf: day, calendar: calendar), time <= date { return time }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day)) else { return nil }
            day = previous
        }
        return nil
    }

    /// Whether a run is due at `now`: a scheduled time has passed since `anchor`.
    func isDue(at now: Date, calendar: Calendar) -> Bool {
        guard isEnabled, let anchor, let latest = latestOccurrence(atOrBefore: now, calendar: calendar) else { return false }
        return latest > anchor
    }
}
