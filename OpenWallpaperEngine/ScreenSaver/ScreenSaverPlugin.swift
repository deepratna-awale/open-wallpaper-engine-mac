import AppKit
import Combine

/// Settings › Plugins › Screen Saver. While on, the current wallpaper's loop video is rendered for
/// each display size (`ScreenSaverLoopRenderer` for a scene, `ScreenSaverWebLoopRecorder` for a
/// web wallpaper or WebM video, in the app's helper run) and the bundled saver plays it; a video
/// wallpaper AVFoundation plays has its own file linked (or repaired) for the saver instead, with
/// no render (`ScreenSaverVideoSource`). Off stops rendering and removes the saver and the videos.
///
/// - Renders run as `.library` jobs on the `PreparationPool`, so they wait while the power policy
///   says no (battery, heat), one at a time, each in a helper process at background priority.
/// - Videos are keyed by wallpaper, user properties and display size (`ScreenSaverVideoStore`); a
///   change renders the new key and the manifest moves to it once it exists.
/// - Only the user's own copy installs the saver and writes where it reads
///   (`ScreenSaverInstaller.mayInstall`, `ScreenSaverVideoStore`'s isolated folder).
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
    }

    /// How one helper run ended.
    enum RunResult: Equatable {
        case rendered
        case failed
        case pageDidNotLoad
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
        /// The user properties a web page is recorded with (scenes read their own).
        var properties: [String: String] = [:]
    }

    typealias Runner = @Sendable (_ wallpaper: URL, _ target: Target, _ output: URL) -> RunResult

    private let pool: PreparationPool
    private let store: ScreenSaverVideoStore
    private let installer: ScreenSaverInstaller
    private let runner: Runner
    @Published private(set) var isEnabled = false
    /// The shown wallpaper's status, for its current content and properties only; a failed or
    /// cancelled render leaves no entry.
    @Published private(set) var statuses: [StatusKey: Status] = [:]
    /// Bumped on every change: a finished render for an older one doesn't touch the manifest.
    private var generation = 0
    private var jobs: [PreparationPool.Job] = []
    /// The shown video wallpaper's manifest entry, rewritten when its playback speed changes.
    private var currentVideo: (fileName: String, size: SIMD2<Int>, rate: Float)?
    private var rateSubscription: AnyCancellable?
    private static let fileQueue = DispatchQueue(label: "OWE.ScreenSaverPlugin", qos: .utility)

    init(pool: PreparationPool = .shared, store: ScreenSaverVideoStore = .current,
         installer: ScreenSaverInstaller = .current, runner: @escaping Runner = { ScreenSaverPlugin.runHelper($0, $1, $2) }) {
        self.pool = pool
        self.store = store
        self.installer = installer
        self.runner = runner
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
    /// page didn't load, and nothing for another failure (logged by the runner).
    nonisolated static func finishedStatus(allRendered: Bool, pageDidNotLoad: Bool) -> Status? {
        if allRendered { return .available }
        return pageDidNotLoad ? .notAvailable(.pageDidNotLoad) : nil
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
                        properties: [String: String], resolution: GSRenderResolution = .display) -> [Target] {
        guard !ScreenSaverVideoSource.isEligible(wallpaper), let key = statusKey(for: wallpaper, properties: properties) else { return [] }
        let wallpaperKey = key.wallpaperKey, contentKey = key.contentKey, hash = key.propertyHash
        // One video at the largest display's size, which every display plays scaled to fill: one
        // render and one file. Its sharpness follows Render Resolution like the live wallpaper:
        // Display renders the size in points (1920×1080 on a 4K panel at 2×); Retina and Full
        // render the backing pixels, at several times the render time and storage.
        let sizes = screens.map { resolution == .display ? $0.points : $0.pixels }
        guard let largest = sizes.max(by: { $0.x * $0.y < $1.x * $1.y }),
              let points = screens.map(\.points).max(by: { $0.x * $0.y < $1.x * $1.y }) else { return [] }
        return [Target(pixelSize: largest, pointSize: points,
                       fileName: ScreenSaverVideoStore.fileName(wallpaperKey: wallpaperKey, contentKey: contentKey,
                                                                propertyHash: hash, pixelSize: largest),
                       properties: properties)]
    }

    /// The plugin's setting or the shown wallpaper changed.
    func update(enabled: Bool, wallpaper: WEWallpaper?) {
        generation += 1
        jobs.forEach { $0.cancel() }
        jobs = []
        statuses = [:]
        currentVideo = nil
        let wasEnabled = isEnabled
        isEnabled = enabled
        let store = store, installer = installer
        guard enabled else {
            if wasEnabled { Self.fileQueue.async { installer.uninstall(); store.removeAll() } }
            return
        }
        if !wasEnabled {
            Self.fileQueue.async {
                installer.install()
            }
        }
        guard let wallpaper else { return }
        let screens = NSScreen.screens.map { screen in
            (pixels: SIMD2(Int(screen.frame.width * screen.backingScaleFactor), Int(screen.frame.height * screen.backingScaleFactor)),
             points: SIMD2(Int(screen.frame.width), Int(screen.frame.height)))
        }
        let properties = WallpaperServices.shared.userProperties(
            wallpaper: WallpaperPropertyScope.shared.runtimeKey(directory: wallpaper.settingsDirectory))
        let generation = generation
        let directory = wallpaper.wallpaperDirectory
        let resolution = AppDelegate.shared.globalSettingsViewModel.settings.renderResolution
        if ScreenSaverVideoSource.isEligible(wallpaper) {
            let viewModel = AppDelegate.shared.wallpaperViewModel
            let speed = viewModel.playRate > 0 ? viewModel.playRate : viewModel.lastPlayRate
            observeSpeed(of: viewModel)
            scheduleVideo(wallpaper, rate: speed, generation: generation)
            return
        }
        Self.fileQueue.async { [weak self] in
            let targets = Self.targets(for: wallpaper, screens: screens, properties: properties, resolution: resolution)
            let key = Self.statusKey(for: wallpaper, properties: properties)
            let ready = targets.allSatisfy { store.exists(fileName: $0.fileName) }
            Task { @MainActor in
                self?.schedule(targets, key: key, ready: ready, wallpaper: directory, generation: generation)
            }
        }
    }

    private func schedule(_ targets: [Target], key: StatusKey?, ready: Bool, wallpaper: URL, generation: Int) {
        guard generation == self.generation else { return }
        if let key, !targets.isEmpty { statuses = [key: ready ? .available : .rendering] }
        publish(targets, generation: generation)
        let runner = runner, store = store
        // One render at a time: each is a full scene render (or page recording) and encode.
        let job = pool.submit(priority: .library) { [weak self] job in
            var pageDidNotLoad = false
            for target in targets {
                guard !job.isCancelled else { return }
                guard !store.exists(fileName: target.fileName) else { continue }
                let output = store.url(fileName: target.fileName)
                let result = runner(wallpaper, target, output)
                if result == .pageDidNotLoad { pageDidNotLoad = true }
                guard result == .rendered else { continue }
                Task { @MainActor in self?.publish(targets, generation: generation) }
            }
            let status = Self.finishedStatus(allRendered: targets.allSatisfy { store.exists(fileName: $0.fileName) },
                                             pageDidNotLoad: pageDidNotLoad)
            Task { @MainActor in self?.finish(key, status: status, generation: generation) }
        }
        jobs.append(job)
    }

    /// A video wallpaper: links (or repairs) its file into the store and lists it in the manifest
    /// at its video track's size, played at `rate`.
    private func scheduleVideo(_ wallpaper: WEWallpaper, rate: Float, generation: Int) {
        let store = store
        Self.fileQueue.async { [weak self] in
            guard let key = Self.statusKey(for: wallpaper, properties: [:]) else { return }
            let source = wallpaper.mediaURL
            // The codec first (cached per file version): an unsupported one says so at once.
            guard ScreenSaverVideoSource.hasPlayableTrack(source) else {
                Task { @MainActor in
                    guard let self, generation == self.generation else { return }
                    self.statuses = [key: .notEligible]
                    self.publishVideoManifest(ScreenSaverManifest())
                }
                return
            }
            let fileName = ScreenSaverVideoSource.fileName(key: key, source: source)
            let destination = store.url(fileName: fileName)
            let outcome: ScreenSaverVideoSource.Outcome = store.exists(fileName: fileName)
                ? .ready(repaired: false)
                : ScreenSaverVideoSource.prepare(source, at: destination) {
                    Task { @MainActor in self?.setStatus(.rendering, for: key, generation: generation) }
                }
            let size: SIMD2<Int>? = if case .ready = outcome { ScreenSaverVideoSource.displaySize(of: destination) } else { nil }
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                let manifest: ScreenSaverManifest
                switch (outcome, size) {
                case (.unsupported, _):
                    self.statuses = [key: .notEligible]
                    manifest = ScreenSaverManifest()
                case (.ready, let size?):
                    self.statuses = [key: .available]
                    self.currentVideo = (fileName, size, rate)
                    manifest = Self.videoManifest(fileName: fileName, size: size, rate: rate)
                default:
                    self.statuses = [:]
                    manifest = ScreenSaverManifest()
                }
                self.publishVideoManifest(manifest)
            }
        }
    }

    private func publishVideoManifest(_ manifest: ScreenSaverManifest) {
        let store = store
        Self.fileQueue.async {
            do { try store.writeManifest(manifest) } catch {
                OWELog.error(.app, "Screen saver: can't write the manifest: \(error)")
            }
            store.retain(Set(manifest.videos.map(\.file)))
        }
    }

    /// Follows the playback speed: a settled change (pause excluded) rewrites the shown video's
    /// manifest entry. Nothing is rendered or linked again.
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
        guard isEnabled, var video = currentVideo, abs(video.rate - rate) > 0.001 else { return }
        video.rate = rate
        currentVideo = video
        publishVideoManifest(Self.videoManifest(fileName: video.fileName, size: video.size, rate: rate))
    }

    /// The manifest for a video wallpaper: one entry at its track's size, with the playback speed
    /// when it isn't 1 (the saver is always muted and always loops).
    nonisolated static func videoManifest(fileName: String, size: SIMD2<Int>, rate: Float) -> ScreenSaverManifest {
        let rate: Float? = rate > 0 && abs(rate - 1) > 0.001 ? rate : nil
        return ScreenSaverManifest(videos: [ScreenSaverManifest.Video(file: fileName, width: size.x, height: size.y, rate: rate)])
    }

    private func setStatus(_ status: Status, for key: StatusKey, generation: Int) {
        guard generation == self.generation else { return }
        statuses = [key: status]
    }

    private func finish(_ key: StatusKey?, status: Status?, generation: Int) {
        guard generation == self.generation, let key else { return }
        statuses = status.map { [key: $0] } ?? [:]
    }

    /// Lists the targets' videos that exist in the manifest and removes every other video.
    private func publish(_ targets: [Target], generation: Int) {
        guard generation == self.generation else { return }
        let store = store
        Self.fileQueue.async {
            let ready = targets.filter { store.exists(fileName: $0.fileName) }
            let manifest = ScreenSaverManifest(videos: ready.map {
                ScreenSaverManifest.Video(file: $0.fileName, width: $0.pixelSize.x, height: $0.pixelSize.y)
            })
            do { try store.writeManifest(manifest) } catch {
                OWELog.error(.app, "Screen saver: can't write the manifest: \(error)")
            }
            store.retain(Set(targets.map(\.fileName)))
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
        guard process.terminationStatus == 0 else {
            OWELog.error(.app, "Screen saver: the loop render of \(wallpaper.lastPathComponent) failed (\(process.terminationStatus))")
            return .failed
        }
        return .rendered
    }
}
