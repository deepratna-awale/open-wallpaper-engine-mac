import JavaScriptCore
import MetalKit
import XCTest
@testable import OpenWallpaperEngine

/// A scene folder loaded through the real loader into a `SceneMetalRenderer` on one offscreen
/// view, drawn headlessly with its wall clock stepped by hand (as `TimelineRenderTests` does),
/// with the scripts waited for every frame.
final class SceneFrameHarness {
    let renderer: SceneMetalRenderer
    let view: MTKView
    let directory: URL
    let model: SceneWallpaperViewModel
    let size: SIMD2<Int>
    /// The wall clock the renderer reads.
    var now: CFTimeInterval = 1000

    init(directory: URL, scope: WallpaperPropertyScope = .shared, size: SIMD2<Int> = SIMD2(128, 64),
         services: SceneScriptServices? = nil, screenID: String = "harness",
         configure: (SceneMetalRenderer) -> Void = { _ in }) throws {
        // The CI scenes draw WE's util models (`models/util/solidlayer.json`), which come from the assets.
        _ = try Fixtures.assets()
        self.directory = directory
        self.size = size
        let project = try JSONDecoder().decode(WEProject.self, from: Data(contentsOf: directory.appending(path: "project.json")))
        model = SceneWallpaperViewModel(wallpaper: WEWallpaper(using: project, where: directory), propertyScope: scope)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        view = MTKView(frame: CGRect(x: 0, y: 0, width: size.x, height: size.y), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: size.x, height: size.y)
        renderer = try XCTUnwrap(SceneMetalRenderer(view: view, scriptServices: services, screenID: screenID))
        view.isPaused = true
        renderer.setPlacement(.stretch)
        renderer.scripts.frameWait = 5
        renderer.wallTime = { [unowned self] in self.now }
        // Before the content: a draw can land while the load is waited for.
        configure(renderer)
        renderer.setContent(try XCTUnwrap(model.metalContent()))
        let deadline = Date().addingTimeInterval(60)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(renderer.hasContent)
    }

    func close() {
        renderer.releaseContent()
        Fixtures.removeStoredSettings(for: directory)
    }

    /// Draws `frames` frames, the wall clock `step` further each, waiting for each frame's
    /// scripts and GPU work.
    func draw(frames: Int, step: Double = 1.0 / 60) {
        for _ in 0..<frames {
            now += step
            renderer.draw(in: view)
            renderer.lastCommandBuffer?.waitUntilCompleted()
            renderer.scripts.wallpaper?.waitUntilIdle()
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
    }

    /// `expression` evaluated in the scripts' context (their `shared` object is global there), as
    /// a string.
    func evaluate(_ expression: String) throws -> String? {
        let wallpaper = try XCTUnwrap(renderer.scripts.wallpaper)
        return wallpaper.thread.sync { wallpaper.scriptRuntime?.context.evaluateScript(expression)?.toString() }
    }
}
