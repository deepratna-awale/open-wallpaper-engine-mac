import XCTest
import MetalKit
@testable import OpenWallpaperEngine

/// One scene for several displays (docs/architecture.md "Wallpaper instances"): one render per
/// frame at the largest scene target the displays need, presented on each at its own size and
/// placement; one script runtime stepped once per frame; one player for a video.
@MainActor
final class SceneSharedInstanceTests: XCTestCase {
    private var storage: URL!

    override func setUpWithError() throws {
        storage = FileManager.default.temporaryDirectory.appending(path: "owe-shared-instance-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let storage, FileManager.default.fileExists(atPath: storage.path) {
            try FileManager.default.removeItem(at: storage)
        }
    }

    private func view(_ width: Int, _ height: Int, device: MTLDevice) -> MTKView {
        // Made as the app makes its scene views: the view's own timer stopped from the start, so
        // only the render thread draws (an unpaused `MTKView` draws on main before `show`).
        let view = SceneRenderLoop.makeView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: width, height: height)
        return view
    }

    /// The first green column along the middle row of `view`'s last presented frame.
    private func seam(in view: MTKView) throws -> Int {
        let texture = try XCTUnwrap(view.currentDrawable?.texture)
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&pixels, bytesPerRow: texture.width * 4,
                         from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        let row = texture.height / 2
        return try XCTUnwrap((0..<texture.width).first { x in
            let index = (row * texture.width + x) * 4
            return pixels[index + 1] > 128 && pixels[index + 2] < 128
        }, "no green in the row")
    }

    /// Two fake displays, 64×64 and 128×64, showing one 64×64 scene fitted: one render, and each
    /// display presents the same frame at its own size (the wider one letterboxed by 32 pixels).
    func testDisplaysPresentTheSameFrameAtTheirOwnSizeAndPlacement() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(SceneMetalRenderer(pixelFormat: .bgra8Unorm))
        let small = view(64, 64, device: device), wide = view(128, 64, device: device)
        for display in [small, wide] {
            renderer.configure(display)
            display.isPaused = true
            display.framebufferOnly = false
        }
        renderer.setPlacement(.fit)
        var layer = SceneMetalLayer(
            id: "1", name: "halves", source: .image(try Self.halves()), position: SIMD2(40, 32),
            size: SIMD2(128, 64), scale: SIMD2(1, 1), opacity: 1, brightness: 1, color: SIMD4(repeating: 1),
            text: nil, parallaxDepth: .zero, perspective: false, rotation: 0, effects: .identity)
        layer.order = 0
        renderer.setContent(SceneMetalContent(
            size: SIMD2(64, 64), layers: [layer], particleSystems: [],
            bloom: SceneBloomSettings(enabled: false, strength: 0, threshold: 0.7, tint: SIMD3(repeating: 1))))
        let deadline = Date().addingTimeInterval(10)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }

        var renders = 0
        renderer.frameTimeObserver = { _ in renders += 1 }
        renderer.renderShared([SceneViewport(small), SceneViewport(wide)])
        renderer.present(in: small)
        renderer.lastPresentCommandBuffer?.waitUntilCompleted()
        renderer.present(in: wide)
        renderer.lastPresentCommandBuffer?.waitUntilCompleted()

        XCTAssertEqual(renders, 1, "one render for both displays")
        let frame = try XCTUnwrap(renderer.sharedFrame)
        XCTAssertEqual(frame.width, 128, "the scene target the wider display needs (2 pixels a unit)")
        XCTAssertEqual(frame.height, 128)
        XCTAssertEqual(try seam(in: small), 40, "scene x 40 at one pixel a unit")
        XCTAssertEqual(try seam(in: wide), 32 + 40, "fitted: centred with 32 black columns each side")
        renderer.releaseContent()
    }

    /// A loading snapshot is the shared frame as a display of its size shows it: one 64×64 scene
    /// fitted onto 128×64 pixels, letterboxed like `present(in:)`, read back into an image.
    func testLoadingSnapshotCopiesTheFrameAsTheDisplayShowsIt() throws {
        let renderer = try XCTUnwrap(SceneMetalRenderer(pixelFormat: .bgra8Unorm))
        renderer.setPlacement(.fit)
        var layer = SceneMetalLayer(
            id: "1", name: "halves", source: .image(try Self.halves()), position: SIMD2(40, 32),
            size: SIMD2(128, 64), scale: SIMD2(1, 1), opacity: 1, brightness: 1, color: SIMD4(repeating: 1),
            text: nil, parallaxDepth: .zero, perspective: false, rotation: 0, effects: .identity)
        layer.order = 0
        renderer.setContent(SceneMetalContent(
            size: SIMD2(64, 64), layers: [layer], particleSystems: [],
            bloom: SceneBloomSettings(enabled: false, strength: 0, threshold: 0.7, tint: SIMD3(repeating: 1))))
        let deadline = Date().addingTimeInterval(10)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        defer { renderer.releaseContent() }

        XCTAssertFalse(renderer.captureSharedFrame(pixelSize: SIMD2(128, 64), pixelsPerPoint: 1) { _ in },
                       "nothing to copy before a shared frame")
        renderer.renderShared([SceneViewport(drawableSize: SIMD2(128, 64), pointSize: SIMD2(128, 64), cursor: nil, frameRateLimit: 30)])
        let captured = expectation(description: "captured")
        nonisolated(unsafe) var image: CGImage?  // Written once by the completion, read after the wait.
        XCTAssertTrue(renderer.captureSharedFrame(pixelSize: SIMD2(128, 64), pixelsPerPoint: 1) {
            image = $0
            captured.fulfill()
        })
        wait(for: [captured], timeout: 10)
        renderer.releaseSharedFrame()
        XCTAssertNil(renderer.sharedFrame)

        let snapshot = try XCTUnwrap(image)
        XCTAssertEqual(snapshot.width, 128)
        XCTAssertEqual(snapshot.height, 64)
        let context = try XCTUnwrap(CGContext(data: nil, width: 128, height: 64, bitsPerComponent: 8, bytesPerRow: 128 * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(snapshot, in: CGRect(x: 0, y: 0, width: 128, height: 64))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let row = 32
        let seam = (0..<128).first { x in
            let index = (row * 128 + x) * 4
            return pixels[index + 1] > 128 && pixels[index] < 128
        }
        XCTAssertEqual(seam, 32 + 40, "fitted: centred with 32 black columns each side")
        XCTAssertLessThan(pixels[(row * 128 + 10) * 4], 16, "letterbox is black")
    }

    /// Two displays drawing a scripted scene every frame: one script runtime, one script frame and
    /// one render per frame, and the scene's one set of sound layers.
    func testTwoDisplaysStepTheScriptsOncePerFrame() throws {
        let directory = Fixtures.url("Scenes/scripted-counter")
        defer { Fixtures.removeStoredSettings(for: directory) }
        let project = try JSONDecoder().decode(WEProject.self, from: Fixtures.data("Scenes/scripted-counter/project.json"))
        let wallpaper = WEWallpaper(using: project, where: directory)
        let wallpapers = WallpaperViewModel(persistsWallpapers: false)
        wallpapers.playVolume = 0
        // Paused views: only the test's draws render (the instance pauses them at rate 0).
        wallpapers.playRate = 0
        let services = SceneScriptServices(prelude: SceneScriptPrelude.load(), storage: SceneScriptStorage(directory: storage),
                                           media: SceneScriptReplayMediaSource(), spectrum: { .silent })
        let environment = SceneWallpaperEnvironment(wallpapers: wallpapers, settings: GlobalSettingsViewModel(),
                                                    scriptServices: services)
        var made = 0
        func lease() -> SceneWallpaperPresenter.Lease {
            SceneWallpaperPresenter.Lease(wallpapers.sceneInstances, key: WallpaperInstanceKey(wallpaper)) {
                made += 1
                return SceneWallpaperInstance(wallpaper: wallpaper, environment: environment, screenID: "A")
            }
        }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let left = SceneWallpaperPresenter(), right = SceneWallpaperPresenter()
        let leftView = view(64, 64, device: device), rightView = view(96, 64, device: device)
        left.show(lease(), in: leftView, screenID: "A")
        right.show(lease(), in: rightView, screenID: "B")
        defer {
            left.stop()
            right.stop()
        }
        let instance = try XCTUnwrap(left.instance)
        XCTAssertIdentical(instance, right.instance)
        XCTAssertEqual(made, 1)
        XCTAssertEqual(instance.displayCount, 2)
        let renderer = try XCTUnwrap(instance.renderer)
        // The renderer lives on the instance's render thread: the test reaches it there.
        let thread = instance.renderLoop.thread

        let deadline = Date().addingTimeInterval(30)
        while !thread.sync({ renderer.hasContent && renderer.scripts.wallpaper != nil }), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let runtime = try XCTUnwrap(thread.sync { renderer.scripts.wallpaper }, "the scene's scripts run")
        var renders = 0
        thread.sync { renderer.frameTimeObserver = { _ in renders += 1 } }
        let framesBefore = runtime.frameTiming.frames
        let loop = instance.renderLoop
        for _ in 0..<5 {
            thread.sync {
                loop.draw(ObjectIdentifier(left), in: leftView)
                loop.draw(ObjectIdentifier(right), in: rightView)
                renderer.lastPresentCommandBuffer?.waitUntilCompleted()
            }
            runtime.waitUntilIdle()
        }
        XCTAssertEqual(thread.sync { renders }, 5, "the driving display renders; the other presents")
        XCTAssertEqual(runtime.frameTiming.frames - framesBefore, 5, "one script frame per frame")
        XCTAssertIdentical(thread.sync { renderer.scripts.wallpaper }, runtime, "one runtime for both displays")
    }

    /// The AVKit path: two displays of one video share its player, so its sound plays once.
    func testTwoDisplaysOfAVideoShareOnePlayer() {
        let wallpapers = WallpaperViewModel(persistsWallpapers: false)
        wallpapers.playVolume = 0
        wallpapers.audioOutputEnabled = false
        let video = WallpaperViewModel.defaultWallpaper
        typealias Lease = WallpaperInstanceLease<WallpaperInstanceKey, VideoWallpaperViewModel>
        var made = 0
        let make = { () -> VideoWallpaperViewModel in
            made += 1
            return VideoWallpaperViewModel(wallpaper: video, wallpaperViewModel: wallpapers)
        }
        let left = Lease(wallpapers.videoInstances, key: WallpaperInstanceKey(video), make: make)
        let right = Lease(wallpapers.videoInstances, key: WallpaperInstanceKey(video), make: make)
        XCTAssertEqual(made, 1)
        XCTAssertIdentical(left.instance, right.instance)
        XCTAssertIdentical(left.instance.player, right.instance.player, "one player for both views")
        left.release()
        right.release()
    }

    /// A 128×1 image: 64 red texels, then 64 green.
    private static func halves() throws -> NSImage {
        let bytes: [UInt8] = Array(repeating: [255, 0, 0, 255], count: 64).flatMap { $0 }
            + Array(repeating: [0, 255, 0, 255], count: 64).flatMap { $0 }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: 128, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 512,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder32Big),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return NSImage(cgImage: image, size: NSSize(width: 128, height: 1))
    }
}
