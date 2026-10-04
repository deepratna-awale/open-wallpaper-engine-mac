import Darwin
import Foundation

/// Settings › Restart after crashing: a small watcher process that opens the app again when it
/// crashes (`CrashRelaunchPolicy`).
///
/// The watcher is a copy of the app's own executable run with `--crash-watcher`, handled in
/// `AppMain` before any app lifecycle: no Dock icon, no windows, no playback. The app holds the
/// write end of a pipe to the watcher's standard input and writes a line before it goes away
/// cleanly: `quit` (from `applicationWillTerminate`, which a normal quit, SIGTERM, a logout and an
/// update relaunch all reach) or `stop` (the setting turned off). If the pipe closes with no line,
/// the app crashed or was killed, and the watcher opens it again once the rate limit allows.
/// Each launch starts its own watcher; the old one exits after relaunching.
///
/// `SafeRestart` still decides what comes back: after an unclean exit the wallpapers that were
/// showing stay unloaded, so a crashing wallpaper is never replayed by the relaunch.
@MainActor
final class CrashWatcher {
    static let argument = "--crash-watcher"
    static let quitMessage = "quit"
    static let stopMessage = "stop"

    private var process: Process?
    private var pipe: Pipe?
    private let isIsolated: Bool

    init(isIsolated: Bool = AppStorageLocation.current.isIsolated) {
        self.isIsolated = isIsolated
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Starts or stops the watcher for the setting's value: at launch, and on every change.
    func update(enabled: Bool) {
        if CrashRelaunchPolicy.shouldWatch(enabled: enabled, isIsolated: isIsolated) {
            start()
        } else {
            send(Self.stopMessage)
        }
    }

    /// Call from `applicationWillTerminate`: the app is quitting on purpose.
    func applicationWillTerminate() {
        send(Self.quitMessage)
    }

    private func start() {
        guard !isRunning, let executable = AppRelauncher.helperExecutable else { return }
        let pipe = Pipe()
        // The watcher may be gone (killed): a write then fails instead of raising SIGPIPE here.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let process = Process()
        process.executableURL = executable
        process.arguments = [Self.argument, Bundle.main.bundleURL.path(percentEncoded: false),
                             AppStorageLocation.current.supportDirectory.path(percentEncoded: false)]
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            OWELog.error(.app, "Can't start the crash watcher: \(error)")
            return
        }
        // Only the app holds the write end; the watcher sees EOF when the app goes away.
        try? pipe.fileHandleForReading.close() // Optional: the child has its own copy.
        self.pipe = pipe
        self.process = process
        OWELog.info(.app, "Crash watcher started (pid \(process.processIdentifier))")
    }

    private func send(_ message: String) {
        guard let pipe else { return }
        let fd = pipe.fileHandleForWriting.fileDescriptor
        let line = Array((message + "\n").utf8)
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } // Optional: the watcher may be gone.
        try? pipe.fileHandleForWriting.close() // Optional: already closed if the watcher is gone.
        self.pipe = nil
        process = nil
    }

    // MARK: - The watcher process

    /// Runs the watcher when `arguments` ask for it and returns its exit status, or nil otherwise.
    /// Blocks until the app says it quits or goes away.
    nonisolated static func runIfRequested(arguments: [String]) -> Int32? {
        guard let index = arguments.firstIndex(of: argument), arguments.count > index + 2 else { return nil }
        let bundle = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        let history = CrashRelaunchHistory(directory: URL(filePath: arguments[index + 2], directoryHint: .isDirectory))
        setpriority(PRIO_PROCESS, 0, 10)
        // A terminated watcher (logout, shutdown) ends with the default SIGTERM action: no relaunch.
        let ending = readEnding(from: FileHandle.standardInput)
        let decision = CrashRelaunchPolicy.decide(ending, isIsolated: false, history: history.load(), now: Date())
        switch decision {
        case .stay:
            return 0
        case .rateLimited:
            OWELog.error(.app, "Open Wallpaper Engine crashed again; not restarting it (\(CrashRelaunchPolicy.maxRelaunches) restarts in 5 minutes)")
            return 0
        case .relaunch(let dates):
            history.save(dates)
            OWELog.info(.app, "Open Wallpaper Engine crashed; restarting it")
            // Lets the crashed process finish going away so the new one isn't refused as a duplicate.
            Thread.sleep(forTimeInterval: 1)
            let open = Process()
            open.executableURL = URL(filePath: "/usr/bin/open")
            open.arguments = [bundle.path(percentEncoded: false)]
            do {
                try open.run()
                open.waitUntilExit()
            } catch {
                OWELog.error(.app, "Can't restart Open Wallpaper Engine: \(error)")
                return 1
            }
            return 0
        }
    }

    /// Reads the app's lines until it says it quits, says stop, or the pipe closes.
    nonisolated static func readEnding(from handle: FileHandle) -> CrashRelaunchPolicy.Ending {
        var buffer = Data()
        while true {
            let chunk = handle.availableData // Blocks; empty at EOF.
            if chunk.isEmpty { return ending(for: buffer) }
            buffer.append(chunk)
            let ended = ending(for: buffer)
            if ended != .vanished { return ended }
        }
    }

    /// The ending the lines received so far mean; `.vanished` while nothing decisive arrived.
    nonisolated static func ending(for data: Data) -> CrashRelaunchPolicy.Ending {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        if lines.contains(quitMessage) { return .quit }
        if lines.contains(stopMessage) { return .stopWatching }
        return .vanished
    }
}
