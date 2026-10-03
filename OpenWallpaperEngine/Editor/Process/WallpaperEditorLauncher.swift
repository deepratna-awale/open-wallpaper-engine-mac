import AppKit

extension AppDelegate {
    /// Opens `wallpaper` in the Wallpaper Editor (docs/editor-plan.md), which runs as its own
    /// process: quitting Open Wallpaper Engine leaves it open, and closing it leaves the app as it
    /// was. Scene wallpapers only.
    func showWallpaperEditor(for wallpaper: WEWallpaper) {
        guard WallpaperEditorController.canEdit(wallpaper) else { return }
        wallpaperEditorLauncher.open(wallpaper.settingsDirectory)
    }
}

/// Open Wallpaper Engine's side of the Wallpaper Editor's process: one editor process for every
/// wallpaper. Opening a wallpaper asks the running editor (`AppProcessChannel.Message.openWallpaper`),
/// else launches one with `--wallpaper-editor <folder>` through LaunchServices, so it is no child
/// of the app and outlives it. Requests made while it starts wait until it says it is ready.
@MainActor
final class WallpaperEditorLauncher {
    struct Dependencies {
        var messaging: AppProcessMessaging
        var channel: AppProcessChannel
        var sender: String = AppProcessChannel.processSender
        var isolationTag: String? = AppStorageLocation.current.isolationTag
        /// Whether an editor process (isolated as this app is) runs.
        var editorIsRunning: () -> Bool = { !AppProcessList.running(.wallpaperEditor).isEmpty }
        /// Launches a new instance of the app with these arguments and environment.
        var launch: (_ arguments: [String], _ environment: [String: String], _ done: @escaping @MainActor (Error?) -> Void) -> Void
            = WallpaperEditorLauncher.launchNewInstance
        var now: () -> Date = Date.init
    }

    /// How long requests wait for a launched editor to say it is ready before asking again.
    static let launchTimeout: TimeInterval = 20

    private let dependencies: Dependencies
    private var tokens: [AnyObject] = []
    /// When the editor this app launched started, until it says it is ready.
    private var launchStarted: Date?
    /// Folders asked for while the editor starts.
    private var waiting: [URL] = []
    /// The editor's process couldn't be launched.
    var onLaunchFailure: ((Error) -> Void)?
    /// The app was opened (Finder, Spotlight) while only the editor ran, which LaunchServices
    /// hands to the editor's process: it asks this one to show its window.
    var onShowMainWindow: (() -> Void)?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func start() {
        guard tokens.isEmpty else { return }
        let messaging = dependencies.messaging, channel = dependencies.channel
        tokens.append(messaging.observe(channel.name(.editorReady)) { [weak self] sender, _ in
            guard let self, sender != self.dependencies.sender else { return }
            self.editorDidBecomeReady()
        })
        tokens.append(messaging.observe(channel.name(.showMainWindow)) { [weak self] sender, _ in
            guard let self, sender != self.dependencies.sender else { return }
            self.onShowMainWindow?()
        })
    }

    func stop() {
        for token in tokens { dependencies.messaging.remove(token) }
        tokens = []
    }

    /// Opens (or brings forward) the editor of the wallpaper in `folder`.
    func open(_ folder: URL) {
        let folder = folder.standardizedFileURL
        if let launchStarted, dependencies.now().timeIntervalSince(launchStarted) < Self.launchTimeout {
            if !waiting.contains(folder) { waiting.append(folder) }
            return
        }
        launchStarted = nil
        if dependencies.editorIsRunning() {
            send(folder)
            return
        }
        launchStarted = dependencies.now()
        let arguments = AppLaunchMode.wallpaperEditorArguments(folder: folder, isolationTag: dependencies.isolationTag)
        var environment: [String: String] = [:]
        if let tag = dependencies.isolationTag { environment[AppStorageLocation.environmentKey] = tag }
        OWELog.info(.ui, "Launching the Wallpaper Editor for \(folder.path)")
        dependencies.launch(arguments, environment) { [weak self] error in
            guard let self, let error else { return }
            OWELog.error(.ui, "Can't launch the Wallpaper Editor: \(error)")
            self.launchStarted = nil
            self.waiting = []
            self.onLaunchFailure?(error)
        }
    }

    private func editorDidBecomeReady() {
        launchStarted = nil
        let folders = waiting
        waiting = []
        for folder in folders { send(folder) }
    }

    private func send(_ folder: URL) {
        dependencies.messaging.post(dependencies.channel.name(.openWallpaper), sender: dependencies.sender,
                                    userInfo: [AppProcessChannel.folderKey: folder.path(percentEncoded: false)])
    }

    /// A new instance of this app, launched by LaunchServices (not a child process).
    nonisolated static func launchNewInstance(arguments: [String], environment: [String: String],
                                  done: @escaping @MainActor (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.arguments = arguments
        if !environment.isEmpty { configuration.environment = environment }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(error) } }
        }
    }
}
