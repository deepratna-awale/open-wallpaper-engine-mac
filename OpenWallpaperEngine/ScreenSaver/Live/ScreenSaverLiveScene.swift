import AppKit
import Metal
import QuartzCore

/// One loop of the screen saver's layout drawn live while the screen saver runs: the scene
/// wallpaper loaded by the real loader (`SceneWallpaperViewModel`, in the background) and drawn by
/// the real renderer (`SceneMetalRenderer`) on its own render thread (`SceneRenderThread`), as the
/// screen saver (`engine.isScreensaver()` true, silent, the pointer held at the centre, its clock
/// layers drawn), at the loop's pixel size, into its ring of surfaces
/// (`ScreenSaverFramePublisher`) through the same placement a display presents with
/// (`encodeSharedFrame`). The audio spectrum is the app's own capture, so audio-reactive scenes
/// follow the music. Paced by a display link of the loop's first display at the user's frame
/// rate, capped by the power policy and the display.
@MainActor
final class ScreenSaverLiveScene {
    /// What it draws.
    struct Target: Equatable {
        var ring: Int
        var pixels: SIMD2<Int>
        var points: SIMD2<Int>
        var frameRate: Int
    }

    let target: Target
    private let viewModel: SceneWallpaperViewModel
    private let thread: SceneRenderThread
    /// Render thread only, once made.
    private let renderer: SceneMetalRenderer?
    private let publisher: ScreenSaverFramePublisher
    private var link: CADisplayLink?
    private let ticker: Ticker

    init?(wallpaper: WEWallpaper, propertyScope: WallpaperPropertyScope, target: Target, screen: NSScreen?,
          settings: GlobalSettings, placement: WallpaperPlacement, scriptServices: SceneScriptServices?,
          publisher: ScreenSaverFramePublisher) {
        let name = wallpaper.wallpaperDirectory.lastPathComponent
        guard let renderer = SceneMetalRenderer(pixelFormat: .bgra8Unorm, scriptServices: scriptServices,
                                                screenID: "screensaver-live-\(name)") else {
            OWELog.error(.app, "Live screen saver: no Metal renderer for \(name)")
            return nil
        }
        self.target = target
        self.publisher = publisher
        self.renderer = renderer
        viewModel = SceneWallpaperViewModel(wallpaper: wallpaper, propertyScope: propertyScope, loadsInBackground: true)
        thread = SceneRenderThread(name: "OWE screen saver \(name)")
        let pixels = SIMD2(Float(target.pixels.x), Float(target.pixels.y))
        let renderSettings = SceneRenderSettings(settings, outputPixels: pixels, sceneSize: viewModel.textureReductionSceneSize)
        viewModel.setRenderSettings(renderSettings)
        renderer.performOnRenderThread = { [thread] block in thread.perform(block) }
        renderer.drawsOnRenderThreadOnly = true
        renderer.rendersScreenSaver = true
        renderer.hidesClockLayers = false
        renderer.renderSettings = renderSettings
        renderer.fixedPointer = SIMD2(0.5, 0.5)
        renderer.setPlacement(placement)
        renderer.sounds.setTargetGain(0)
        let viewport = SceneViewport(drawableSize: pixels, pointSize: SIMD2(Float(target.points.x), Float(target.points.y)),
                                     cursor: nil, frameRateLimit: target.frameRate)
        ticker = Ticker(renderer: renderer, viewport: viewport, ring: target.ring, publisher: publisher)
        // Loaded on the preparation pool; frames start once the content lands on the render thread.
        viewModel.contentAsync { [thread, renderer] content in
            thread.perform { renderer.setContent(content) }
            if content == nil { OWELog.error(.app, "Live screen saver: \(name) has no scene content") }
        }
        startLink(screen: screen)
        OWELog.info(.app, "Live screen saver: drawing \(name) at \(target.pixels.x)×\(target.pixels.y), \(target.frameRate) fps, ring \(target.ring)")
    }

    /// Stops the frames and the render thread, and lets the scene go.
    func shutdown() {
        let link = link
        self.link = nil
        thread.perform { [renderer] in
            link?.invalidate()
            renderer?.releaseContent()
        }
        thread.stop()
    }

    private func startLink(screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else {
            OWELog.error(.app, "Live screen saver: no display to pace the frames by")
            return
        }
        let link = screen.displayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
        let rate = Float(target.frameRate)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(rate, 10), maximum: rate, preferred: rate)
        self.link = link
        thread.perform { [thread] in link.add(to: thread.runLoop, forMode: .default) }
    }

    /// The display link's target, on the render thread: a frame, then its copy into the ring.
    private final class Ticker: NSObject {
        private let renderer: SceneMetalRenderer
        private let viewport: SceneViewport
        private let ring: Int
        private let publisher: ScreenSaverFramePublisher

        init(renderer: SceneMetalRenderer, viewport: SceneViewport, ring: Int, publisher: ScreenSaverFramePublisher) {
            self.renderer = renderer
            self.viewport = viewport
            self.ring = ring
            self.publisher = publisher
        }

        @objc func tick(_ link: CADisplayLink) {
            guard renderer.hasContent else { return }
            renderer.renderShared([viewport])
            guard let target = publisher.target(ring: ring),
                  let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }
            commandBuffer.label = "Live screen saver frame"
            guard renderer.encodeSharedFrame(into: target.texture, pixelsPerPoint: viewport.pixelsPerPoint,
                                             commandBuffer: commandBuffer) else { return }
            let publisher = publisher, ring = ring, slot = target.slot, generation = target.generation
            commandBuffer.addCompletedHandler { finished in
                guard finished.status == .completed else { return }
                publisher.drawn(ring: ring, slot: slot, generation: generation)
            }
            commandBuffer.commit()
        }
    }
}
