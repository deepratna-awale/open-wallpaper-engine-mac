import Foundation

/// A thread with its own run loop that one scene instance renders on: its displays' links tick
/// there, and every access to the instance's renderer is a block sent to it (`perform`). The main
/// thread only handles UI, windows and displays, so a stall there doesn't delay a frame.
///
/// The whole run loop runs inside `ThreadGuards.renderFrame`, so the thread guards see this thread
/// as the render thread for anything it runs.
final class SceneRenderThread: @unchecked Sendable {
    /// Written once by the thread before `init` returns; read-only afterwards.
    private final class State: @unchecked Sendable {
        var runLoop: RunLoop?
        var stopped = false
        let ready = DispatchSemaphore(value: 0)
    }

    private let thread: Thread
    private let state: State
    /// The thread's run loop. Only the render thread adds sources to it (`RunLoop` isn't thread-safe).
    private let cfRunLoop: CFRunLoop

    init(name: String) {
        let state = State()
        self.state = state
        thread = Thread {
            ThreadGuards.renderFrame {
                state.runLoop = RunLoop.current
                // A port keeps the run loop running while no display link is attached.
                RunLoop.current.add(NSMachPort(), forMode: .default)
                state.ready.signal()
                while !state.stopped {
                    autoreleasepool { _ = RunLoop.current.run(mode: .default, before: .distantFuture) }
                }
            }
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        state.ready.wait()
        cfRunLoop = state.runLoop!.getCFRunLoop()
    }

    var isCurrent: Bool { Thread.current == thread }

    /// The render thread's run loop; only use it from the render thread.
    var runLoop: RunLoop { state.runLoop! }

    /// Thread boundary: runs `block` on the render thread, after the blocks sent before it.
    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(cfRunLoop)
    }

    /// Runs `body` on the render thread and waits for it. For tests and teardown only: the main
    /// thread must never wait on a frame in normal running.
    func sync<T>(_ body: () -> T) -> T {
        if isCurrent { return body() }
        var result: T?
        let done = DispatchSemaphore(value: 0)
        withoutActuallyEscaping(body) { body in
            perform {
                result = body()
                done.signal()
            }
            done.wait()
        }
        return result!
    }

    /// Ends the thread once the blocks already sent have run.
    func stop() {
        let state = state
        perform {
            state.stopped = true
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}
