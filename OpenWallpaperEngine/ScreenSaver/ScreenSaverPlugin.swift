import AppKit
import Combine

/// Settings › Plugins › Screen Saver. While on, the bundled saver is installed and shows the
/// screen saver's layout (`ScreenSaverLayoutPlan`: per display, cloned, or one stretched over the
/// displays' canvas): scenes, web wallpapers and WebM videos drawn live by the app while the
/// screen saver runs (`liveLoops`, `ScreenSaverLiveController`), and a video wallpaper AVFoundation
/// plays as its own file, linked (or copied, or repaired) into the saver's folder (`ScreenSaverVideoSource`)
/// and listed in the manifest, cropped per display for a stretch. Nothing is recorded. Off removes
/// the saver and the linked videos.
///
/// - Only the user's own copy installs the saver and writes where it reads
///   (`ScreenSaverInstaller.mayInstall`, `ScreenSaverVideoStore`'s isolated folder).
/// - While a wallpaper is picked as the screen saver (`ScreenSaverSettingsStore.livePick`) it is
///   drawn live on every display and the manifest lists no video; while a video wallpaper's own
///   file is set as the screen saver (`ScreenSaverSettingsStore.selection`) the saver plays that.
@MainActor
final class ScreenSaverPlugin: ObservableObject {
    /// What the Details pane says about a wallpaper in the screen saver.
    enum Status: Equatable {
        /// The screen saver shows it: drawn live, or its own video file is in place.
        case available
        /// A video wallpaper's file is being repaired for the saver.
        case rendering
        /// Not a wallpaper the screen saver shows (`isEligible`), or a video in a codec it can't play.
        case notEligible
        /// A web wallpaper or WebM video, drawn only by the Chromium engine, which isn't installed.
        case needsChromium
    }

    /// A video wallpaper's file, keyed as the store names it.
    struct StatusKey: Hashable {
        var wallpaperKey: String
        var contentKey: String
        var propertyHash: String
    }

    private let store: ScreenSaverVideoStore
    private let installer: ScreenSaverInstaller
    let settingsStore: ScreenSaverSettingsStore
    /// Videos being set as the screen saver (`beginSettingVideo`): nothing is linked or listed meanwhile.
    private var settingVideos = 0
    @Published private(set) var isEnabled = false
    /// The video wallpapers' statuses, for their current files only.
    @Published private(set) var statuses: [StatusKey: Status] = [:]
    /// Bumped on every change: a finished link for an older one doesn't touch the manifest.
    private var generation = 0
    /// The view model whose displays the plan follows (`observe(_:)`).
    private(set) weak var viewModel: WallpaperViewModel?
    private var observation: AnyCancellable?
    /// The current plan; nil while none is followed.
    private var plan: ScreenSaverLayoutPlan?
    /// The plan's video wallpapers' loops as the manifest lists them.
    private var entries: [Entry] = []
    /// The prepared video wallpapers' files' sizes, by file name.
    private var videoSizes: [String: SIMD2<Int>] = [:]
    /// The playback speed the video wallpapers' entries are written with.
    private var videoRate: Float = 1
    private var rateSubscription: AnyCancellable?
    private static let fileQueue = DispatchQueue(label: "OWE.ScreenSaverPlugin", qos: .utility)

    init(store: ScreenSaverVideoStore = .current, installer: ScreenSaverInstaller = .current,
         settingsStore: ScreenSaverSettingsStore = ScreenSaverSettingsStore()) {
        self.store = store
        self.installer = installer
        self.settingsStore = settingsStore
    }

    /// Whether the screen saver shows `wallpaper`: scenes, web wallpapers and WebM videos (drawn
    /// live, the last two through Chromium), and videos in a container AVFoundation plays (their
    /// own file; the codec is checked when the file is prepared, `ScreenSaverVideoSource`); never
    /// application wallpapers.
    nonisolated static func isEligible(_ wallpaper: WEWallpaper) -> Bool {
        isScene(wallpaper) || ScreenSaverVideoSource.isEligible(wallpaper) || isWeb(wallpaper) || isWebMVideo(wallpaper)
    }

    nonisolated static func isScene(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    nonisolated static func isWeb(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("web") == .orderedSame
    }

    nonisolated static func isWebMVideo(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("video") == .orderedSame
            && (wallpaper.project.file as NSString).pathExtension.lowercased() == "webm"
    }

    /// The store key of a video wallpaper's file now; nil for any other wallpaper, or one that
    /// can't be read.
    nonisolated static func statusKey(for wallpaper: WEWallpaper) -> StatusKey? {
        guard ScreenSaverVideoSource.isEligible(wallpaper),
              let contentKey = SceneLoadingSnapshotStore.contentKey(for: wallpaper.wallpaperDirectory) else { return nil }
        return StatusKey(wallpaperKey: SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory),
                         contentKey: contentKey, propertyHash: ScreenSaverVideoStore.propertyHash([:]))
    }

