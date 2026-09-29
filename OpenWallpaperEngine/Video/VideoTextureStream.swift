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
final class VideoTextureStream {
    let player: AVPlayer
    /// Natural frame size, once the first frame has arrived.
    private(set) var frameSize = SIMD2<Float>(1920, 1080)

    /// Native bi-planar Y'CbCr until something about it is unsupported, then BGRA for good.
    private var output: AVPlayerItemVideoOutput
    private let item: AVPlayerItem
    private let converter: VideoYCbCrConverter
    private var decodesYCbCr = true
    /// Audio is a second player on the same file, mirroring the AVKit path: the video player stays
    /// muted so music pacing never pitch-shifts the soundtrack.
    private let audioPlayer: AVPlayer
    private var textureCache: CVMetalTextureCache?
    private let ownAudioTap = AudioLevelTap()
    private var audioIsAudible = false
    /// The CVMetalTextures (and so their pool CVPixelBuffer) must outlive every GPU read of them:
    /// the BGRA texture handed to the renderer, or the Y'CbCr planes the conversion reads. This
    /// holds the newest frame's; `holdCurrentFrame(until:)` keeps them alive past replacement until
    /// each command buffer that used them completes, so the decoder can't be handed the buffer
    /// back while a frame in flight still reads it.
    private var retainedTextures: [CVMetalTexture] = []
    private var latestTexture: MTLTexture?
    private var observers: [NSObjectProtocol] = []

    private var appliedVideoRate: Float?
    private var appliedAudioRate: Float?
    private var smoothedAudioLevel: Double = 0
    private static let rateEpsilon: Float = 0.01
    private static let audioSmoothing = 0.25

    init?(url: URL, device: MTLDevice) {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { return nil }
        textureCache = cache
        converter = VideoYCbCrConverter(device: device)

        // The decoder's own format, so it skips its RGB conversion; the range is whichever the
        // source is, read back from each frame.
        let output = Self.makeOutput(formats: [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                               kCVPixelFormatType_420YpCbCr8BiPlanarFullRange])
        self.output = output
        let item = AVPlayerItem(url: url)
        self.item = item
        item.add(output)
        player = WallpaperAVPlayer.make(item: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        let audioItem = AVPlayerItem(url: url)
        audioItem.audioTimePitchAlgorithm = .timeDomain
        audioPlayer = WallpaperAVPlayer.make(item: audioItem)
        audioPlayer.actionAtItemEnd = .none
        ownAudioTap.attach(to: audioItem)

        for observed in [item, audioItem] {
            observers.append(NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: observed, queue: .main
            ) { [weak self] _ in self?.restart() })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        player.pause()
        audioPlayer.pause()
        player.replaceCurrentItem(with: nil)
        audioPlayer.replaceCurrentItem(with: nil)
    }

    /// Stops both players and drops their items, so audio cannot keep playing through whatever
    /// still holds a reference to this stream (the renderer retains it inside the built layer).
    func stop() {
        player.pause()
        audioPlayer.pause()
        player.replaceCurrentItem(with: nil)
        audioPlayer.replaceCurrentItem(with: nil)
        appliedVideoRate = nil
        appliedAudioRate = nil
    }

    /// Whether a frame newer than the one last handed out is ready now (nothing is consumed): a
    /// frame without one shows the same picture, so the renderer can skip it.
    var hasNewFrame: Bool {
        latestTexture == nil || output.hasNewPixelBuffer(forItemTime: output.itemTime(forHostTime: CACurrentMediaTime()))
    }

    /// The newest frame taken by `prepareFrame(commandBuffer:)`; nil before the first one.
    func currentTexture() -> MTLTexture? { latestTexture }

    /// Takes the frame for the current host time, if a new one is ready, and makes it the current
    /// texture. A Y'CbCr frame is converted to RGB in `commandBuffer`, so call this once per drawn
    /// frame before anything samples `currentTexture()`, and `holdCurrentFrame(until:)` after.
    func prepareFrame(commandBuffer: MTLCommandBuffer) {
        if decodesYCbCr {
            switch converter.state {
            case .building: return
            case .failed: fallBackToBGRA()
            case .ready: break
            }
        }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
              let textureCache else { return }
        defer { CVMetalTextureCacheFlush(textureCache, 0) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        guard decodesYCbCr else {
            guard let frame = Self.texture(buffer, plane: 0, format: .bgra8Unorm, cache: textureCache),
                  let texture = CVMetalTextureGetTexture(frame) else { return }
            publish(texture, retaining: [frame], width: width, height: height)
            return
        }
        guard let conversion = VideoYCbCrConversion(buffer: buffer),
              let luma = Self.texture(buffer, plane: 0, format: .r8Unorm, cache: textureCache),
              let chroma = Self.texture(buffer, plane: 1, format: .rg8Unorm, cache: textureCache),
              let lumaTexture = CVMetalTextureGetTexture(luma),
              let chromaTexture = CVMetalTextureGetTexture(chroma),
              let texture = converter.convert(luma: lumaTexture, chroma: chromaTexture, conversion: conversion,
                                              commandBuffer: commandBuffer) else {
            OWELog.error(.scene, "Video frame format \(CVPixelBufferGetPixelFormatType(buffer)) can't be converted "
                         + "on the GPU; decoding to BGRA instead")
            fallBackToBGRA()
            return
        }
        publish(texture, retaining: [luma, chroma], width: width, height: height)
    }

    /// Keeps the current frame's CVMetalTextures alive until `commandBuffer` completes. Call it for
    /// every command buffer that converted or sampled `currentTexture()`, before committing it.
    func holdCurrentFrame(until commandBuffer: MTLCommandBuffer) {
        guard !retainedTextures.isEmpty else { return }
        let frame = HeldVideoFrame(retainedTextures)
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(frame) {} }
    }

    private func publish(_ texture: MTLTexture, retaining frames: [CVMetalTexture], width: Int, height: Int) {
        retainedTextures = frames
        latestTexture = texture
        frameSize = SIMD2<Float>(Float(width), Float(height))
    }

    /// Swaps the item's output for a BGRA one; the last picture stays until its first frame.
    private func fallBackToBGRA() {
        decodesYCbCr = false
        item.remove(output)
        output = Self.makeOutput(formats: [kCVPixelFormatType_32BGRA])
        item.add(output)
    }

    private static func makeOutput(formats: [OSType]) -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: formats.map { NSNumber(value: $0) }
        ])
    }

    /// A Metal view of one plane of `buffer` (plane 0 of a non-planar buffer is the whole image).
    private static func texture(_ buffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat,
                                cache: CVMetalTextureCache) -> CVMetalTexture? {
        let planar = CVPixelBufferIsPlanar(buffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, plane) : CVPixelBufferGetWidth(buffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
        var created: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil, format,
                                                        width, height, plane, &created) == kCVReturnSuccess
        else { return nil }
        return created
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

    func restart() {
        player.seek(to: .zero)
        audioPlayer.seek(to: .zero)
        // Seeking clears the rate, so the cache no longer describes the players.
        appliedVideoRate = nil
        appliedAudioRate = nil
    }
}

/// A decoded frame kept alive by a command buffer's completion handler; CoreVideo objects are
/// thread-safe to retain and release.
private final class HeldVideoFrame: @unchecked Sendable {
    let textures: [CVMetalTexture]
    init(_ textures: [CVMetalTexture]) { self.textures = textures }
}
