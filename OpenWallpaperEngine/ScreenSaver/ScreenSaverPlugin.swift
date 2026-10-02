import AppKit
import Combine

/// Settings › Plugins › Screen Saver. While on, the current scene wallpaper's loop video is
/// rendered for each display size (`ScreenSaverLoopRenderer`, in the app's helper run) and the
/// bundled saver plays it; off stops rendering and removes the saver and the videos.
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
        /// A render job for it is queued or running.
        case rendering
        /// Not a wallpaper loops are made from (`isEligible`).
        case notEligible
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
    }

    typealias Runner = @Sendable (_ wallpaper: URL, _ target: Target, _ output: URL) -> Bool

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

    /// Whether loops are made from `wallpaper`: valid scene wallpapers only. `targets(for:)` and
    /// the Details pane both ask this.
    nonisolated static func isEligible(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project != .invalid && wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    /// The store key of `wallpaper`'s videos now; nil when it isn't eligible or can't be read.
    nonisolated static func statusKey(for wallpaper: WEWallpaper, properties: [String: String]) -> StatusKey? {
        guard isEligible(wallpaper),
              let contentKey = SceneLoadingSnapshotStore.contentKey(for: wallpaper.wallpaperDirectory) else { return nil }
        return StatusKey(wallpaperKey: SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory),
                         contentKey: contentKey, propertyHash: ScreenSaverVideoStore.propertyHash(properties))
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

    /// The video names `wallpaper` needs on `screens`; empty for anything but a scene.
    nonisolated static func targets(for wallpaper: WEWallpaper, screens: [(pixels: SIMD2<Int>, points: SIMD2<Int>)],
                        properties: [String: String]) -> [Target] {
        guard let key = statusKey(for: wallpaper, properties: properties) else { return [] }
        let wallpaperKey = key.wallpaperKey, contentKey = key.contentKey, hash = key.propertyHash
        // One video at the largest display's size in points (what the desktop looks like, e.g.
        // 1920×1080 on a 4K panel at 2×), which every display plays scaled to fill: one render
        // and one file, and rendering backing pixels would cost several times as much for no
        // visible gain.
        guard let largest = screens.map(\.points).max(by: { $0.x * $0.y < $1.x * $1.y }) else { return [] }
        return [Target(pixelSize: largest, pointSize: largest,
                       fileName: ScreenSaverVideoStore.fileName(wallpaperKey: wallpaperKey, contentKey: contentKey,
                                                                propertyHash: hash, pixelSize: largest))]
    }

    /// The plugin's setting or the shown wallpaper changed.
    func update(enabled: Bool, wallpaper: WEWallpaper?) {
        generation += 1
        jobs.forEach { $0.cancel() }
        jobs = []
        statuses = [:]
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
            wallpaper: WallpaperPropertyScope.shared.runtimeKey(directory: wallpaper.wallpaperDirectory))
        let generation = generation
        let directory = wallpaper.wallpaperDirectory
        Self.fileQueue.async { [weak self] in
            let targets = Self.targets(for: wallpaper, screens: screens, properties: properties)
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
        // One render at a time: each is a full scene render and encode.
        let job = pool.submit(priority: .library) { [weak self] job in
            for target in targets {
                guard !job.isCancelled else { return }
                guard !store.exists(fileName: target.fileName) else { continue }
                let output = store.url(fileName: target.fileName)
                guard runner(wallpaper, target, output) else { continue }
                Task { @MainActor in self?.publish(targets, generation: generation) }
            }
            // Done: available if every video exists, otherwise a render failed (logged by the
            // runner) and there is nothing to show.
            let finished = targets.allSatisfy { store.exists(fileName: $0.fileName) }
            Task { @MainActor in self?.finish(key, available: finished, generation: generation) }
        }
        jobs.append(job)
    }

    private func finish(_ key: StatusKey?, available: Bool, generation: Int) {
        guard generation == self.generation, let key else { return }
        statuses = available ? [key: .available] : [:]
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
    nonisolated static func runHelper(_ wallpaper: URL, _ target: Target, _ output: URL) -> Bool {
        guard let executable = AppRelauncher.helperExecutable else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = [ShaderPrewarmCommand.screenSaverArgument, wallpaper.path(percentEncoded: false),
                             "\(target.pixelSize.x)x\(target.pixelSize.y)", "\(target.pointSize.x)x\(target.pointSize.y)",
                             output.path(percentEncoded: false)]
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
            return false
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            OWELog.error(.app, "Screen saver: the loop render of \(wallpaper.lastPathComponent) failed (\(process.terminationStatus))")
            return false
        }
        return true
    }
}
