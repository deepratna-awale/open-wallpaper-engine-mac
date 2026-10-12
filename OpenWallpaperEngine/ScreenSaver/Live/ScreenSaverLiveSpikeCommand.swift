#if DEBUG
import AppKit
import Darwin
import Metal
import WebKit

/// Debug builds only: measures ways of feeding the live screen saver's ring of surfaces
/// (`ScreenSaverFramePublisher`) without a screen saver running.
///
///     "Open Wallpaper Engine" --saver-spike <mode> <target> <seconds> <width>x<height> [fps]
///
/// `mode` is `scene` (a scene wallpaper folder, drawn by `ScreenSaverLiveScene`), `shared` (a
/// scene folder loaded first, as a display runs it, then lent to the ring), `chromium` (a
/// URL in the Chromium engine's windowless browser, each frame blitted into the ring) or
/// `webkit` (a URL in a `WKWebView` in a transparent window, captured with `takeSnapshot`). The
/// manifest goes to `$OWE_SPIKE_DIR/live.json` (none without it) and no Darwin notification is
/// posted, so no saver sees the frames. Prints one line per second and a summary.
@MainActor
enum ScreenSaverLiveSpikeCommand {
    static let argument = "--saver-spike"

    static func run(arguments: [String]) -> Int32? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let rest = Array(arguments[(index + 1)...])
        guard rest.count >= 4, let seconds = Double(rest[2]), let size = ShaderPrewarmCommand.size(rest[3]) else {
            print("usage: \(argument) scene|shared|chromium|webkit <target> <seconds> <width>x<height> [fps]")
            return 1
        }
        let fps = rest.count > 4 ? Int(rest[4]) ?? 60 : 60
        guard let device = MTLCreateSystemDefaultDevice() else { print("No Metal device"); return 1 }
        // Windows and display links need the app object, with no Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
        let counter = CountingNotifier()
        let manifestURL = ProcessInfo.processInfo.environment["OWE_SPIKE_DIR"].map {
            URL(fileURLWithPath: $0).appending(path: ScreenSaverLiveManifest.fileName, directoryHint: .notDirectory)
        }
        let publisher = ScreenSaverFramePublisher(manifestURL: manifestURL, notifier: counter, device: device)
        do {
            try publisher.publish(sizes: [size], displays: [.init(display: nil, ring: 0)], frameRate: fps)
        } catch {
            print("Can't allocate the ring: \(error)")
            return 1
        }
        let stats = SpikeStats(startedAt: processStart())
        var keep: [AnyObject] = []
        switch rest[0] {
        case "scene":
            let folder = URL(fileURLWithPath: rest[1])
            guard let data = try? Data(contentsOf: folder.appending(path: "project.json")),
                  let project = try? JSONDecoder().decode(WEProject.self, from: data) else {
                print("No project.json in \(folder.path)")
                return 1
            }
            let wallpaper = WEWallpaper(using: project, where: folder)
            let target = ScreenSaverLiveScene.Target(ring: 0, pixels: size, points: size, frameRate: fps)
            guard let scene = ScreenSaverLiveScene(wallpaper: wallpaper, propertyScope: .shared, target: target,
                                                   screen: NSScreen.main, settings: GlobalSettings(), placement: .fill,
                                                   scriptServices: nil, publisher: publisher) else { return 1 }
            keep.append(scene)
        case "shared":
            // A display's running scene, loaded first as the desktop has it, then lent to the ring
            // (`SceneRenderLoop.lend`, `ScreenSaverSharedScene`): the time to the first frame and
            // the memory the lend adds.
            let folder = URL(fileURLWithPath: rest[1])
            guard let data = try? Data(contentsOf: folder.appending(path: "project.json")),
                  let project = try? JSONDecoder().decode(WEProject.self, from: data),
                  let renderer = SceneMetalRenderer(pixelFormat: .bgra8Unorm, scriptServices: nil, screenID: "spike-shared")
            else { return 1 }
            let model = SceneWallpaperViewModel(wallpaper: WEWallpaper(using: project, where: folder))
            let pixels = SIMD2(Float(size.x), Float(size.y))
            let settings = SceneRenderSettings(GlobalSettings(), outputPixels: pixels, sceneSize: model.textureReductionSceneSize)
            model.setRenderSettings(settings)
            renderer.renderSettings = settings
            let loadStart = CFAbsoluteTimeGetCurrent()
            guard let content = model.metalContent() else { print("No content"); return 1 }
            let loop = SceneRenderLoop(renderer: renderer, name: "OWE spike shared")
            loop.thread.sync { renderer.setContent(content) }
            // Drawn for a while first, as a display runs it (`OWE_SPIKE_WARM` seconds, 5 by default).
            let viewport = SceneViewport(drawableSize: pixels, pointSize: pixels, cursor: nil, frameRateLimit: fps)
            let warm = ProcessInfo.processInfo.environment["OWE_SPIKE_WARM"].flatMap(Double.init) ?? 5
            let warmStart = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - warmStart < warm {
                loop.thread.sync {
                    renderer.renderShared([viewport])
                    renderer.lastCommandBuffer?.waitUntilCompleted()
                }
                _ = RunLoop.main.run(mode: .default, before: .now + 1.0 / Double(fps))
            }
            print(String(format: "loaded in %.0f ms; footprint %.0f MB", (CFAbsoluteTimeGetCurrent() - loadStart) * 1000, Self.footprintMB()))
            let target = ScreenSaverLiveScene.Target(ring: 0, pixels: size, points: size, frameRate: fps)
            stats.lentAt = CFAbsoluteTimeGetCurrent()
            guard let screen = NSScreen.main,
                  let shared = ScreenSaverSharedScene(renderLoop: loop, target: target, screen: screen, publisher: publisher,
                                                      name: folder.lastPathComponent) else { return 1 }
            keep.append(shared)
            keep.append(loop)
            keep.append(model)
        case "chromium":
            guard let url = URL(string: rest[1]) else { return 1 }
            guard let chromium = ChromiumSpike(url: url, size: size, fps: fps, device: device, publisher: publisher,
                                               stats: stats) else { return 1 }
            keep.append(chromium)
        case "webkit":
            guard let url = URL(string: rest[1]) else { return 1 }
            keep.append(WebKitSpike(url: url, size: size, fps: fps, device: device, publisher: publisher, stats: stats))
        default:
            print("Unknown mode \(rest[0])")
            return 1
        }
        let usageStart = Usage.now()
        let wallStart = CFAbsoluteTimeGetCurrent()
        var lastFrames = 0
        var second = 0
        var firstDrawnReported = false
        while CFAbsoluteTimeGetCurrent() - wallStart < seconds {
            _ = RunLoop.main.run(mode: .default, before: .now + 0.05)
            if !firstDrawnReported, let first = counter.firstAt {
                firstDrawnReported = true
                print(String(format: "first frame in the ring %.0f ms after process start (start epoch %.3f, first frame epoch %.3f)",
                             (first - stats.startedAt) * 1000, stats.startedAt + kCFAbsoluteTimeIntervalSince1970,
                             first + kCFAbsoluteTimeIntervalSince1970))
                if let lentAt = stats.lentAt {
                    print(String(format: "first frame %.1f ms after the lend; footprint %.0f MB", (first - lentAt) * 1000, Self.footprintMB()))
                }
            }
            let elapsed = Int(CFAbsoluteTimeGetCurrent() - wallStart)
            if elapsed > second {
                second = elapsed
                let frames = counter.count
                print("t=\(second)s ring frames/s=\(frames - lastFrames) \(stats.line())")
                lastFrames = frames
            }
        }
        let usage = Usage.now()
        let wall = CFAbsoluteTimeGetCurrent() - wallStart
        print(String(format: "SUMMARY mode=%@ size=%dx%d requested=%d fps: ring %.1f fps, app cpu %.1f%%, app gpu %.2f%% over %.0f s; %@",
                     rest[0], size.x, size.y, fps, Double(counter.count) / wall,
                     (usage.cpu - usageStart.cpu) / wall * 100, (usage.gpu - usageStart.gpu) / wall * 100, wall, stats.summary()))
        withExtendedLifetime(keep) {}
        return 0
    }

    /// The process's physical footprint, in MB.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// The process's start, from the kernel.
    static func processStart() -> CFAbsoluteTime {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return CFAbsoluteTimeGetCurrent() }
        let start = info.kp_proc.p_un.__p_starttime
        return Double(start.tv_sec) + Double(start.tv_usec) / 1e6 - kCFAbsoluteTimeIntervalSince1970
    }

    struct Usage {
        var cpu: Double
        var gpu: Double

        static func now() -> Usage {
            var info = task_power_info_v2()
            var count = mach_msg_type_number_t(MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
                }
            }
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            guard status == KERN_SUCCESS else { return Usage(cpu: cpu, gpu: 0) }
            return Usage(cpu: cpu, gpu: Double(info.gpu_energy.task_gpu_utilisation) / 1e9)
        }
    }
}

