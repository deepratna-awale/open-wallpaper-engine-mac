import AVFoundation
import CoreVideo
import Metal
import QuartzCore

/// Publishes decoded video frames as Metal textures so a video can be drawn by the scene renderer
/// instead of an `AVPlayerLayer`.
///
/// Wallpaper Engine renders video through its normal scene pipeline — `scenes/videoplayer` binds
/// the movie as a `videotex` user texture on a `genericimage` material — which is why scene effects
/// apply to video there. Rendering into `AVPlayerView` keeps the frames outside Metal entirely, so
/// no effect can touch them.
///
/// An SDR video decodes to 8-bit BGRA, sampled as it is. A HDR one in HDR mode (`dynamicRange`,
/// WE 2.8's "Scene DX11 (HDR Support)" framework) decodes to linear half floats that
/// `VideoHDRConversion` turns into linear BT.709 light, 1.0 = 100 nits, which the scene's
/// `combine_video_hdr` shows as EDR (`SceneHDRChain`).
final class VideoTextureStream {
    /// The picture and the soundtrack, each looping without a pause at the end (`GaplessLoop`).
    /// The sound is a second player, mirroring the AVKit path: the picture's player stays muted so
    /// music pacing never pitch-shifts the soundtrack.
    private let videoLoop: GaplessLoop
    private let audioLoop: GaplessLoop
    var player: AVPlayer { videoLoop.player }
    private var audioPlayer: AVPlayer { audioLoop.player }
    /// Natural frame size, once the first frame has arrived.
    private(set) var frameSize = SIMD2<Float>(1920, 1080)
    /// How the frames decode: `.sdr` is the 8-bit path; PQ or HLG, linear light (`VideoHDRConversion`).
    let dynamicRange: VideoDynamicRange
    /// The HDR mode's conversion; nil for SDR.
    private let hdrConversion: VideoHDRConversion?

    /// Each pass's video output (an output serves one item), by item; a pass's goes when it ends.
    /// The main thread queues passes while the renderer reads frames, so `outputsLock` guards it.
    private var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private let outputsLock = NSLock()
    /// The output of the pass playing now.
    private var output: AVPlayerItemVideoOutput? {
        guard let item = player.currentItem else { return nil }
        return outputsLock.withLock { outputs[ObjectIdentifier(item)] }
    }
    /// Splits the file into picture and sound before the loops start (`makeLoopAssets`).
    private var loading: Task<Void, Never>?
    private var stopped = false
    private var textureCache: CVMetalTextureCache?
    private let ownAudioTap = AudioLevelTap()
    private var audioIsAudible = false
    /// The CVMetalTexture (and so its pool CVPixelBuffer) must outlive every GPU read of the
    /// MTLTexture handed to the renderer. This holds the newest frame; `holdCurrentFrame(until:)`
    /// keeps it alive past replacement until each command buffer that sampled it completes, so the
    /// decoder can't be handed the buffer back while a frame in flight still reads it.
    private var retainedTexture: CVMetalTexture?
    private var latestTexture: MTLTexture?

    /// Whether the end runs on into the start (`IVideoTexture.loop`); a video that doesn't loop
    /// holds its last frame.
    private(set) var loops = true {
        didSet {
            videoLoop.loops = loops
            audioLoop.loops = loops
        }
    }
    /// `IVideoTexture.rate` of an embedded video texture, with `isPlaying`.
    private var scriptRate: Float = 1
    private var scriptPlaying = true
    private var hostRate: Float = 1

    private var appliedVideoRate: Float?
    private var appliedAudioRate: Float?
    private var smoothedAudioLevel: Double = 0
    private static let rateEpsilon: Float = 0.01
    private static let audioSmoothing = 0.25
    /// The file is in use while the stream plays it: Clear Caches and the cache expiry keep it.
    private let fileLease: CacheLease?
    /// The file the players read, kept while they do: from memory, it owns the bytes.
    private let file: VideoFileSource

    convenience init?(url: URL, device: MTLDevice, dynamicRange: VideoDynamicRange = .sdr) {
        self.init(file: VideoFileSource(url: url, mode: .fromDisk), device: device, dynamicRange: dynamicRange)
    }

    /// Plays `file` (WE's "Video loading", `VideoFileSource`); a HDR `dynamicRange` decodes it as
    /// linear light, and falls back to SDR (logged) when its conversion can't be made.
    init?(file: VideoFileSource, device: MTLDevice, dynamicRange: VideoDynamicRange = .sdr) {
        self.file = file
        fileLease = file.url.isFileURL ? CacheLeases.current.lease(file.url) : nil
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { return nil }
        textureCache = cache

        hdrConversion = dynamicRange.isHDR ? VideoHDRConversion(device: device) : nil
        if dynamicRange.isHDR, hdrConversion == nil {
            OWELog.error(.scene, "Video \(file.url.lastPathComponent) plays as SDR: its HDR conversion can't be made")
        }
        self.dynamicRange = hdrConversion == nil ? .sdr : dynamicRange
        videoLoop = GaplessLoop(player: WallpaperAVPlayer.makeQueue())
        audioLoop = GaplessLoop(player: WallpaperAVPlayer.makeQueue())
        player.isMuted = true
        let isHDR = hdrConversion != nil
        let ref = StreamReference(stream: self)
        videoLoop.passEnded = { ref.stream?.videoPassEnded() }
        loading = Task { @MainActor in
            let assets = await file.makeLoopAssets()
            ref.stream?.start(assets, isHDR: isHDR)
        }
    }

