//
//  WebWallpaperViewModel.swift
//  Open Wallpaper Engine
//
//  Created by Toby on 2023/8/28.
//

import WebKit
import SwiftUI
import Combine

class WebWallpaperViewModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var currentWallpaper: WEWallpaper
    
    var fileUrl: URL {
        currentWallpaper.wallpaperDirectory.appending(path: currentWallpaper.project.file)
    }
    
    var readAccessURL: URL {
        currentWallpaper.wallpaperDirectory
    }
    
    weak var webView: WKWebView?
    /// Serves the wallpaper's folder, with WE's patches (`assets/zcompat/web`) applied.
    let schemeHandler = WebWallpaperSchemeHandler()

    /// WE's compatibility patches for the current wallpaper, if it has any.
    var compatPatches: WebCompatPatches? {
        WebCompatPatches(workshopId: Self.compatWorkshopId(of: currentWallpaper),
                         assetsDirectory: WallpaperEngineAssets.directory)
    }

    /// The Workshop id that picks a wallpaper's zcompat entry: the numeric name Steam gives the
    /// item's folder. project.json's `workshopid` is the author's own text, so it doesn't choose.
    static func compatWorkshopId(of wallpaper: WEWallpaper) -> String? {
        let folder = wallpaper.wallpaperDirectory.standardizedFileURL.lastPathComponent
        return !folder.isEmpty && folder.allSatisfy({ $0.isASCII && $0.isNumber }) ? folder : nil
    }
    /// Receives the page's frame intervals and heartbeats (a page that stops beating is hung).
    weak var renderWatchdog: RenderWatchdog?
    private var heartbeatGate = WebHeartbeatGate()
    /// Whether the current page has beaten yet: one that never runs the bridge (a load error
    /// page) is not judged.
    private var pageHasBeaten = false
    private var visibilityObservers: [NSObjectProtocol] = []
    private var audioTimer: Timer?
    /// The page's own smoothing of the captured spectrum, stepped by `audioTimer`, so the page
    /// hears audio whether or not a scene is running next to it.
    private var audioClock: AudioSpectrumClock?
    private var propertyObserver: NSObjectProtocol?
    /// Resends WE's general properties when the user's FPS changes.
    private var fpsObserver: AnyCancellable?

    /// Whose user properties the page gets: its display's, or the shared ones while synced.
    let propertyScope: WallpaperPropertyScope

    /// The now-playing session the page's media listeners hear (`WebWallpaperMediaBridge`).
    private let media: MediaSessionSource?
    private var mediaSubscription: Int?
    /// The media state the current page has been sent; nil until its first delivery.
    private var mediaSent: MediaSessionState?
    /// Which page a delivery is for; a new page (`pageWillLoad`) invalidates older deliveries.
    private var mediaPage = 0

    init(wallpaper: WEWallpaper, propertyScope: WallpaperPropertyScope = .shared, media: MediaSessionSource? = nil) {
        self.currentWallpaper = wallpaper
        self.propertyScope = propertyScope
        self.media = media
        super.init()
        propertyObserver = NotificationCenter.default.addObserver(
            forName: .wallpaperUserPropertyChanged, object: nil, queue: .main
        ) { [weak self] notification in
            self?.propertyChanged(notification)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWillSleep(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        observeVisibility()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let propertyObserver { NotificationCenter.default.removeObserver(propertyObserver) }
        for observer in visibilityObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        audioTimer?.invalidate()
        if let mediaSubscription { media?.unsubscribe(mediaSubscription) }
        renderWatchdog?.endHeartbeat(from: ObjectIdentifier(self))
    }

    // MARK: Heartbeat

    /// Tracks what makes WebKit stop the page's timers: an occluded window and sleeping displays
    /// (system sleep also sleeps the displays).
    private func observeVisibility() {
        let workspace = NSWorkspace.shared.notificationCenter
        let displays: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true),
            (NSWorkspace.willSleepNotification, false), (NSWorkspace.didWakeNotification, true),
            (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true),
        ]
        for (name, awake) in displays {
            visibilityObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.heartbeatGate.displaysAwake = awake
                self?.reportHeartbeatGate()
            })
        }
        visibilityObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow, window === self.webView?.window else { return }
            self.heartbeatGate.windowVisible = window.occlusionState.contains(.visible)
            self.reportHeartbeatGate()
        })
    }

    /// A new page is loading; it is judged from its first heartbeat on.
    func pageWillLoad() {
        stopMedia()
        pageHasBeaten = false
        renderWatchdog?.recordHeartbeat(from: ObjectIdentifier(self), expectingMore: false)
    }

    /// Restarts the heartbeat clock when the gate opens and stops it when it closes.
    private func reportHeartbeatGate() {
        updateAudioTimer()
        guard pageHasBeaten else { return }
        renderWatchdog?.recordHeartbeat(from: ObjectIdentifier(self), expectingMore: heartbeatGate.expectsHeartbeats)
    }

    fileprivate func heartbeatReceived(_ heartbeat: WebWallpaperPropertyBridge.Heartbeat) {
        heartbeat.intervals.forEach { renderWatchdog?.recordFrame(duration: $0) }
        heartbeatGate.pageVisible = heartbeat.visible
        pageHasBeaten = true
        reportHeartbeatGate()
    }

    // MARK: Wallpaper Engine web API

    func installBridge(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: WebWallpaperPropertyBridge.pauseScript,
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: WebWallpaperPropertyBridge.bootstrapScript,
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakScriptMessageHandler(self), name: WebWallpaperPropertyBridge.audioMessageName)
        controller.add(WeakScriptMessageHandler(self), name: WebWallpaperPropertyBridge.frameMessageName)
        controller.addUserScript(WKUserScript(source: WebWallpaperMediaBridge.bootstrapScript,
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakScriptMessageHandler(self), name: WebWallpaperMediaBridge.messageName)
    }

    // MARK: Media integration

    /// The page registered a media listener: the first one subscribes it to the session.
    fileprivate func mediaListenerRegistered() {
        guard mediaSubscription == nil, let media else { return }
        let page = mediaPage
        mediaSubscription = media.subscribe { [weak self] state in
            DispatchQueue.main.async { self?.mediaChanged(state, page: page) }
        }
    }

    /// Sends the page what changed: everything that isn't empty the first time, as WE does for a
    /// newly registered page, then each change.
    private func mediaChanged(_ state: MediaSessionState, page: Int) {
        guard page == mediaPage, let webView else { return }
        let changes = mediaSent.map { state.changes(since: $0) } ?? state.initialChanges
        mediaSent = state
        for change in changes {
            if let script = WebWallpaperMediaBridge.deliveryScript(change) {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        }
    }

    private func stopMedia() {
        if let mediaSubscription { media?.unsubscribe(mediaSubscription) }
        mediaSubscription = nil
        mediaSent = nil
        mediaPage += 1
    }

    private var declaredProperties: [String: WebWallpaperPropertyBridge.Property] {
        WebWallpaperPropertyBridge.declaredProperties(wallpaperDirectory: currentWallpaper.wallpaperDirectory)
    }

    /// Sends every declared property, as WE does once the page has loaded; the bootstrap holds
    /// them for a listener the page assigns later.
    private func applyAllProperties(to webView: WKWebView) {
        let properties = declaredProperties
        let stored = WallpaperSettingsIdentity.resolve(currentWallpaper)
            .userSetValues(scope: propertyScope)
        let values = WebWallpaperPropertyBridge.currentValues(properties: properties, stored: stored)
        if let script = WebWallpaperPropertyBridge.applyUserPropertiesScript(
            WebWallpaperPropertyBridge.payload(properties: properties, values: values), full: true) {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        let settings = AppDelegate.shared.globalSettingsViewModel
        webView.evaluateJavaScript(WebWallpaperPropertyBridge.applyGeneralPropertiesScript(fps: Int(settings.settings.fps)),
                                   completionHandler: nil)
        if fpsObserver == nil {
            fpsObserver = settings.$settings.map { Int($0.fps) }.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] fps in
                    self?.webView?.evaluateJavaScript(WebWallpaperPropertyBridge.applyGeneralPropertiesScript(fps: fps),
                                                      completionHandler: nil)
                }
        }
    }

    private func propertyChanged(_ notification: Notification) {
        guard let path = notification.object as? String, path == currentWallpaper.wallpaperDirectory.path,
              // An edit of another display's properties doesn't reach this page.
              (notification.userInfo?["stores"] as? [String])?
                .contains(propertyScope.runtimeKey(directory: currentWallpaper.wallpaperDirectory)) ?? true,
              let key = notification.userInfo?["key"] as? String,
              let value = notification.userInfo?["value"] as? String,
              let webView else { return }
        let payload = WebWallpaperPropertyBridge.payload(properties: declaredProperties, values: [key: value])
        if let script = WebWallpaperPropertyBridge.applyUserPropertiesScript(payload) {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    fileprivate func audioListenerRegistered() {
        audioRegistered = true
        updateAudioTimer()
    }

    /// Whether the page registered an audio listener; the timer runs only while it can be seen.
    private var audioRegistered = false
    /// Keeps system audio capture on while the audio delivery runs.
    private var audioCaptureLease: AudioCaptureLease?

    /// Runs the 30 Hz delivery only while the page is registered, playing and visible: a paused,
    /// covered or sleeping page would drop the values, so the timer and its IPC stop too.
    private func updateAudioTimer() {
        guard audioRegistered, heartbeatGate.expectsHeartbeats else {
            audioTimer?.invalidate()
            audioTimer = nil
            audioCaptureLease = nil
            return
        }
        guard audioTimer == nil else { return }
        audioCaptureLease = WallpaperServices.shared.acquireAudioCapture()
        let clock = audioClock ?? WallpaperServices.shared.makeAudioSpectrumClock(publishes: false)
        audioClock = clock
        // WE delivers 64 left and 64 right values to web listeners 30 times a second.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused, let webView = self.webView else { return }
            let snapshot = clock.advanceFrame()
            let samples = WebWallpaperPropertyBridge.audioArray(left: snapshot.left64, right: snapshot.right64)
            webView.evaluateJavaScript(WebWallpaperPropertyBridge.audioDeliveryScript(samples), completionHandler: nil)
        }
        RunLoop.main.add(timer, forMode: .common)
        audioTimer = timer
    }

    /// Whether this display's page is silent: it isn't on the wallpaper's audible display, audio
    /// output is off, or the volume is 0 (`WallpaperAudioRouting`).
    private(set) var isMuted = false

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        if let webView { WebPageAudio.setMuted(muted, on: webView) }
        applySchedulingPolicy()
    }

    /// What WebKit does with the page while its window is covered: a muted page is suspended (no
    /// JS, timers or frames), an audible one only throttled, because a suspended page falls silent
    /// and Wallpaper Engine keeps a covered wallpaper's sound. The heartbeat gate and the audio
    /// timer already expect nothing from a covered window (`WebHeartbeatGate.windowVisible`).
    func applySchedulingPolicy() {
        webView?.configuration.preferences.inactiveSchedulingPolicy = isMuted ? .suspend : .throttle
    }

    /// Whether the playback rules pause this display's page: its media is suspended and the page
    /// hears WE's `setPaused(true)`. WebKit has no public way to stop a page's animation frames,
    /// so a page that ignores `setPaused` keeps drawing.
    private(set) var isPaused = false

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        heartbeatGate.playing = !paused
        reportHeartbeatGate()
        if let webView { applyPaused(to: webView) }
    }

    private func applyPaused(to webView: WKWebView) {
        webView.setAllMediaPlaybackSuspended(isPaused, completionHandler: nil)
        // WE's order: the page hears setPaused, then its callbacks and media are held.
        webView.evaluateJavaScript(WebWallpaperPropertyBridge.setPausedScript(isPaused) +
                                   WebWallpaperPropertyBridge.wpxPauseScript(isPaused), completionHandler: nil)
    }

    func stopAudio() {
        audioRegistered = false
        audioTimer?.invalidate()
        audioTimer = nil
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow navigation to external URLs (e.g. YouTube embeds from URL-based web wallpapers)
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let javascriptStyle = "var css = '*{-webkit-touch-callout:none;-webkit-user-select:none}'; var head = document.head || document.getElementsByTagName('head')[0]; var style = document.createElement('style'); style.type = 'text/css'; style.appendChild(document.createTextNode(css)); head.appendChild(style);"
        webView.evaluateJavaScript(javascriptStyle, completionHandler: nil)
        applyAllProperties(to: webView)
        // A new page starts unmuted by script, and playing.
        if isMuted { WebPageAudio.setMuted(true, on: webView) }
        if isPaused { applyPaused(to: webView) }
        
        if AppDelegate.shared.globalSettingsViewModel.settings.adjustMenuBarTint {
            // The display this page shows on gets its snapshot (small, under a stable name).
            webView.takeSnapshot(with: nil) { [weak webView] nsImage, error in
                guard let image = nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    if let error { OWELog.error(.web, "Menu bar tint snapshot failed: \(error)") }
                    return
                }
                guard let screen = webView?.window?.screen ?? NSScreen.main else { return }
                DesktopSnapshotCache.setDesktopPicture(image, for: [screen])
            }
        }
    }
    
    @objc func systemWillSleep(_ notification: Notification) {
        // Handle going to sleep
        OWELog.info(.web, "System is going to sleep")
        // Update your SwiftUI state here if needed
    }
        
    @objc func systemDidWake(_ notification: Notification) {
        // Handle waking up
        OWELog.info(.web, "System woke up from sleep")
        // Update your SwiftUI state here if needed
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var owner: WebWallpaperViewModel?

    init(_ owner: WebWallpaperViewModel) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case WebWallpaperPropertyBridge.audioMessageName:
            owner?.audioListenerRegistered()
        case WebWallpaperMediaBridge.messageName:
            owner?.mediaListenerRegistered()
        case WebWallpaperPropertyBridge.frameMessageName:
            guard let heartbeat = WebWallpaperPropertyBridge.heartbeat(from: message.body) else {
                OWELog.debug(.web, "Ignoring a malformed heartbeat message")
                return
            }
            owner?.heartbeatReceived(heartbeat)
        default:
            break
        }
    }
}
