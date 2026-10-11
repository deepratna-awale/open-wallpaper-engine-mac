import AppKit
import Combine
import Metal
import notify

/// The live screen saver, the app's side: while the screen saver runs and an Open Wallpaper Engine
/// saver shows (`ScreenSaverLiveState`), the loops of the screen saver's layout
/// (`ScreenSaverPlugin.liveLoops`) are drawn live (scenes by `ScreenSaverLiveScene`, web pages and
/// WebM videos through Chromium by `ScreenSaverLiveWeb`) into rings of surfaces
/// published for the `.saver` (`live.json`, Darwin notifications) and the extension (XPC,
/// `ScreenSaverFrameService`) by `ScreenSaverFramePublisher`. Nothing is drawn at any other time:
/// drawing stops on `willstop`/`didstop`, an unlock, or when no saver has said it is there for
/// `ScreenSaverLiveState.saverTimeout`. The savers play their videos whenever frames stop.
///
/// Only the user's own copy draws (an isolated copy, like the tests, never installs the saver
/// and never publishes), and only while the Screen Saver plugin follows the desktop. Until the
/// real screen saver hosts confirm it (the live screen saver's Phase 0), only development builds
/// draw (`isAvailable`); release builds keep the recorded loop.
@MainActor
final class ScreenSaverLiveController {
    /// What the drawing reads from the app.
    struct Environment {
        var settings: () -> GlobalSettings
        var placement: () -> WallpaperPlacement
        var scriptServices: () -> SceneScriptServices?
        /// The desktop's Chromium page on a display, while it shows the wallpaper.
        var pageSharing: (_ screenId: String, _ wallpaper: WEWallpaper) -> ScreenSaverPageSharing? = { _, _ in nil }
    }

    /// How often the frames each ring drew are logged while drawing.
    static let countsInterval: TimeInterval = 10

    private let plugin: ScreenSaverPlugin
    private let environment: Environment
    private let store: ScreenSaverVideoStore
    private let mayPublish: Bool
    private var state = ScreenSaverLiveState()
    private var enabledSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var aliveToken: Int32 = NOTIFY_TOKEN_INVALID
    private var timer: Timer?
    private var publisher: ScreenSaverFramePublisher?
    private var service: ScreenSaverFrameService?
    private var scenes: [ScreenSaverLiveScene] = []
    private var pages: [ScreenSaverLiveWeb] = []
    private var countsSince: TimeInterval = 0
    /// Launched for a saver (`launchedForScreenSaver`), heard once the plugin is observed.
    private var launchedForSaver = false
    /// The screen saver session this app was launched for ended.
    var onLaunchedSessionEnded: (() -> Void)?
    private var frameRate = 0

    init(plugin: ScreenSaverPlugin, environment: Environment, store: ScreenSaverVideoStore = .current,
         mayPublish: Bool = ScreenSaverInstaller.current.mayInstall) {
        self.plugin = plugin
        self.environment = environment
        self.store = store
        self.mayPublish = mayPublish
    }

    /// Development builds only, until Phase 0 confirms the hosts.
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Follows the Screen Saver plugin: observing the screen saver while it is on.
    func start() {
        guard Self.isAvailable, mayPublish, enabledSubscription == nil else { return }
        enabledSubscription = plugin.$isEnabled.removeDuplicates().sink { [weak self] enabled in
            MainActor.assumeIsolated { self?.setObserving(enabled) }
        }
    }

    /// The broker launched the app for a saver showing (`ScreenSaverLiveNames.launchArgument`):
    /// the screen saver runs, and its `didstart` came before the app.
    func launchedForScreenSaver() {
        launchedForSaver = true
        if !observers.isEmpty { handle(.launchedForScreenSaver) }
    }

    private func setObserving(_ observing: Bool) {
        if observing, observers.isEmpty {
            observeLifecycle()
            defer { if launchedForSaver { handle(.launchedForScreenSaver) } }
            if publisher == nil, let device = MTLCreateSystemDefaultDevice() {
                let publisher = ScreenSaverFramePublisher(
                    manifestURL: store.directory.appending(path: ScreenSaverLiveManifest.fileName, directoryHint: .notDirectory),
                    notifier: DarwinFrameNotifier(), device: device)
                let service = ScreenSaverFrameService()
                service.onAlive = { [weak self] in self?.handle(.saverAlive) }
                service.isDrawing = { [weak publisher] in publisher?.current.isLive ?? false }
                publisher.onRings = { [weak service] in service?.use($0) }
                publisher.onStamp = { [weak service] in service?.show(ring: $0, stamp: $1) }
                service.registerWithBroker()
                self.publisher = publisher
                self.service = service
                // Nothing is drawn yet: a manifest left by an earlier run lists nothing.
                publisher.clear()
            }
        } else if !observing, !observers.isEmpty {
            stopDrawing()
            let center = DistributedNotificationCenter.default()
            for observer in observers { center.removeObserver(observer) }
            observers.removeAll()
            if aliveToken != NOTIFY_TOKEN_INVALID { notify_cancel(aliveToken) }
            aliveToken = NOTIFY_TOKEN_INVALID
            timer?.invalidate()
            timer = nil
            service?.invalidate()
            service = nil
            publisher = nil
            state = ScreenSaverLiveState()
        }
    }

