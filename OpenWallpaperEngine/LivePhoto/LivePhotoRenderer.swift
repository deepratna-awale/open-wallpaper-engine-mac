import AVFoundation
import CoreGraphics
import Metal

/// Renders a scene wallpaper's clip as a Live Photo (a HEIC still and an HEVC movie paired by one
/// content identifier), or as the clip's movie alone for its preview, in the app's helper run
/// (`ShaderPrewarmCommand`, `--render-live-photo`): in its own process, never on the app's main
/// or render thread. The app shows the progress the helper reports and shares the files
/// (`LivePhotoHelper`).
///
/// The scene is loaded by the real loader and drawn offscreen by its own real renderer, as the
/// screen saver's loop is (`ScreenSaverLoopRenderer`): the job's user properties, no sound, a
/// silent spectrum, the clock, day and date layers hidden (iOS draws its own,
/// `SceneClockLayers`), on a fixed frame step from load, so frame `i` shows scene time
/// `i / frameRate`. The whole scene is drawn at `LivePhotoCrop.renderScale` (never below its
/// authored size nor below the phone's pixels), whatever the user's playback settings, and the
/// crop is cut out at the phone's exact pixel size.
@MainActor
final class LivePhotoRenderer {
    enum Failure: LocalizedError {
        case noScene, loadTimedOut, readBack, movie

        var errorDescription: String? {
            switch self {
            case .noScene: return String(localized: "The scene couldn't be loaded for the Live Photo.")
            case .loadTimedOut: return String(localized: "The scene took too long to load for the Live Photo.")
            case .readBack: return String(localized: "A frame of the Live Photo couldn't be rendered.")
            case .movie: return String(localized: "The Live Photo's movie couldn't be written.")
            }
        }
    }

    /// What every Live Photo render does: a recorded picture shows no clock, and is silent.
    enum Policy {
        static let hidesClockLayers = true
        static let muted = true
    }

    let wallpaper: WEWallpaper
    let defaults: UserDefaults
    var timeoutSeconds: TimeInterval = 120

    /// `defaults`: the helper's read-only view of the app's (`UserDefaults.app`); the job's
    /// properties are written to its scratch suite, never to the app's.
    init(wallpaper: WEWallpaper, defaults: UserDefaults = .app) {
        self.wallpaper = wallpaper
        self.defaults = defaults
    }

    /// The export's quality: the user's settings with WE's full scene detail, no upscaling and
    /// full-size textures. The scene target is sized for the export's drawable, which
    /// `LivePhotoCrop` sizes to the scene's authored size or more ("Full" render resolution's
    /// floor, raised to the phone's pixels when they need more).
    nonisolated static func renderSettings(from settings: GlobalSettings) -> SceneRenderSettings {
        var render = SceneRenderSettings(settings)
        render.renderResolution = .retina
        render.sceneDetail = .full
        render.upscaling = .off
        render.textureReduction = 1
        return render
    }

    /// The renderer's configuration for a Live Photo.
    static func configure(_ renderer: SceneMetalRenderer) {
        renderer.rendersScreenSaver = true
        renderer.hidesClockLayers = Policy.hidesClockLayers
        if Policy.muted { renderer.sounds.setTargetGain(0) }
        renderer.audioSpectrumFrame = { _ in .silent }
    }

    // MARK: Helper run

    /// The helper's work: renders `job`, writing progress lines to standard output; 0 when done.
    static func run(_ job: LivePhotoJob) -> Int32 {
        guard let crop = job.crop,
              let wallpaper = InstalledLibrary.wallpaper(at: URL(filePath: job.wallpaperDirectory, directoryHint: .isDirectory), hiding: []),
              wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame else {
            OWELog.error(.app, "Live Photo: bad job for \(job.wallpaperDirectory)")
            return 2
        }
        let renderer = LivePhotoRenderer(wallpaper: wallpaper)
        renderer.useProperties(job.properties)
        var status: Int32?
        Task { @MainActor in
            do {
                try await renderer.write(job, crop: crop) { fraction in
                    FileHandle.standardOutput.write(Data(LivePhotoJob.progressLine(fraction).utf8))
                }
                status = 0
            } catch {
                OWELog.error(.app, "Live Photo: \(wallpaper.wallpaperDirectory.lastPathComponent) failed: \(error)")
                status = 1
            }
        }
        while status == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return status ?? 1
    }

