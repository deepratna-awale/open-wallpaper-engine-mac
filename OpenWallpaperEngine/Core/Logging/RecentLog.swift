import Darwin
import Foundation
import os

/// The app's own recent messages on disk, so the launch after a crash can put the messages from
/// just before it into a problem report (`ProblemReporter`).
///
/// `OWELog` hands it every `.info` and `.error` message while the Log Level isn't None, whatever
/// the level lets into the unified log: info messages are lifecycle only (CONTRIBUTING rule 5)
/// and the unified log doesn't keep them on disk, so this is the only record of what the app was
/// doing. `.debug` (per-frame detail) never comes here.
///
/// Each run writes `current.log`; past `maxFileSize` (1 MB) it becomes `current.1.log` and a new one
/// starts, so a run keeps at most twice that. `startRun()` moves the last run's pair to
/// `previous.log` and `previous.1.log`. Writes go straight to the file descriptor, unbuffered,
/// so nothing written before a crash is lost with the process.
final class RecentLog: Sendable {
    enum Run: String, Sendable {
        case current, previous
    }

    let directory: URL
    let maxFileSize: Int
    private struct State {
        var descriptor: Int32 = -1
        var size = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(directory: URL, maxFileSize: Int = 1 << 20) {
        self.directory = directory
        self.maxFileSize = maxFileSize
    }

    deinit {
        state.withLock { if $0.descriptor >= 0 { close($0.descriptor) } }
    }

    /// `<app caches>/Logs`, beside the shader caches.
    static var defaultDirectory: URL {
        AppStorageLocation.current.appCachesDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    }

    static func fileURL(_ run: Run, chunk: Int = 0, in directory: URL) -> URL {
        directory.appending(path: chunk == 0 ? "\(run.rawValue).log" : "\(run.rawValue).\(chunk).log",
                            directoryHint: .notDirectory)
    }

    /// Call once at launch, before the first message: keeps the last run's log as `previous` and
    /// opens a new one.
    func startRun() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        } catch {
            OWELog.error(.app, "Can't create the recent log folder at \(directory.path): \(error)")
            return
        }
        state.withLock { state in
            if state.descriptor >= 0 { close(state.descriptor) }
            state = State()
            for chunk in [0, 1] {
                let from = Self.fileURL(.current, chunk: chunk, in: directory)
                let to = Self.fileURL(.previous, chunk: chunk, in: directory)
                // Either may be missing (first run, or a run that never filled a chunk).
                _ = unlink(to.path)
                _ = rename(from.path, to.path)
            }
            state.descriptor = Self.open(Self.fileURL(.current, in: directory))
        }
    }

    /// Appends one message as a line: `<time> <severity> <category>: <message>`.
    func append(_ severity: OWELog.Severity, _ category: OWELog.Category, _ message: String, date: Date = Date()) {
        let mark: String
        switch severity {
        case .debug: mark = "D"
        case .info: mark = "I"
        case .error: mark = "E"
        case .silent: return
        }
        let line = "\(date.formatted(Self.timeFormat)) \(mark) \(category.rawValue): \(message)\n"
        let bytes = Array(line.utf8)
        state.withLock { state in
            guard state.descriptor >= 0 else { return }
            if state.size > 0, state.size + bytes.count > maxFileSize {
                close(state.descriptor)
                let current = Self.fileURL(.current, in: directory)
                _ = rename(current.path, Self.fileURL(.current, chunk: 1, in: directory).path)
                state = State(descriptor: Self.open(current))
                guard state.descriptor >= 0 else { return }
            }
            let written = bytes.withUnsafeBytes { write(state.descriptor, $0.baseAddress, $0.count) }
            if written > 0 { state.size += written }
        }
    }

    /// The last `maxBytes` of a run's log, cut at a line start; empty when there is none.
    static func tail(of run: Run, in directory: URL, maxBytes: Int = 256 * 1024) -> String {
        var data = Data()
        for chunk in [1, 0] {
            // A missing chunk is normal: the run didn't fill one, or never ran.
            if let part = try? Data(contentsOf: fileURL(run, chunk: chunk, in: directory)) { data.append(part) }
        }
        guard data.count > maxBytes else { return String(decoding: data, as: UTF8.self) }
        var cut = data.suffix(maxBytes)
        if let newline = cut.firstIndex(of: UInt8(ascii: "\n")) {
            cut = cut[cut.index(after: newline)...]
        }
        return String(decoding: cut, as: UTF8.self)
    }

    /// When a run last wrote to its log, roughly when it ended for the previous run.
    static func lastWrite(of run: Run, in directory: URL) -> Date? {
        let path = fileURL(run, in: directory).path
        // Missing when the run logged nothing.
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static let timeFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func open(_ url: URL) -> Int32 {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND | O_CLOEXEC, 0o600)
        if descriptor < 0 {
            // Not through OWELog: this is called with the log's lock held.
            Logger(subsystem: "app.openwallpaperengine", category: OWELog.Category.app.rawValue)
                .error("Can't open the recent log at \(url.path, privacy: .public): errno \(errno)")
        }
        return descriptor
    }
}