    private func observeLifecycle() {
        let center = DistributedNotificationCenter.default()
        let events: [(Notification.Name, ScreenSaverLiveState.Event)] = [
            (ScreenSaverLiveNames.didStart, .didStart), (ScreenSaverLiveNames.willStop, .willStop),
            (ScreenSaverLiveNames.didStop, .didStop), (ScreenSaverLiveNames.screenLocked, .screenLocked),
            (ScreenSaverLiveNames.screenUnlocked, .screenUnlocked),
        ]
        for (name, event) in events {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    OWELog.info(.app, "Live screen saver: \(name.rawValue)")
                    self?.handle(event)
                }
            })
        }
        let status = notify_register_dispatch(ScreenSaverLiveNames.saverAlive, &aliveToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.saverAlive) }
        }
        if status != UInt32(NOTIFY_STATUS_OK) {
            OWELog.error(.app, "Live screen saver: can't observe the savers (\(status))")
        }
    }

    private func handle(_ event: ScreenSaverLiveState.Event) {
        let now = ProcessInfo.processInfo.systemUptime
        if state.handle(event, at: now) {
            if state.isDrawing { startDrawing() } else { stopDrawing() }
        }
        if state.isDrawing, now - countsSince >= Self.countsInterval { logCounts(at: now) }
        // Timeouts need a clock only while the screen saver runs.
        if state.screenSaverRuns, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.tick) }
            }
            timer?.tolerance = 0.2
        } else if !state.screenSaverRuns {
            timer?.invalidate()
            timer = nil
            if launchedForSaver {
                launchedForSaver = false
                onLaunchedSessionEnded?()
            }
        }
    }

    private func startDrawing() {
        guard let publisher, scenes.isEmpty, pages.isEmpty else { return }
        let (loops, displays) = plugin.liveLoops()
        guard !loops.isEmpty else {
            OWELog.info(.app, "Live screen saver: nothing to draw live; the saver plays its videos")
            return
        }
        let settings = environment.settings()
        let limits = FramePacing.Limits(settings, power: PowerPolicyMonitor.shared.policy)
        let screens = Dictionary(NSScreen.screens.map { (WallpaperViewModel.screenId(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        // As the desktop paces scenes: the user's rate, capped by the power policy, rounded down to
        // a whole divisor of the display's refresh so every frame lasts as long (55 for 60 on a
        // 165 Hz display, `FramePacing.cadence`).
        func rate(for screen: NSScreen?) -> Int {
            let refresh = screen?.maximumFramesPerSecond ?? 60
            let target = max(1, min(limits.userLimit, limits.powerCap ?? .max))
            return FramePacing.cadence(target, refreshRate: refresh > 0 ? refresh : 60)
        }
        let frameRate = loops.map { rate(for: $0.screenId.flatMap { screens[$0] }) }.max() ?? 30
        // A page's ring is the page's own pixels (Web Standard Resolution and Texture Resolution
        // may draw it below the display's); a scene's the loop's.
        func pagePixelsPerPoint(_ loop: ScreenSaverPlugin.LiveLoop) -> CGFloat {
            ScreenSaverLiveWeb.pixelsPerPoint(settings, backingScale: CGFloat(loop.pixels.x) / CGFloat(max(loop.points.x, 1)))
        }
        let sizes = loops.map { loop in
            loop.kind == .scene ? loop.pixels
                : ScreenSaverLiveWeb.pixels(points: loop.points, pixelsPerPoint: pagePixelsPerPoint(loop))
        }
        do {
            try publisher.publish(sizes: sizes,
                                  displays: ScreenSaverPlugin.liveDisplayEntries(loops.map(\.loop), pixels: sizes,
                                                                                 displays: displays),
                                  frameRate: frameRate)
        } catch {
            OWELog.error(.app, "Live screen saver: can't allocate the frames: \(error)")
            return
        }
        self.frameRate = frameRate
        countsSince = ProcessInfo.processInfo.systemUptime
        _ = publisher.takeCounts()
        for (ring, loop) in loops.enumerated() {
            let screen = loop.screenId.flatMap { screens[$0] }
            if case .page(let kind) = loop.kind {
                let sharing = loop.screenId.flatMap { environment.pageSharing($0, loop.wallpaper) }
                if let page = ScreenSaverLiveWeb(kind: kind, wallpaper: loop.wallpaper, propertyScope: loop.propertyScope,
                                                 ring: ring, points: loop.points, pixelsPerPoint: pagePixelsPerPoint(loop),
                                                 frameRate: rate(for: screen), placement: environment.placement(),
                                                 sharing: sharing, publisher: publisher) {
                    pages.append(page)
                }
                continue
            }
            let target = ScreenSaverLiveScene.Target(ring: ring, pixels: loop.pixels, points: loop.points, frameRate: rate(for: screen))
            if let scene = ScreenSaverLiveScene(wallpaper: loop.wallpaper, propertyScope: loop.propertyScope, target: target,
                                                screen: screen, settings: settings, placement: environment.placement(),
                                                scriptServices: environment.scriptServices(), publisher: publisher) {
                scenes.append(scene)
            }
        }
    }

    private func stopDrawing() {
        let drew = !scenes.isEmpty || !pages.isEmpty
        scenes.forEach { $0.shutdown() }
        scenes.removeAll()
        pages.forEach { $0.shutdown() }
        pages.removeAll()
        if drew {
            publisher?.clear()
            OWELog.info(.app, "Live screen saver: stopped drawing")
        }
    }

    /// Where frames are lost: each ring's ticks (a scene's display link, a page's frames) and
    /// frames drawn, against the rate asked for.
    private func logCounts(at now: TimeInterval) {
        guard let publisher else { return }
        let seconds = now - countsSince
        countsSince = now
        for (ring, counts) in publisher.takeCounts().sorted(by: { $0.key < $1.key }) {
            OWELog.info(.app, String(format: "Live screen saver: ring %d ticks %.1f/s drawn %.1f/s (asked %d) over %.0f s",
                                     ring, Double(counts.ticks) / seconds, Double(counts.drawn) / seconds, frameRate, seconds))
        }
    }
}
