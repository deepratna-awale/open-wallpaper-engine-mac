import AVFoundation
import CoreGraphics
import CoreVideo
import Metal

/// Renders a scene wallpaper's seamless loop video for the screen saver, in the app's helper run
/// (`ShaderPrewarmCommand`, `--render-screensaver-loop`), at background priority in its own
/// process: never on the app's main or render thread.
///
/// The scene is loaded by the real loader and drawn offscreen by the real renderer, with
/// `engine.isScreensaver()` true, no sound and a silent spectrum, on a fixed frame step, so frame
/// `i` shows scene time `i / frameRate`. The loop length:
/// 1. **Known periods** (`ScreenSaverLoopLength`): with no particles or scripts and only periodic
///    timelines and sprite sheets, the least common multiple of their periods, capped. The frame
///    after the last is rendered too and checked against frame 0; a scene whose other motion (an
///    effect's `g_Time`) doesn't follow falls through to 2.
/// 2. **Search** (`ScreenSaverSeamFinder`): up to the cap is rendered and compared with frame 0;
///    the loop ends before the best match after the minimum length, and is rendered again into
///    the video, crossfading the seam when it is still visible.
///
/// The video is HEVC through `AVAssetWriter`, at the display's pixel size, written to a partial
/// file and moved into place when complete.
@MainActor
struct ScreenSaverLoopRenderer {
    var wallpaper: WEWallpaper
    var pixelSize: SIMD2<Int>
    var pointSize: SIMD2<Float>
    var output: URL
    var defaults: UserDefaults
    var timeoutSeconds: TimeInterval = 120
    /// The scripts run as they do on the desktop, with `engine.isScreensaver()` true, no media
    /// session and no sound; their `localStorage` is a scratch folder, so the loop never changes
    /// what the wallpaper's scripts saved.
    var scriptServices: SceneScriptServices

    init(wallpaper: WEWallpaper, pixelSize: SIMD2<Int>, pointSize: SIMD2<Float>, output: URL, defaults: UserDefaults,
         scratchDirectory: URL) {
        self.wallpaper = wallpaper
        self.pixelSize = pixelSize
        self.pointSize = pointSize
        self.output = output
        self.defaults = defaults
        scriptServices = SceneScriptServices(prelude: SceneScriptPrelude.load(),
                                             storage: SceneScriptStorage(directory: scratchDirectory),
                                             media: SilentMediaSession(), spectrum: { .silent })
    }

    /// Renders the video; false when it couldn't (logged).
    func run() -> Bool {
        let name = wallpaper.wallpaperDirectory.lastPathComponent
        guard let first = makeSession() else { return false }
        var plan: (frames: Int, frameRate: Int, seam: ScreenSaverSeamFinder.Seam)?
        if !first.aperiodic, let loop = ScreenSaverLoopLength.periodicLoop(first.periods) {
            if write(first, frames: loop.frames, frameRate: loop.frameRate, seam: .cut, verify: true) {
                first.end()
                OWELog.info(.app, "Screen saver: \(name) loops every \(loop.seconds) s (known periods)")
                return true
            }
            OWELog.info(.app, "Screen saver: \(name)'s periods don't cover its motion; searching for a loop")
        } else {
            plan = search(first)
        }
        first.end()
        if plan == nil {
            guard let session = makeSession() else { return false }
            plan = search(session)
            session.end()
        }
        guard let plan, let session = makeSession() else {
            OWELog.error(.app, "Screen saver: \(name) has no loop")
            return false
        }
        defer { session.end() }
        OWELog.info(.app, "Screen saver: \(name) loops after \(plan.frames) frames (\(plan.seam))")
        return write(session, frames: plan.frames, frameRate: plan.frameRate, seam: plan.seam, verify: false)
    }

    // MARK: Session

    /// One loaded scene, compiled and held at scene time 0.
    final class Session {
        let renderer: SceneMetalRenderer
        let viewport: SceneViewport
        let periods: [ScreenSaverLoopLength.Period]
        let aperiodic: Bool
        let startTime: CFTimeInterval
        var frame = 0

        init(renderer: SceneMetalRenderer, viewport: SceneViewport, periods: [ScreenSaverLoopLength.Period],
             aperiodic: Bool, startTime: CFTimeInterval) {
            self.renderer = renderer
            self.viewport = viewport
            self.periods = periods
            self.aperiodic = aperiodic
            self.startTime = startTime
        }

        func end() { renderer.releaseContent() }
    }

