import AVFoundation
import AppKit
import WebKit

/// Records a web wallpaper's loop video for the screen saver, or a WebM video's (which plays
/// through WebKit, `WebKitVideoPlayer`), in the app's helper run (`--render-screensaver-loop`).
///
/// The page is loaded in an offscreen `WKWebView` of the display's size in points, configured as
/// the desktop's: served by `WebWallpaperSchemeHandler` with WE's patches, the pause script and
/// the WE web API bridge, user properties and `applyGeneralProperties({fps})` sent once loaded, a
/// silent audio listener feed and no now-playing session. The page is muted.
///
/// **Time is stepped**, not real: `clockScript` gives the page a virtual clock (`performance.now`,
/// `Date.now`, animation frames, timers, CSS animations and `<video>` time), and each frame
/// advances it by exactly 1/30 s before `takeSnapshot` captures it. Capture then needs no Screen
/// Recording permission and no real-time speed: a slow snapshot only makes the recording take
/// longer, the video still shows 30 frames per page second. The time each frame took is logged.
///
/// Pages aren't periodic, so the loop is always found by `ScreenSaverSeamFinder` (best match to
/// frame 0 after 5 s, at most 60 s, a crossfade when the seam shows). A page can't be replayed
/// identically (randomness, network), so the frames are kept in a near-lossless intermediate
/// video while searching and re-encoded from it into the loop, at constant quality 0.95.
@MainActor
final class ScreenSaverWebLoopRecorder: NSObject, WKNavigationDelegate {
    enum Outcome: Equatable {
        case recorded
        /// The page didn't load (navigation failed, an HTTP error, or no video), with why.
        case pageDidNotLoad(String)
        case failed
    }

    static let frameRate = 30

    /// Whether `wallpaper` is recorded from WebKit: a web wallpaper, or a WebM video.
    nonisolated static func records(_ wallpaper: WEWallpaper) -> Bool {
        isWeb(wallpaper) || isWebMVideo(wallpaper)
    }

    nonisolated static func isWeb(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("web") == .orderedSame
    }

    nonisolated static func isWebMVideo(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("video") == .orderedSame
            && (wallpaper.project.file as NSString).pathExtension.lowercased() == "webm"
    }

    let wallpaper: WEWallpaper
    let pixelSize: SIMD2<Int>
    let pointSize: SIMD2<Int>
    let output: URL
    /// The user properties the page gets (stored values; declared defaults fill the rest).
    var properties: [String: String]
    /// The FPS the desktop sends in `applyGeneralProperties`.
    var fps: Int
    var minimumSeconds = ScreenSaverSeamFinder.minimumSeconds
    var maximumSeconds = ScreenSaverSeamFinder.maximumSeconds
    var loadTimeout: TimeInterval = 30
    /// Page time run before frame 0, so the loop doesn't start on the page's first paint.
    var settleSeconds = 1.0
    /// Seconds each captured frame took (step and snapshot), for the log and tests.
    private(set) var frameDurations: [TimeInterval] = []

    private var webView: WKWebView?
    private var window: NSWindow?
    private let schemeHandler = WebWallpaperSchemeHandler()
    private var loadFailure: String?
    private var loadFinished = false
    /// Whether the virtual clock answered; without it frames are captured in real time.
    private var stepsTime = true

    init(wallpaper: WEWallpaper, pixelSize: SIMD2<Int>, pointSize: SIMD2<Int>, output: URL,
         properties: [String: String], fps: Int) {
        self.wallpaper = wallpaper
        self.pixelSize = pixelSize
        self.pointSize = pointSize
        self.output = output
        self.properties = properties
        self.fps = fps
    }

    private var name: String { wallpaper.wallpaperDirectory.lastPathComponent }

