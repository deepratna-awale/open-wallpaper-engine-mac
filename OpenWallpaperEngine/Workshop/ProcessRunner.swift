//
//  ProcessRunner.swift
//  Open Wallpaper Engine
//
//  Runs one Steam helper download: its input goes to stdin, and its output is collected (and
//  streamed to the caller, for download progress) until it exits.
//

import Foundation
import os

struct ProcessRun: Sendable {
    let output: String
    let exitCode: Int32
}

/// Stops a running download from another thread. One token per run.
final class ProcessCancellation: @unchecked Sendable {
    // `lock` owns `isCancelled` and `onCancel`.
    private let lock = NSLock()
    private var cancelled = false
    private var onCancel: (() -> Void)?

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        let action: (() -> Void)? = lock.withLock {
            cancelled = true
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }

    /// Runs `action` on cancellation, or right away when already cancelled.
    func setCancelAction(_ action: (() -> Void)?) {
        let runNow: Bool = lock.withLock {
            onCancel = cancelled ? nil : action
            return cancelled
        }
        if runNow { action?() }
    }
}

/// Runs a program to the end, collecting its output.
enum ProcessRunner {
    /// Runs `executable` with `standardInput` written to its stdin, which is then closed, and blocks
    /// until it exits or `timeout` passes (nil waits for as long as it takes). `onOutput` receives the
    /// output as it arrives, on a background queue; `cancellation` terminates the program.
    static func runProcess(executable: URL, arguments: [String], standardInput: Data, timeout: TimeInterval?,
                           cancellation: ProcessCancellation,
                           onOutput: @escaping @Sendable (String) -> Void) -> ProcessRun {
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Read the pipe while the program runs, so a full pipe buffer can't block it.
        let outputData = OSAllocatedUnfairLock(initialState: Data())
        let handle = outputPipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            outputData.withLock { $0.append(data) }
            onOutput(String(decoding: data, as: UTF8.self))
        }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            let failure = SteamHelperError(code: .helperExited,
                                           message: "Can't start \(executable.lastPathComponent): \(error.localizedDescription)")
            return ProcessRun(output: failure.errorDescription ?? failure.message, exitCode: -1)
        }
        cancellation.setCancelAction { process.terminate() }
        defer { cancellation.setCancelAction(nil) }
        write(standardInput, to: inputPipe)

        let exited = DispatchGroup()
        exited.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            exited.leave()
        }
        if let timeout, exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            handle.readabilityHandler = nil
            return ProcessRun(output: "\(executable.lastPathComponent) timed out after \(Int(timeout))s", exitCode: -1)
        }
        exited.wait()

        handle.readabilityHandler = nil
        let remaining = handle.readDataToEndOfFile()
        if !remaining.isEmpty { onOutput(String(decoding: remaining, as: UTF8.self)) }
        let output: Data = outputData.withLock {
            $0.append(remaining)
            return $0
        }
        return ProcessRun(output: String(decoding: output, as: UTF8.self), exitCode: process.terminationStatus)
    }

    /// Writes the whole input and closes stdin, so the program reads EOF after it.
    private static func write(_ input: Data, to pipe: Pipe) {
        let handle = pipe.fileHandleForWriting
        // If the program already exited, the write must fail with EPIPE rather than kill the app.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try handle.write(contentsOf: input)
            try handle.close()
        } catch {
            // The program exited before reading its input; its output says why.
            OWELog.error(.workshop, "Can't write the program's input: \(error)")
        }
    }
}