    /// Starts both loops, each pass of the picture with its own output, at the rates asked so far.
    private func start(_ assets: VideoFileSource.LoopAssets, isHDR: Bool) {
        guard !stopped else { return }
        let ref = StreamReference(stream: self)
        videoLoop.play {
            let item = AVPlayerItem(asset: assets.picture)
            let output = isHDR
                ? AVPlayerItemVideoOutput(outputSettings: Self.hdrOutputSettings)
                : AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
            item.add(output)
            if let stream = ref.stream { stream.outputsLock.withLock { stream.outputs[ObjectIdentifier(item)] = output } }
            return item
        }
        if let soundtrack = assets.soundtrack {
            audioLoop.play { assets.makeSoundtrackItem() }
            ownAudioTap.attach(toItemsOf: soundtrack) { mix in ref.stream?.audioLoop.audioMix = mix }
        }
        // Rates set while nothing was queued: hand them to the players again.
        if let appliedVideoRate { player.rate = appliedVideoRate }
        if let appliedAudioRate { audioPlayer.rate = appliedAudioRate }
    }

    deinit {
        loading?.cancel()
        player.pause()
        audioPlayer.pause()
        videoLoop.clear()
        audioLoop.clear()
    }

    /// Stops both players and drops their items, so audio cannot keep playing through whatever
    /// still holds a reference to this stream (the renderer retains it inside the built layer).
    func stop() {
        stopped = true
        loading?.cancel()
        player.pause()
        audioPlayer.pause()
        videoLoop.clear()
        audioLoop.clear()
        outputsLock.withLock { outputs.removeAll() }
        appliedVideoRate = nil
        appliedAudioRate = nil
    }

    /// Whether a frame newer than the one last handed out is ready now (nothing is consumed): a
    /// frame without one shows the same picture, so the renderer can skip it.
    var hasNewFrame: Bool {
        guard latestTexture != nil, let output else { return true }
        return output.hasNewPixelBuffer(forItemTime: output.itemTime(forHostTime: CACurrentMediaTime()))
    }

