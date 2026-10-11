import Foundation

/// When the broker (`owe-saver-broker`) launches the app for a saver that shows while the app
/// isn't running: a saver asked (the extension for the app's endpoint, the `.saver` by its Darwin
/// `saverAlive`, which launchd turns into a launch of the broker), the app isn't running, and it
/// wasn't launched within `retryInterval` (a launch that is still starting, or one that failed,
/// isn't repeated every second). Times are seconds on one monotonic clock.
struct LiveSaverLaunchPolicy: Equatable {
    /// A launch isn't repeated within this long.
    static let retryInterval: TimeInterval = 20

    private(set) var lastLaunch: TimeInterval?

    /// Whether to launch the app now; records the launch when so.
    mutating func shouldLaunch(at now: TimeInterval, appRunning: Bool) -> Bool {
        guard !appRunning else { return false }
        if let lastLaunch, now - lastLaunch < Self.retryInterval { return false }
        lastLaunch = now
        return true
    }
}