    private func makeSession() -> Session? {
        let name = wallpaper.wallpaperDirectory.lastPathComponent
        let model = SceneWallpaperViewModel(wallpaper: wallpaper)
        let settings = Self.globalSettings(from: defaults)
        let drawable = SIMD2(Float(pixelSize.x), Float(pixelSize.y))
        let renderSettings = SceneRenderSettings(settings, outputPixels: drawable, sceneSize: model.textureReductionSceneSize)
        model.setRenderSettings(renderSettings)
        guard let content = model.metalContent(),
              let renderer = SceneMetalRenderer(pixelFormat: .bgra8Unorm, scriptServices: scriptServices,
                                                screenID: "screensaver-\(name)") else {
            OWELog.error(.app, "Screen saver: \(name) has no scene content or renderer")
            return nil
        }
        let startTime: CFTimeInterval = 1000
        renderer.rendersScreenSaver = true
        renderer.hidesClockLayers = true
        renderer.renderSettings = renderSettings
        renderer.sounds.setTargetGain(0)
        renderer.audioSpectrumFrame = { _ in .silent }
        renderer.wallTime = { startTime }
        renderer.holdsClock = true
        renderer.setContent(content)
        let viewport = SceneViewport(drawableSize: drawable, pointSize: pointSize, cursor: nil, frameRateLimit: 30)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        var settled = 0
        while renderer.hasContent, settled < 3, Date() < deadline {
            renderer.renderShared([viewport])
            renderer.lastCommandBuffer?.waitUntilCompleted()
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            settled = renderer.hasPendingEffectPipelines ? 0 : settled + 1
        }
        guard renderer.hasContent, settled >= 3 else {
            OWELog.error(.app, "Screen saver: \(name) didn't finish loading in \(Int(timeoutSeconds)) s")
            renderer.releaseContent()
            return nil
        }
        renderer.holdsClock = false
        var periods: [ScreenSaverLoopLength.Period] = []
        var aperiodic = !content.particleSystems.isEmpty || content.scripts != nil
        if let set = renderer.timelines.set {
            let timeline = set.loopPeriods()
            periods += timeline.periods
            aperiodic = aperiodic || timeline.aperiodic
            periods += set.textures.frameTimeLists.compactMap { ScreenSaverLoopLength.Period(frameTimes: $0) }
        }
        return Session(renderer: renderer, viewport: viewport, periods: periods, aperiodic: aperiodic, startTime: startTime)
    }

    /// Draws the session's next frame at a fixed step and reads it back.
    private func nextFrame(_ session: Session, frameRate: Int) -> CGImage? {
        let time = session.startTime + Double(session.frame) / Double(frameRate)
        session.renderer.wallTime = { time }
        session.frame += 1
        session.renderer.renderShared([session.viewport])
        let capture = FrameCapture()
        guard session.renderer.captureSharedFrame(pixelSize: pixelSize, pixelsPerPoint: session.viewport.pixelsPerPoint,
                                                  completion: { capture.finish($0) }),
              capture.done.wait(timeout: .now() + 10) == .success else { return nil }
        return capture.image
    }

    // MARK: Search

    private func search(_ session: Session) -> (frames: Int, frameRate: Int, seam: ScreenSaverSeamFinder.Seam)? {
        let frameRate = ScreenSaverLoopLength.frameRates[0]
        let count = Int(ScreenSaverSeamFinder.maximumSeconds * Double(frameRate)) + 1
        var reference: ScreenSaverFrameSignature?
        var differences: [Double] = []
        differences.reserveCapacity(count)
        for _ in 0..<count {
            guard let image = nextFrame(session, frameRate: frameRate),
                  let signature = ScreenSaverFrameSignature(image) else { return nil }
            if reference == nil { reference = signature }
            differences.append(reference.map { signature.difference($0) } ?? 1)
        }
        guard let decision = ScreenSaverSeamFinder.decide(differences: differences, frameRate: frameRate) else { return nil }
        return (decision.frames, frameRate, decision.seam)
    }

    // MARK: Writing

