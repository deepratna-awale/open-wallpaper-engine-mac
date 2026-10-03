import XCTest
import ImageIO
import MetalKit
import simd
@testable import OpenWallpaperEngine

/// Measures each fullscreen-layer change (`SceneFullscreenEffectOptions`) on library wallpapers:
/// GPU time per frame against the render without any of them, and SSIM of what a display shows
/// against that render. Only runs when asked: `OWE_FX_MEASURE` (`TEST_RUNNER_OWE_FX_MEASURE`
/// through xcodebuild) lists workshop ids (`default` for rain 1444077782, Tsunade 3742916237 and
/// witcher 3803167460); skipped without the library (`OWE_LIBRARY`).
///
/// - `OWE_FX_MEASURE_SIZE`: the drawable (default 3840x2160, a 4K display at 2×), placed `fill`.
/// - `OWE_FX_MEASURE_ROUNDS`: rounds of every variant, alternated (default 3); a variant's GPU
///   time is the median (and least) of its frames over every round.
/// - `OWE_FX_MEASURE_OUT`: a folder for the report, and each variant's frames and difference ×8.
///
/// GPU rows draw the whole scene, particles included. SSIM rows draw it without particle systems
/// (two renderers' GPU simulations don't draw the same particles), with the clock stepped 1/60 s
/// a frame, and compare the display's picture (`encodeSharedFrame`) after the warm-up and 45
/// frames later. The gate is the optimisation rule's: SSIM ≥ 0.98 (docs/optimizations.md).
final class FullscreenEffectMeasureTests: XCTestCase {
    private static let defaultWallpapers = ["1444077782", "3742916237", "3803167460"]
    private static let warmFrames = 150
    private static let timedFrames = 60
    private static let comparedFrames = [0, 45]

    private var storage: URL!

    override func setUpWithError() throws {
        storage = FileManager.default.temporaryDirectory.appending(path: "owe-fx-measure-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let storage, FileManager.default.fileExists(atPath: storage.path) {
            try FileManager.default.removeItem(at: storage)
        }
    }

    private struct Variant {
        let name: String
        let options: SceneFullscreenEffectOptions
    }

    /// Every change alone over the reference, then all of them.
    private static let variants: [Variant] = [
        Variant(name: "baseline", options: .none),
        Variant(name: "clamp", options: SceneFullscreenEffectOptions(clampToVisible: true, aliasCopies: false,
                                                                     halfResolutionAccumulation: false)),
        Variant(name: "copy alias", options: SceneFullscreenEffectOptions(clampToVisible: false, aliasCopies: true,
                                                                          halfResolutionAccumulation: false)),
        Variant(name: "half accum", options: SceneFullscreenEffectOptions(clampToVisible: false, aliasCopies: false,
                                                                          halfResolutionAccumulation: true)),
        Variant(name: "all", options: SceneFullscreenEffectOptions(clampToVisible: true, aliasCopies: true,
                                                                   halfResolutionAccumulation: true)),
    ]