    /// The scene loads with `values` as its stored user properties (the shared store).
    func useProperties(_ values: [String: String]) {
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)
        defaults.set(values, forKey: identity.key(.userProperties, scope: .shared))
        defaults.set(true, forKey: identity.key(.explicitUserProperties, scope: .shared))
    }

    /// Writes the job's movie, and its still when it has one.
    func write(_ job: LivePhotoJob, crop: LivePhotoCrop, progress: @escaping (Double) -> Void) async throws {
        let clip = job.clip
        var stillAdaptor: AVAssetWriterInputMetadataAdaptor?
        let paired = job.still != nil
        guard let writer = HEVCWriter(url: job.movie, pixelSize: crop.outputPixels, frameRate: LivePhotoClip.frameRate,
                                      prepare: { writer in
                                          guard paired else { return }
                                          writer.metadata = [LivePhotoMetadata.contentIdentifierItem(job.identifier)]
                                          stillAdaptor = try LivePhotoMetadata.addStillImageTimeInput(to: writer)
                                      }) else { throw Failure.movie }
        if let stillAdaptor {
            // The still's moment is known up front: written first, its track is done before the frames.
            let keyTime = CMTime(value: CMTimeValue(clip.keyFrameIndex), timescale: CMTimeScale(LivePhotoClip.frameRate))
            guard stillAdaptor.append(LivePhotoMetadata.stillImageTimeGroup(at: keyTime, frameRate: LivePhotoClip.frameRate)) else {
                writer.cancel()
                throw Failure.movie
            }
            stillAdaptor.assetWriterInput.markAsFinished()
        }
        do {
            try await render(crop: crop, clip: clip, progress: progress) { index, image in
                if index == clip.keyFrameIndex, let still = job.still {
                    try LivePhotoMetadata.writeStill(image, to: still, identifier: job.identifier)
                }
                guard writer.append(image, overlay: nil, weight: 0, frame: index) else { throw Failure.movie }
            }
        } catch {
            writer.cancel()
            throw error
        }
        guard writer.finish() else { throw Failure.movie }
    }

    // MARK: Rendering

    /// Loads the scene, runs it to the clip's start and hands each of the clip's frames, cut to
    /// `crop`, to `frame`. Checks for cancellation between frames.
    private func render(crop: LivePhotoCrop, clip: LivePhotoClip, progress: @escaping (Double) -> Void,
                        frame: (Int, CGImage) throws -> Void) async throws {
        let name = wallpaper.wallpaperDirectory.lastPathComponent
        let scratch = FileManager.default.temporaryDirectory.appending(path: "owe-livephoto-\(UUID().uuidString)",
                                                                       directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let services = SceneScriptServices(prelude: SceneScriptPrelude.load(),
                                           storage: SceneScriptStorage(directory: scratch),
                                           media: SilentMediaSession(), spectrum: { .silent })
        let model = SceneWallpaperViewModel(wallpaper: wallpaper)
        let settings = Self.renderSettings(from: ScreenSaverLoopRenderer.globalSettings(from: defaults))
        model.setRenderSettings(settings)
        guard let content = model.metalContent(),
              let renderer = SceneMetalRenderer(pixelFormat: .bgra8Unorm, scriptServices: services,
                                                screenID: "livephoto-\(name)") else { throw Failure.noScene }
        defer { renderer.releaseContent() }
        let pixelSize = crop.renderPixelSize
        let drawable = SIMD2(Float(pixelSize.x), Float(pixelSize.y))
        let startTime: CFTimeInterval = 1000
        Self.configure(renderer)
        renderer.renderSettings = settings
        renderer.wallTime = { startTime }
        renderer.holdsClock = true
        renderer.setContent(content)
        let viewport = SceneViewport(drawableSize: drawable, pointSize: drawable, cursor: nil,
                                     frameRateLimit: LivePhotoClip.frameRate)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !renderer.hasContent, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        var settled = 0
        while renderer.hasContent, settled < 3, Date() < deadline {
            try Task.checkCancellation()
            renderer.renderShared([viewport])
            renderer.lastCommandBuffer?.waitUntilCompleted()
            try await Task.sleep(for: .milliseconds(5))
            settled = renderer.hasPendingEffectPipelines ? 0 : settled + 1
        }
        guard renderer.hasContent, settled >= 3 else { throw Failure.loadTimedOut }
        renderer.holdsClock = false

        let total = Double(clip.leadInFrames + clip.frameCount)
        for index in 0..<(clip.leadInFrames + clip.frameCount) {
            try Task.checkCancellation()
            let time = startTime + Double(index) / Double(LivePhotoClip.frameRate)
            renderer.wallTime = { time }
            renderer.renderShared([viewport])
            if index < clip.leadInFrames {
                renderer.lastCommandBuffer?.waitUntilCompleted()
            } else {
                guard let image = await capture(renderer, pixelSize: pixelSize),
                      let output = crop.outputImage(from: image) else { throw Failure.readBack }
                try frame(index - clip.leadInFrames, output)
            }
            progress(Double(index + 1) / total)
            await Task.yield()
        }
    }

    private func capture(_ renderer: SceneMetalRenderer, pixelSize: SIMD2<Int>) async -> CGImage? {
        let capture = FrameCapture()
        guard renderer.captureSharedFrame(pixelSize: pixelSize, pixelsPerPoint: 1, completion: { capture.finish($0) }) else {
            return nil
        }
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: capture.done.wait(timeout: .now() + 10) == .success)
            }
        }
        return finished ? capture.image : nil
    }

    /// A file name from the wallpaper's title: no path separators, never empty.
    nonisolated static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Live Photo" : String(cleaned.prefix(80))
    }
}
