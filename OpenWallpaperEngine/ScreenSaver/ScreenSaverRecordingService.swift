import AppKit

/// Makes and sets the Screen Saver mode's recordings: a scene's version (the mode's values,
/// `ScreenSaverSettingsStore`) recorded as a seamless loop (`ScreenSaverRecorder`) at the size the
/// screen saver plugin would render (`ScreenSaverPlugin.targets`), installed as the screen saver's
/// video and kept as the selection, which the plugin then plays instead of a loop of the desktop's
/// wallpaper. The mode records by hand; the daily schedule (`ScreenSaverDailyScheduler`) records
/// the selection again.
@MainActor
final class ScreenSaverRecordingService: ObservableObject {
    /// What a recording needs from the app: the displays, whether the screen saver plugin is on,
    /// and the desktop's wallpaper.
    struct Environment {
        var screens: @MainActor () -> [(pixels: SIMD2<Int>, points: SIMD2<Int>)]
        var isPluginEnabled: @MainActor () -> Bool
        /// Turns Settings › Plugins › Screen Saver on (it installs the saver).
        var enablePlugin: @MainActor () -> Void
        var desktopWallpaper: @MainActor () -> WEWallpaper?
    }

    @Published private(set) var isRecording = false
    let store: ScreenSaverSettingsStore
    private let recorder: ScreenSaverRecorder
    private let plugin: ScreenSaverPlugin
    private let environment: Environment
    private let videos: ScreenSaverVideoStore

    init(plugin: ScreenSaverPlugin, environment: Environment, store: ScreenSaverSettingsStore = ScreenSaverSettingsStore(),
         recorder: ScreenSaverRecorder = .current, videos: ScreenSaverVideoStore = .current) {
        self.plugin = plugin
        self.environment = environment
        self.store = store
        self.recorder = recorder
        self.videos = videos
    }

    /// The recording set as the screen saver, if any.
    var selection: ScreenSaverSettingsStore.Selection? { store.selection }

