import AVFoundation
import CoreGraphics
import Metal

/// Renders a scene wallpaper's clip as a Live Photo (a HEIC still and an HEVC movie paired by one
/// content identifier) or as preview frames.
///
/// The scene is loaded by the real loader and drawn offscreen by its own real renderer, as the
/// screen saver's loop is (`ScreenSaverLoopRenderer`): the stored user properties, no sound, a
/// silent spectrum, the clock, day and date layers hidden (iOS draws its own,
/// `SceneClockLayers`), on a fixed frame step from load, so frame `i` shows scene time
/// `i / frameRate`. The whole scene is drawn at `LivePhotoCrop.renderScale` (never below its
/// authored size nor below the phone's pixels), whatever the user's playback settings, and the
/// crop is cut out at the phone's exact pixel size.
@MainActor
final class LivePhotoRenderer {
    struct Files {
        let directory: URL
        let still: URL
        let movie: URL
        let identifier: String
    }

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
    /// The user properties it renders with: the store the inspector edits.
    let properties: WallpaperPropertyScope
    var timeoutSeconds: TimeInterval = 120

    init(wallpaper: WEWallpaper, properties: WallpaperPropertyScope = .shared) {
        self.wallpaper = wallpaper
        self.properties = properties
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

    /// The app's cache folder for exports; each export gets its own folder in it.
    static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: Bundle.main.bundleIdentifier ?? "OpenWallpaperEngine", directoryHint: .isDirectory)
            .appending(path: "LivePhoto", directoryHint: .isDirectory)
    }

    static func remove(_ files: Files) {
        try? FileManager.default.removeItem(at: files.directory)
    }

    /// Removes earlier exports' folders (a crash or quit left them).
    static func removeStaleExports() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    // MARK: Export

    /// Renders the Live Photo into a new folder under `cacheDirectory`. `progress` gets 0…1.
    func export(crop: LivePhotoCrop, clip: LivePhotoClip, progress: @escaping (Double) -> Void) async throws -> Files {
        let identifier = UUID().uuidString
        let directory = Self.cacheDirectory.appending(path: identifier, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = Self.fileName(wallpaper.project.displayTitle)
        let files = Files(directory: directory, still: directory.appending(path: base + ".HEIC"),
                          movie: directory.appending(path: base + ".MOV"), identifier: identifier)
        do {
            try await write(files, crop: crop, clip: clip, progress: progress)
            return files
        } catch {
            Self.remove(files)
            throw error
        }
    }

    /// The clip's frames at `crop`'s output size, for previewing the loop.
    func previewFrames(crop: LivePhotoCrop, clip: LivePhotoClip, progress: @escaping (Double) -> Void) async throws -> [CGImage] {
        var frames: [CGImage] = []
        try await render(crop: crop, clip: clip, progress: progress) { _, image in frames.append(image) }
        return frames
    }

    private func write(_ files: Files, crop: LivePhotoCrop, clip: LivePhotoClip, progress: @escaping (Double) -> Void) async throws {
        var stillAdaptor: AVAssetWriterInputMetadataAdaptor?
        guard let writer = HEVCWriter(url: files.movie, pixelSize: crop.outputPixels, frameRate: LivePhotoClip.frameRate,
                                      prepare: { writer in
                                          writer.metadata = [LivePhotoMetadata.contentIdentifierItem(files.identifier)]
                                          stillAdaptor = try LivePhotoMetadata.addStillImageTimeInput(to: writer)
                                      }), let stillAdaptor else { throw Failure.movie }
        // The still's moment is known up front: written first, its track is done before the frames.
        let keyTime = CMTime(value: CMTimeValue(clip.keyFrameIndex), timescale: CMTimeScale(LivePhotoClip.frameRate))
        guard stillAdaptor.append(LivePhotoMetadata.stillImageTimeGroup(at: keyTime, frameRate: LivePhotoClip.frameRate)) else {
            writer.cancel()
            throw Failure.movie
        }
        stillAdaptor.assetWriterInput.markAsFinished()
        do {
            try await render(crop: crop, clip: clip, progress: progress) { index, image in
                if index == clip.keyFrameIndex {
                    try LivePhotoMetadata.writeStill(image, to: files.still, identifier: files.identifier)
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
        let model = SceneWallpaperViewModel(wallpaper: wallpaper, propertyScope: properties)
        let settings = Self.renderSettings(from: ScreenSaverLoopRenderer.globalSettings(from: .standard))
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
