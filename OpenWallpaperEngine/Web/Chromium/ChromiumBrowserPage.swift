import AppKit
import CoreImage
import Foundation

/// One Chromium browser showing one page, as `WebWallpaperPage`: what a WKWebView is to the
/// WebKit path. It owns the browser in the shared helper (`ChromiumBrowserHost`), serves its
/// `owe-wallpaper` requests from the wallpaper folder, relays the bridge's messages and hands
/// frames to its view. The browser is created once the view has a size, and created again if
/// the page or the helper goes away.
final class ChromiumBrowserPage: NSObject, WebWallpaperPage, ChromiumBrowserClient, @unchecked Sendable {
    /// What the page is: the URL to open and the folder its `owe-wallpaper` requests come from.
    struct Content: Equatable {
        var url: URL
        var directory: URL?
        var patches: WebCompatPatches = WebCompatPatches(actions: [])
        /// A remote embed page, served at `ChromiumResourceServing.embedPageURL`.
        var embedHTML: String?
    }

    private let host: ChromiumBrowserHost
    private let startScript: String

    /// The page's messages, decoded from JSON (main thread).
    var onMessage: ((String, Any) -> Void)?
    /// The main frame finished loading (main thread); the status is HTTP's or a CEF error.
    var onLoad: ((Int) -> Void)?
    /// Each frame (XPC's queue).
    var onFrame: ((ChromiumFrame) -> Void)?
    weak var view: NSView?

    // Main thread only.
    private(set) var browserId: Int?
    private var content: Content?
    private var size: (width: Int, height: Int, scale: Double)?
    private var hidden = false
    private var muted = false
    private var frameRate: Int
    private var evaluations: [Int: (Any?) -> Void] = [:]
    private var nextEvaluation = 1
    private var closed = false
    /// Recreations after a crash in a row; a page that keeps crashing stops being retried.
    private var crashes = 0
    static let maxCrashes = 3

    // `lock` guards what the XPC queue reads.
    private let lock = NSLock()
    private var servedContent: Content?
    private var lastFrame: ChromiumFrame?

    init(host: ChromiumBrowserHost = .shared, startScripts: [String], frameRate: Int) {
        self.host = host
        self.startScript = ChromiumPageScripts.startScript(startScripts)
        self.frameRate = frameRate
    }

    deinit {
        if let browserId { host.closeBrowser(browserId) }
    }

    /// Opens `content` (closing the page shown before).
    func load(_ content: Content) {
        self.content = content
        lock.withLock { servedContent = content }
        crashes = 0
        recreate()
    }

    /// The view's size in points and its pixels per point.
    func resize(width: Int, height: Int, scale: Double) {
        guard width > 0, height > 0, scale > 0 else { return }
        if let size, size.width == width, size.height == height, size.scale == scale { return }
        let hadSize = size != nil
        size = (width, height, scale)
        if let browserId {
            host.resize(browserId, width: width, height: height, scale: scale)
        } else if !hadSize {
            recreate()
        }
    }

    func setFrameRate(_ frameRate: Int) {
        guard frameRate != self.frameRate else { return }
        self.frameRate = frameRate
        if let browserId { host.setFrameRate(browserId, frameRate: frameRate) }
    }

    /// Closes the browser for good.
    func close() {
        closed = true
        if let browserId { host.closeBrowser(browserId) }
        browserId = nil
        evaluations.values.forEach { $0(nil) }
        evaluations.removeAll()
    }

    private func recreate() {
        if let browserId { host.closeBrowser(browserId) }
        browserId = nil
        guard !closed, let content, let size else { return }
        let url = content.embedHTML != nil ? URL(string: ChromiumResourceServing.embedPageURL)! : content.url
        var opened: Int?
        let id = host.openBrowser(for: self, url: url, width: size.width, height: size.height, scale: size.scale,
                                  frameRate: frameRate, startScript: startScript) { [weak self] error in
            guard let error else { return }
            OWELog.error(.web, "Can't open \(url.lastPathComponent) in Chromium: \(error)")
            if let self, self.browserId == opened { self.browserId = nil }
        }
        opened = id
        browserId = id
        // A new browser starts shown and audible.
        if hidden { host.setHidden(id, hidden: true) }
        if muted { host.setAudioMuted(id, muted: true) }
    }

