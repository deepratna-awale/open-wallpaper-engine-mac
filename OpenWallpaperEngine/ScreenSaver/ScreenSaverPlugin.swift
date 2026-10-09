import AppKit
import Combine

/// Settings › Plugins › Screen Saver. While on, the loops the screen saver's layout plans
/// (`ScreenSaverLayoutPlan`: per display, cloned, or one stretched over the displays' canvas)
/// are rendered (`ScreenSaverLoopRenderer` for a scene, `ScreenSaverWebLoopRecorder` for a web
/// wallpaper or WebM video, in the app's helper run) and the bundled saver plays each display's;
/// a video wallpaper AVFoundation plays has its own file linked (or repaired) for the saver
/// instead, with no render (`ScreenSaverVideoSource`), cropped per display for a stretch. Off
/// stops rendering and removes the saver and the videos.
///
/// - Renders run as `.library` jobs on the `PreparationPool`, so they wait while the power policy
///   says no (battery, heat), one at a time, each in a helper process at background priority.
/// - Videos are keyed by wallpaper, user properties and display size (`ScreenSaverVideoStore`); a
///   change renders the new key and the manifest moves to it once it exists.
/// - Only the user's own copy installs the saver and writes where it reads
///   (`ScreenSaverInstaller.mayInstall`, `ScreenSaverVideoStore`'s isolated folder).
/// - While a recording from Scene Edit / Export's Screen Saver mode is set as the screen saver
///   (`ScreenSaverSettingsStore.selection`), or one is being made (`beginRecording`), the saver
///   plays that and nothing is rendered for the desktop's wallpaper (`ScreenSaverRecordingService`).
@MainActor
final class ScreenSaverPlugin: ObservableObject {
    /// What the Details pane says about a wallpaper's loop video.
    enum Status: Equatable {
        /// Every display's video for the current content and properties is in the store.
        case available
        /// A render job for it is queued or running (for a video wallpaper: its repair).
        case rendering
        /// Not a wallpaper loops are made from (`isEligible`).
        case notEligible
        /// An eligible wallpaper whose loop couldn't be made, and why.
        case notAvailable(Reason)
    }

    enum Reason: Equatable {
        /// The web page (or WebKit video) didn't load in the recorder.
        case pageDidNotLoad
        /// The page's recording has no seam that loops smoothly (`ScreenSaverSeamFinder.searchActiveSeam`).
        case doesNotLoop
    }

    /// How one helper run ended.
    enum RunResult: Equatable {
        case rendered
        case failed
        case pageDidNotLoad
        case doesNotLoop
    }

    /// A wallpaper's videos, keyed as the store names them.
    struct StatusKey: Hashable {
        var wallpaperKey: String
        var contentKey: String
        var propertyHash: String
    }

    struct Target: Equatable {
        var pixelSize: SIMD2<Int>
        var pointSize: SIMD2<Int>
        var fileName: String
        /// The user properties a web page is recorded with (scenes read their own, unless `isRecording`).
        var properties: [String: String] = [:]
        /// A Screen Saver mode recording: the scene renders with `properties` (its user properties
        /// and layer edits) and its clock layers are drawn like any other, the user's layer
        /// choices deciding what shows.
        var isRecording = false
    }

    typealias Runner = @Sendable (_ wallpaper: URL, _ target: Target, _ output: URL) -> RunResult

