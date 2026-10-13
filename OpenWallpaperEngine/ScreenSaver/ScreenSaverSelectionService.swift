import AppKit

/// What is set as the screen saver, from Scene Edit / Export's Screen Saver mode, the library's
/// and Workshop's Set as Screen Saver, and MCP: a wallpaper picked to be drawn live with the
/// mode's values (`pick`, `ScreenSaverSettingsStore.livePick`), or a video wallpaper's own file
/// (`useVideo`, `ScreenSaverSettingsStore.selection`), which the plugin then plays instead of
/// following the desktop. Nothing is recorded.
@MainActor
final class ScreenSaverSelectionService: ObservableObject {
    /// What setting the screen saver needs from the app: whether the screen saver plugin is on,
    /// and the desktop's wallpaper.
    struct Environment {
        var isPluginEnabled: @MainActor () -> Bool
        /// Turns Settings › Plugins › Screen Saver on (it installs the saver).
        var enablePlugin: @MainActor () -> Void
        var desktopWallpaper: @MainActor () -> WEWallpaper?
    }

    /// A video wallpaper's file is being put in place (`useVideo`).
    @Published private(set) var isSettingVideo = false
    /// The video wallpaper whose file is being put in place, for its Details panel.
    @Published private(set) var settingVideo: String?
    /// A web wallpaper or WebM video Set as Screen Saver was chosen for without the Chromium
    /// engine: the main window offers to install it (`setAsScreenSaver`).
    @Published var chromiumOffer: WEWallpaper?
    let store: ScreenSaverSettingsStore
    private let plugin: ScreenSaverPlugin
    private let environment: Environment
    private let videos: ScreenSaverVideoStore

    init(plugin: ScreenSaverPlugin, environment: Environment, store: ScreenSaverSettingsStore = ScreenSaverSettingsStore(),
         videos: ScreenSaverVideoStore = .current) {
        self.plugin = plugin
        self.environment = environment
        self.store = store
        self.videos = videos
    }

    /// The video wallpaper whose own file is the screen saver, if any.
    var selection: ScreenSaverSettingsStore.Selection? { store.selection }

    /// The wallpaper picked as the screen saver, drawn live, if any.
    var livePick: ScreenSaverSettingsStore.LivePick? { store.livePick }

    /// Where the picked wallpaper's still goes; nil in a copy that never installs the saver.
    var stills: ScreenSaverStillPublisher?
    /// A new wallpaper was picked: its still is made now (`ScreenSaverLiveController.renderPickStill`).
    var onPicked: ((WEWallpaper) -> Void)?

    /// Whether `wallpaper`'s video is being put in place as the screen saver (`useVideo`).
    func isSetting(_ wallpaper: WEWallpaper) -> Bool {
        settingVideo == wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false)
    }

    /// Whether `wallpaper` is the screen saver: picked, or its video set.
    func isSelected(_ wallpaper: WEWallpaper) -> Bool {
        let folder = wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false)
        return selection?.wallpaperDirectory == folder || livePick?.wallpaperDirectory == folder
    }

    /// Makes `wallpaper` the screen saver, drawn live with `values` (its user properties and
    /// layer edits), which become the screen saver's own choices for it; turns the plugin on when
    /// it is off. Nothing is recorded. Its preview is the still until the live draw keeps a frame.
    func pick(_ wallpaper: WEWallpaper, values: [String: String]) {
        let folder = wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false)
        store.setValues(values, for: WallpaperSettingsIdentity.resolve(wallpaper, defaults: store.defaults))
        let isNew = store.livePick?.wallpaperDirectory != folder
        store.livePick = ScreenSaverSettingsStore.LivePick(wallpaperDirectory: folder, picked: Date())
        store.selection = nil
        if isNew { onPicked?(wallpaper) }
        OWELog.info(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) is the screen saver, drawn live")
        if !environment.isPluginEnabled() { environment.enablePlugin() }
        plugin.update(enabled: environment.isPluginEnabled(), wallpaper: environment.desktopWallpaper())
        objectWillChange.send()
    }

    /// Sets `wallpaper` as the screen saver with `values` (the Screen Saver mode's, else the
    /// wallpaper's): a video's own file (`useVideo`), anything else picked to be drawn live
    /// (`pick`). `completion` gets whether it was set.
    func set(_ wallpaper: WEWallpaper, values: [String: String], completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        if ScreenSaverVideoSource.isEligible(wallpaper) {
            useVideo(wallpaper, completion: completion)
            return
        }
        pick(wallpaper, values: values)
        completion(true)
    }

    /// Sets a video wallpaper's own video as the screen saver (turning the plugin on when it is
    /// off): nothing is rendered, the file goes in as the desktop's video does
    /// (`ScreenSaverVideoSource.prepare`: linked, copied, or repaired), and becomes the selection.
    /// `completion` gets whether it was set.
    func useVideo(_ wallpaper: WEWallpaper, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isSettingVideo else {
            completion(false)
            return
        }
        guard ScreenSaverVideoSource.isEligible(wallpaper),
              let key = ScreenSaverPlugin.statusKey(for: wallpaper) else {
            OWELog.error(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) isn't a video the screen saver plays")
            completion(false)
            return
        }
        let started = Date()
        let source = wallpaper.mediaURL
        let loopName = ScreenSaverVideoSource.fileName(key: key, source: source)
        let fileName = "\((loopName as NSString).deletingPathExtension)-rec\(Int(started.timeIntervalSince1970)).\(source.pathExtension.lowercased())"
        let videos = videos
        isSettingVideo = true
        settingVideo = wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false)
        plugin.beginSettingVideo()
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

    /// `wallpaper`'s video, set as the screen saver, is a symbolic link an earlier version made
    /// (its library is on another volume), which the saver can't follow: it is set again, so it
    /// is copied in (`ScreenSaverVideoSource.prepare`). Returns whether it was.
    @discardableResult
    func replaceLinkedSelection(_ wallpaper: WEWallpaper) -> Bool {
        guard let selection, selection.wallpaperDirectory == wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false),
              !ScreenSaverVideoSource.isInPlace(videos.url(fileName: selection.fileName)) else { return false }
        OWELog.info(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent)'s video isn't in the screen saver's folder; setting it again")
        useVideo(wallpaper)
        return true
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

    private func finish(_ wallpaper: WEWallpaper, fileName: String, size: SIMD2<Int>, started: Date, succeeded: Bool) {
        isSettingVideo = false
        settingVideo = nil
        if succeeded {
            if store.livePick != nil {
                store.livePick = nil
                stills?.clearPick()
            }
            store.selection = ScreenSaverSettingsStore.Selection(
                wallpaperDirectory: wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false),
                fileName: fileName, width: size.x, height: size.y, recorded: started)
            if !environment.isPluginEnabled() { environment.enablePlugin() }
        }
        plugin.endSettingVideo(wallpaper: environment.desktopWallpaper())
        objectWillChange.send()
    }

    /// Goes back to the desktop's wallpapers.
    func stopUsingSelection() {
        guard store.selection != nil || store.livePick != nil else { return }
        store.selection = nil
        if store.livePick != nil {
            store.livePick = nil
            stills?.clearPick()
        }
        OWELog.info(.app, "Screen saver: back to the desktop's wallpaper")
        plugin.update(enabled: environment.isPluginEnabled(), wallpaper: environment.desktopWallpaper())
        objectWillChange.send()
    }
}