/// Counts the ring's frames instead of posting them.
private final class CountingNotifier: ScreenSaverFrameNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var first: CFAbsoluteTime?

    var count: Int { lock.withLock { frames } }
    var firstAt: CFAbsoluteTime? { lock.withLock { first } }

    func post(_ name: String, state: UInt64) {
        lock.withLock {
            frames += 1
            if first == nil { first = CFAbsoluteTimeGetCurrent() }
        }
    }
}

/// Source frames, capture and copy times, and the copy's latency.
private final class SpikeStats: @unchecked Sendable {
    let startedAt: CFAbsoluteTime
    /// When a running scene was lent to the ring (mode `shared`). Main thread.
    var lentAt: CFAbsoluteTime?
    private let lock = NSLock()
    private var sourceFrames = 0
    private var lastSource = 0
    private var captureMs: [Double] = []
    private var latencyMs: [Double] = []
    private var gpuMs: [Double] = []
    private var skipped = 0
    var extra: () -> String = { "" }

    init(startedAt: CFAbsoluteTime) { self.startedAt = startedAt }

    func source() { lock.withLock { sourceFrames += 1 } }
    func skip() { lock.withLock { skipped += 1 } }
    func capture(_ ms: Double) { lock.withLock { captureMs.append(ms) } }
    func copied(latency: Double, gpu: Double) { lock.withLock { latencyMs.append(latency); gpuMs.append(gpu) } }

