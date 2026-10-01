import AppKit

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
final class ScreenSaverPlugin {
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
    private var enabled = false
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

    /// The video names `wallpaper` needs on `screens`; empty for anything but a scene.
    nonisolated static func targets(for wallpaper: WEWallpaper, screens: [(pixels: SIMD2<Int>, points: SIMD2<Int>)],
                        properties: [String: String]) -> [Target] {
        guard wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame,
              let contentKey = SceneLoadingSnapshotStore.contentKey(for: wallpaper.wallpaperDirectory) else { return [] }
        let wallpaperKey = SceneLoadingSnapshotStore.wallpaperKey(for: wallpaper.wallpaperDirectory)
        let hash = ScreenSaverVideoStore.propertyHash(properties)
        var seen = Set<SIMD2<Int>>()
        return screens.compactMap { screen in
            guard seen.insert(screen.pixels).inserted else { return nil }
            return Target(pixelSize: screen.pixels, pointSize: screen.points,
                          fileName: ScreenSaverVideoStore.fileName(wallpaperKey: wallpaperKey, contentKey: contentKey,
                                                                   propertyHash: hash, pixelSize: screen.pixels))
        }
    }

    /// The plugin's setting or the shown wallpaper changed.
    func update(enabled: Bool, wallpaper: WEWallpaper?) {
        generation += 1
        jobs.forEach { $0.cancel() }
        jobs = []
        let wasEnabled = self.enabled
        self.enabled = enabled
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
            Task { @MainActor in self?.schedule(targets, wallpaper: directory, generation: generation) }
        }
    }

    private func schedule(_ targets: [Target], wallpaper: URL, generation: Int) {
        guard generation == self.generation else { return }
        publish(targets, generation: generation)
        let runner = runner, store = store
        for target in targets {
            let job = pool.submit(priority: .library) { [weak self] job in
                guard !job.isCancelled, !store.exists(fileName: target.fileName) else { return }
                let output = store.url(fileName: target.fileName)
                guard runner(wallpaper, target, output) else { return }
                Task { @MainActor in self?.publish(targets, generation: generation) }
            }
            jobs.append(job)
        }
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