    func testFullscreenEffectChanges() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let request = environment["OWE_FX_MEASURE"], !request.isEmpty else {
            throw XCTSkip("set OWE_FX_MEASURE to measure the fullscreen-layer changes")
        }
        let library = LibrarySweepTests.libraryRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: library.path), "wallpaper library not present")
        let ids = request == "default" ? Self.defaultWallpapers : request.split(separator: ",").map(String.init)
        let parts = (environment["OWE_FX_MEASURE_SIZE"] ?? "3840x2160").split(separator: "x").compactMap { Int($0) }
        let drawable = SIMD2(parts.first ?? 3840, parts.count > 1 ? parts[1] : 2160)
        let rounds = max(1, Int(environment["OWE_FX_MEASURE_ROUNDS"] ?? "") ?? 3)
        let output = environment["OWE_FX_MEASURE_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        var report = [String(format: "Fullscreen-layer changes at %dx%d (fill), %d rounds: GPU ms median / least over every "
                             + "round's frames, against the baseline; SSIM of the display's picture without particles "
                             + "at frames %d and %d after the warm-up", drawable.x, drawable.y, rounds,
                             Self.comparedFrames[0], Self.comparedFrames[1]),
                      "| wallpaper | variant | GPU median | Δ | GPU least | SSIM | min SSIM | clamped layers |",
                      "|---|---|---|---|---|---|---|---|"]
        for id in ids {
            let directory = library.appending(path: id, directoryHint: .isDirectory)
            let data = try XCTUnwrap(FileManager.default.contents(atPath: directory.appending(path: "project.json").path))
            let project = try JSONDecoder().decode(WEProject.self, from: data)
            defer { Fixtures.removeStoredSettings(for: directory) }
            let model = SceneWallpaperViewModel(wallpaper: WEWallpaper(using: project, where: directory))
            var settings = SceneRenderSettings()
            settings.particleBudget = .unlimited
            model.setRenderSettings(settings)
            let content = try XCTUnwrap(model.metalContent())

            // GPU time: every variant once per round, in turn, so drift spreads over all of them.
            var gpu: [String: [Double]] = [:]
            var clamped: [String: Int] = [:]
            for _ in 0..<rounds {
                for variant in Self.variants {
                    let timing = try gpuFrames(content, drawable: drawable, settings: settings, options: variant.options)
                    gpu[variant.name, default: []] += timing.milliseconds
                    clamped[variant.name] = timing.clampedLayers
                }
            }
            // Pictures: the baseline, then each variant against it.
            let still = Self.withoutParticles(content)
            let reference = try pictures(still, drawable: drawable, settings: settings, options: SceneFullscreenEffectOptions.none)
            let baselineMedian = Self.median(gpu["baseline"] ?? [])
            for variant in Self.variants {
                let times = gpu[variant.name] ?? []
                let median = Self.median(times)
                let frames = variant.name == "baseline" ? reference
                    : try pictures(still, drawable: drawable, settings: settings, options: variant.options)
                let ssims = zip(reference, frames).map { PerceptualCompare.ssim($0, $1) }
                let mean = ssims.isEmpty ? 1 : ssims.reduce(0, +) / Double(ssims.count)
                let delta = baselineMedian > 0 ? (median - baselineMedian) / baselineMedian * 100 : 0
                report.append(String(format: "| %@ %@ | %@ | %.2f ms | %+.1f %% | %.2f ms | %.4f | %.4f | %d |",
                                     id, String(project.title.prefix(24)), variant.name, median, delta, times.min() ?? 0, mean,
                                     ssims.min() ?? 1, clamped[variant.name] ?? 0))
                print(report.last!)
                if variant.name != "baseline" {
                    XCTAssertGreaterThanOrEqual(ssims.min() ?? 1, 0.98, "\(id) \(variant.name): perceptual gate")
                }
                if let output {
                    let folder = output.appending(path: "\(id)-\(drawable.x)x\(drawable.y)", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for (index, frame) in frames.enumerated() {
                        let name = variant.name.replacingOccurrences(of: " ", with: "-")
                        try Self.png(frame, to: folder.appending(path: "\(name)-\(Self.comparedFrames[index]).png"))
                        if variant.name != "baseline" {
                            try Self.png(Self.amplifiedDifference(reference[index], frame),
                                         to: folder.appending(path: "\(name)-\(Self.comparedFrames[index])-diff×8.png"))
                        }
                    }
                }
            }
        }
        let text = report.joined(separator: "\n")
        print(text)
        if let output {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try text.write(to: output.appending(path: "fullscreen-effects.md"), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Drawing

    private func makeRenderer(_ content: SceneMetalContent, drawable: SIMD2<Int>, settings: SceneRenderSettings,
                              options: SceneFullscreenEffectOptions)
        throws -> (renderer: SceneMetalRenderer, view: MTKView, viewport: SceneViewport, clock: () -> Void) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: drawable.x / 2, height: drawable.y / 2), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: drawable.x, height: drawable.y)
        let services = SceneScriptServices(prelude: SceneScriptPrelude.load(), storage: SceneScriptStorage(directory: storage),
                                           media: SceneScriptReplayMediaSource(), spectrum: { .silent })
        let renderer = try XCTUnwrap(SceneMetalRenderer(view: view, scriptServices: services, screenID: "fx-measure"))
        view.isPaused = true
        renderer.renderSettings = settings
        renderer.fullscreenEffectOptions = options
        renderer.setPlacement(.fill)
        renderer.scripts.frameWait = 5
        var now: CFTimeInterval = 1000
        renderer.wallTime = { now }
        renderer.setContent(content)
        let deadline = Date().addingTimeInterval(60)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        let viewport = SceneViewport(drawableSize: SIMD2(Float(drawable.x), Float(drawable.y)),
                                     pointSize: SIMD2(Float(drawable.x / 2), Float(drawable.y / 2)), cursor: nil,
                                     frameRateLimit: 60)
        return (renderer, view, viewport, { now += 1.0 / 60 })
    }

    /// GPU milliseconds of `timedFrames` frames after the warm-up, and how many layers the last
    /// frame drew clamped.
    private func gpuFrames(_ content: SceneMetalContent, drawable: SIMD2<Int>, settings: SceneRenderSettings,
                           options: SceneFullscreenEffectOptions) throws -> (milliseconds: [Double], clampedLayers: Int) {
        let made = try makeRenderer(content, drawable: drawable, settings: settings, options: options)
        defer { made.renderer.releaseContent() }
        var times: [Double] = []
        for frame in 0..<(Self.warmFrames + Self.timedFrames) {
            made.clock()
            made.renderer.renderShared([made.viewport])
            guard let buffer = made.renderer.lastCommandBuffer else { continue }
            buffer.waitUntilCompleted()
            made.renderer.scripts.wallpaper?.waitUntilIdle()
            // Pipelines compile off the render thread; give them the warm-up's time.
            RunLoop.main.run(until: Date().addingTimeInterval(frame < Self.warmFrames ? 0.01 : 0))
            if frame >= Self.warmFrames { times.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000) }
        }
        return (times, made.renderer.clampedLayerIDs.count)
    }

    /// The display's picture (the shared frame placed at `fill`) at `comparedFrames` after the warm-up.
    private func pictures(_ content: SceneMetalContent, drawable: SIMD2<Int>, settings: SceneRenderSettings,
                          options: SceneFullscreenEffectOptions) throws -> [PerceptualImage] {
        let made = try makeRenderer(content, drawable: drawable, settings: settings, options: options)
        defer { made.renderer.releaseContent() }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: drawable.x,
                                                                  height: drawable.y, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let readable = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: drawable.x,
                                                                height: drawable.y, mipmapped: false)
        readable.storageMode = .shared
        let copy = try XCTUnwrap(device.makeTexture(descriptor: readable))
        var images: [PerceptualImage] = []
        let last = Self.warmFrames + (Self.comparedFrames.max() ?? 0)
        for frame in 0...last {
            made.clock()
            made.renderer.renderShared([made.viewport])
            made.renderer.lastCommandBuffer?.waitUntilCompleted()
            made.renderer.scripts.wallpaper?.waitUntilIdle()
            RunLoop.main.run(until: Date().addingTimeInterval(frame < Self.warmFrames ? 0.01 : 0))
            guard frame >= Self.warmFrames, Self.comparedFrames.contains(frame - Self.warmFrames) else { continue }
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertTrue(made.renderer.encodeSharedFrame(into: target, pixelsPerPoint: made.viewport.pixelsPerPoint,
                                                          commandBuffer: buffer))
            let blit = try XCTUnwrap(buffer.makeBlitCommandEncoder())
            blit.copy(from: target, to: copy)
            blit.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: drawable.x * drawable.y * 4)
            copy.getBytes(&bytes, bytesPerRow: drawable.x * 4, from: MTLRegionMake2D(0, 0, drawable.x, drawable.y), mipmapLevel: 0)
            // BGRA → RGBA, opaque.
            for index in stride(from: 0, to: bytes.count, by: 4) {
                bytes.swapAt(index, index + 2)
                bytes[index + 3] = 255
            }
            images.append(PerceptualImage(width: drawable.x, height: drawable.y, rgba: bytes))
        }
        return images
    }

    private static func withoutParticles(_ content: SceneMetalContent) -> SceneMetalContent {
        var copy = SceneMetalContent(size: content.size, layers: content.layers, particleSystems: [], bloom: content.bloom)
        copy.transforms = content.transforms
        copy.motions = content.motions
        copy.camera = content.camera
        copy.wallpaperKey = content.wallpaperKey
        copy.visibility = content.visibility
        copy.objectIDs = content.objectIDs
        copy.scripts = content.scripts
        copy.timelines = content.timelines
        copy.sounds = content.sounds
        copy.lighting = content.lighting
        copy.volumetrics = content.volumetrics
        copy.engineCombos = content.engineCombos
        copy.bloomChain = content.bloomChain
        copy.hdrChain = content.hdrChain
        return copy
    }

    private static func median(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.sorted()[values.count / 2]
    }

    private static func amplifiedDifference(_ a: PerceptualImage, _ b: PerceptualImage) -> PerceptualImage {
        var pixels = [UInt8](repeating: 255, count: a.rgba.count)
        for index in stride(from: 0, to: min(a.rgba.count, b.rgba.count), by: 4) {
            for channel in 0..<3 {
                pixels[index + channel] = UInt8(min(255, abs(Int(a.rgba[index + channel]) - Int(b.rgba[index + channel])) * 8))
            }
        }
        return PerceptualImage(width: a.width, height: a.height, rgba: pixels)
    }

    private static func png(_ image: PerceptualImage, to url: URL) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(image.rgba) as CFData))
        let picture = try XCTUnwrap(CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, picture, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
