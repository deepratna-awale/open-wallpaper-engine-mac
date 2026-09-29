import XCTest
import MetalKit
@testable import OpenWallpaperEngine

/// A scene renders on its own render thread (`SceneRenderLoop`): its displays' links draw there,
/// not on the main thread, so a main-thread stall doesn't hold back frames.
@MainActor
final class SceneRenderThreadTests: XCTestCase {
    /// What the frames saw, written on the render thread.
    private final class Frames: @unchecked Sendable {
        private let lock = NSLock()
        private var times: [CFTimeInterval] = []
        private var offMain = true
        private var onRenderThread = true

        func record() {
            let main = Thread.isMainThread, render = ThreadGuards.isRenderThread
            lock.withLock {
                times.append(CACurrentMediaTime())
                offMain = offMain && !main
                onRenderThread = onRenderThread && render
            }
        }

        var count: Int { lock.withLock { times.count } }
        func count(between start: CFTimeInterval, and end: CFTimeInterval) -> Int {
            lock.withLock { times.filter { $0 >= start && $0 <= end }.count }
        }
        var allOffMain: Bool { lock.withLock { offMain } }
        var allOnRenderThread: Bool { lock.withLock { onRenderThread } }
    }

    private var window: NSWindow?
    private var loop: SceneRenderLoop?
    /// The view holds its delegate weakly.
    private var delegate: Delegate?

    override func tearDown() {
        loop?.shutdown()
        loop = nil
        delegate = nil
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }

    /// A render loop drawing one on-screen view, its frames recorded in `frames`.
    private func startLoop(_ frames: Frames) throws -> SceneRenderLoop {
        let screen = try XCTUnwrap(NSScreen.main, "needs a display")
        let renderer = try XCTUnwrap(SceneMetalRenderer(pixelFormat: .bgra8Unorm))
        renderer.frameTimeObserver = { _ in frames.record() }
        let loop = SceneRenderLoop(renderer: renderer, name: "test render")
        self.loop = loop
        let window = NSWindow(contentRect: CGRect(x: screen.frame.minX, y: screen.frame.minY, width: 64, height: 64),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        renderer.configure(view)
        let delegate = Delegate(loop: loop)
        self.delegate = delegate
        let id = ObjectIdentifier(delegate)
        // As the instance does: the link takes over (the view's own timer stops) before the view
        // gets its delegate and goes on screen.
        loop.attach(id, view: view, state: SceneRenderLoop.DisplayState(refresh: screen.maximumFramesPerSecond))
        view.delegate = delegate
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
        var playback = SceneRenderLoop.Playback()
        playback.displays[id] = SceneRenderLoop.DisplayState(refresh: screen.maximumFramesPerSecond)
        loop.update(playback)
        return loop
    }

    /// Forwards the view's draws to the loop, as `SceneWallpaperPresenter` does.
    private final class Delegate: NSObject, MTKViewDelegate {
        let loop: SceneRenderLoop
        init(loop: SceneRenderLoop) { self.loop = loop }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) { loop.draw(ObjectIdentifier(self), in: view) }
    }

    private func waitForFrames(_ frames: Frames, atLeast count: Int, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while frames.count < count, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testDrawRunsOffTheMainThread() throws {
        let frames = Frames()
        _ = try startLoop(frames)
        waitForFrames(frames, atLeast: 3)
        XCTAssertGreaterThanOrEqual(frames.count, 3, "the display link draws")
        XCTAssertTrue(frames.allOffMain, "every frame draws off the main thread")
        #if DEBUG
        XCTAssertTrue(frames.allOnRenderThread, "the thread guards see the render thread")
        #endif
    }

    func testMainThreadStallDoesNotDelayFrames() throws {
        let frames = Frames()
        _ = try startLoop(frames)
        waitForFrames(frames, atLeast: 2)
        XCTAssertGreaterThanOrEqual(frames.count, 2, "the display link draws")
        let start = CACurrentMediaTime()
        // The main thread stalls for half a second; the render thread keeps drawing.
        Thread.sleep(forTimeInterval: 0.5)
        let end = CACurrentMediaTime()
        XCTAssertGreaterThanOrEqual(frames.count(between: start, and: end), 3, "frames kept coming while main stalled")
    }
}
