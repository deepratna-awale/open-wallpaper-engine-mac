import AppKit
import Combine
import IOKit.ps

/// Evaluates Settings › Performance › Playback for each display (`PlaybackRules`) and hands the
/// result to the app (`WallpaperViewModel.displayPlayback`, the wallpaper windows).
///
/// Cheap by construction: it re-evaluates on the events that change the answer (an application
/// activated, hidden, launched or quit, a Space or the screens changed, the displays slept or
/// woke, the power source changed), at most ten times a second. Windows moved or zoomed within an
/// application post no event, so while a rule about windows or other applications' audio is on
/// it also looks twice a second; with those rules off, or the displays asleep, it doesn't poll.
///
/// The main thread only gathers what AppKit owns (the displays, the active application) and
/// applies a changed answer. Reading the window list, Core Audio and the power source, and
/// evaluating the rules, happen on `scanQueue`; the poll timer runs there too, so an unchanged
/// desktop never wakes the main thread.
@MainActor
final class DisplayPlaybackMonitor {
    /// Events closer together than this are evaluated once.
    static let throttle: TimeInterval = 0.1
    /// How often windows and audio are looked at while a rule needs them.
    static let pollInterval: TimeInterval = 0.5

    private let sources: DisplayPlaybackSources
    private let apply: ([String: DisplayPlayback]) -> Void
    private(set) var rules = PlaybackRules()
    private(set) var displaysAsleep = false
    /// Video memory ran out (`VideoMemoryWatch`, only while its setting is on).
    private(set) var videoMemoryExhausted = false
    /// The last states handed to `apply`.
    private(set) var states: [String: DisplayPlayback]?
    private var evaluationPending = false
    private var pollTimer: DispatchSourceTimer?
    /// Where the expensive reads run; nil reads everything on the calling thread (tests).
    private let scanQueue: DispatchQueue?
    /// What the scan needs from the main thread, and the last answer, shared with `scanQueue`.
    private let shared = Shared()
    /// Answers from scans started before the latest are dropped.
    private var generation: UInt64 = 0
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var settingsCancellable: AnyCancellable?
    private var powerSource: CFRunLoopSource?

    init(sources: DisplayPlaybackSources,
         scanQueue: DispatchQueue? = DispatchQueue(label: "OpenWallpaperEngine.DisplayPlaybackMonitor", qos: .utility),
         apply: @escaping ([String: DisplayPlayback]) -> Void) {
        self.sources = sources
        self.scanQueue = scanQueue
        self.apply = apply
    }

    /// Whether it looks at the desktop on a timer.
    var isPolling: Bool { pollTimer != nil }

    /// Starts following `settings` and the system's events, and evaluates once.
    func start<Settings: Publisher>(settings: Settings) where Settings.Output == GlobalSettings, Settings.Failure == Never {
        observeWorkspace()
        observePowerSource()
        settingsCancellable = settings
            .map { PlaybackRules($0) }
            .removeDuplicates()
            .sink { [weak self] rules in MainActor.assumeIsolated { self?.setRules(rules) } }
        evaluate()
    }

    func stop() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        settingsCancellable = nil
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    func setRules(_ rules: PlaybackRules) {
        self.rules = rules
        updatePolling()
        evaluate()
    }

    func setDisplaysAsleep(_ asleep: Bool) {
        displaysAsleep = asleep
        updatePolling()
        evaluate()
    }

    func setVideoMemoryExhausted(_ exhausted: Bool) {
        guard exhausted != videoMemoryExhausted else { return }
        videoMemoryExhausted = exhausted
        evaluate()
    }

