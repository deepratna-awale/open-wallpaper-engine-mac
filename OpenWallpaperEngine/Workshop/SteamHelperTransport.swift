import Foundation
import os

/// One running `owe-steam-helper serve`: lines to its stdin, lines from its stdout.
/// `SteamHelperClient` takes a factory for these, so tests can stand in a fake helper.
protocol SteamHelperTransport: AnyObject, Sendable {
    /// Starts the helper. `onLine` gets each line of its output in order, without the newline, on
    /// a background queue; `onExit` gets its exit status once, after the last line.
    func start(onLine: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws
    /// Writes `line` and a newline to the helper's stdin.
    func send(_ line: Data) throws
    /// Closes the helper's stdin, which ends it once its requests have answered.
    func stop()
}

/// The real helper, as a subprocess.
final class ProcessSteamHelperTransport: SteamHelperTransport, @unchecked Sendable {
    // `process` and the pipes are set up once in `init` and only used through their own
    // thread-safe calls; `pendingOutput` is owned by its lock.
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let pendingOutput = OSAllocatedUnfairLock(initialState: Data())

    init(executable: URL) {
        process.executableURL = executable
        process.arguments = ["serve"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    func start(onLine: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws {
        let exited = OSAllocatedUnfairLock(initialState: (outputClosed: false, status: Int32?.none))
        // The exit is reported after the last line: whichever of end-of-output and exit comes second reports it.
        let reportExitIfDone: @Sendable () -> Void = {
            let status: Int32? = exited.withLock { $0.outputClosed ? $0.status : nil }
            if let status { onExit(status) }
        }
        output.fileHandleForReading.readabilityHandler = { [pendingOutput] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                exited.withLock { $0.outputClosed = true }
                reportExitIfDone()
                return
            }
            let lines: [Data] = pendingOutput.withLock { buffer in
                buffer.append(data)
                var lines: [Data] = []
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    lines.append(Data(buffer[buffer.startIndex..<newline]))
                    buffer.removeSubrange(buffer.startIndex...newline)
                }
                return lines
            }
            lines.forEach(onLine)
        }
        // The helper writes its diagnostics (never a token) to stderr.
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            OWELog.info(.workshop, "Steam helper: \(String(decoding: data, as: UTF8.self))")
        }
        process.terminationHandler = { process in
            exited.withLock { $0.status = process.terminationStatus }
            reportExitIfDone()
        }
        // If the helper already exited, a write must fail with EPIPE rather than kill the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func send(_ line: Data) throws {
        try input.fileHandleForWriting.write(contentsOf: line + Data([UInt8(ascii: "\n")]))
    }

    func stop() {
        do {
            try input.fileHandleForWriting.close()
        } catch {
            OWELog.error(.workshop, "Can't close the Steam helper's input: \(error)")
        }
    }
}
