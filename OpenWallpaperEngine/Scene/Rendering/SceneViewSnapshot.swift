import AppKit
import MetalKit

/// A view's AppKit state as a frame needs it, taken on the main thread (`SceneViewSnapshots.refresh`)
/// so a render thread never reads the view, its window or its screen.
struct SceneViewSnapshot {
    /// The view, in points.
    var pointSize: SIMD2<Float> = .zero
    var frameRateLimit = 60
    /// The view's bounds in screen coordinates, and its screen's frame; nil off-screen.
    var viewInScreen: CGRect?
    var screenFrame: CGRect?
    var headroom = SceneDisplayHeadroom()
    /// The view's layer, which Core Animation lets any thread configure.
    weak var layer: CAMetalLayer?

    /// The cursor in the view's points (origin bottom-left) when `mouse` is on its screen.
    func cursor(at mouse: CGPoint) -> SIMD2<Float>? {
        guard let viewInScreen, let screenFrame, screenFrame.contains(mouse) else { return nil }
        return SIMD2(Float(mouse.x - viewInScreen.minX), Float(mouse.y - viewInScreen.minY))
    }
}

/// The snapshots of the views a render thread draws (`SceneRenderLoop`). A view without one is
/// drawn on the main thread and read directly. Thread-safe.
enum SceneViewSnapshots {
    private static let lock = NSLock()
    private static var snapshots: [ObjectIdentifier: SceneViewSnapshot] = [:]

    /// Main: takes `view`'s state now.
    static func refresh(_ view: MTKView) {
        dispatchPrecondition(condition: .onQueue(.main))
        var snapshot = SceneViewSnapshot()
        snapshot.pointSize = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        snapshot.frameRateLimit = view.preferredFramesPerSecond
        if let window = view.window, let screen = window.screen {
            snapshot.viewInScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
            snapshot.screenFrame = screen.frame
            snapshot.headroom = SceneDisplayHeadroom(screen: screen)
        }
        snapshot.layer = view.layer as? CAMetalLayer
        lock.withLock { snapshots[ObjectIdentifier(view)] = snapshot }
    }

    static func remove(_ id: ObjectIdentifier) {
        lock.withLock { snapshots[id] = nil }
    }

    static func snapshot(of view: MTKView) -> SceneViewSnapshot? {
        lock.withLock { snapshots[ObjectIdentifier(view)] }
    }
}