    // MARK: WebWallpaperPage

    func evaluate(_ script: String) {
        guard let browserId else { return }
        host.execute(browserId, script: script)
    }

    func evaluate(_ script: String, completion: @escaping (Any?) -> Void) {
        guard let browserId else {
            completion(nil)
            return
        }
        let id = nextEvaluation
        nextEvaluation += 1
        evaluations[id] = completion
        host.execute(browserId, script: ChromiumPageScripts.evaluation(script, id: id))
    }

    func setPageMuted(_ muted: Bool) {
        self.muted = muted
        if let browserId { host.setAudioMuted(browserId, muted: muted) }
    }

    /// Pausing is the bridge's scripts plus hiding the page (`applySchedulingPolicy`), which stops
    /// Chromium drawing it: unlike WebKit, a page that ignores `setPaused` stops too.
    func setPagePaused(_ paused: Bool) {}

    /// A page nobody can see is hidden: Chromium stops its layout, painting and animation frames
    /// and throttles its timers, while its sound plays on (an audible covered wallpaper keeps its
    /// sound, as in WebKit).
    func applySchedulingPolicy(muted: Bool, visible: Bool) {
        guard hidden == visible else { return }
        hidden = !visible
        if let browserId { host.setHidden(browserId, hidden: hidden) }
    }

    var hostWindow: NSWindow? { view?.window }

    func snapshot(completion: @escaping (CGImage?) -> Void) {
        guard let frame = lock.withLock({ lastFrame }),
              let image = CIImage(mtlTexture: frame.texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        else {
            completion(nil)
            return
        }
        // Metal's origin is top-left, Core Image's bottom-left.
        let upright = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))
        completion(CIContext().createCGImage(upright, from: upright.extent))
    }

    func sendMouse(_ event: ChromiumMouseEvent) {
        guard let browserId, !hidden else { return }
        host.send(browserId, mouse: event)
    }

    // MARK: ChromiumBrowserClient

    func chromiumFrame(_ frame: ChromiumFrame) {
        lock.withLock { lastFrame = frame }
        onFrame?(frame)
    }

    func chromiumMessage(name: String, body: String) {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed])
        } catch {
            OWELog.debug(.web, "Ignoring a malformed \(name) message from a Chromium page")
            return
        }
        if name == ChromiumPageScripts.evaluationResultMessage {
            guard let object = value as? [String: Any], let id = (object["id"] as? NSNumber)?.intValue,
                  let completion = evaluations.removeValue(forKey: id) else { return }
            completion(object["value"] is NSNull ? nil : object["value"])
            return
        }
        onMessage?(name, value)
    }

    func chromiumDidFinishLoading(status: Int) {
        if status > 0 { crashes = 0 }
        onLoad?(status)
    }

    func chromiumTerminated(reason: String) {
        browserId = nil
        evaluations.values.forEach { $0(nil) }
        evaluations.removeAll()
        guard !closed else { return }
        crashes += 1
        guard crashes <= Self.maxCrashes else {
            OWELog.error(.web, "A Chromium web wallpaper page ended \(crashes) times in a row; not reopening it")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.browserId == nil else { return }
            self.recreate()
        }
    }

    func chromiumResource(url: String, range: String?) -> ChromiumResourceResponse {
        guard let content = lock.withLock({ servedContent }) else { return .notFound() }
        return ChromiumResourceServing.response(for: url, range: range, directory: content.directory,
                                                patches: content.patches, embedHTML: content.embedHTML)
    }
}
