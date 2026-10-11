import AppKit
import ImageIO
import Metal
import MetalPerformanceShaders
import QuartzCore

/// What a saver view shows (the `.saver`'s `OWESaverView` and the extension's view): the app's
/// live frames while they arrive (`LiveFrameSource`), else the loop video (`SaverVideoPlayer`),
/// switched with a short crossfade (`LiveFrameFallback`), over the display's still picture
/// (`ScreenSaverStills`), which shows until the first frames come. It works around the hosts' known bugs
/// (live screen saver notes §4):
///
/// - It starts on `startAnimation` whatever it heard (a new host misses `didstart`), and again on
///   `didstart` (hosts are reused); it stops on `willstop`/`didstop` and `stopAnimation`, keeping
///   its last frame, which the lock screen shows. It never exits.
/// - A view whose frames aren't presented (a stacked instance, a hidden host) parks at 1 fps
///   (`SaverParkPolicy`).
/// - Each frame is drawn as it comes (the store's observer), not on a display link of its own,
///   which beat against the app's and dropped frames; the link only checks for a stall, pings and
///   reports, a few times a second.
/// - A view that starts while the process already shows live frames (the host's new views at the
///   lock) shows them at once, with no fade from black.
/// - A small view is the System Settings preview whatever its flag says: it never makes the app draw.
/// - Every view of the process shares one frame source, and the app draws each loop once.
///
/// Frames are drawn into a `CAMetalLayer` (scaled to fill, a stretch's rect cropped) so that
/// `presentedTime` says whether the view is on screen. Main thread.
@MainActor
final class LiveSaverPresenter: NSObject {
    /// The rate a view checks for a stall, pings the app and reports.
    static let housekeepingRate = 4
    /// How long the switch between the video and live frames fades.
    static let crossfade: CFTimeInterval = 0.3

    private weak var view: NSView?
    private let source: LiveFrameSource
    private let video = SaverVideoPlayer()
    private let still = CALayer()
    private var stillFile: String?
    private let metalLayer = CAMetalLayer()
    private let viewID = UUID().uuidString
    private let isPreview: Bool
    private var link: CADisplayLink?
    private var linkRate = 0
    private var fallback = LiveFrameFallback()
    private var park = SaverParkPolicy(startedAt: 0)
    private var shown: ScreenSaverLiveStamp?
    private var showsLive = false
    private(set) var isRunning = false
    private var lastPing: CFTimeInterval = -.infinity
    private var lastDrawn: CFTimeInterval?
    private var observers: [NSObjectProtocol] = []
    private var textures: [IOSurfaceID: MTLTexture] = [:]
    private var stats = Stats()

    /// What the lab log reports every `Stats.interval` seconds.
    private struct Stats {
        static let interval: CFTimeInterval = 10
        var since: CFTimeInterval = 0
        var arrived = 0
        var drawn = 0
        var presented = 0
        var ticks = 0
        var skippedParked = 0
    }

