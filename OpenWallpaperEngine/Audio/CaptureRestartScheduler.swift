import Foundation

/// Coalesces capture restarts and backs off when they keep failing.
///
/// Sleep, display changes and stream errors tend to arrive in bursts; each one used to start a
/// separate restart. Requests are debounced, at most one start is in flight, a failed start is
/// retried with exponential backoff, and after `maxFailures` consecutive failures the scheduler
/// gives up until `reset()`.
///
/// A start that succeeds can still be asked to restart at once, over and over (a Core Audio
/// notification the new capture itself sets off, say). Every such rebuild stalls coreaudiod, so a
/// capture that is restarted within `stableInterval` of starting counts as a rapid restart, and
/// past `rapidTolerance` of those in a row each restart waits twice as long as the one before, up
/// to `maxRapidDelay`. A capture that runs longer clears the count.
@MainActor
final class CaptureRestartScheduler {
    typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    let debounce: TimeInterval
    let baseBackoff: TimeInterval
    let maxFailures: Int
    let stableInterval: TimeInterval
    let rapidTolerance: Int
    let maxRapidDelay: TimeInterval
    private let schedule: Schedule
    /// A monotonic clock, in seconds.
    private let now: () -> TimeInterval
    /// Starts capture; must eventually call `finished(success:)` exactly once.
    private let start: @MainActor () -> Void
    private var token = 0
    private var pendingRequest = false
    private(set) var isInFlight = false
    private(set) var consecutiveFailures = 0
    private(set) var hasGivenUp = false
    /// How many captures in a row were asked to restart within `stableInterval` of starting.
    private(set) var rapidRestarts = 0
    /// When the running capture started; nil before the first start, while one is failing, and
    /// once a restart request has been counted against it.
    private var lastStart: TimeInterval?

    init(debounce: TimeInterval = 1.5, baseBackoff: TimeInterval = 2, maxFailures: Int = 4,
         stableInterval: TimeInterval = 10, rapidTolerance: Int = 2, maxRapidDelay: TimeInterval = 60,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Schedule, start: @escaping @MainActor () -> Void) {
        self.debounce = debounce
        self.baseBackoff = baseBackoff
        self.maxFailures = maxFailures
        self.stableInterval = stableInterval
        self.rapidTolerance = rapidTolerance
        self.maxRapidDelay = maxRapidDelay
        self.now = now
        self.schedule = schedule
        self.start = start
    }

    /// The wait before the next restart: the debounce, doubled for every rapid restart past
    /// `rapidTolerance`.
    var restartDelay: TimeInterval {
        guard rapidRestarts > rapidTolerance else { return debounce }
        return min(debounce * pow(2, Double(rapidRestarts - rapidTolerance)), maxRapidDelay)
    }

    /// Returns the wait before the restart when this request is the one that slowed it down (the
    /// capture it restarts had only just started, once too often), so the caller can log that
    /// once per restart instead of on every request of a burst; nil otherwise.
    @discardableResult
    func requestRestart() -> TimeInterval? {
        guard !hasGivenUp else { return nil }
        let slowed = countRapidRestart()
        fire(after: restartDelay)
        return slowed ? restartDelay : nil
    }

    /// Judges the running capture once, on the first restart request after it started. True when
    /// that request makes the restarts back off.
    private func countRapidRestart() -> Bool {
        guard let started = lastStart else { return false }
        lastStart = nil
        rapidRestarts = now() - started < stableInterval ? rapidRestarts + 1 : 0
        return rapidRestarts > rapidTolerance
    }

    /// Returns true exactly once, on the failure that makes the scheduler give up, so the caller
    /// logs that once instead of on every attempt.
    @discardableResult
    func finished(success: Bool) -> Bool {
        isInFlight = false
        if success {
            consecutiveFailures = 0
            lastStart = now()
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= maxFailures {
                hasGivenUp = true
                pendingRequest = false
                token &+= 1
                return true
            }
            fire(after: baseBackoff * pow(2, Double(consecutiveFailures - 1)))
        }
        if pendingRequest {
            pendingRequest = false
            requestRestart()
        }
        return false
    }

    /// Clears the failure and rapid restart history, e.g. after the permission was newly granted
    /// or the capture was stopped.
    func reset() {
        token &+= 1
        consecutiveFailures = 0
        rapidRestarts = 0
        lastStart = nil
        hasGivenUp = false
        pendingRequest = false
    }

    private func fire(after delay: TimeInterval) {
        token &+= 1
        let expected = token
        schedule(delay) { [weak self] in
            guard let self, expected == self.token else { return }
            guard !self.isInFlight else {
                self.pendingRequest = true
                return
            }
            self.isInFlight = true
            self.start()
        }
    }
}
