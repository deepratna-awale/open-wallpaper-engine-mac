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
    /// The last states handed to `apply`.
    private(set) var states: [String: DisplayPlayback]?
    private var evaluationPending = false
    private var pollTimer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var settingsCancellable: AnyCancellable?
    private var powerSource: CFRunLoopSource?

    init(sources: DisplayPlaybackSources, apply: @escaping ([String: DisplayPlayback]) -> Void) {
        self.sources = sources
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
        pollTimer?.invalidate()
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

    /// Evaluates the rules now; hands the states on when they changed.
    func evaluate() {
        let displays = sources.displays()
        let conditions = rules.watchesWindows
            ? DesktopWindowLayout.conditions(windows: sources.windows(), displays: displays,
                                             frontmostPID: sources.frontmostPID(), ignoredPIDs: [sources.ownPID])
            : [:]
        let system = SystemPlaybackConditions(
            otherApplicationPlayingAudio: rules.watchesAudio && sources.otherApplicationPlayingAudio(),
            displaysAsleep: displaysAsleep,
            onBattery: rules.watchesPower && sources.onBattery())
        let next = rules.playback(displays: displays.map(\.id), conditions: conditions, system: system)
        guard next != states else { return }
        states = next
        let summary: [String] = next.keys.sorted().map { (screen: String) -> String in "\(screen)=\(next[screen] ?? .run)" }
        OWELog.debug(.app, "Playback per display: \(summary.joined(separator: ", "))")
        apply(next)
    }

    // MARK: - Events

    private func updatePolling() {
        let needed = (rules.watchesWindows || rules.watchesAudio) && !displaysAsleep
        guard needed != isPolling else { return }
        if needed {
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            timer.tolerance = Self.pollInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else {
            pollTimer?.invalidate()
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
