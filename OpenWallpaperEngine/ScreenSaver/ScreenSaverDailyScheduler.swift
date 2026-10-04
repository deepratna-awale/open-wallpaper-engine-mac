import AppKit

/// Runs the screen saver's daily re-recording (`ScreenSaverSchedule`) while the app runs: one
/// one-shot `Timer` armed for the next scheduled time (a minute's tolerance, so the system can
/// coalesce it), and a check whether a run is due at launch (`start`), at wake, and when the
/// clock, the time zone or the day changes. A time missed while the Mac slept or the app was quit
/// runs at the next of those checks. (`NSBackgroundActivityScheduler` runs work at intervals, not
/// at a time of day, so it isn't used.)
///
/// Nothing runs while the app is quit: macOS would need a LaunchAgent to start it at that time,
/// and the app has none, so the check at the next launch catches up instead.
///
/// A run records the selection again (`ScreenSaverRecordingService.recordSelection`) at
/// background priority, which replaces the installed video at once when it is done. It waits
/// while the Mac is on battery below `PowerPolicy.scheduledRecordingMinimumBattery` or critically
/// hot, checking again every `retryInterval`. Each run, skip and result is logged.
@MainActor
final class ScreenSaverDailyScheduler: ObservableObject {
    static let retryInterval: TimeInterval = 30 * 60

    @Published private(set) var schedule: ScreenSaverSchedule
    @Published private(set) var nextFire: Date?
    private let store: ScreenSaverSettingsStore
    /// Starts a recording of the selection; false when there is nothing to record or one is running.
    private let record: @MainActor () -> Bool
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let power: () -> PowerPolicy
    private var timer: Timer?
    private var retryAt: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(store: ScreenSaverSettingsStore, record: @escaping @MainActor () -> Bool,
         now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { Calendar.autoupdatingCurrent },
         power: @escaping () -> PowerPolicy = { PowerPolicyMonitor.shared.policy }) {
        self.store = store
        self.record = record
        self.now = now
        self.calendar = calendar
        self.power = power
        schedule = store.schedule
    }

    convenience init(service: ScreenSaverRecordingService) {
        self.init(store: service.store, record: { [weak service] in
            service?.recordSelection(background: true) { succeeded in
                OWELog.info(.app, "Screen saver: daily re-recording \(succeeded ? "installed" : "failed; the previous video stays")")
            } ?? false
        })
    }

    /// At launch: catches up a missed run and arms the timer; then follows wake and clock changes.
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(reason: "wake") }
        }))
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(reason: "clock change") }
            }))
        }
        check(reason: "launch")
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        timer?.invalidate()
        timer = nil
    }

    // MARK: Settings

    func setEnabled(_ isEnabled: Bool) {
        update(schedule.enabled(isEnabled, at: now()))
        OWELog.info(.app, "Screen saver: daily re-recording \(isEnabled ? "on at \(schedule.hour):\(String(format: "%02d", schedule.minute))" : "off")")
    }

    func setTime(hour: Int, minute: Int) {
        update(schedule.moved(hour: hour, minute: minute, at: now()))
    }

    /// The time of day as a date today, for a time picker.
    var timeToday: Date {
        calendar().date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: now()) ?? now()
    }

    private func update(_ schedule: ScreenSaverSchedule) {
        self.schedule = schedule
        store.schedule = schedule
        retryAt = nil
        arm()
    }

    // MARK: Running

    /// Runs a due re-recording, then arms the timer for the next time (or a retry).
    func check(reason: String) {
        defer { arm() }
        let now = now()
        guard schedule.isDue(at: now, calendar: calendar()) else { return }
        guard store.selection != nil else {
            OWELog.info(.app, "Screen saver: daily re-recording skipped (\(reason)): nothing is set as the screen saver")
            markRun(at: now)
            return
        }
        let policy = power()
        guard policy.allowsScheduledRecording else {
            OWELog.info(.app, "Screen saver: daily re-recording waits (\(reason)): on battery below \(Int(PowerPolicy.scheduledRecordingMinimumBattery * 100)) % or too hot")
            retryAt = now.addingTimeInterval(Self.retryInterval)
            return
        }
        guard record() else {
            OWELog.info(.app, "Screen saver: daily re-recording waits (\(reason)): a recording is running")
            retryAt = now.addingTimeInterval(Self.retryInterval)
            return
        }
        OWELog.info(.app, "Screen saver: daily re-recording started (\(reason))")
        markRun(at: now)
    }

    private func markRun(at date: Date) {
        retryAt = nil
        schedule.anchor = date
        store.schedule = schedule
    }

    private func arm() {
        timer?.invalidate()
        timer = nil
        let next = schedule.nextFire(after: now(), calendar: calendar())
        nextFire = next
        guard let fire = [next, retryAt].compactMap({ $0 }).min() else { return }
        let isRetry = retryAt.map { $0 == fire } ?? false
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(reason: isRetry ? "retry" : "timer") }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension PowerPolicy {
    /// The daily re-recording waits on battery below this charge…
    static let scheduledRecordingMinimumBattery = 0.3

    /// …and at `.critical` heat. On AC it always runs.
    var allowsScheduledRecording: Bool {
        if state.thermal == .critical { return false }
        guard state.onBattery else { return true }
        return (state.batteryLevel ?? 0) >= Self.scheduledRecordingMinimumBattery
    }
}
