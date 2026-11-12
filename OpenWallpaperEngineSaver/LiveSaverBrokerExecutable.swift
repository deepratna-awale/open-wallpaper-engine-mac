import Darwin
import Foundation

/// Whether the running broker (`owe-saver-broker`) is still the binary in its app bundle.
///
/// The broker is a `KeepAlive` launch agent and never exits on its own. An update swaps the app
/// bundle, so the broker launchd started before it keeps running the old binary until the user
/// logs out. It records the file it was started from (device and inode at its path); once the
/// path holds another file, or none, it is out of date: it refuses the connection and exits, and
/// launchd starts the new binary at the same path. The app's broker connection retries
/// (`ScreenSaverFrameService.brokerRetryDelay`), so it registers with the new broker.
struct LiveSaverBrokerExecutable: Equatable {
    struct Identity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    let path: String
    /// The file at `path` when the broker started; nil when it couldn't be read, and then the
    /// broker never counts as out of date.
    let started: Identity?

    init(path: String, started: Identity?) {
        self.path = path
        self.started = started
    }

    /// The executable as it is now: call once, when the broker starts.
    init(path: String) {
        self.init(path: path, started: Self.identity(atPath: path))
    }

    /// The file at `path` now (following symlinks); nil when there is none.
    static func identity(atPath path: String) -> Identity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    /// Whether `current` (the file at `path` now) is another binary than the one that started.
    func isOutOfDate(current: Identity?) -> Bool {
        guard let started else { return false }
        return current != started
    }

    var isOutOfDate: Bool { isOutOfDate(current: Self.identity(atPath: path)) }
}
