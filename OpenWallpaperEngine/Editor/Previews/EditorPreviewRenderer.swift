import CoreGraphics
import Foundation
import ImageIO
import Metal
import OWESceneEditing
import UniformTypeIdentifiers

/// Renders the Wallpaper Editor's previews of effects and particle systems
/// (`EditorPreviewCache`), in the app's helper run (`ShaderPrewarmCommand`,
/// `--render-editor-previews`): in its own process, never on the app's main or render thread.
///
/// Each preview's small wallpaper (`EditorPreviewFolder`) is loaded by the real loader and drawn
/// offscreen by its own real renderer, as the screen saver's loop and Live Photos are: muted, a
/// silent spectrum, on a fixed frame step from load. An effect is drawn for `effectFrames`; when
/// its picture doesn't change over the first half second it is a still (HEIC), else a loop. A
/// particle system runs `particleLeadIn` frames first, so it is under way, and is always a loop.
/// A loop is HEVC, its last frames crossfaded into its first so it wraps without a jump.
@MainActor
final class EditorPreviewRenderer {
    enum Failure: LocalizedError {
        case noScene, loadTimedOut, readBack, write

        var errorDescription: String? {
            switch self {
            case .noScene: return "the preview's scene has no content or renderer"
            case .loadTimedOut: return "the preview's scene didn't finish loading"
            case .readBack: return "a frame couldn't be read back"
            case .write: return "the preview couldn't be written"
            }
        }
    }

    /// An effect's loop: 24 frames at 12 per second, its last 4 crossfaded into its first.
    static let effectFrames = 24
    static let effectFrameRate = 12
    static let effectFade = 4
    /// A particle system's loop: 2 s at 24 frames per second after 1.5 s of lead-in.
    static let particleFrames = 48
    static let particleFrameRate = 24
    static let particleLeadIn = 36
    static let particleFade = 6
    /// The frame an effect is compared at to tell a still from a loop: half a second in.
    static let stillProbeFrame = 6
    /// The HEIC still's quality.
    static let stillQuality = 0.85

    var timeoutSeconds: TimeInterval = 60
    private let scratch: URL

    init(scratch: URL) {
        self.scratch = scratch
    }

    // MARK: Helper run

    /// The helper's work: renders each item of `job`, writing a `done` line for each; 0 when
    /// every preview was written.
    static func run(_ job: EditorPreviewJob) -> Int32 {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "owe-editor-previews-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) } // Optional: a scratch folder.
        let renderer = EditorPreviewRenderer(scratch: scratch)
        var status: Int32?
        Task { @MainActor in
            var failed = 0
            for (index, item) in job.items.enumerated() {
                do {
                    let url = try await renderer.render(item.subject, outputBase: URL(filePath: item.outputBase))
                    OWELog.debug(.scene, "Editor preview: wrote \(url.lastPathComponent)")
                } catch {
                    failed += 1
                    OWELog.error(.scene, "Editor preview of \(item.subject) failed: \(error.localizedDescription)")
                }
                FileHandle.standardOutput.write(Data(EditorPreviewJob.doneLine(index).utf8))
            }
            status = failed == 0 ? 0 : 1
        }
        while status == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return status ?? 1
    }

    // MARK: Rendering