    /// Evaluates soon, once for a burst of events.
    func setNeedsEvaluation() {
        guard !evaluationPending else { return }
        evaluationPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.throttle) { [weak self] in
            MainActor.assumeIsolated {
                self?.evaluationPending = false
                self?.evaluate()
            }
        }
    }

    /// Evaluates the rules now (with a scan queue, the answer comes back on the main thread
    /// shortly); hands the states on when they changed.
    func evaluate() {
        let inputs = Inputs(rules: rules, displays: sources.displays(), frontmostPID: sources.frontmostPID(),
                            ignoresWebKitAudio: rules.watchesAudio && sources.showsWebWallpaper(),
                            displaysAsleep: displaysAsleep, videoMemoryExhausted: videoMemoryExhausted)
        shared.set(inputs: inputs)
        generation &+= 1
        let generation = generation
        guard let scanQueue, inputs.needsScan else {
            finish(Self.playback(inputs, sources: sources), generation: generation)
            return
        }
        let sources = sources
        scanQueue.async { [weak self] in
            let next = Self.playback(inputs, sources: sources)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(next, generation: generation) }
            }
        }
    }

    private func finish(_ next: [String: DisplayPlayback], generation: UInt64) {
        guard generation == self.generation, next != states else { return }
        states = next
        shared.set(states: next)
        let summary: [String] = next.keys.sorted().map { (screen: String) -> String in "\(screen)=\(next[screen] ?? .run)" }
        OWELog.debug(.app, "Playback per display: \(summary.joined(separator: ", "))")
        apply(next)
    }

    /// The rules' answer for `inputs`, reading the windows, audio and power as they need.
    /// Runs on the scan queue.
    nonisolated private static func playback(_ inputs: Inputs, sources: DisplayPlaybackSources) -> [String: DisplayPlayback] {
        let rules = inputs.rules
        let conditions = rules.watchesWindows
            ? DesktopWindowLayout.conditions(windows: sources.windows(), displays: inputs.displays,
                                             frontmostPID: inputs.frontmostPID, ignoredPIDs: [sources.ownPID])
            : [:]
        let system = SystemPlaybackConditions(
            otherApplicationPlayingAudio: rules.watchesAudio && sources.otherApplicationPlayingAudio(inputs.ignoresWebKitAudio),
            displaysAsleep: inputs.displaysAsleep,
            onBattery: rules.watchesPower && sources.onBattery(),
            videoMemoryExhausted: inputs.videoMemoryExhausted)
        return rules.playback(displays: inputs.displays.map(\.id), conditions: conditions, system: system)
    }

    /// One poll on the scan queue: hops to the main thread only when the answer changed.
    nonisolated private static func poll(_ shared: Shared, sources: DisplayPlaybackSources,
                                         monitor: DisplayPlaybackMonitor?) {
        guard let inputs = shared.inputs else { return }
        let next = playback(inputs, sources: sources)
        guard next != shared.states else { return }
        DispatchQueue.main.async { [weak monitor] in
            // The main thread may have moved on (new rules, displays); evaluate afresh.
            MainActor.assumeIsolated { monitor?.evaluate() }
        }
    }

    /// What an evaluation reads on the main thread.
    struct Inputs {
        var rules: PlaybackRules
        var displays: [DesktopDisplay]
        var frontmostPID: pid_t?
        var ignoresWebKitAudio: Bool
        var displaysAsleep: Bool
        var videoMemoryExhausted = false

        /// Whether the answer needs a read that is too slow for the main thread.
        var needsScan: Bool { rules.watchesWindows || rules.watchesAudio || rules.watchesPower }
    }

    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var _inputs: Inputs?
        private var _states: [String: DisplayPlayback]?
        var inputs: Inputs? { lock.lock(); defer { lock.unlock() }; return _inputs }
        var states: [String: DisplayPlayback]? { lock.lock(); defer { lock.unlock() }; return _states }
        func set(inputs: Inputs) { lock.lock(); _inputs = inputs; lock.unlock() }
        func set(states: [String: DisplayPlayback]) { lock.lock(); _states = states; lock.unlock() }
    }

    // MARK: - Events

    private func updatePolling() {
        let needed = (rules.watchesWindows || rules.watchesAudio) && !displaysAsleep
        guard needed != isPolling else { return }
        if needed {
            let queue = scanQueue ?? DispatchQueue.main
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let interval = DispatchTimeInterval.milliseconds(Int(Self.pollInterval * 1000))
            timer.schedule(deadline: .now() + interval, repeating: interval,
                           leeway: .milliseconds(Int(Self.pollInterval * 500)))
            let shared = shared
            let sources = sources
            timer.setEventHandler { [weak self] in Self.poll(shared, sources: sources, monitor: self) }
            timer.resume()
            pollTimer = timer
        } else {
            pollTimer?.cancel()
            pollTimer = nil
        }
    }

    private func observeWorkspace() {
        let workspace = NSWorkspace.shared.notificationCenter
        let changes: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in changes {
            observe(workspace, name) { $0.setNeedsEvaluation() }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.setDisplaysAsleep(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.setDisplaysAsleep(false) }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.setNeedsEvaluation() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (DisplayPlaybackMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    /// The battery rule follows the power source; IOKit calls back on the main run loop.
    private func observePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Optional: nil only without IOKit's power-source service (then the rule sees mains power).
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<DisplayPlaybackMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.setNeedsEvaluation() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }
}