    /// Writes `frames` frames of `session` as the video. With `verify`, frame `frames` is drawn
    /// too and the video is kept only when it matches frame 0.
    private func write(_ session: Session, frames: Int, frameRate: Int, seam: ScreenSaverSeamFinder.Seam,
                       verify: Bool) -> Bool {
        let name = wallpaper.wallpaperDirectory.lastPathComponent
        let partial = output.deletingLastPathComponent()
            .appending(path: ".partial-\(output.lastPathComponent)", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: partial)
            }
        } catch {
            OWELog.error(.app, "Screen saver: can't prepare \(partial.lastPathComponent): \(error)")
            return false
        }
        guard let writer = HEVCWriter(url: partial, pixelSize: pixelSize, frameRate: frameRate) else { return false }
        let fade: Int = { if case .crossfade(let frames) = seam { return frames }; return 0 }()
        // With a crossfade the video starts `fade` frames in: its last frames fade into the scene's
        // first `fade` frames, and it wraps to the frame that follows them, so the motion runs on
        // through the seam instead of replaying the first frames.
        var head: [CGImage] = []
        var reference: ScreenSaverFrameSignature?
        for rendered in 0..<(frames + fade) {
            guard let image = nextFrame(session, frameRate: frameRate) else {
                OWELog.error(.app, "Screen saver: \(name)'s frame \(rendered) couldn't be read back")
                writer.cancel()
                return false
            }
            if rendered == 0, verify { reference = ScreenSaverFrameSignature(image) }
            if rendered < fade {
                head.append(image)
                continue
            }
            let index = rendered - fade
            let weight = ScreenSaverSeamFinder.crossfadeWeight(index: index, loopFrames: frames, fade: fade)
            let overlay = weight > 0 ? head[index - (frames - fade)] : nil
            guard writer.append(image, overlay: overlay, weight: weight, frame: index) else {
                writer.cancel()
                return false
            }
        }
        if verify {
            guard let next = nextFrame(session, frameRate: frameRate), let reference,
                  let signature = ScreenSaverFrameSignature(next),
                  signature.difference(reference) <= ScreenSaverSeamFinder.invisibleDifference else {
                writer.cancel()
                return false
            }
        }
        guard writer.finish() else { return false }
        do {
            if FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: output)
            }
            try FileManager.default.moveItem(at: partial, to: output)
            return true
        } catch {
            OWELog.error(.app, "Screen saver: can't move \(output.lastPathComponent) into place: \(error)")
            return false
        }
    }

    static func globalSettings(from defaults: UserDefaults) -> GlobalSettings {
        guard let data = defaults.data(forKey: "GlobalSettings") else { return GlobalSettings() }
        do {
            return try JSONDecoder().decode(GlobalSettings.self, from: data)
        } catch {
            OWELog.error(.app, "Screen saver: can't read the settings, using the defaults: \(error)")
            return GlobalSettings()
        }
    }
}

/// No now-playing session: a saver plays without media integration.
private final class SilentMediaSession: MediaSessionSource {
    func subscribe(_ update: @escaping (MediaSessionState) -> Void) -> Int {
        update(MediaSessionState())
        return 0
    }

    func unsubscribe(_ id: Int) {}
}

/// One capture's result, handed over from the Metal thread that completes it: `done` orders the
/// write of `image` before the waiting thread reads it.
private final class FrameCapture: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private(set) var image: CGImage?

    func finish(_ image: CGImage?) {
        self.image = image
        done.signal()
    }
}

/// An HEVC `.mov` written frame by frame from `CGImage`s.
final class HEVCWriter {
    /// HEVC encoder quality (0…1) for the loop video.
    static let quality: Double = 0.95
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pixelSize: SIMD2<Int>
    private let frameRate: Int

    init?(url: URL, pixelSize: SIMD2<Int>, frameRate: Int, quality: Double = HEVCWriter.quality) {
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            OWELog.error(.app, "Screen saver: can't create the video writer: \(error)")
            return nil
        }
        // Constant quality, not a bitrate: rain, particles and glow need several times the bits
        // of a calm scene (a fixed 0.07 bit per pixel smeared them), and a still scene stays small.
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: pixelSize.x,
            AVVideoHeightKey: pixelSize.y,
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: quality,
                                              AVVideoExpectedSourceFrameRateKey: frameRate],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelSize.x,
            kCVPixelBufferHeightKey as String: pixelSize.y,
        ])
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        guard writer.canAdd(input) else {
            OWELog.error(.app, "Screen saver: the video writer takes no HEVC input")
            return nil
        }
        writer.add(input)
        guard writer.startWriting() else {
            OWELog.error(.app, "Screen saver: the video writer didn't start: \(String(describing: writer.error))")
            return nil
        }
        writer.startSession(atSourceTime: .zero)
    }

    /// Appends `image`, with `overlay` blended over it at `weight` (the seam's crossfade).
    func append(_ image: CGImage, overlay: CGImage?, weight: Double, frame: Int) -> Bool {
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard writer.status == .writing, let pool = adaptor.pixelBufferPool else {
            OWELog.error(.app, "Screen saver: the video writer stopped: \(String(describing: writer.error))")
            return false
        }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return false }
        CVPixelBufferLockBaseAddress(buffer, [])
        let drawn: Bool = {
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: pixelSize.x, height: pixelSize.y,
                                          bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            let rect = CGRect(x: 0, y: 0, width: pixelSize.x, height: pixelSize.y)
            context.draw(image, in: rect)
            if let overlay, weight > 0 {
                context.setAlpha(weight)
                context.draw(overlay, in: rect)
            }
            return true
        }()
        guard drawn else { return false }
        return adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(frameRate)))
    }

    func finish() -> Bool {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            OWELog.error(.app, "Screen saver: the video didn't finish: \(String(describing: writer.error))")
            return false
        }
        return true
    }

    func cancel() { writer.cancelWriting() }
}