    func line() -> String {
        let (frames, more) = lock.withLock { () -> (Int, String) in
            defer { lastSource = sourceFrames }
            return (sourceFrames - lastSource, "")
        }
        return "source frames/s=\(frames)\(more) \(extra())"
    }

    func summary() -> String {
        lock.withLock {
            func median(_ values: [Double]) -> Double {
                guard !values.isEmpty else { return 0 }
                return values.sorted()[values.count / 2]
            }
            func p95(_ values: [Double]) -> Double {
                guard !values.isEmpty else { return 0 }
                return values.sorted()[min(values.count - 1, Int(Double(values.count) * 0.95))]
            }
            return String(format: "source frames %d, skipped %d, capture median %.2f ms p95 %.2f ms, copy latency median %.2f ms p95 %.2f ms, copy gpu median %.3f ms",
                          sourceFrames, skipped, median(captureMs), p95(captureMs), median(latencyMs), p95(latencyMs), median(gpuMs))
        }
    }
}

/// The Chromium engine's windowless browser; each frame (an IOSurface-backed texture) is blitted
/// into the ring on the GPU.
private final class ChromiumSpike: @unchecked Sendable {
    private let session: ChromiumEngineSession
    private let queue: MTLCommandQueue

    @MainActor
    init?(url: URL, size: SIMD2<Int>, fps: Int, device: MTLDevice, publisher: ScreenSaverFramePublisher, stats: SpikeStats) {
        let installer = ChromiumEngineInstaller()
        guard let install = installer.activeInstall else { print("The Chromium engine isn't installed"); return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        session = ChromiumEngineSession.embedded(device: device, onFrame: { frame in
            stats.source()
            let arrived = CFAbsoluteTimeGetCurrent()
            guard frame.texture.width == size.x, frame.texture.height == size.y,
                  let target = publisher.target(ring: 0), let buffer = queue.makeCommandBuffer(),
                  let blit = buffer.makeBlitCommandEncoder() else { stats.skip(); return }
            blit.copy(from: frame.texture, to: target.texture)
            blit.endEncoding()
            // The helper may reuse the surface once the frame is handed on: hold it until copied.
            let held = frame
            buffer.addCompletedHandler { done in
                withExtendedLifetime(held) {}
                guard done.status == .completed else { return }
                stats.copied(latency: (CFAbsoluteTimeGetCurrent() - arrived) * 1000, gpu: (done.gpuEndTime - done.gpuStartTime) * 1000)
                publisher.drawn(ring: 0, slot: target.slot, generation: target.generation)
            }
            buffer.commit()
        }, onExit: { reason in print("Chromium helper exited: \(reason)") })
        session.start(url: url, install: install, profile: installer.profileDirectory, width: size.x, height: size.y,
                      frameRate: fps) { error in
            if let error { print("Chromium didn't start: \(error)") }
        }
    }

    deinit { session.stop() }
}

/// A `WKWebView` in a transparent, mouse-transparent window on screen; `takeSnapshot` on a timer
/// at `fps`, each image uploaded into the ring by the CPU.
@MainActor
private final class WebKitSpike: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private var timer: Timer?
    private var inFlight = false
    private let publisher: ScreenSaverFramePublisher
    private let stats: SpikeStats
    private let size: SIMD2<Int>
    private var rafCount = 0
    private var rafPrevious = 0