    private let pool: PreparationPool
    private let store: ScreenSaverVideoStore
    private let installer: ScreenSaverInstaller
    private let runner: Runner
    private let settingsStore: ScreenSaverSettingsStore
    /// Recordings being made (`beginRecording`): nothing else is rendered or listed meanwhile.
    private var recordings = 0
    @Published private(set) var isEnabled = false
    /// The shown wallpaper's status, for its current content and properties only; a failed or
    /// cancelled render leaves no entry.
    @Published private(set) var statuses: [StatusKey: Status] = [:]
    /// Bumped on every change: a finished render for an older one doesn't touch the manifest.
    private var generation = 0
    private var jobs: [PreparationPool.Job] = []
    /// The view model whose displays the plan follows (`observe(_:)`).
    private weak var viewModel: WallpaperViewModel?
    private var observation: AnyCancellable?
    /// The current plan; nil while none is followed.
    private var plan: ScreenSaverLayoutPlan?
    /// The plan's loops as the manifest lists them.
    private var entries: [Entry] = []
    /// The prepared video wallpapers' files' sizes, by file name.
    private var videoSizes: [String: SIMD2<Int>] = [:]
    /// The playback speed the video wallpapers' entries are written with.
    private var videoRate: Float = 1
    private var rateSubscription: AnyCancellable?
    private static let fileQueue = DispatchQueue(label: "OWE.ScreenSaverPlugin", qos: .utility)

    init(pool: PreparationPool = .shared, store: ScreenSaverVideoStore = .current,
         installer: ScreenSaverInstaller = .current, runner: @escaping Runner = { ScreenSaverPlugin.runHelper($0, $1, $2) },
         settingsStore: ScreenSaverSettingsStore = ScreenSaverSettingsStore()) {
        self.pool = pool
        self.store = store
        self.installer = installer
        self.runner = runner
        self.settingsStore = settingsStore
        // The shared pool's library jobs wait on the power policy once its scheduler exists.
        if pool === PreparationPool.shared { _ = LibraryPreparationScheduler.shared }
    }

    /// Whether the saver plays `wallpaper`: valid scene and web wallpapers and WebM videos (a
    /// rendered or recorded loop), and videos in a container AVFoundation plays (their own file;
    /// the codec is checked when the file is prepared, `ScreenSaverVideoSource`); never
    /// application wallpapers. `targets(for:)` and the Details
    /// pane both ask this.
    nonisolated static func isEligible(_ wallpaper: WEWallpaper) -> Bool {
        isScene(wallpaper) || ScreenSaverVideoSource.isEligible(wallpaper) || ScreenSaverWebLoopRecorder.records(wallpaper)
    }

    nonisolated static func isScene(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    /// The status a finished job leaves: available when every video exists, not available when a
    /// page didn't load or doesn't loop smoothly, and nothing for another failure (logged by the runner).
    nonisolated static func finishedStatus(allRendered: Bool, pageDidNotLoad: Bool, doesNotLoop: Bool = false) -> Status? {
        if allRendered { return .available }
        if pageDidNotLoad { return .notAvailable(.pageDidNotLoad) }
        return doesNotLoop ? .notAvailable(.doesNotLoop) : nil
    }

    /// The properties as the helper's last argument, and back.
    nonisolated static func encodeProperties(_ properties: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: properties, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func decodeProperties(_ text: String) -> [String: String] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: String] ?? [:]
    }