    /// What to show for `wallpaper`: nil while the plugin is off, or for a video wallpaper whose
    /// file isn't prepared yet. A wallpaper drawn live is available at once (a web page or WebM
    /// video once Chromium is installed).
    nonisolated static func status(for wallpaper: WEWallpaper, enabled: Bool, statuses: [StatusKey: Status],
                                   chromiumInstalled: Bool) -> Status? {
        guard enabled else { return nil }
        guard isEligible(wallpaper) else { return .notEligible }
        if isScene(wallpaper) { return .available }
        if isWeb(wallpaper) || isWebMVideo(wallpaper) { return chromiumInstalled ? .available : .needsChromium }
        let wallpaperKey = SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory)
        return statuses.first { $0.key.wallpaperKey == wallpaperKey }?.value
    }

    func status(for wallpaper: WEWallpaper) -> Status? {
        Self.status(for: wallpaper, enabled: isEnabled, statuses: statuses,
                    chromiumInstalled: ChromiumEngineInstaller.hasActiveInstall)
    }

    /// The plugin's setting or the shown wallpapers changed: plans the loops anew
    /// (`ScreenSaverLayoutPlan`) from the observed view model (`observe(_:)`), or, before one is
    /// observed, with `wallpaper` on every display, and links the video wallpapers' files.
    func update(enabled: Bool, wallpaper: WEWallpaper?) {
        reset()
        let wasEnabled = isEnabled
        isEnabled = enabled
        let store = store, installer = installer
        guard enabled else {
            // The linked videos go, so a video set as the screen saver goes with them.
            settingsStore.selection = nil
            if wasEnabled { Self.fileQueue.async { installer.uninstall(); store.removeAll() } }
            return
        }
        if !wasEnabled {
            Self.fileQueue.async {
                installer.install()
            }
        }
        // A wallpaper picked as the screen saver is drawn live: no video, so no other wallpaper's
        // video plays before its first frames.
        if settingVideos == 0, settingsStore.livePick != nil {
            Self.fileQueue.async {
                do { try store.writeManifest(ScreenSaverManifest()) } catch {
                    OWELog.error(.app, "Screen saver: can't clear the videos' manifest: \(error)")
                }
            }
            return
        }
        // A video set as the screen saver plays instead; its manifest stays.
        guard settingVideos == 0, settingsStore.selection == nil, viewModel != nil || wallpaper != nil else { return }
        let (plan, wallpapers) = currentPlan(fallback: wallpaper)
        self.plan = plan
        let generation = generation
        Self.fileQueue.async { [weak self] in
            let work = Self.work(for: plan, wallpapers: wallpapers)
            Task { @MainActor in self?.start(work, generation: generation) }
        }
    }

    /// Re-plans when the wallpapers, the layouts or the displays change; a change that leaves the
    /// plan as it is renders nothing.
    func observe(_ viewModel: WallpaperViewModel) {
        self.viewModel = viewModel
        let screens = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in () }
        observation = Publishers.Merge5(viewModel.$wallpapers.map { _ in () }, viewModel.$layoutResolution.map { _ in () },
                                        viewModel.$screenSaverLayout.map { _ in () }, viewModel.$instanceKeys.map { _ in () },
                                        screens)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.replanIfChanged() }
            }
    }

    private func replanIfChanged() {
        guard isEnabled, settingVideos == 0, settingsStore.selection == nil, settingsStore.livePick == nil else { return }
        guard currentPlan(fallback: nil).plan != plan else { return }
        update(enabled: true, wallpaper: nil)
    }

    /// The plan for the displays now, with each planned content's wallpaper by its id.
    func currentPlan(fallback: WEWallpaper?) -> (plan: ScreenSaverLayoutPlan, wallpapers: [String: WEWallpaper]) {
        var wallpapers: [String: WEWallpaper] = [:]
        func content(_ wallpaper: WEWallpaper, scope: WallpaperPropertyScope) -> ScreenSaverLayoutPlan.Content {
            let id = wallpaper.wallpaperDirectory.standardizedFileURL.path
            wallpapers[id] = wallpaper
            // A video plays as it is: its user properties don't change the file.
            guard !ScreenSaverVideoSource.isEligible(wallpaper) else { return ScreenSaverLayoutPlan.Content(id: id) }
            return ScreenSaverLayoutPlan.Content(id: id, properties: WallpaperServices.shared.userProperties(
                wallpaper: scope.runtimeKey(directory: wallpaper.settingsDirectory)))
        }
        let scales = Dictionary(NSScreen.screens.map { (WallpaperViewModel.screenId(for: $0), $0.backingScaleFactor) },
                                uniquingKeysWith: max)
        let identities = viewModel?.connectedDisplays() ?? DisplayIdentity.connected()
        let displays = identities.map {
            ScreenSaverLayoutPlan.Display(screenId: $0.screenId, identity: $0.identity, frame: $0.frame, scale: scales[$0.screenId] ?? 1)
        }
        guard let viewModel else {
            var shown: [String: ScreenSaverLayoutPlan.Content] = [:]
            if let fallback {
                let fallback = content(fallback, scope: .shared)
                for display in displays { shown[display.screenId] = fallback }
            }
            let plan = ScreenSaverLayoutPlan(ScreenSaverDisplayLayout(), wallpaperLayout: .perDisplay, resolution: .empty,
                                             displays: displays, shown: shown)
            return (plan, wallpapers)
        }
        var displayed: [String: ScreenSaverLayoutPlan.Content] = [:]
        for (screen, wallpaper) in viewModel.displayedWallpapers {
            displayed[screen] = content(wallpaper, scope: viewModel.instanceKey(for: screen).properties)
        }
        let resolution = viewModel.layoutResolution
        let shown = ScreenSaverLayoutPlan.shown(displayed, screenIds: displays.map(\.screenId), resolution: resolution)
        let plan = ScreenSaverLayoutPlan(viewModel.screenSaverLayout, wallpaperLayout: viewModel.displayLayout.layout,
                                         resolution: resolution, displays: displays, shown: shown)
        return (plan, wallpapers)
    }

    /// A video wallpaper's loop of the plan as the manifest lists it: its own file, listed once
    /// it is prepared (`videoSizes`).
    struct Entry: Equatable {
        var loop: ScreenSaverLayoutPlan.Loop
        var file: String
    }

    /// What a plan takes: its video wallpapers' manifest entries and the files to link, each with
    /// its status key.
    struct Work {
        var entries: [Entry] = []
        var videos: [(key: StatusKey, wallpaper: WEWallpaper, file: String)] = []
    }

    /// The plan's video wallpapers: their loops play their own file (cropped for a stretch).
    /// Every other loop is drawn live. Reads the wallpapers' content keys: never call it on the
    /// main thread.
    nonisolated static func work(for plan: ScreenSaverLayoutPlan, wallpapers: [String: WEWallpaper]) -> Work {
        var work = Work()
        for loop in plan.loops {
            guard let wallpaper = wallpapers[loop.content.id], let key = statusKey(for: wallpaper) else { continue }
            let file = ScreenSaverVideoSource.fileName(key: key, source: wallpaper.mediaURL)
            work.entries.append(Entry(loop: loop, file: file))
            if !work.videos.contains(where: { $0.file == file }) { work.videos.append((key, wallpaper, file)) }
        }
        return work
    }

    /// The manifest's videos for a loop in `file` of `size`: one for its displays (any display
    /// when it plays on every one), or, for a stretch, one per display with its crop.
    nonisolated static func manifestVideos(for loop: ScreenSaverLayoutPlan.Loop, file: String, size: SIMD2<Int>,
                                           rate: Float?, everyDisplay: Bool) -> [ScreenSaverManifest.Video] {
        // The saver is always muted and always loops; a speed of 1 isn't written.
        let rate = rate.flatMap { $0 > 0 && abs($0 - 1) > 0.001 ? $0 : nil }
        guard let canvas = loop.canvas else {
            return [ScreenSaverManifest.Video(file: file, width: size.x, height: size.y, rate: rate,
                                              displays: everyDisplay ? nil : loop.displays)]
        }
        let video = CGSize(width: size.x, height: size.y)
        return loop.displays.compactMap { display in
            loop.crops[display].map {
                ScreenSaverManifest.Video(file: file, width: size.x, height: size.y, rate: rate, displays: [display],
                                          crop: ScreenSaverManifest.Crop($0, canvas: canvas.size, video: video))
            }
        }
    }

    /// A video wallpaper's own file is being set as the screen saver (`ScreenSaverSelectionService.useVideo`):
    /// the plan's links and manifest writes stop (a late one of an older generation is dropped),
    /// so none replaces it or prunes its staging copy.
    func beginSettingVideo() {
        settingVideos += 1
        reset()
    }

    /// The video was set (or not); the plugin follows `wallpaper` again unless something is set
    /// as the screen saver.
    func endSettingVideo(wallpaper: WEWallpaper?) {
        settingVideos = max(settingVideos - 1, 0)
        guard settingVideos == 0, settingsStore.selection == nil else { return }
        update(enabled: isEnabled, wallpaper: wallpaper)
    }

    /// Whether the saver follows the desktop's wallpapers: on, with nothing set as the screen
    /// saver (the live screen saver then draws the desktop's layout, `ScreenSaverLiveController`).
    var followsDesktop: Bool {
        isEnabled && settingVideos == 0 && settingsStore.selection == nil && settingsStore.livePick == nil
    }

    /// The wallpaper picked as the screen saver (Scene Edit / Export's Screen Saver mode, Set as
    /// Screen Saver), while the plugin is on and it is still in the library.
    var livePick: WEWallpaper? {
        guard isEnabled, let pick = settingsStore.livePick else { return nil }
        return InstalledLibrary.wallpaper(at: URL(filePath: pick.wallpaperDirectory, directoryHint: .isDirectory), hiding: [])
    }

    /// Drops the current plan: its late results are ignored.
    private func reset() {
        generation += 1
        statuses = [:]
        plan = nil
        entries = []
        videoSizes = [:]
    }

    private func start(_ work: Work, generation: Int) {
        guard generation == self.generation else { return }
        entries = work.entries
        if !work.videos.isEmpty, let viewModel {
            videoRate = viewModel.playRate > 0 ? viewModel.playRate : viewModel.lastPlayRate
            observeSpeed(of: viewModel)
        }
        publishManifest(generation: generation)
        for video in work.videos { scheduleVideo(video.wallpaper, key: video.key, fileName: video.file, generation: generation) }
    }

    /// A video wallpaper: links (or copies, or repairs) its file into the store; the manifest lists its
    /// loops at its video track's size once it's there.
    private func scheduleVideo(_ wallpaper: WEWallpaper, key: StatusKey, fileName: String, generation: Int) {
        let store = store
        Self.fileQueue.async { [weak self] in
            let source = wallpaper.mediaURL
            // The codec first (cached per file version): an unsupported one says so at once.
            guard ScreenSaverVideoSource.hasPlayableTrack(source) else {
                Task { @MainActor in self?.setStatus(.notEligible, for: key, generation: generation) }
                return
            }
            let destination = store.url(fileName: fileName)
            // An earlier version's symbolic link out of the folder is replaced: the saver can't follow it.
            let outcome: ScreenSaverVideoSource.Outcome = ScreenSaverVideoSource.isInPlace(destination)
                ? .ready(repaired: false)
                : ScreenSaverVideoSource.prepare(source, at: destination) {
                    Task { @MainActor in self?.setStatus(.rendering, for: key, generation: generation) }
                }
            let size: SIMD2<Int>? = if case .ready = outcome { ScreenSaverVideoSource.displaySize(of: destination) } else { nil }
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                switch (outcome, size) {
                case (.unsupported, _):
                    self.statuses[key] = .notEligible
                case (.ready, let size?):
                    self.statuses[key] = .available
                    self.videoSizes[fileName] = size
                    self.publishManifest(generation: generation)
                default:
                    self.statuses[key] = nil
                }
            }
        }
    }

    /// Follows the playback speed: a settled change (pause excluded) rewrites the video
    /// wallpapers' manifest entries. Nothing is rendered or linked again.
    private func observeSpeed(of viewModel: WallpaperViewModel) {
        guard rateSubscription == nil else { return }
        rateSubscription = viewModel.$playRate
            .filter { $0 > 0 }
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] rate in
                MainActor.assumeIsolated { self?.speedDidChange(rate) }
            }
    }

    private func speedDidChange(_ rate: Float) {
        guard isEnabled, abs(videoRate - rate) > 0.001 else { return }
        videoRate = rate
        if !entries.isEmpty { publishManifest(generation: generation) }
    }

    private func setStatus(_ status: Status, for key: StatusKey, generation: Int) {
        guard generation == self.generation else { return }
        statuses[key] = status
    }

    /// Lists the plan's video loops whose files exist in the manifest and removes every other video.
    private func publishManifest(generation: Int) {
        guard generation == self.generation else { return }
        let store = store, entries = entries, videoSizes = videoSizes, rate = videoRate
        let everyDisplay = Set(plan?.displays ?? [])
        Self.fileQueue.async {
            var videos: [ScreenSaverManifest.Video] = []
            for entry in entries {
                guard let size = videoSizes[entry.file], store.exists(fileName: entry.file) else { continue }
                videos += Self.manifestVideos(for: entry.loop, file: entry.file, size: size, rate: rate,
                                              everyDisplay: everyDisplay.isSubset(of: entry.loop.displays))
            }
            do { try store.writeManifest(ScreenSaverManifest(videos: videos)) } catch {
                OWELog.error(.app, "Screen saver: can't write the manifest: \(error)")
            }
            store.retain(Set(entries.map(\.file)))
        }
    }
}
