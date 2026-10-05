import AppKit
import CoreVideo
import IOSurface
import Metal
import QuartzCore

/// Plays one transition for one changing wallpaper: renders each frame once on the GPU into one of
/// a few IOSurfaces at the wallpaper's size, which every display showing it shows through its
/// overlay (`WallpaperTransitionOverlayView`). Paced by the first overlay's display link, it draws
/// a frame only when the last one is done, and frees everything when it ends.
@MainActor
final class WallpaperTransitionPlayer {
    let kind: WallpaperTransitionKind
    let duration: TimeInterval
    /// The display, region or group source it plays for.
    let target: String
    private let renderer: WallpaperTransitionRenderer
    private let queue: MTLCommandQueue
    private let seed: WallpaperTransitionSeed
    private(set) var overlays: [WallpaperTransitionOverlayView]
    /// The outgoing picture as `kind` samples it; nil once it ended.
    private(set) var outgoing: MTLTexture?
    /// The frames' IOSurfaces and their textures, used in turn; empty once it ended.
    private(set) var surfaces: [(surface: IOSurface, texture: MTLTexture)] = []
    private var nextSurface = 0
    private var displayLink: CADisplayLink?
    private var ticker: WallpaperTransitionTicker?
    private var startTime: CFTimeInterval?
    private var frameInFlight = false
    private var onFinish: ((WallpaperTransitionPlayer) -> Void)?

    static let surfaceCount = 3

    /// Errors setting one up: the change then applies without it.
    enum Failure: Error, CustomStringConvertible {
        case surface(SIMD2<Int>)
        case commandBuffer

        var description: String {
            switch self {
            case .surface(let size): return "can't allocate a \(size.x)×\(size.y) frame"
            case .commandBuffer: return "no command buffer"
            }
        }
    }

    var isFinished: Bool { outgoing == nil }

    init(kind: WallpaperTransitionKind, duration: TimeInterval, target: String, outgoing: MTLTexture,
         pixelSize: SIMD2<Int>, renderer: WallpaperTransitionRenderer, queue: MTLCommandQueue,
         seed: WallpaperTransitionSeed = .random(), overlays: [WallpaperTransitionOverlayView]) throws {
        self.kind = kind
        self.duration = max(duration, 0.001)
        self.target = target
        self.renderer = renderer
        self.queue = queue
        self.seed = seed
        self.overlays = overlays
        guard let commandBuffer = queue.makeCommandBuffer() else { throw Failure.commandBuffer }
        commandBuffer.label = "Transition outgoing"
        self.outgoing = try renderer.prepareOutgoing(outgoing, for: kind, commandBuffer: commandBuffer)
        commandBuffer.commit()
        for _ in 0..<Self.surfaceCount {
            surfaces.append(try Self.makeSurface(pixelSize, device: renderer.device))
        }
    }

    /// Draws the first frame (progress 0: the outgoing picture) and waits for it, so the overlays
    /// cover the display before the wallpaper underneath changes.
    func showFirstFrame() throws {
        let commandBuffer = try render(progress: 0)
        commandBuffer.waitUntilCompleted()
        present(nextSurface)
        nextSurface = (nextSurface + 1) % surfaces.count
    }

    /// Plays it out from now; `onFinish` runs once it ended or was stopped.
    func run(onFinish: @escaping (WallpaperTransitionPlayer) -> Void) {
        self.onFinish = onFinish
        guard let view = overlays.first else { return stop() }
        let ticker = WallpaperTransitionTicker { [weak self] link in self?.tick(link) }
        let link = view.displayLink(target: ticker, selector: #selector(WallpaperTransitionTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.ticker = ticker
        displayLink = link
    }

    /// The progress `time` after it started.
    func progress(at time: CFTimeInterval) -> Float {
        guard let startTime else { return 0 }
        return Float(min(max((time - startTime) / duration, 0), 1))
    }

    private func tick(_ link: CADisplayLink) {
        guard !isFinished else { return }
        let now = link.timestamp
        if startTime == nil { startTime = now }
        let progress = progress(at: now)
        guard progress < 1 else { return stop() }
        // A frame still on the GPU: this refresh keeps showing the last one.
        guard !frameInFlight else { return }
        let index = nextSurface
        nextSurface = (nextSurface + 1) % surfaces.count
        do {
            let commandBuffer = try render(progress: progress, surface: index)
            frameInFlight = true
            commandBuffer.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, !self.isFinished else { return }
                        self.frameInFlight = false
                        self.present(index)
                    }
                }
            }
            commandBuffer.commit()
        } catch {
            OWELog.error(.app, "Transition \(kind) on \(target) stopped: \(error)")
            stop()
        }
    }

    @discardableResult
    private func render(progress: Float, surface index: Int? = nil) throws -> MTLCommandBuffer {
        guard let outgoing, let commandBuffer = queue.makeCommandBuffer() else { throw Failure.commandBuffer }
        commandBuffer.label = "Transition \(kind)"
        try renderer.encode(kind, progress: progress, outgoing: outgoing, seed: seed,
                            into: surfaces[index ?? nextSurface].texture, commandBuffer: commandBuffer)
        if index == nil { commandBuffer.commit() }
        return commandBuffer
    }

    private func present(_ index: Int) {
        guard surfaces.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for overlay in overlays { overlay.show(surfaces[index].surface) }
        CATransaction.commit()
    }

    /// Ends it: the overlays leave the windows and the frames and the outgoing picture are freed.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        ticker = nil
        for overlay in overlays { overlay.removeFromSuperview() }
        overlays = []
        surfaces = []
        outgoing = nil
        let finish = onFinish
        onFinish = nil
        finish?(self)
    }

    /// A BGRA IOSurface of `size` in sRGB and a render target over it.
    static func makeSurface(_ size: SIMD2<Int>, device: MTLDevice) throws -> (surface: IOSurface, texture: MTLTexture) {
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: size.x, .height: size.y, .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        guard let surface = IOSurface(properties: properties) else { throw Failure.surface(size) }
        if let space = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, space)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size.x,
                                                                  height: size.y, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            throw Failure.surface(size)
        }
        return (surface, texture)
    }
}

/// The display link's target: calls the player without keeping it alive.
final class WallpaperTransitionTicker: NSObject {
    private let action: @MainActor (CADisplayLink) -> Void

    init(_ action: @escaping @MainActor (CADisplayLink) -> Void) {
        self.action = action
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { action(link) }
    }
}
