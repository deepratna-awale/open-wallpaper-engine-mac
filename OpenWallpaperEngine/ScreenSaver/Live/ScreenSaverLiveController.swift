import AppKit
import Combine
import Metal
import notify

/// The live screen saver, the app's side: while the screen saver runs and an Open Wallpaper Engine
/// saver shows (`ScreenSaverLiveState`), the scene loops of the screen saver's layout
/// (`ScreenSaverPlugin.liveLoops`) are drawn live (`ScreenSaverLiveScene`) into rings of surfaces
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
    }

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

    private func setObserving(_ observing: Bool) {
        if observing, observers.isEmpty {
            observeLifecycle()
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
        // Timeouts need a clock only while the screen saver runs.
        if state.screenSaverRuns, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.tick) }
            }
            timer?.tolerance = 0.2
        } else if !state.screenSaverRuns {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startDrawing() {
        guard let publisher, scenes.isEmpty else { return }
        let (loops, displays) = plugin.liveLoops()
        guard !loops.isEmpty else {
            OWELog.info(.app, "Live screen saver: no scene to draw live; the saver plays its videos")
            return
        }
        let settings = environment.settings()
        let limits = FramePacing.Limits(settings, power: PowerPolicyMonitor.shared.policy)
        let screens = Dictionary(NSScreen.screens.map { (WallpaperViewModel.screenId(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        func rate(for screen: NSScreen?) -> Int {
            let refresh = screen?.maximumFramesPerSecond ?? 60
            return max(1, min(limits.userLimit, limits.powerCap ?? .max, refresh > 0 ? refresh : 60))
        }
        let frameRate = loops.map { rate(for: $0.screenId.flatMap { screens[$0] }) }.max() ?? 30
        do {
            try publisher.publish(sizes: loops.map(\.pixels),
                                  displays: ScreenSaverPlugin.liveDisplayEntries(loops.map(\.loop), pixels: loops.map(\.pixels),
                                                                                 displays: displays),
                                  frameRate: frameRate)
        } catch {
            OWELog.error(.app, "Live screen saver: can't allocate the frames: \(error)")
            return
        }
        for (ring, loop) in loops.enumerated() {
            let screen = loop.screenId.flatMap { screens[$0] }
            let target = ScreenSaverLiveScene.Target(ring: ring, pixels: loop.pixels, points: loop.points, frameRate: rate(for: screen))
            if let scene = ScreenSaverLiveScene(wallpaper: loop.wallpaper, propertyScope: loop.propertyScope, target: target,
                                                screen: screen, settings: settings, placement: environment.placement(),
                                                scriptServices: environment.scriptServices(), publisher: publisher) {
                scenes.append(scene)
            }
        }
    }

    private func stopDrawing() {
        let drew = !scenes.isEmpty
        scenes.forEach { $0.shutdown() }
        scenes.removeAll()
        if drew {
            publisher?.clear()
            OWELog.info(.app, "Live screen saver: stopped drawing")
        }
    }
}
