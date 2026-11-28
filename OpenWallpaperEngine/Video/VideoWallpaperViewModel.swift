//
//  VideoWallpaperViewModel.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/14.
//

import AVKit
import SwiftUI
import Combine

/// One video wallpaper (AVKit path), running once for every display that shows it
/// (`WallpaperViewModel.videoInstances`): one player decodes the video, which each display's
/// `AVPlayerView` shows, and one plays its sound.
@MainActor
class VideoWallpaperViewModel: ObservableObject {
    /// Whether the soundtrack plays: the app's audio output (`WallpaperAudioRouting`).
    private var playsAudio: Bool
    private unowned let wallpaperViewModel: WallpaperViewModel

    @Published var currentWallpaper: WEWallpaper {
        didSet {
            preparePlayers(for: currentWallpaper)
            updateMusicSyncCapture()
        }
    }

    /// The file the players read, kept while they do: from memory, it owns the bytes.
    private var videoFile: VideoFileSource?
    /// Finds the file the players open, off the main thread.
    private var preparation: Task<Void, Never>?
    /// Identifies the preparation in flight; nil once its file is open.
    private var pendingPreparation: UUID?
    private var stopped = false
    /// The file the players have open (a repaired copy is a cache entry: `CacheLeases`).
    private var mediaLease: CacheLease?

    var playRate: Float = 0 {
        didSet {
            updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
        }
    }

    var playVolume: Float = 0 {
        didSet {
            self.player.volume = playVolume
            applyAudioVolume()
        }
    }

    /// What the displays showing this video agree on under the playback rules: it plays while any
    /// of them plays (one player serves them all, so a paused display keeps showing it moving) and
    /// is heard unless every one of them is muted, paused or stopped (`DisplayPlaybackRouting`).
    private var displayPlayback: DisplayPlayback {
        wallpaperViewModel.wallpaperPlayback(of: WallpaperInstanceKey(currentWallpaper))
    }

    /// The soundtrack's volume: the app's, or silent while the playback rules mute the video.
    private func applyAudioVolume() {
        audioPlayer.volume = displayPlayback.playsSound ? playVolume : 0
    }

    /// The picture and the soundtrack, each looping without a pause at the end (`GaplessLoop`).
    private let videoQueue = WallpaperAVPlayer.makeQueue()
    private let audioQueue = WallpaperAVPlayer.makeQueue()
    private lazy var videoLoop = GaplessLoop(player: videoQueue)
    private lazy var audioLoop = GaplessLoop(player: audioQueue)
    var player: AVPlayer { videoQueue }
    private var audioPlayer: AVPlayer { audioQueue }
    private let ownAudioTap = AudioLevelTap()
    private var cancellables = Set<AnyCancellable>()
    /// The notification observers and the probe timer, which the nonisolated `deinit` removes.
    private let teardown = VideoWallpaperTeardown()
    /// Keeps system audio capture on while any music sync of the current wallpaper is on.
    private var musicSyncCaptureLease: AudioCaptureLease?
    /// Samples playback once a second for the render watchdog.
    private var probe = VideoPlaybackProbe()

    /// Rates last handed to AVFoundation, so redundant assignments can be skipped.
    private var appliedVideoRate: Float?
    private var appliedAudioRate: Float?
    private var smoothedAudioLevel: Double = 0
    private static let rateEpsilon: Float = 0.01
    private static let audioSmoothing = 0.25

    init(wallpaper currentWallpaper: WEWallpaper, wallpaperViewModel: WallpaperViewModel) {
        self.currentWallpaper = currentWallpaper
        self.playsAudio = wallpaperViewModel.playsInstanceAudio
        self.wallpaperViewModel = wallpaperViewModel
        self.player.isMuted = true
        self.audioPlayer.isMuted = !playsAudio
        // Called on the main queue (`GaplessLoop`), so `assumeIsolated` holds.
        videoLoop.passEnded = { [weak self] in
            MainActor.assumeIsolated { self?.videoPassEnded() }
        }
        // Block-based observers with a weak target, so this instance can still deinit (and stop
        // playback) when the wallpaper view is torn down instead of being kept alive forever.
        // Each is delivered on the main queue (`queue: .main`), so `assumeIsolated` holds.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        teardown.observe(.sleep, on: workspaceCenter, token: workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        })
        teardown.observe(.wake, on: workspaceCenter, token: workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })
        teardown.observe(.musicSync, on: .default, token: NotificationCenter.default.addObserver(forName: .videoMusicSyncAudioLevelDidChange, object: nil, queue: .main) { [weak self] notification in
            let level = notification.userInfo?["level"] as? Double
            MainActor.assumeIsolated { self?.videoMusicSyncAudioLevelDidChange(level: level) }
        })

