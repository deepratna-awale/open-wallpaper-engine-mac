import Foundation
import QuartzCore

/// Debug measurements of one transition, taken only at the Verbose log level and logged once
/// when it ends: when each frame was presented (the intervals, and the refreshes that showed no
/// new frame), and how late the main thread ran work posted to it while the transition played
/// (a main-thread stall: the incoming wallpaper loading, a layout pass…).
///
/// Thread-safe: frames are recorded from any thread, the main-thread probe posts from a utility
/// queue; every mutable field is guarded by `lock`.
final class WallpaperTransitionMetrics: @unchecked Sendable {
    /// The refresh interval of the display it plays on.
    let refreshInterval: CFTimeInterval
    private let lock = NSLock()
    // Guarded by `lock`.
    private var presents: [CFTimeInterval] = []
    private var submitted = 0
    private var stalls: [CFTimeInterval] = []
    private var probe: DispatchSourceTimer?
    private var probeOutstanding = false
    private var finished = false

    /// How often the main thread is probed.
    static let probeInterval: DispatchTimeInterval = .milliseconds(4)

    /// Whether transitions are measured: only when debug messages are logged.
    static var isEnabled: Bool { OWELog.minimumSeverity <= .debug }

    init(refreshInterval: CFTimeInterval) {
        self.refreshInterval = max(refreshInterval, 1.0 / 1000)
    }

    deinit {
        probe?.cancel()
    }

    /// Starts probing the main thread.
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: Self.probeInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.probeMainThread() }
        lock.withLock { probe = timer }
        timer.resume()
    }

    /// A frame reached the screen (or was handed to it) at `time` (`CACurrentMediaTime`).
    func recordPresent(at time: CFTimeInterval) {
        lock.withLock {
            guard !finished else { return }
            presents.append(time)
        }
    }

    /// A frame was handed to the GPU to be presented; it may not reach the screen (a covered window).
    func recordSubmitted() {
        lock.withLock {
            if !finished { submitted += 1 }
        }
    }

    /// Stops measuring and returns what it measured.
    func finish() -> WallpaperTransitionFrameSummary {
        let (presents, submitted, stalls, probe) = lock.withLock {
            () -> ([CFTimeInterval], Int, [CFTimeInterval], DispatchSourceTimer?) in
            finished = true
            let probe = self.probe
            self.probe = nil
            return (self.presents, self.submitted, self.stalls, probe)
        }
        probe?.cancel()
        var summary = WallpaperTransitionFrameSummary(presents: presents.sorted(), stalls: stalls,
                                                      refreshInterval: refreshInterval)
        summary.submitted = submitted
        return summary
    }

    /// Posts one probe to the main queue unless one is still waiting, and records how late it ran
    /// when that is a refresh or more.
    private func probeMainThread() {
        let posted = lock.withLock { () -> Bool in
            guard !finished, !probeOutstanding else { return false }
            probeOutstanding = true
            return true
        }
        guard posted else { return }
        let sent = CACurrentMediaTime()
        DispatchQueue.main.async { [self] in
            let late = CACurrentMediaTime() - sent
            lock.withLock {
                probeOutstanding = false
                if !finished, late >= refreshInterval { stalls.append(late) }
            }
        }
    }
}