    func run() -> Outcome {
        defer { tearDown() }
        if let failure = load() {
            OWELog.error(.app, "Screen saver: \(name)'s page didn't load: \(failure)")
            return .pageDidNotLoad(failure)
        }
        let frameRate = Self.frameRate
        let count = Int(maximumSeconds * Double(frameRate)) + 1
        let fadeFrames = max(Int((ScreenSaverSeamFinder.crossfadeSeconds * Double(frameRate)).rounded()), 1)
        let pass = output.deletingLastPathComponent()
            .appending(path: ".pass-\(output.lastPathComponent)", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: pass) } // Optional: a scratch file.
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: pass) // Optional: a leftover of an earlier run.
        } catch {
            OWELog.error(.app, "Screen saver: can't prepare \(pass.lastPathComponent): \(error)")
            return .failed
        }

        // Pass 1: capture, compare with frame 0, keep every frame in the intermediate video.
        guard let intermediate = HEVCWriter(url: pass, pixelSize: pixelSize, frameRate: frameRate, quality: 1) else {
            return .failed
        }
        for _ in 0..<Int(settleSeconds * Double(frameRate)) { _ = advance() }
        var reference: ScreenSaverFrameSignature?
        var differences: [Double] = []
        differences.reserveCapacity(count)
        for index in 0..<(count + fadeFrames) {
            let started = Date()
            guard advance(), let image = snapshot() else {
                OWELog.error(.app, "Screen saver: \(name)'s frame \(index) couldn't be captured")
                intermediate.cancel()
                return .failed
            }
            frameDurations.append(Date().timeIntervalSince(started))
            if index < count {
                guard let signature = ScreenSaverFrameSignature(image) else { intermediate.cancel(); return .failed }
                if reference == nil { reference = signature }
                differences.append(reference.map { signature.difference($0) } ?? 1)
            }
            guard intermediate.append(image, overlay: nil, weight: 0, frame: index) else {
                intermediate.cancel()
                return .failed
            }
        }
        guard intermediate.finish() else { return .failed }
        logTiming()
        guard let decision = ScreenSaverSeamFinder.decide(differences: differences, frameRate: frameRate,
                                                          minimumSeconds: minimumSeconds) else {
            OWELog.error(.app, "Screen saver: \(name) has no loop")
            return .failed
        }
        OWELog.info(.app, "Screen saver: \(name) loops after \(decision.frames) frames (\(decision.seam))")
        // Pass 2: the loop, from the intermediate frames.
        return encodeLoop(from: pass, frames: decision.frames, seam: decision.seam) ? .recorded : .failed
    }

    private func logTiming() {
        guard !frameDurations.isEmpty else { return }
        let mean = frameDurations.reduce(0, +) / Double(frameDurations.count)
        let worst = frameDurations.max() ?? 0
        let realTime = mean <= 1 / Double(Self.frameRate)
        OWELog.info(.app, "Screen saver: \(name) captured \(frameDurations.count) frames at \(Int((mean * 1000).rounded())) ms each "
                    + "(worst \(Int((worst * 1000).rounded())) ms; \(realTime ? "faster" : "slower") than real time; "
                    + "\(stepsTime ? "page time stepped at 30 fps" : "no page clock, captured in real time"))")
    }

    // MARK: Page

    /// Loads the page and waits for it; the reason it failed, or nil.
    private func load() -> String? {
        let video = Self.isWebMVideo(wallpaper)
        let configuration = WebWallpaperView.makeConfiguration()
        let controller = configuration.userContentController
        // The virtual clock first: the pause script and the bridge wrap its frames and timers.
        for source in [Self.clockScript, WebWallpaperPropertyBridge.pauseScript, WebWallpaperPropertyBridge.bootstrapScript,
                       WebWallpaperMediaBridge.bootstrapScript] {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        configuration.preferences.inactiveSchedulingPolicy = .none
        if !video { configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebWallpaperSchemeHandler.scheme) }
        let frame = NSRect(x: 0, y: 0, width: pointSize.x, height: pointSize.y)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        // A window of its own, off every screen: the page is laid out at the display's size and
        // never shown.
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -100_000, y: -100_000))
        window.orderBack(nil)
        self.webView = webView
        self.window = window
        // Pixels at the points' size: the page draws at a scale of 1, as with Render Resolution "Display".
        WebPageScale.apply(standardResolution: pixelSize.x <= pointSize.x, to: webView)

        let page = wallpaper.wallpaperDirectory.appending(path: wallpaper.project.file)
        if video {
            webView.loadFileURL(page, allowingReadAccessTo: wallpaper.wallpaperDirectory)
        } else {
            switch WebWallpaperView.pageLoad(pageFile: page, relativePath: wallpaper.project.file) {
            case .remoteEmbed(let html):
                webView.loadHTMLString(html, baseURL: URL(string: "https://localhost"))
            case .scheme(let url):
                schemeHandler.directory = wallpaper.wallpaperDirectory
                schemeHandler.patches = WebCompatPatches(
                    workshopId: WebWallpaperViewModel.compatWorkshopId(of: wallpaper),
                    assetsDirectory: WallpaperEngineAssets.directory) ?? WebCompatPatches(actions: [])
                webView.load(URLRequest(url: url))
            case nil:
                return "invalid page path \(wallpaper.project.file)"
            }
        }
        let deadline = Date().addingTimeInterval(loadTimeout)
        if video {
            // A media document reports no navigation finish to rely on: wait for a decoded frame.
            while loadFailure == nil, Date() < deadline {
                if evaluate("(function(){var v=document.querySelector('video');return !!v&&v.readyState>=2;})()") as? Bool == true {
                    loadFinished = true
                    break
                }
                spin(0.05)
            }
        } else {
            while loadFailure == nil, !loadFinished, Date() < deadline { spin(0.01) }
        }
        if let loadFailure { return loadFailure }
        guard loadFinished else { return "no load in \(Int(loadTimeout)) s" }

        WebPageAudio.setMuted(true, on: webView)
        if video {
            evaluate(Self.videoPlacementScript)
        } else {
            let declared = WebWallpaperPropertyBridge.declaredProperties(wallpaperDirectory: wallpaper.wallpaperDirectory)
            let values = WebWallpaperPropertyBridge.currentValues(properties: declared, stored: properties)
            if let script = WebWallpaperPropertyBridge.applyUserPropertiesScript(
                WebWallpaperPropertyBridge.payload(properties: declared, values: values)) {
                evaluate(script)
            }
            evaluate(WebWallpaperPropertyBridge.applyGeneralPropertiesScript(fps: fps))
        }
        stepsTime = evaluate("typeof window.__oweClock === 'object'") as? Bool == true
        if !stepsTime { OWELog.info(.app, "Screen saver: \(name) has no page clock; capturing in real time") }
        return nil
    }

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        window?.contentView = nil
        window?.close()
        webView = nil
        window = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { loadFinished = true }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let reason = error.localizedDescription
        MainActor.assumeIsolated { loadFailure = reason }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        let reason = error.localizedDescription
        MainActor.assumeIsolated { loadFailure = reason }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            let reason = "HTTP \(response.statusCode)"
            MainActor.assumeIsolated { loadFailure = reason }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: Frames

    /// Moves the page 1/30 s on, with a silent audio frame; false when the page stopped answering.
    private func advance() -> Bool {
        guard let webView else { return false }
        let silence = WebWallpaperPropertyBridge.audioDeliveryScript(Array(repeating: 0, count: 128))
        webView.evaluateJavaScript(silence, completionHandler: nil)
        guard stepsTime else {
            spin(1 / Double(Self.frameRate))
            return true
        }
        let box = Box<Bool>()
        webView.callAsyncJavaScript("return await window.__oweClock.step(dt);",
                                    arguments: ["dt": 1000 / Double(Self.frameRate)], in: nil, in: .page) { result in
            if case .failure(let error) = result {
                OWELog.debug(.app, "Screen saver: page step failed: \(error.localizedDescription)")
            }
            box.value = true
        }
        return wait(for: box, timeout: 10) != nil
    }

    private func snapshot() -> CGImage? {
        guard let webView else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = NSNumber(value: pointSize.x)
        configuration.afterScreenUpdates = true
        let box = Box<CGImage>()
        webView.takeSnapshot(with: configuration) { image, error in
            if let error { OWELog.debug(.app, "Screen saver: snapshot failed: \(error.localizedDescription)") }
            box.value = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            box.done = true
        }
        return wait(for: box, timeout: 10)
    }

    @discardableResult
    private func evaluate(_ script: String) -> Any? {
        guard let webView else { return nil }
        let box = Box<Any>()
        webView.evaluateJavaScript(script) { result, _ in
            box.value = result
            box.done = true
        }
        return wait(for: box, timeout: 5)
    }

    private final class Box<Value> {
        var value: Value? { didSet { done = true } }
        var done = false
    }

    private func wait<Value>(for box: Box<Value>, timeout: TimeInterval) -> Value? {
        let deadline = Date().addingTimeInterval(timeout)
        while !box.done, Date() < deadline { spin(0.001) }
        return box.value
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(seconds))
    }

    // MARK: Loop

    /// Re-encodes `frames` frames of the intermediate video as the loop, crossfading its seam
    /// into the frames that follow, as `ScreenSaverLoopRenderer` does.
    private func encodeLoop(from pass: URL, frames: Int, seam: ScreenSaverSeamFinder.Seam) -> Bool {
        let partial = output.deletingLastPathComponent()
            .appending(path: ".partial-\(output.lastPathComponent)", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: partial) // Optional: a leftover of an earlier run.
        guard let reader = IntermediateReader(url: pass),
              let writer = HEVCWriter(url: partial, pixelSize: pixelSize, frameRate: Self.frameRate) else { return false }
        let fade: Int = { if case .crossfade(let frames) = seam { return frames }; return 0 }()
        var head: [CGImage] = []
        for rendered in 0..<(frames + fade) {
            guard let image = reader.next() else {
                OWELog.error(.app, "Screen saver: \(name)'s recorded frame \(rendered) couldn't be read")
                writer.cancel()
                return false
            }
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
        reader.cancel()
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

    // MARK: Scripts

    /// The media document's `<video>` filling the page, as the desktop's default placement does.
    static let videoPlacementScript = """
    document.documentElement.style.background='black';document.body.style.margin='0';\
    document.querySelectorAll('video').forEach(function(v){v.style.position='fixed';v.style.left='0';v.style.top='0';\
    v.style.width='100vw';v.style.height='100vh';v.style.objectFit='cover';v.controls=false;});
    """

    /// Injected at document start: the page's time only moves when `__oweClock.step(ms)` is
    /// called. `performance.now`, `Date.now`, animation frame timestamps and timers follow the
    /// virtual clock; CSS/Web animations are held and moved by the step; each `<video>` is paused
    /// and seeked to the clock (looping), and the step's promise resolves once every seek is done.
    /// `new Date()` keeps the real time, so a page's clock shows the time it was recorded.
    static let clockScript = """
    (function(){
      if (window.__oweClock) return;
      var realNow = performance.now.bind(performance), realTimeout = window.setTimeout.bind(window);
      var origin = realNow(), dateOrigin = Date.now(), now = origin;
      var frames = [], nextFrame = 1, timers = new Map(), nextTimer = 1;
      performance.now = function(){ return now; };
      Date.now = function(){ return Math.floor(dateOrigin + (now - origin)); };
      window.requestAnimationFrame = function(fn){ var id = nextFrame++; frames.push([id, fn]); return id; };
      window.cancelAnimationFrame = function(id){ frames = frames.filter(function(f){ return f[0] !== id; }); };
      var run = function(fn, args){ if (typeof fn === 'function') fn.apply(window, args); else (0, eval)(String(fn)); };
      window.setTimeout = function(fn, ms){
        var id = nextTimer++;
        timers.set(id, { due: now + Math.max(0, +ms || 0), fn: fn, args: Array.prototype.slice.call(arguments, 2), every: 0 });
        return id;
      };
      window.setInterval = function(fn, ms){
        var id = nextTimer++, every = Math.max(1, +ms || 0);
        timers.set(id, { due: now + every, fn: fn, args: Array.prototype.slice.call(arguments, 2), every: every });
        return id;
      };
      window.clearTimeout = window.clearInterval = function(id){ timers.delete(id); };
      var videoTime = new WeakMap();
      window.__oweClock = { step: function(dt){
        var target = now + dt;
        for (var guard = 0; guard < 10000; guard++) {
          var dueId = null, due = Infinity;
          timers.forEach(function(t, id){ if (t.due <= target && t.due < due) { due = t.due; dueId = id; } });
          if (dueId === null) break;
          var timer = timers.get(dueId);
          now = Math.max(now, timer.due);
          if (timer.every) timer.due += timer.every; else timers.delete(dueId);
          try { run(timer.fn, timer.args); } catch(e) { console.error(e); }
        }
        now = target;
        if (document.getAnimations) document.getAnimations().forEach(function(a){
          try { if (a.playState === 'running') a.pause(); if (a.playState === 'paused') a.currentTime = (a.currentTime || 0) + dt; } catch(e) {}
        });
        var callbacks = frames; frames = [];
        callbacks.forEach(function(f){ try { f[1](now); } catch(e) { console.error(e); } });
        var seeks = [];
        document.querySelectorAll('video').forEach(function(v){
          if (!v.paused) v.pause();
          if (!(v.duration > 0) || !isFinite(v.duration)) return;
          var t = ((videoTime.get(v) || 0) + dt / 1000) % v.duration;
          videoTime.set(v, t);
          seeks.push(new Promise(function(resolve){
            var done = function(){ v.removeEventListener('seeked', done); resolve(); };
            v.addEventListener('seeked', done);
            realTimeout(done, 1000);
            v.currentTime = t;
          }));
        });
        return Promise.all(seeks).then(function(){ return true; });
      } };
    })();
    """
}

/// Reads the intermediate video's frames back in order as `CGImage`s.
private final class IntermediateReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    init?(url: URL) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else {
            OWELog.error(.app, "Screen saver: can't read the recorded frames back")
            return nil
        }
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        self.reader = reader
    }

    func next() -> CGImage? {
        guard let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // A copy: the buffer goes back to the decoder's pool.
        let data = Data(bytes: base, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                    | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func cancel() { reader.cancelReading() }
}