        startPlaybackProbe()

        wallpaperViewModel.$playRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.playRate = rate
            }
            .store(in: &cancellables)
        wallpaperViewModel.$audioPlayRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Assigning the rate directly here used to restart audio even while paused.
                self?.updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
            }
            .store(in: &cancellables)
        wallpaperViewModel.displayOptions.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel) }
            .store(in: &cancellables)
        VideoMusicSyncStore.shared.$revision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMusicSyncCapture() }
            .store(in: &cancellables)
        wallpaperViewModel.$playVolume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.playVolume = volume
            }
            .store(in: &cancellables)
        wallpaperViewModel.$displayPlayback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAudioVolume()
                self?.updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
            }
            .store(in: &cancellables)
        wallpaperViewModel.$audioOutputEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setAudioEnabled(enabled)
            }
            .store(in: &cancellables)
        playVolume = wallpaperViewModel.playVolume
        playRate = wallpaperViewModel.playRate
        preparePlayers(for: currentWallpaper)
    }

    /// Stops playback for good: no display shows the video any more.
    func stop() {
        stopped = true
        preparation?.cancel()
        preparation = nil
        pendingPreparation = nil
        cancellables.removeAll()
        musicSyncCaptureLease = nil
        teardown.setTimer(nil)
        player.pause()
        audioPlayer.pause()
        videoLoop.clear()
        audioLoop.clear()
        videoFile = nil
    }

    deinit {
        preparation?.cancel()
        videoQueue.pause()
        audioQueue.pause()
        teardown.removeAll()
    }

    private func updateMusicSyncCapture() {
        let needed = VideoMusicSyncStore.shared.isAnyEnabled(currentWallpaper)
        guard needed != (musicSyncCaptureLease != nil) else { return }
        musicSyncCaptureLease = needed ? WallpaperServices.shared.acquireAudioCapture() : nil
    }

    // MARK: - Watchdog

    private func startPlaybackProbe() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePlayback() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        teardown.setTimer(timer)
    }

    private func samplePlayback() {
        guard let watchdog = wallpaperViewModel.renderWatchdog, let item = player.currentItem else { return }
        // Optional: an item keeps no access log until playback starts.
        let events = item.accessLog()?.events.filter { $0.numberOfDroppedVideoFrames >= 0 } ?? []
        let video = item.tracks.first { $0.assetTrack?.mediaType == .video }
        let sample = VideoPlaybackProbe.Sample(
            time: CACurrentMediaTime(), mediaTime: item.currentTime().seconds, rate: player.rate,
            droppedFrames: events.isEmpty ? nil : events.reduce(0) { $0 + $1.numberOfDroppedVideoFrames },
            frameRate: Double(video?.currentVideoFrameRate ?? 0))
        if let duration = probe.frameDuration(after: sample) { watchdog.recordFrame(duration: duration) }
    }

    func setAudioEnabled(_ enabled: Bool) {
        playsAudio = enabled
        player.isMuted = true
        audioPlayer.isMuted = !enabled
        updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
    }

    /// The wallpaper's own soundtrack drives music sync whenever you can actually hear it;
    /// otherwise sync follows whatever else is playing on the system.
    var musicSyncLevel: Double {
        !audioPlayer.isMuted && audioPlayer.volume > 0 && ownAudioTap.isMeasuring
            ? ownAudioTap.level
            : WallpaperServices.shared.audioLevel
    }

    func updatePlaybackRates(audioLevel: Double) {
        let paceAmount = VideoMusicSyncStore.shared.bool(currentWallpaper, "paceEnabled")
            ? VideoMusicSyncStore.shared.double(currentWallpaper, "paceAmount", default: 0.25)
            : 0
        // The raw level is per-sample noisy; pacing straight off it reads as stutter rather than
        // a pulse. Smoothing is skipped when pacing is off so play/pause stays instant.
        let level = musicSyncLevel
        if paceAmount > 0 {
            smoothedAudioLevel += (level - smoothedAudioLevel) * Self.audioSmoothing
        } else {
            smoothedAudioLevel = level
        }
        // A paused wallpaper stays paused; pacing only modulates a video that is playing. The
        // wallpaper's own playback rate (WE's per-wallpaper option) scales the app's.
        let displayRate = wallpaperViewModel.displayPlaybackRate(of: currentWallpaper)
        // Held for the screen saver: the picture plays at the wallpaper's speed (the last one
        // while paused), silent, whatever the rules and the windows covering it say.
        if heldForScreenSaver {
            let speed = playRate > 0 ? playRate : (wallpaperViewModel.lastPlayRate > 0 ? wallpaperViewModel.lastPlayRate : 1)
            setVideoRate(speed * displayRate)
            setAudioRate(0)
            return
        }
        let rate = displayPlayback.rendersFrames ? playRate * displayRate : 0
        setVideoRate(rate > 0 ? max(0, rate + Float(smoothedAudioLevel * paceAmount)) : 0)
        // Audio runs on a second player, so a paused wallpaper keeps playing sound unless the
        // pause is applied here too.
        setAudioRate(playsAudio && !audioPlayer.isMuted && rate > 0 ? wallpaperViewModel.audioPlayRate * displayRate : 0)
    }

    /// The live screen saver draws this video's frames (`ScreenSaverVideoSharing`): it plays,
    /// silent, while the screen saver runs.
    private(set) var heldForScreenSaver = false

    /// Assigning `AVPlayer.rate` restarts the timebase, so doing it on every audio sample stutters
    /// the video and pitches the audio. Only meaningful changes are forwarded.
    private func setVideoRate(_ rate: Float) {
        if let applied = appliedVideoRate, abs(rate - applied) <= Self.rateEpsilon { return }
        appliedVideoRate = rate
        player.rate = rate
    }

    private func setAudioRate(_ rate: Float) {
        if let applied = appliedAudioRate, abs(rate - applied) <= Self.rateEpsilon { return }
        appliedAudioRate = rate
        audioPlayer.rate = rate
    }

    /// The picture played to its end and runs on into its next pass (`GaplessLoop`), as the
    /// soundtrack does on its own.
    private func videoPassEnded() {
        wallpaperViewModel.advancePlaylistIfVideoEnds(currentWallpaper)
        probe.reset()
        resyncSoundtrackIfDrifted()
    }

    /// The soundtrack runs to the audio device's clock and loops on its own, so over hours it can
    /// drift from the picture; at the picture's loop point a drift past `maximumDrift` is put right.
    /// Nothing is done while music pacing or the rates make the two run apart on purpose.
    private func resyncSoundtrackIfDrifted() {
        guard playsAudio, !audioPlayer.isMuted, !VideoMusicSyncStore.shared.bool(currentWallpaper, "paceEnabled"),
              let audioRate = appliedAudioRate, audioRate > 0, let videoRate = appliedVideoRate,
              abs(audioRate - videoRate) <= Self.rateEpsilon,
              let duration = audioPlayer.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
        let video = player.currentTime()
        guard let drift = Self.loopDrift(audio: audioPlayer.currentTime().seconds, video: video.seconds, duration: duration),
              abs(drift) > Self.maximumDrift else { return }
        audioPlayer.seek(to: video, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// How far a soundtrack shows lip-sync drift: about what people notice with sound running late.
    static let maximumDrift = 0.08

    /// How far the soundtrack at `audio` runs ahead of the picture at `video` (seconds; negative
    /// when it runs behind), on a loop of `duration`: the shorter way round the loop.
    static func loopDrift(audio: Double, video: Double, duration: Double) -> Double? {
        guard audio.isFinite, video.isFinite, duration.isFinite, duration > 0 else { return nil }
        var drift = (audio - video).truncatingRemainder(dividingBy: duration)
        if drift > duration / 2 { drift -= duration } else if drift < -duration / 2 { drift += duration }
        return drift
    }

    private func systemWillSleep() {
        setVideoRate(0)
        setAudioRate(0)
    }

    private func systemDidWake() {
        updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
    }

    private func videoMusicSyncAudioLevelDidChange(level: Double?) {
        updatePlaybackRates(audioLevel: level ?? WallpaperServices.shared.audioLevel)
    }

    /// Opens the wallpaper's video in the players once its source is made, off the main thread: a
    /// video whose track AVFoundation refuses as it is plays repaired (`VideoSampleEntryRepair`,
    /// read from its `moov`), and WE's "Video loading" set to in memory reads the file into memory
    /// (`VideoFileSource`).
    private func preparePlayers(for wallpaper: WEWallpaper) {
        preparation?.cancel()
        let source = wallpaper.mediaURL
        let readMode = wallpaperViewModel.videoReadMode
        let offMain = VideoSampleEntryRepair.mayNeedRepair(source) || readMode == .inMemory
        let id = UUID()
        pendingPreparation = id
        preparation = Task { [weak self] in
            let file = offMain
                ? await Task.detached(priority: .userInitiated) { VideoFileSource(url: source, mode: readMode) }.value
                : VideoFileSource(url: source, mode: .fromDisk)
            let assets = await file.makeLoopAssets()
            guard let self, !Task.isCancelled, !self.stopped, self.pendingPreparation == id else { return }
            self.pendingPreparation = nil
            self.replacePlayers(with: file, assets: assets)
        }
    }

    /// Plays `file`, split into `assets`; what played before plays until then.
    private func replacePlayers(with file: VideoFileSource, assets: VideoFileSource.LoopAssets) {
        let url = file.url
        videoFile = file
        mediaLease = CacheLeases.current.lease(url)
        // Emptied queues stop, so the cached rates no longer describe the players.
        appliedVideoRate = nil
        appliedAudioRate = nil
        probe.reset()
        videoLoop.play { AVPlayerItem(asset: assets.picture) }
        if let soundtrack = assets.soundtrack {
            audioLoop.play { assets.makeSoundtrackItem() }
            ownAudioTap.attach(toItemsOf: soundtrack) { [weak self] mix in self?.audioLoop.audioMix = mix }
        } else {
            audioLoop.clear()
            ownAudioTap.detach()
        }
        player.isMuted = true
        audioPlayer.isMuted = !playsAudio
        updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
    }
}

extension VideoWallpaperViewModel: ScreenSaverVideoSharing {
    var sharedPlayer: AVPlayer { player }

    func holdForScreenSaver(_ hold: Bool) {
        guard hold != heldForScreenSaver else { return }
        heldForScreenSaver = hold
        updatePlaybackRates(audioLevel: WallpaperServices.shared.audioLevel)
    }
}

/// The view model's notification observers and probe timer, kept outside the main actor so its
/// nonisolated `deinit` can remove them. `@unchecked Sendable`: `lock` guards both fields.
private final class VideoWallpaperTeardown: @unchecked Sendable {
    enum Observer { case sleep, wake, musicSync }

    private let lock = NSLock()
    private var observers: [Observer: (center: NotificationCenter, token: NSObjectProtocol)] = [:]
    private var timer: Timer?

    /// Keeps `token`, observing on `center`, as `observer`, removing the one it replaces.
    func observe(_ observer: Observer, on center: NotificationCenter, token: NSObjectProtocol) {
        let old = lock.withLock { observers.updateValue((center, token), forKey: observer) }
        if let old { old.center.removeObserver(old.token) }
    }

    /// Keeps `timer` (nil for none), invalidating the one it replaces.
    func setTimer(_ newTimer: Timer?) {
        let old = lock.withLock { () -> Timer? in
            defer { timer = newTimer }
            return timer
        }
        old?.invalidate()
    }

    func removeAll() {
        let (removed, oldTimer) = lock.withLock { () -> ([(center: NotificationCenter, token: NSObjectProtocol)], Timer?) in
            defer { observers = [:]; timer = nil }
            return (Array(observers.values), timer)
        }
        removed.forEach { $0.center.removeObserver($0.token) }
        oldTimer?.invalidate()
    }
}
