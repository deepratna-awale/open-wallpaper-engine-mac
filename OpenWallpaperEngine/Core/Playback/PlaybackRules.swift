import Foundation

/// The conditions that hold for every display at once.
struct SystemPlaybackConditions: Equatable {
    /// Another application plays sound ("Other application playing audio").
    var otherApplicationPlayingAudio = false
    /// The displays sleep ("Display asleep"); macOS sleeps them together.
    var displaysAsleep = false
    /// The Mac runs on its battery ("Laptop on battery").
    var onBattery = false
    /// Video memory ran out with "Pause when VRAM is exhausted" on (`VideoMemoryWatch`).
    var videoMemoryExhausted = false
}

/// Settings › Performance › Playback, evaluated for each display, as WE does with several
/// monitors: the rules about other applications' windows (focused, maximized, fullscreen) act on
/// the display the window is on, and the others on every display.
///
/// WE's actions (`ui/dist/scripts/scripts.js`, the settings controller's `k(multimonitor, …)`):
/// on a multi-monitor system the window rules offer "Pause per monitor" (the stored value `pause`)
/// and "Pause all" (`pauseall`); with one monitor only "Pause". So `pause` pauses the display
/// whose window triggered it, and `pauseAll` pauses every display. "Stop" acts on the display too.
/// When several rules apply, the most restrictive action wins.
struct PlaybackRules: Equatable {
    var focused: GSPlayback
    var maximized: GSPlayback
    var fullscreen: GSPlayback
    var playingAudio: GSPlayback
    var displayAsleep: GSPlayback
    var onBattery: GSPlayback

    init(focused: GSPlayback = .keepRunning, maximized: GSPlayback = .keepRunning,
         fullscreen: GSPlayback = .keepRunning, playingAudio: GSPlayback = .keepRunning,
         displayAsleep: GSPlayback = .keepRunning, onBattery: GSPlayback = .keepRunning) {
        self.focused = focused
        self.maximized = maximized
        self.fullscreen = fullscreen
        self.playingAudio = playingAudio
        self.displayAsleep = displayAsleep
        self.onBattery = onBattery
    }

    init(_ settings: GlobalSettings) {
        self.init(focused: settings.otherApplicationFocused, maximized: settings.otherApplicationMaximized,
                  fullscreen: settings.otherApplicationFullscreen, playingAudio: settings.otherApplicationPlayingAudio,
                  displayAsleep: settings.displayAsleep, onBattery: settings.laptopOnBattery)
    }

    /// Some rule looks at other applications' windows, so they have to be watched.
    var watchesWindows: Bool { [focused, maximized, fullscreen].contains { $0 != .keepRunning } }

    /// The "playing audio" rule is on, so other applications' sound has to be watched.
    var watchesAudio: Bool { playingAudio != .keepRunning }

    /// The battery rule is on.
    var watchesPower: Bool { onBattery != .keepRunning }

    /// What each of `displays` does. A display missing from `conditions` has no window condition.
    func playback(displays: [String], conditions: [String: DisplayConditions],
                  system: SystemPlaybackConditions) -> [String: DisplayPlayback] {
        var everywhere = DisplayPlayback.run
        if system.otherApplicationPlayingAudio { everywhere = max(everywhere, DisplayPlayback(playingAudio)) }
        if system.displaysAsleep { everywhere = max(everywhere, DisplayPlayback(displayAsleep)) }
        if system.onBattery { everywhere = max(everywhere, DisplayPlayback(onBattery)) }
        if system.videoMemoryExhausted { everywhere = max(everywhere, .pause) }

        var local: [String: DisplayPlayback] = [:]
        for display in displays {
            var playback = DisplayPlayback.run
            for action in triggeredActions(conditions[display] ?? DisplayConditions()) {
                if action == .pauseAll {
                    everywhere = max(everywhere, .pause)
                } else {
                    playback = max(playback, DisplayPlayback(action))
                }
            }
            local[display] = playback
        }
        return local.mapValues { max($0, everywhere) }
    }

    private func triggeredActions(_ conditions: DisplayConditions) -> [GSPlayback] {
        var actions: [GSPlayback] = []
        if conditions.focused { actions.append(focused) }
        if conditions.maximized { actions.append(maximized) }
        if conditions.fullscreen { actions.append(fullscreen) }
        return actions
    }
}