    init(url: URL, size: SIMD2<Int>, fps: Int, device: MTLDevice, publisher: ScreenSaverFramePublisher, stats: SpikeStats) {
        self.publisher = publisher
        self.stats = stats
        self.size = size
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let points = NSRect(x: 0, y: 0, width: CGFloat(size.x) / scale, height: CGFloat(size.y) / scale)
        window = NSWindow(contentRect: points, styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: points, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.orderFrontRegardless()
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture() }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readRAF() }
        }
        stats.extra = { [weak self] in
            guard let self else { return "" }
            return MainActor.assumeIsolated { "page rAF/s=\(self.rafCount - self.rafPrevious) occlusion=\(self.window.occlusionState.contains(.visible) ? "visible" : "occluded")" }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.__spikeRAF=0;(function f(){window.__spikeRAF++;requestAnimationFrame(f)})();0")
    }

    private func readRAF() {
        webView.evaluateJavaScript("window.__spikeRAF||0") { [weak self] value, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rafPrevious = self.rafCount
                self.rafCount = (value as? Int) ?? 0
            }
        }
    }

    private func capture() {
        guard !inFlight else { stats.skip(); return }
        inFlight = true
        let started = CFAbsoluteTimeGetCurrent()
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.inFlight = false
                self.stats.source()
                guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    self.stats.skip()
                    return
                }
                let captured = CFAbsoluteTimeGetCurrent()
                self.stats.capture((captured - started) * 1000)
                guard let target = self.publisher.target(ring: 0) else { return }
                // Draw the image into the ring surface's pixels: the CPU copy a snapshot needs.
                let width = target.texture.width, height = target.texture.height
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                    else { return false }
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                    target.texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                           withBytes: buffer.baseAddress!, bytesPerRow: width * 4)
                    return true
                }
                guard drew else { self.stats.skip(); return }
                self.stats.copied(latency: (CFAbsoluteTimeGetCurrent() - started) * 1000, gpu: 0)
                self.publisher.drawn(ring: 0, slot: target.slot, generation: target.generation)
            }
        }
    }
}
#endif