    /// Whether `wallpaper`'s recording is the screen saver.
    func isSelected(_ wallpaper: WEWallpaper) -> Bool {
        selection?.wallpaperDirectory == wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false)
    }

    /// The video of `wallpaper`'s recording, when it is the screen saver and the file exists.
    func recordedVideo(of wallpaper: WEWallpaper) -> URL? {
        guard isSelected(wallpaper), let selection, videos.exists(fileName: selection.fileName) else { return nil }
        return videos.url(fileName: selection.fileName)
    }

    /// Records `wallpaper` with `values` and sets it as the screen saver (turning the plugin on
    /// when it is off). `background` runs the render at background priority (the schedule); by
    /// hand it runs at user-initiated priority. `completion` gets whether it was set.
    func record(_ wallpaper: WEWallpaper, values: [String: String], background: Bool,
                completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isRecording else {
            OWELog.info(.app, "Screen saver: a recording is already running; \(wallpaper.wallpaperDirectory.lastPathComponent) waits for the next")
            completion(false)
            return
        }
        guard var target = ScreenSaverPlugin.targets(for: wallpaper, screens: environment.screens(), properties: values).first else {
            OWELog.error(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) can't be recorded (not a readable scene, or no display)")
            completion(false)
            return
        }
        let started = Date()
        target.isRecording = true
        target.fileName = ScreenSaverVideoStore.recordedFileName(target.fileName, at: started)
        isRecording = true
        plugin.beginRecording()
        let recorder = recorder, folder = wallpaper.wallpaperDirectory, recorded = target
        OWELog.info(.app, "Screen saver: recording \(folder.lastPathComponent) at \(target.pixelSize.x)×\(target.pixelSize.y)\(background ? " (daily schedule)" : "")")
        let queue = DispatchQueue.global(qos: background ? .background : .userInitiated)
        Task { [weak self] in
            // The render blocks its thread for minutes: a dispatch queue's, not the cooperative pool's.
            let succeeded = await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: recorder.record(wallpaper: folder, target: recorded)) }
            }
            self?.finish(wallpaper, values: values, target: recorded, started: started, succeeded: succeeded)
            completion(succeeded)
        }
    }

    /// Sets a video wallpaper's own video as the screen saver (turning the plugin on when it is
    /// off): nothing is rendered, the file goes in as the desktop's video does
    /// (`ScreenSaverVideoSource.prepare`: linked, or repaired), and becomes the selection.
    /// `completion` gets whether it was set.
    func useVideo(_ wallpaper: WEWallpaper, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isRecording else {
            completion(false)
            return
        }
        guard ScreenSaverVideoSource.isEligible(wallpaper),
              let key = ScreenSaverPlugin.statusKey(for: wallpaper, properties: [:]) else {
            OWELog.error(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) isn't a video the screen saver plays")
            completion(false)
            return
        }
        let started = Date()
        let source = wallpaper.mediaURL
        let loopName = ScreenSaverVideoSource.fileName(key: key, source: source)
        let fileName = "\((loopName as NSString).deletingPathExtension)-rec\(Int(started.timeIntervalSince1970)).\(source.pathExtension.lowercased())"
        let videos = videos
        isRecording = true
        plugin.beginRecording()
        OWELog.info(.app, "Screen saver: setting \(wallpaper.wallpaperDirectory.lastPathComponent)'s video")
        Task { [weak self] in
            let size: SIMD2<Int>? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.installVideo(source, as: fileName, in: videos))
                }
            }
            self?.finish(wallpaper, fileName: fileName, size: size ?? .zero, started: started, succeeded: size != nil)
            completion(size != nil)
        }
    }

    /// Puts `source` in the saver's folder as `fileName` and lists it alone; its display size,
    /// or nil when it can't. Blocking file IO.
    nonisolated private static func installVideo(_ source: URL, as fileName: String, in videos: ScreenSaverVideoStore) -> SIMD2<Int>? {
        let staging = videos.url(fileName: ".staging-\(UUID().uuidString).\(source.pathExtension.lowercased())")
        guard case .ready = ScreenSaverVideoSource.prepare(source, at: staging) else { return nil }
        guard let size = ScreenSaverVideoSource.displaySize(of: staging) else {
            try? FileManager.default.removeItem(at: staging) // Optional: the staging copy of a failed install.
            return nil
        }
        do {
            try videos.install(staging, as: fileName, pixelSize: size)
            return size
        } catch {
            OWELog.error(.app, "Screen saver: can't install \(source.lastPathComponent): \(error)")
            return nil
        }
    }

    private func finish(_ wallpaper: WEWallpaper, values: [String: String], target: ScreenSaverPlugin.Target,
                        started: Date, succeeded: Bool) {
        if succeeded { store.setValues(values, for: WallpaperSettingsIdentity.resolve(wallpaper, defaults: store.defaults)) }
        finish(wallpaper, fileName: target.fileName, size: target.pixelSize, started: started, succeeded: succeeded)
    }

    private func finish(_ wallpaper: WEWallpaper, fileName: String, size: SIMD2<Int>, started: Date, succeeded: Bool) {
        isRecording = false
        if succeeded {
            store.selection = ScreenSaverSettingsStore.Selection(
                wallpaperDirectory: wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false),
                fileName: fileName, width: size.x, height: size.y, recorded: started)
            if !environment.isPluginEnabled() { environment.enablePlugin() }
        }
        plugin.endRecording(wallpaper: environment.desktopWallpaper())
        objectWillChange.send()
    }

    /// Records the selected wallpaper again with its saved values (the daily schedule); false when
    /// nothing is set as the screen saver, it can't be found, or a recording is running.
    @discardableResult
    func recordSelection(background: Bool, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> Bool {
        guard !isRecording, let selection else { return false }
        let folder = URL(filePath: selection.wallpaperDirectory, directoryHint: .isDirectory)
        guard let wallpaper = InstalledLibrary.wallpaper(at: folder, hiding: []) else {
            OWELog.error(.app, "Screen saver: \(folder.lastPathComponent), set as the screen saver, is no longer in the library")
            return false
        }
        // A video is its own screen saver: linked again, as it is.
        if ScreenSaverVideoSource.isEligible(wallpaper) {
            useVideo(wallpaper, completion: completion)
            return true
        }
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: store.defaults)
        let values = store.values(for: identity) ?? IsolatedSceneEditSession.seed(of: wallpaper, from: [.shared], defaults: store.defaults)
        record(wallpaper, values: values, background: background, completion: completion)
        return true
    }

    /// Goes back to the plugin's loop of the desktop's wallpaper (its render replaces the recording).
    func stopUsingSelection() {
        guard store.selection != nil else { return }
        store.selection = nil
        OWELog.info(.app, "Screen saver: back to the desktop's wallpaper")
        plugin.update(enabled: environment.isPluginEnabled(), wallpaper: environment.desktopWallpaper())
        objectWillChange.send()
    }
}