    /// HDR mode's decoder output: linear half floats in BT.2020, whose range AVFoundation keeps
    /// (1.0 = 100 nits). Asked for BT.709 it would tone map into 0…1.
    static let hdrOutputSettings: [String: any Sendable] = [
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
        ],
    ]

    /// The frame for the current host time, or the previous one when no new frame is ready. In HDR
    /// mode, the frame `prepareFrame(on:)` converted last.
    func currentTexture() -> MTLTexture? {
        guard hdrConversion == nil, let texture = takeNewFrame(format: .bgra8Unorm) else { return latestTexture }
        latestTexture = texture
        return texture
    }

    /// HDR mode: takes a new decoded frame, if there is one, and converts it on `commandBuffer`,
    /// before anything this frame samples `currentTexture()`. SDR does nothing here.
    func prepareFrame(on commandBuffer: MTLCommandBuffer) {
        guard let hdrConversion, let decoded = takeNewFrame(format: .rgba16Float),
              let converted = hdrConversion.encode(decoded, on: commandBuffer) else { return }
        latestTexture = converted
    }

    /// The decoder's frame for the current host time as a `format` texture, when a new one is
    /// ready; it becomes the frame `holdCurrentFrame(until:)` keeps.
    private func takeNewFrame(format: MTLPixelFormat) -> MTLTexture? {
        guard let output else { return nil }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
              let textureCache else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var created: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil,
                                                        format, width, height, 0, &created) == kCVReturnSuccess,
              let created, let texture = CVMetalTextureGetTexture(created) else { return nil }

        retainedTexture = created
        frameSize = SIMD2<Float>(Float(width), Float(height))
        CVMetalTextureCacheFlush(textureCache, 0)
        return texture
    }

    /// Keeps the current frame's CVMetalTexture alive until `commandBuffer` completes. Call it for
    /// every command buffer that sampled `currentTexture()`, before committing it.
    func holdCurrentFrame(until commandBuffer: MTLCommandBuffer) {
        guard let retainedTexture, let textureCache else { return }
        let frame = HeldVideoFrame(retainedTexture, cache: textureCache)
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(frame) {} }
    }

    func setAudio(enabled: Bool, volume: Float) {
        audioPlayer.isMuted = !enabled
        audioPlayer.volume = volume
        audioIsAudible = enabled && volume > 0
    }

    /// The wallpaper's own soundtrack drives music sync whenever you can actually hear it;
    /// otherwise sync follows whatever else is playing on the system.
    var musicSyncLevel: Double {
        audioIsAudible && ownAudioTap.isMeasuring ? ownAudioTap.level : WallpaperServices.shared.audioLevel
    }

    /// `paceAmount` warps playback with the music the way the AVKit path does; the audio track keeps
    /// its own steady rate so only the picture is paced.
    func update(playRate: Float, audioRate: Float, audioLevel: Double, paceAmount: Double) {
        if paceAmount > 0 {
            smoothedAudioLevel += (audioLevel - smoothedAudioLevel) * Self.audioSmoothing
        } else {
            smoothedAudioLevel = audioLevel
        }
        setVideoRate(max(0, playRate + Float(smoothedAudioLevel * paceAmount)))
        // The soundtrack runs on its own player, so a paused wallpaper stays audible unless the
        // pause is applied to it explicitly.
        setAudioRate(audioPlayer.isMuted || playRate <= 0 ? 0 : audioRate)
    }

    /// Assigning `AVPlayer.rate` restarts the timebase, so only meaningful changes are forwarded.
    private func setVideoRate(_ rate: Float) {
        if let applied = appliedVideoRate, abs(rate - applied) <= Self.rateEpsilon { return }
        appliedVideoRate = rate
        player.rate = rate
    }

    private func setAudioRate(_ rate: Float) {
        if let applied = appliedAudioRate, abs(rate - applied) <= Self.rateEpsilon { return }
        appliedAudioRate = rate
        audioPlayer.rate = rate
    }

    /// The picture played to its end: a looping one already runs on into its next pass
    /// (`GaplessLoop`), whose output now serves the frames; one that doesn't loop holds its last
    /// frame, silent.
    private func videoPassEnded() {
        let playing = Set(videoLoop.player.items().map(ObjectIdentifier.init))
        outputsLock.withLock { outputs = outputs.filter { playing.contains($0.key) } }
        guard !loops else { return }
        player.pause()
        audioPlayer.pause()
        scriptPlaying = false
        appliedVideoRate = nil
        appliedAudioRate = nil
    }

    // MARK: - Video textures in scenes

    /// A scene image's video texture: muted (WE's video textures are pictures), playing and
    /// looping from the start. Scripts drive it through `perform(_:)`. It plays `data` where it is
    /// (`VideoFileSource(bytes:name:)`).
    static func embedded(mp4 data: Data, device: MTLDevice) -> VideoTextureStream? {
        guard let stream = VideoTextureStream(file: VideoFileSource(bytes: data, name: "video-texture.mp4"), device: device)
        else { return nil }
        stream.setAudio(enabled: false, volume: 0)
        stream.setVideoRate(1)
        return stream
    }

    /// `IVideoTexture.isPlaying()`: what scripts asked, whether or not the wallpaper is paused.
    var isPlaying: Bool { scriptPlaying }
    /// The player's time, in seconds (`IVideoTexture.getCurrentTime()`).
    var currentSeconds: Float {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? Float(seconds) : 0
    }

    /// The wallpaper's own rate: 0 while it is paused, covered or frozen, so the decoder stops
    /// the way a video wallpaper's does; scripts' rate and pause apply on top.
    func setHostRate(_ rate: Float) {
        guard rate != hostRate else { return }
        hostRate = rate
        setVideoRate(scriptPlaying ? scriptRate * hostRate : 0)
    }

    /// An `IVideoTexture` call.
    func perform(_ command: SceneVideoTextureCommand) {
        switch command {
        case .play:
            if !loops, let item = player.currentItem, item.currentTime() >= item.duration {
                player.seek(to: .zero)
                audioPlayer.seek(to: .zero)
            }
            scriptPlaying = true
        case .pause:
            scriptPlaying = false
        case .stop:
            scriptPlaying = false
            player.seek(to: .zero)
        case .seek(let seconds):
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case .rate(let rate):
            scriptRate = rate
        case .loop(let value):
            loops = value
        }
        appliedVideoRate = nil
        setVideoRate(scriptPlaying ? scriptRate * hostRate : 0)
    }

}

/// A weak reference to a stream for the closures its loops and loading call on the main thread.
/// `@unchecked Sendable`: the stream is only reached from the main thread through it.
private struct StreamReference: @unchecked Sendable {
    weak var stream: VideoTextureStream?
}

/// A decoded frame kept alive by a command buffer's completion handler, with the texture cache
/// that made it; CoreVideo objects are thread-safe to retain and release.
///
/// The cache must outlive the texture: a CVMetalTexture's last release hands its backing back to
/// the cache that made it (`CVMetalTextureCache::bufferBackingNotInUse`) without retaining it, so
/// a cache freed by its owner on the main thread while a completion handler on Metal's queue lets
/// go of the frame wrote into freed memory (EXC_BAD_ACCESS). The frame goes first, then the cache.
final class HeldVideoFrame: @unchecked Sendable {
    private var texture: CVMetalTexture?
    private let cache: CVMetalTextureCache

    init(_ texture: CVMetalTexture, cache: CVMetalTextureCache) {
        self.texture = texture
        self.cache = cache
    }

    deinit {
        texture = nil
        withExtendedLifetime(cache) {}
    }
}
