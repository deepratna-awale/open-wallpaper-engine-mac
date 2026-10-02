import Foundation

/// When Settings › Restart after crashing brings the app back (`CrashWatcher`).
///
/// - Only after a crash: the app ending without saying it quits (a crash, a hang the user
///   force-quit, `kill -9`). A normal quit, a SIGTERM (which quits through AppKit), a logout and
///   an update or language relaunch all say so first and are never followed by a relaunch; nor is
///   the watcher being told to stop (the setting turned off) or being terminated itself (logout).
/// - At most `maxRelaunches` in `window`, so a crash loop ends. `SafeRestart` keeps the wallpaper
///   that was showing from loading again after the relaunch.
/// - Never for an isolated copy (`AppStorageLocation.isIsolated`).
struct CrashRelaunchPolicy {
    static let maxRelaunches = 3
    static let window: TimeInterval = 5 * 60

    /// How the watched app ended, as the watcher saw it.
    enum Ending: Equatable {
        /// The app said it is quitting (normal quit, SIGTERM, logout, relaunch for an update).
        case quit
        /// The app said the setting was turned off.
        case stopWatching
        /// The app went away without a word: it crashed or was killed.
        case vanished
        /// The watcher itself was told to terminate (logout, shutdown).
        case watcherTerminated
    }

    enum Decision: Equatable {
        /// Relaunch, and remember these relaunch times.
        case relaunch(history: [Date])
        case stay
        /// A crash, but `maxRelaunches` already happened within `window`.
        case rateLimited
    }

    /// Whether the watcher runs at all.
    static func shouldWatch(enabled: Bool, isIsolated: Bool) -> Bool {
        enabled && !isIsolated
    }

    static func decide(_ ending: Ending, isIsolated: Bool, history: [Date], now: Date) -> Decision {
        guard ending == .vanished, !isIsolated else { return .stay }
        let recent = history.filter { now.timeIntervalSince($0) < window && $0 <= now }
        guard recent.count < maxRelaunches else { return .rateLimited }
        return .relaunch(history: recent + [now])
    }
}

/// The recent crash relaunches, kept in the app's support folder so the limit holds across the
/// watchers each relaunch starts.
struct CrashRelaunchHistory {
    let url: URL

    init(directory: URL = AppStorageLocation.current.supportDirectory) {
        url = directory.appending(path: "CrashRelaunches.json", directoryHint: .notDirectory)
    }

    func load() -> [Date] {
        guard let data = try? Data(contentsOf: url) else { return [] } // Optional: none yet.
        return (try? JSONDecoder().decode([Date].self, from: data)) ?? []
    }

    func save(_ dates: [Date]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(dates).write(to: url, options: .atomic)
        } catch {
            OWELog.error(.app, "Can't record the crash relaunch: \(error)")
        }
    }
}