    init(view: NSView, isPreview flag: Bool, source: LiveFrameSource) {
        self.view = view
        self.source = source
        isPreview = SaverParkPolicy.isPreview(flag: flag, size: view.bounds.size)
        super.init()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        still.frame = view.bounds
        still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        still.contentsGravity = .resizeAspectFill
        still.masksToBounds = true
        view.layer?.addSublayer(still)
        video.layer.frame = view.bounds
        view.layer?.addSublayer(video.layer)
        metalLayer.device = SaverMetal.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.opacity = 0
        metalLayer.frame = view.bounds
        metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(metalLayer)
        SaverLog.lifecycle.notice("view init pid=\(getpid()) view=\(self.viewID, privacy: .public) frame=\(Int(view.bounds.width))x\(Int(view.bounds.height)) previewFlag=\(flag) preview=\(self.isPreview)")
        observeLifecycle()
        source.store.addObserver(self) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.frameCame() } }
        }
    }

    /// Stops observing; the view is going away.
    func invalidate() {
        stop(reason: "deinit")
        source.store.removeObserver(self)
        let center = DistributedNotificationCenter.default()
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    // MARK: Lifecycle

    func start(reason: String) {
        guard !isRunning, let view else { return }
        isRunning = true
        let now = CACurrentMediaTime()
        park = SaverParkPolicy(startedAt: now)
        fallback.reset()
        stats = Stats(since: now)
        shown = nil
        lastDrawn = nil
        loadStill()
        source.attach(viewID: viewID, display: displayIdentity, isPreview: isPreview)
        source.refresh()
        // Another view of this process shows live frames (a new host view at the lock): so does
        // this one, at once.
        let resumes = source.store.hasFreshFrame(at: LiveFrameStore.now(), within: LiveFrameFallback.staleAfter)
            && source.store.newestFrame(display: displayIdentity, pixels: pixels) != nil
        var started = false
        if resumes {
            fallback.resume(at: now)
            showLive(true, animated: false)
            frameCame()
        } else {
            showLive(false, animated: false)
            started = video.start(display: displayIdentity, bounds: view.bounds, scale: scale)
        }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        setRate(Self.housekeepingRate)
        SaverLog.lifecycle.notice("start (\(reason, privacy: .public)) view=\(self.viewID, privacy: .public) display=\(self.displayIdentity ?? "nil", privacy: .public) pixels=\(self.pixels.width)x\(self.pixels.height) live=\(resumes) video=\(started)")
    }

    /// Stops drawing and checking, keeping the last frame shown (the lock screen shows it).
    func stop(reason: String) {
        guard isRunning else { return }
        isRunning = false
        link?.invalidate()
        link = nil
        linkRate = 0
        video.pause()
        source.detach(viewID: viewID)
        SaverLog.lifecycle.notice("stop (\(reason, privacy: .public)) view=\(self.viewID, privacy: .public) live=\(self.showsLive)")
    }

    func layout() {
        guard let view else { return }
        video.layout(in: view.bounds)
    }

    private func observeLifecycle() {
        let center = DistributedNotificationCenter.default()
        let events: [(Notification.Name, Bool)] = [
            (ScreenSaverLiveNames.didStart, true), (ScreenSaverLiveNames.willStop, false), (ScreenSaverLiveNames.didStop, false),
        ]
        for (name, starts) in events {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    SaverLog.lifecycle.notice("\(name.rawValue, privacy: .public) pid=\(getpid())")
                    if starts { self?.start(reason: name.rawValue) } else { self?.stop(reason: name.rawValue) }
                }
            })
        }
        for name in [ScreenSaverLiveNames.screenLocked, ScreenSaverLiveNames.screenUnlocked] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                SaverLog.lifecycle.notice("\(name.rawValue, privacy: .public) pid=\(getpid())")
            })
        }
    }

    // MARK: Frames

    /// A few times a second: the app is pinged, a stall falls back, the park and the report.
    @objc private func tick(_ link: CADisplayLink) {
        guard isRunning else { return }
        let now = CACurrentMediaTime()
        stats.ticks += 1
        source.refresh()
        if now - lastPing >= 1 {
            lastPing = now
            source.ping(viewID: viewID)
        }
        let live = fallback.update(at: now) == .live
        if live != showsLive { showLive(live, animated: true) }
        let parked = park.isParked(at: now)
        setRate(parked ? SaverParkPolicy.parkedRate : Self.housekeepingRate)
        report(at: now, parked: parked)
    }

    /// A new frame is in the store: drawn now, while live (one a second while parked).
    private func frameCame() {
        guard isRunning, let frame = source.store.newestFrame(display: displayIdentity, pixels: pixels),
              frame.stamp.isNewer(than: shown) else { return }
        let now = CACurrentMediaTime()
        shown = frame.stamp
        stats.arrived += 1
        fallback.frameArrived(at: now)
        if fallback.mode == .live, !showsLive { showLive(true, animated: true) }
        guard fallback.mode == .live else { return }
        guard park.mayDraw(at: now, lastDrawn: lastDrawn) else {
            stats.skippedParked += 1
            return
        }
        lastDrawn = now
        draw(frame)
    }

    private func showLive(_ live: Bool, animated: Bool) {
        showsLive = live
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? Self.crossfade : 0)
        CATransaction.setDisableActions(!animated)
        metalLayer.opacity = live ? 1 : 0
        CATransaction.commit()
        if live {
            video.pause()
        } else if let view, isRunning, animated {
            video.start(display: displayIdentity, bounds: view.bounds, scale: scale)
        }
        if animated {
            SaverLog.frames.notice("\(live ? "live frames" : "fallback to video", privacy: .public) view=\(self.viewID, privacy: .public)")
        }
    }

    /// Shows the display's still picture, decoded off the main thread; kept when there is none.
    private func loadStill() {
        let folder = ScreenSaverManifest.sharedFolder(home: ScreenSaverManifest.userHome)
        guard let file = ScreenSaverStills.read(folder.appending(path: ScreenSaverStills.fileName))?
            .file(forDisplay: displayIdentity) else { return }
        let url = folder.appending(path: file)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate // Optional: part of the key.
        let key = "\(file)|\(modified?.timeIntervalSinceReferenceDate ?? 0)"
        guard key != stillFile else { return }
        stillFile = key
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let image else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.still.contents = image
                    CATransaction.commit()
                    SaverLog.lifecycle.notice("still view=\(self.viewID, privacy: .public) \(file, privacy: .public)")
                }
            }
        }
    }

    /// Draws `frame` filling the view (a stretch's rect of it), and records whether it reached
    /// the screen.
    private func draw(_ frame: LiveFrame) {
        guard let device = SaverMetal.device, let queue = SaverMetal.queue, let scaler = SaverMetal.scaler else { return }
        let size = pixels
        guard size.width > 0, size.height > 0 else { return }
        let drawableSize = CGSize(width: size.width, height: size.height)
        if metalLayer.drawableSize != drawableSize { metalLayer.drawableSize = drawableSize }
        guard let texture = texture(for: frame.surface, device: device), let drawable = metalLayer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer() else { return }
        var transform = Self.fillTransform(source: CGSize(width: texture.width, height: texture.height), crop: frame.crop,
                                           destination: drawableSize)
        withUnsafePointer(to: &transform) { pointer in
            scaler.scaleTransform = pointer
            scaler.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: drawable.texture)
            scaler.scaleTransform = nil
        }
        drawable.addPresentedHandler { [weak self] presented in
            guard presented.presentedTime > 0 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.park.presented(at: CACurrentMediaTime())
                    self?.stats.presented += 1
                }
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        stats.drawn += 1
    }

    /// The scale and offset (in pixels) that make `crop` of a `source`-sized frame (all of it
    /// when nil) cover `destination`, centred, keeping its aspect.
    nonisolated static func fillTransform(source: CGSize, crop: ScreenSaverManifest.Crop?,
                                          destination: CGSize) -> MPSScaleTransform {
        let rect = crop.map { CGRect(x: $0.x * source.width, y: $0.y * source.height,
                                     width: $0.width * source.width, height: $0.height * source.height) }
            ?? CGRect(origin: .zero, size: source)
        guard rect.width > 0, rect.height > 0 else { return MPSScaleTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0) }
        let scale = max(destination.width / rect.width, destination.height / rect.height)
        return MPSScaleTransform(scaleX: Double(scale), scaleY: Double(scale),
                                 translateX: Double((destination.width - rect.width * scale) / 2 - rect.minX * scale),
                                 translateY: Double((destination.height - rect.height * scale) / 2 - rect.minY * scale))
    }

    private func texture(for surface: IOSurface, device: MTLDevice) -> MTLTexture? {
        let id = IOSurfaceGetID(surface)
        if let texture = textures[id], texture.width == surface.width, texture.height == surface.height { return texture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: surface.width,
                                                                  height: surface.height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            SaverLog.frames.error("can't wrap surface \(id) (\(surface.width)x\(surface.height)) in a texture")
            return nil
        }
        // A new ring replaces the old surfaces; keep only the current ones.
        if textures.count > 12 { textures.removeAll() }
        textures[id] = texture
        return texture
    }

    private func setRate(_ rate: Int) {
        let rate = max(rate, 1)
        guard rate != linkRate, let link else { return }
        linkRate = rate
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(min(rate, 1)), maximum: Float(rate),
                                                         preferred: Float(rate))
    }

    // MARK: Lab log

    private func report(at now: CFTimeInterval, parked: Bool) {
        guard now - stats.since >= Stats.interval else { return }
        SaverLog.frames.notice("view=\(self.viewID, privacy: .public) live=\(self.showsLive) parked=\(parked) rate=\(self.linkRate) ticks=\(self.stats.ticks) arrived=\(self.stats.arrived) drawn=\(self.stats.drawn) presented=\(self.stats.presented) skippedParked=\(self.stats.skippedParked) over \(Int(now - self.stats.since)) s")
        SaverCostMeter.report(at: now, parked: parked)
        stats = Stats(since: now)
    }

    // MARK: Display

    private var scale: CGFloat {
        view?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var pixels: (width: Int, height: Int) {
        guard let view else { return (0, 0) }
        return (Int(view.bounds.width * scale), Int(view.bounds.height * scale))
    }

    /// The view's display's identity, as the app names displays (`DisplayIdentity`).
    private var displayIdentity: String? {
        guard let number = view?.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

/// The Metal objects every view of a saver process shares.
@MainActor
enum SaverMetal {
    static let device = MTLCreateSystemDefaultDevice()
    static let queue = device?.makeCommandQueue()
    static let scaler: MPSImageBilinearScale? = device.flatMap {
        MPSSupportsMTLDevice($0) ? MPSImageBilinearScale(device: $0) : nil
    }
}

/// The process's CPU and GPU time, logged with the views' reports: what a parked or hidden host
/// costs (Phase 0).
@MainActor
enum SaverCostMeter {
    private static var last: (time: CFTimeInterval, cpu: Double, gpu: UInt64)?

    static func report(at now: CFTimeInterval, parked: Bool) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = task_power_info_v2()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
            }
        }
        let gpu = status == KERN_SUCCESS ? info.gpu_energy.task_gpu_utilisation : 0
        defer { last = (now, cpu, gpu) }
        guard let last, now > last.time else { return }
        let seconds = now - last.time
        let cpuPercent = (cpu - last.cpu) / seconds * 100
        let gpuPercent = Double(gpu &- last.gpu) / 1_000_000_000 / seconds * 100
        SaverLog.cost.notice("pid=\(getpid()) parked=\(parked) cpu=\(String(format: "%.2f", cpuPercent), privacy: .public)% gpu=\(String(format: "%.2f", gpuPercent), privacy: .public)% over \(Int(seconds)) s")
    }
}