    /// Renders the subject's preview to `outputBase` plus `.heic` or `.mov`, and returns the file.
    func render(_ subject: EditorPreviewSubject, outputBase: URL) async throws -> URL {
        let folder = scratch.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) } // Optional: a scratch folder.
        let frame = try EditorPreviewFolder.write(subject, into: folder)
        guard let wallpaper = InstalledLibrary.wallpaper(at: folder, hiding: []) else { throw Failure.noScene }
        try FileManager.default.createDirectory(at: outputBase.deletingLastPathComponent(), withIntermediateDirectories: true)
        let session = try await Session.start(wallpaper, frame: frame, scratch: folder, timeout: timeoutSeconds)
        defer { session.end() }
        if subject.isParticle {
            for _ in 0..<Self.particleLeadIn { session.advance(by: Self.particleFrameRate, capture: false) }
            return try await writeLoop(session, frames: Self.particleFrames, frameRate: Self.particleFrameRate,
                                       fade: Self.particleFade, head: [], to: outputBase)
        }
        // A still unless the picture moves over the first half second.
        var head: [CGImage] = []
        guard let first = await session.capture() else { throw Failure.readBack }
        head.append(first)
        let reference = ScreenSaverFrameSignature(first)
        var moves = false
        for _ in 1...Self.stillProbeFrame {
            session.advance(by: Self.effectFrameRate, capture: true)
            guard let image = await session.capture() else { throw Failure.readBack }
            head.append(image)
            if let reference, let signature = ScreenSaverFrameSignature(image),
               signature.difference(reference) > ScreenSaverSeamFinder.invisibleDifference {
                moves = true
            }
        }
        guard moves else { return try writeStill(first, to: outputBase) }
        return try await writeLoop(session, frames: Self.effectFrames, frameRate: Self.effectFrameRate, fade: Self.effectFade,
                                   head: head, to: outputBase)
    }

    /// Writes a loop of `frames` frames: `head` holds the frames already captured, from the
    /// first. The loop starts `fade` frames in and its last `fade` frames fade into those, as the
    /// screen saver's loop does (`ScreenSaverLoopRenderer.write`).
    private func writeLoop(_ session: Session, frames: Int, frameRate: Int, fade: Int, head: [CGImage],
                           to outputBase: URL) async throws -> URL {
        var captured = head
        if captured.isEmpty {
            guard let first = await session.capture() else { throw Failure.readBack }
            captured.append(first)
        }
        while captured.count < frames + fade {
            session.advance(by: frameRate, capture: true)
            guard let image = await session.capture() else { throw Failure.readBack }
            captured.append(image)
        }
        let url = outputBase.appendingPathExtension(EditorPreviewCache.movieExtension)
        let partial = outputBase.deletingLastPathComponent().appending(path: ".partial-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: partial) // Optional: a partial file of an earlier run.
        guard let writer = HEVCWriter(url: partial, pixelSize: session.pixelSize, frameRate: frameRate) else { throw Failure.write }
        for index in 0..<frames {
            let weight = ScreenSaverSeamFinder.crossfadeWeight(index: index, loopFrames: frames, fade: fade)
            let overlay = weight > 0 ? captured[index - (frames - fade)] : nil
            guard writer.append(captured[index + fade], overlay: overlay, weight: weight, frame: index) else {
                writer.cancel()
                throw Failure.write
            }
        }
        guard writer.finish() else { throw Failure.write }
        try replace(url, with: partial)
        return url
    }

    private func writeStill(_ image: CGImage, to outputBase: URL) throws -> URL {
        let url = outputBase.appendingPathExtension(EditorPreviewCache.stillExtension)
        let partial = outputBase.deletingLastPathComponent().appending(path: ".partial-\(url.lastPathComponent)")
        guard let destination = CGImageDestinationCreateWithURL(partial as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw Failure.write }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Self.stillQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.write }
        try replace(url, with: partial)
        return url
    }

    private func replace(_ url: URL, with partial: URL) throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: partial, to: url)
    }

    // MARK: Session

    /// One loaded preview scene, held at its start until the first frame is asked for. Drawn and
    /// read back on the helper's main thread, its render thread.
    @MainActor
    final class Session {
        let renderer: SceneMetalRenderer
        let viewport: SceneViewport
        let pixelSize: SIMD2<Int>
        private let startTime: CFTimeInterval
        private var seconds: Double = 0

        private init(renderer: SceneMetalRenderer, viewport: SceneViewport, pixelSize: SIMD2<Int>, startTime: CFTimeInterval) {
            self.renderer = renderer
            self.viewport = viewport
            self.pixelSize = pixelSize
            self.startTime = startTime
        }

        static func start(_ wallpaper: WEWallpaper, frame: EditorPreviewScene.Frame, scratch: URL,
                          timeout: TimeInterval) async throws -> Session {
            let services = SceneScriptServices(prelude: SceneScriptPrelude.load(),
                                               storage: SceneScriptStorage(directory: scratch.appending(path: "storage")),
                                               media: SilentMediaSession(), spectrum: { .silent })
            let model = SceneWallpaperViewModel(wallpaper: wallpaper)
            let settings = LivePhotoRenderer.renderSettings(from: ScreenSaverLoopRenderer.globalSettings(from: .app))
            model.setRenderSettings(settings)
            guard let content = model.metalContent(),
                  let renderer = SceneMetalRenderer(pixelFormat: .bgra8Unorm, scriptServices: services,
                                                    screenID: "editor-preview") else { throw Failure.noScene }
            let pixelSize = SIMD2(frame.pixelWidth, frame.pixelHeight)
            let drawable = SIMD2(Float(pixelSize.x), Float(pixelSize.y))
            let startTime: CFTimeInterval = 1000
            renderer.sounds.setTargetGain(0)
            renderer.audioSpectrumFrame = { _ in .silent }
            renderer.renderSettings = settings
            renderer.wallTime = { startTime }
            renderer.holdsClock = true
            renderer.setContent(content)
            let viewport = SceneViewport(drawableSize: drawable, pointSize: drawable, cursor: nil, frameRateLimit: 30)
            let deadline = Date().addingTimeInterval(timeout)
            while !renderer.hasContent, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            var settled = 0
            while renderer.hasContent, settled < 3, Date() < deadline {
                renderer.renderShared([viewport])
                renderer.lastCommandBuffer?.waitUntilCompleted()
                try await Task.sleep(for: .milliseconds(5))
                settled = renderer.hasPendingEffectPipelines ? 0 : settled + 1
            }
            guard renderer.hasContent, settled >= 3 else {
                renderer.releaseContent()
                throw Failure.loadTimedOut
            }
            renderer.holdsClock = false
            let session = Session(renderer: renderer, viewport: viewport, pixelSize: pixelSize, startTime: startTime)
            session.draw()
            return session
        }

        /// Steps the clock one frame at `frameRate` and draws; without `capture` the frame isn't
        /// read back, so it waits for the GPU here.
        func advance(by frameRate: Int, capture: Bool) {
            seconds += 1 / Double(frameRate)
            draw()
            if !capture { renderer.lastCommandBuffer?.waitUntilCompleted() }
        }

        private func draw() {
            let time = startTime + seconds
            renderer.wallTime = { time }
            renderer.renderShared([viewport])
        }

        /// The frame last drawn, read back.
        func capture() async -> CGImage? {
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

        func end() { renderer.releaseContent() }
    }
}
