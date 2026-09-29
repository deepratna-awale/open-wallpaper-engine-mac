import Foundation

/// Debug-only checks that heavy work stays off the main thread and the render thread, and that
/// per-frame work stays on the render thread. Release builds compile every check to nothing.
///
/// The render thread is whichever thread is inside `ThreadGuards.renderFrame { … }`: the render
/// loop wraps its frame entry in it, so the flag follows the loop wherever it runs (today that
/// may be the main thread, which is then both).
///
/// A hit is logged once per call site and passed to `handler`. The default handler only calls
/// `assertionFailure` when `OWE_STRICT_THREAD_GUARDS=1`, so existing offenders are reported, not
/// fatal, until they are moved; tests swap the handler to observe hits.
enum ThreadGuards {
    struct Violation: Equatable, Sendable {
        enum Kind: String, Sendable { case onMainThread = "main thread", onRenderThread = "render thread",
                                            offRenderThread = "off the render thread" }
        let kind: Kind
        let what: String
        let file: String
        let line: UInt
    }

    typealias Handler = @Sendable (Violation) -> Void

    #if DEBUG
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler = defaultHandler
    nonisolated(unsafe) private static var reported = Set<String>()
    private static let renderKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()
    static let strict = ProcessInfo.processInfo.environment["OWE_STRICT_THREAD_GUARDS"] == "1"
    #endif

    static let defaultHandler: Handler = { violation in
        #if DEBUG
        if strict { assertionFailure("\(violation.what) ran on the \(violation.kind.rawValue)") }
        #endif
    }

    /// Swaps the handler; returns the previous one so a test can restore it.
    @discardableResult
    static func setHandler(_ handler: @escaping Handler) -> Handler {
        #if DEBUG
        lock.lock(); defer { lock.unlock() }
        let previous = _handler
        _handler = handler
        reported.removeAll()
        return previous
        #else
        return handler
        #endif
    }

    /// Marks the calling thread as the render thread for the duration of `body`. Nests.
    @inline(__always)
    static func renderFrame<T>(_ body: () throws -> T) rethrows -> T {
        #if DEBUG
        let previous = pthread_getspecific(renderKey)
        pthread_setspecific(renderKey, UnsafeRawPointer(bitPattern: 1))
        defer { pthread_setspecific(renderKey, previous) }
        #endif
        return try body()
    }

    static var isRenderThread: Bool {
        #if DEBUG
        return pthread_getspecific(renderKey) != nil
        #else
        return false
        #endif
    }

    @inline(__always)
    static func assertNotMainThread(_ what: @autoclosure () -> String,
                                    file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        if Thread.isMainThread { report(.onMainThread, what(), file, line) }
        #endif
    }

    @inline(__always)
    static func assertNotRenderThread(_ what: @autoclosure () -> String,
                                      file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        if isRenderThread { report(.onRenderThread, what(), file, line) }
        #endif
    }

    /// Heavy work: neither the main thread nor the render thread.
    @inline(__always)
    static func assertBackground(_ what: @autoclosure () -> String,
                                 file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        if Thread.isMainThread { report(.onMainThread, what(), file, line) }
        else if isRenderThread { report(.onRenderThread, what(), file, line) }
        #endif
    }

    /// Per-frame work that must not run anywhere else.
    @inline(__always)
    static func assertRenderThread(_ what: @autoclosure () -> String,
                                   file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        if !isRenderThread { report(.offRenderThread, what(), file, line) }
        #endif
    }

    #if DEBUG
    private static func report(_ kind: Violation.Kind, _ what: String, _ file: StaticString, _ line: UInt) {
        let violation = Violation(kind: kind, what: what, file: "\(file)", line: line)
        lock.lock()
        let first = reported.insert("\(kind.rawValue)|\(violation.file):\(line)").inserted
        let handler = _handler
        lock.unlock()
        if first {
            OWELog.error(.perf, "Thread guard: \(what) ran on the \(kind.rawValue) (\(violation.file):\(line))\n"
                         + Thread.callStackSymbols.prefix(12).joined(separator: "\n"))
        }
        handler(violation)
    }
    #endif
}
