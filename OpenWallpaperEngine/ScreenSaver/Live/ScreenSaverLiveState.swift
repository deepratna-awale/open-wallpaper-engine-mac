import Foundation

/// When the app draws the screen saver live: only while the screen saver runs (loginwindow's
/// `didstart` until `willstop`/`didstop`, or an unlock) **and** an Open Wallpaper Engine saver
/// shows (a `.saver` view's `saverAlive` notification, or an extension view over XPC, about once
/// a second). Another screen saver, a preview, or a hidden host after the session ended never
/// makes it draw. Times are seconds on one monotonic clock.
struct ScreenSaverLiveState: Equatable {
    enum Event: Equatable {
        case didStart
        case willStop
        case didStop
        /// A saver view showing (not a preview) said it is there.
        case saverAlive
        case screenLocked
        case screenUnlocked
        /// The clock moved on: timeouts apply.
        case tick
    }

    /// A saver that stops saying it is there stops the drawing after this long.
    static let saverTimeout: TimeInterval = 2.5

    /// Between `didstart` and `willstop`.
    private(set) var screenSaverRuns = false
    private(set) var isLocked = false
    private(set) var lastAlive: TimeInterval?
    /// Whether the app draws, as of the last event.
    private(set) var isDrawing = false

    /// Whether the app should draw at `now`.
    func shouldDraw(at now: TimeInterval) -> Bool {
        guard screenSaverRuns, let lastAlive else { return false }
        return now - lastAlive <= Self.saverTimeout
    }

    /// Applies `event`; returns whether drawing started or stopped.
    @discardableResult
    mutating func handle(_ event: Event, at now: TimeInterval) -> Bool {
        switch event {
        case .didStart:
            screenSaverRuns = true
            lastAlive = nil
        case .willStop, .didStop:
            screenSaverRuns = false
            lastAlive = nil
        case .saverAlive:
            // A saver outside a session (a stacked view that missed willstop) never starts it.
            if screenSaverRuns { lastAlive = now }
        case .screenLocked:
            isLocked = true
        case .screenUnlocked:
            // The session is over whatever the saver posted.
            isLocked = false
            screenSaverRuns = false
            lastAlive = nil
        case .tick:
            break
        }
        let drawing = shouldDraw(at: now)
        defer { isDrawing = drawing }
        return drawing != isDrawing
    }
}
