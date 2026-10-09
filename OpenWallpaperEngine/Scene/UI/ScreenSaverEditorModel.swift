import AVFoundation
import Combine
import Foundation

/// Scene Edit / Export's Screen Saver mode: the wallpaper's screen saver version in the mode's
/// private instance (`IsolatedSceneEditSession`), its layer and property choices, recording it as
/// the screen saver, the daily re-recording, and playing the last recording.
///
/// The session starts from the screen saver's saved choices for this wallpaper
/// (`ScreenSaverSettingsStore`) when it has any, else from the wallpaper's own values. What the
/// mode changes is saved back there as it changes (and when the mode closes), never to the
/// wallpaper's own stores, so later recordings, by hand or on the schedule, reuse it.
@MainActor
final class ScreenSaverEditorModel: ObservableObject {
    /// The isolated session's purpose (`WallpaperPropertyScope.isolated`).
    static let purpose = "screen-saver"

    let session: IsolatedSceneEditSession
    let wallpaper: WEWallpaper
    let recordings: ScreenSaverRecordingService
    let schedule: ScreenSaverDailyScheduler
    private let store: ScreenSaverSettingsStore
    private let defaults: UserDefaults
    private let identity: WallpaperSettingsIdentity
    /// The stores the session was seeded from: the wallpaper's own values, which the screen saver
    /// follows until its choices first differ.
    private let seedScopes: [WallpaperPropertyScope]

    /// The last recording, looping, while it is previewed; nil shows the live scene.
    @Published private(set) var preview: AVQueuePlayer?
    @Published var errorMessage: String?
    private var looper: AVPlayerLooper?
    private var subscriptions: Set<AnyCancellable> = []

    /// `defaults` holds the stores (the session's too); `store` the screen saver's own settings.
    init(session: IsolatedSceneEditSession, seededFrom seedScopes: [WallpaperPropertyScope],
         recordings: ScreenSaverRecordingService, schedule: ScreenSaverDailyScheduler,
         store: ScreenSaverSettingsStore, defaults: UserDefaults = .app) {
        self.seedScopes = seedScopes
        self.session = session
        wallpaper = session.wallpaper
        self.recordings = recordings
        self.schedule = schedule
        self.store = store
        self.defaults = defaults
        identity = session.targets.identity
        if let saved = store.values(for: identity) { session.replaceValues(saved) }
        recordings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        schedule.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        // The editor's models write the session's store directly; its changes are saved as they settle.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.persist() } }
            .store(in: &subscriptions)
    }

    /// Only scenes are recorded here (their loop is rendered by the scene renderer).
    static func isEligible(_ wallpaper: WEWallpaper) -> Bool { ScreenSaverPlugin.isScene(wallpaper) }

    /// Saves the session's values as the screen saver's choices for this wallpaper, when they changed.
    func persist() {
        guard !session.isEnded else { return }
        let values = session.values
        guard store.values(for: identity) != values else { return }
        // The first change makes the choices the screen saver's own; until then it follows the wallpaper.
        if store.values(for: identity) == nil, values == IsolatedSceneEditSession.seed(of: wallpaper, from: seedScopes, defaults: defaults) {
            return
        }
        store.setValues(values, for: identity)
    }

    /// Whether this wallpaper's recording is the screen saver.
    var isScreenSaver: Bool { recordings.isSelected(wallpaper) }

    var isRecording: Bool { recordings.isRecording }

    /// When this wallpaper's recording was made, while it is the screen saver.
    var lastRecorded: Date? { isScreenSaver ? recordings.selection?.recorded : nil }

    /// The recording to preview, when there is one.
    var hasRecording: Bool { recordings.recordedVideo(of: wallpaper) != nil }

    /// Records this version and sets it as the screen saver.
    func record() {
        guard !recordings.isRecording else { return }
        persist()
        stopPreview()
        errorMessage = nil
        recordings.record(wallpaper, values: session.values, background: false) { [weak self] succeeded in
            guard !succeeded else { return }
            self?.errorMessage = String(localized: "The screen saver couldn't be recorded. The logs say why.")
        }
    }

    func stopUsingAsScreenSaver() {
        stopPreview()
        recordings.stopUsingSelection()
    }

    // MARK: Preview

    /// Plays the last recording in a loop, muted, as the saver does.
    func playRecording() {
        guard let url = recordings.recordedVideo(of: wallpaper) else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        preview = player
        player.play()
    }

    func stopPreview() {
        preview?.pause()
        looper = nil
        preview = nil
    }

    // MARK: Schedule

    var scheduleTime: Date {
        get { schedule.timeToday }
        set {
            let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: newValue)
            schedule.setTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
    }

    /// The mode closes: its last changes are saved and the preview stops.
    func close() {
        persist()
        stopPreview()
    }
}