    /// The store key of `wallpaper`'s videos now; nil when it isn't eligible or can't be read.
    nonisolated static func statusKey(for wallpaper: WEWallpaper, properties: [String: String]) -> StatusKey? {
        guard isEligible(wallpaper),
              let contentKey = SceneLoadingSnapshotStore.contentKey(for: wallpaper.wallpaperDirectory) else { return nil }
        return StatusKey(wallpaperKey: SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory),
                         contentKey: contentKey,
                         // A video plays as it is: its user properties don't change the file.
                         propertyHash: ScreenSaverVideoStore.propertyHash(ScreenSaverVideoSource.isEligible(wallpaper) ? [:] : properties))
    }

    /// What to show for `wallpaper`: nil while the plugin is off, or for an eligible wallpaper
    /// with no finished or pending loop.
    nonisolated static func status(for wallpaper: WEWallpaper, enabled: Bool,
                                   statuses: [StatusKey: Status]) -> Status? {
        guard enabled else { return nil }
        guard isEligible(wallpaper) else { return .notEligible }
        let wallpaperKey = SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory)
        return statuses.first { $0.key.wallpaperKey == wallpaperKey }?.value
    }

    func status(for wallpaper: WEWallpaper) -> Status? {
        Self.status(for: wallpaper, enabled: isEnabled, statuses: statuses)
    }

    /// The video names `wallpaper` needs on `screens`; empty for a video played from its own file.
    nonisolated static func targets(for wallpaper: WEWallpaper, screens: [(pixels: SIMD2<Int>, points: SIMD2<Int>)],
                        properties: [String: String]) -> [Target] {
        guard !ScreenSaverVideoSource.isEligible(wallpaper), let key = statusKey(for: wallpaper, properties: properties) else { return [] }
        let wallpaperKey = key.wallpaperKey, contentKey = key.contentKey, hash = key.propertyHash
        // One video at the largest display's backing pixels, which every display plays scaled to
        // fill: one render and one file. The scene in it is drawn as Render Resolution and
        // Upscaling draw the live wallpaper (`ScreenSaverLoopRenderer`), then fitted to the video.
        let sizes = screens.map(\.pixels)
        guard let largest = sizes.max(by: { $0.x * $0.y < $1.x * $1.y }),
              let points = screens.map(\.points).max(by: { $0.x * $0.y < $1.x * $1.y }) else { return [] }
        return [Target(pixelSize: largest, pointSize: points,
                       fileName: ScreenSaverVideoStore.fileName(wallpaperKey: wallpaperKey, contentKey: contentKey,
                                                                propertyHash: hash, pixelSize: largest),
                       properties: properties)]
    }

    /// The plugin's setting or the shown wallpapers changed: plans the loops anew
    /// (`ScreenSaverLayoutPlan`) from the observed view model (`observe(_:)`), or, before one is
    /// observed, with `wallpaper` on every display.
    func update(enabled: Bool, wallpaper: WEWallpaper?) {
        reset()
        let wasEnabled = isEnabled
        isEnabled = enabled
        let store = store, installer = installer
        guard enabled else {
            // The videos go, so a recording set as the screen saver goes with them.
            settingsStore.selection = nil
            if wasEnabled { Self.fileQueue.async { installer.uninstall(); store.removeAll() } }
            return
        }
        if !wasEnabled {
            Self.fileQueue.async {
                installer.install()
            }
        }
        // A recording set as the screen saver (or being made) plays instead; its manifest stays.
        guard recordings == 0, settingsStore.selection == nil, viewModel != nil || wallpaper != nil else { return }
        let (plan, wallpapers) = currentPlan(fallback: wallpaper)
        self.plan = plan
        let generation = generation
        Self.fileQueue.async { [weak self] in
            let work = Self.work(for: plan, wallpapers: wallpapers, store: store)
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
        guard isEnabled, recordings == 0, settingsStore.selection == nil else { return }
        guard currentPlan(fallback: nil).plan != plan else { return }
        update(enabled: true, wallpaper: nil)
    }

    /// The plan for the displays now, with each planned content's wallpaper by its id.
    private func currentPlan(fallback: WEWallpaper?) -> (plan: ScreenSaverLayoutPlan, wallpapers: [String: WEWallpaper]) {
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

    /// A loop of the plan as the manifest lists it: its file (rendered, or a video wallpaper's
    /// own) and, for a render, its size.
    struct Entry: Equatable {
        var loop: ScreenSaverLayoutPlan.Loop
        var file: String
        /// The rendered size; nil for a video wallpaper's file, whose size is known once it's
        /// prepared (`videoSizes`).
        var size: SIMD2<Int>?
        var isVideo: Bool { size == nil }
    }

    /// What a plan takes: its manifest entries, the renders (one per file) and the video
    /// wallpapers' files to link, each with its status key.
    struct Work {
        var entries: [Entry] = []
        var renders: [(key: StatusKey, target: Target, wallpaper: URL)] = []
        var videos: [(key: StatusKey, wallpaper: WEWallpaper, file: String)] = []
        /// The renders whose files exist.
        var ready: Set<String> = []
    }

    /// The plan's work: a video wallpaper's loops play its own file (cropped for a stretch, with
    /// no render); every other loop renders once at the largest of its sizes. Reads the
    /// wallpapers' content keys: never call it on the main thread.
    nonisolated static func work(for plan: ScreenSaverLayoutPlan, wallpapers: [String: WEWallpaper],
                                 store: ScreenSaverVideoStore) -> Work {
        var work = Work()
        for loop in plan.loops {
            guard let wallpaper = wallpapers[loop.content.id] else { continue }
            if ScreenSaverVideoSource.isEligible(wallpaper) {
                guard let key = statusKey(for: wallpaper, properties: [:]) else { continue }
                let file = ScreenSaverVideoSource.fileName(key: key, source: wallpaper.mediaURL)
                work.entries.append(Entry(loop: loop, file: file))
                if !work.videos.contains(where: { $0.file == file }) { work.videos.append((key, wallpaper, file)) }
                continue
            }
            let screens = loop.sizes.map { (pixels: $0.pixels, points: $0.points) }
            guard let key = statusKey(for: wallpaper, properties: loop.content.properties),
                  let target = targets(for: wallpaper, screens: screens, properties: loop.content.properties).first
            else { continue }
            work.entries.append(Entry(loop: loop, file: target.fileName, size: target.pixelSize))
            guard !work.renders.contains(where: { $0.target.fileName == target.fileName }) else { continue }
            work.renders.append((key, target, wallpaper.wallpaperDirectory))
            if store.exists(fileName: target.fileName) { work.ready.insert(target.fileName) }
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

    /// A Screen Saver mode recording starts: renders and manifest writes for the desktop's
    /// wallpaper stop (a finished one of an older generation is dropped), so none replaces it.
    func beginRecording() {
        recordings += 1
        reset()
    }

    /// The recording finished (installed or not); the plugin follows `wallpaper` again unless a
    /// recording is set as the screen saver.
    func endRecording(wallpaper: WEWallpaper?) {
        recordings = max(recordings - 1, 0)
        guard recordings == 0, settingsStore.selection == nil else { return }
        update(enabled: isEnabled, wallpaper: wallpaper)
    }

    /// Drops the current plan: its jobs stop and its late results are ignored.
    private func reset() {
        generation += 1
        jobs.forEach { $0.cancel() }
        jobs = []
        statuses = [:]
        plan = nil
        entries = []
        videoSizes = [:]
    }

    private func start(_ work: Work, generation: Int) {
        guard generation == self.generation else { return }
        entries = work.entries
        for render in work.renders {
            // A wallpaper with several videos is available once all of them are.
            let ready = work.ready.contains(render.target.fileName) && statuses[render.key] != .rendering
            statuses[render.key] = ready ? .available : .rendering
        }
        if !work.videos.isEmpty, let viewModel {
            videoRate = viewModel.playRate > 0 ? viewModel.playRate : viewModel.lastPlayRate
            observeSpeed(of: viewModel)
        }
        publishManifest(generation: generation)
        for video in work.videos { scheduleVideo(video.wallpaper, key: video.key, fileName: video.file, generation: generation) }
        let renders = work.renders.filter { !work.ready.contains($0.target.fileName) }
        guard !renders.isEmpty else { return }
        let runner = runner, store = store, all = work.renders
        // One render at a time: each is a full scene render (or page recording) and encode.
        let job = pool.submit(priority: .library) { [weak self] job in
            var pageDidNotLoad: Set<StatusKey> = []
            var doesNotLoop: Set<StatusKey> = []
            for render in renders {
                guard !job.isCancelled else { return }
                guard !store.exists(fileName: render.target.fileName) else { continue }
                let result = runner(render.wallpaper, render.target, store.url(fileName: render.target.fileName))
                if result == .pageDidNotLoad { pageDidNotLoad.insert(render.key) }
                if result == .doesNotLoop { doesNotLoop.insert(render.key) }
                guard result == .rendered else { continue }
                Task { @MainActor in self?.publishManifest(generation: generation) }
            }
            var finished: [StatusKey: Status?] = [:]
            for key in Set(renders.map(\.key)) {
                let files = all.filter { $0.key == key }.map(\.target.fileName)
                finished[key] = Self.finishedStatus(allRendered: files.allSatisfy { store.exists(fileName: $0) },
                                                    pageDidNotLoad: pageDidNotLoad.contains(key),
                                                    doesNotLoop: doesNotLoop.contains(key))
            }
            let statuses = finished
            Task { @MainActor in self?.finish(statuses, generation: generation) }
        }
        jobs.append(job)
    }

    /// A video wallpaper: links (or repairs) its file into the store; the manifest lists its
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
            let outcome: ScreenSaverVideoSource.Outcome = store.exists(fileName: fileName)
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
        if entries.contains(where: \.isVideo) { publishManifest(generation: generation) }
    }

    private func setStatus(_ status: Status, for key: StatusKey, generation: Int) {
        guard generation == self.generation else { return }
        statuses[key] = status
    }

    private func finish(_ finished: [StatusKey: Status?], generation: Int) {
        guard generation == self.generation else { return }
        for (key, status) in finished { statuses[key] = status }
    }

    /// Lists the plan's loops whose files exist in the manifest and removes every other video.
    private func publishManifest(generation: Int) {
        guard generation == self.generation else { return }
        let store = store, entries = entries, videoSizes = videoSizes, rate = videoRate
        let everyDisplay = Set(plan?.displays ?? [])
        Self.fileQueue.async {
            var videos: [ScreenSaverManifest.Video] = []
            for entry in entries {
                guard let size = entry.size ?? videoSizes[entry.file], store.exists(fileName: entry.file) else { continue }
                videos += Self.manifestVideos(for: entry.loop, file: entry.file, size: size, rate: entry.isVideo ? rate : nil,
                                              everyDisplay: everyDisplay.isSubset(of: entry.loop.displays))
            }
            do { try store.writeManifest(ScreenSaverManifest(videos: videos)) } catch {
                OWELog.error(.app, "Screen saver: can't write the manifest: \(error)")
            }
            store.retain(Set(entries.map(\.file)))
        }
    }

    /// Runs this app's executable with `--render-screensaver-loop`, in this process's isolated
    /// state, at background priority, and waits for it.
    nonisolated static func runHelper(_ wallpaper: URL, _ target: Target, _ output: URL) -> RunResult {
        guard let executable = AppRelauncher.helperExecutable else { return .failed }
        let process = Process()
        process.executableURL = executable
        process.arguments = [ShaderPrewarmCommand.screenSaverArgument, wallpaper.path(percentEncoded: false),
                             "\(target.pixelSize.x)x\(target.pixelSize.y)", "\(target.pointSize.x)x\(target.pointSize.y)",
                             output.path(percentEncoded: false), encodeProperties(target.properties)]
            + (target.isRecording ? [ShaderPrewarmCommand.screenSaverRecordingArgument] : [])
        var environment = ProcessInfo.processInfo.environment
        if let tag = AppStorageLocation.current.isolationTag { environment[AppStorageLocation.environmentKey] = tag }
        process.environment = environment
        process.qualityOfService = .background
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            OWELog.error(.app, "Screen saver: can't start the loop render: \(error)")
            return .failed
        }
        process.waitUntilExit()
        if process.terminationStatus == ShaderPrewarmCommand.pageDidNotLoadStatus {
            OWELog.error(.app, "Screen saver: \(wallpaper.lastPathComponent)'s page didn't load for its loop")
            return .pageDidNotLoad
        }
        if process.terminationStatus == ShaderPrewarmCommand.doesNotLoopStatus {
            OWELog.error(.app, "Screen saver: \(wallpaper.lastPathComponent)'s page doesn't loop smoothly")
            return .doesNotLoop
        }
        guard process.terminationStatus == 0 else {
            OWELog.error(.app, "Screen saver: the loop render of \(wallpaper.lastPathComponent) failed (\(process.terminationStatus))")
            return .failed
        }
        return .rendered
    }
}
