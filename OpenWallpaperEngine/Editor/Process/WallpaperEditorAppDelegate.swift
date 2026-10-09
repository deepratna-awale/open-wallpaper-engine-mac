import AppKit

/// The Wallpaper Editor as its own app (`<app>/Contents/Helpers/Wallpaper Editor.app`, its own
/// bundle id, `AppBundleLayout`; `AppLaunchPlan`): only editor windows, with its own Dock tile and
/// menu bar.
/// None of Open Wallpaper Engine's launch services run here (no desktop wallpapers, menu bar
/// item, screen saver, lock-screen picture, Workshop sync, updates, crash watcher or safe
/// restart), and `AppDelegate.shared` is never made.
///
/// One process holds every wallpaper's editor: Open Wallpaper Engine sends it the wallpapers to
/// open (`WallpaperEditorRequests`). It quits when its last window closes; the app quitting
/// sends it nothing, and its own quit or crash leaves the app alone.
@MainActor
final class WallpaperEditorAppDelegate: NSObject, NSApplicationDelegate, WallpaperEditorWindows {
    private let initialFolder: URL?
    private let messaging: AppProcessMessaging
    private let channel: AppProcessChannel
    /// The open editors, by the wallpaper's folder (a Workshop preset item's own).
    private(set) var editors: [URL: WallpaperEditorController] = [:]
    private lazy var requests = WallpaperEditorRequests(messaging: messaging, channel: channel, windows: self)
    private lazy var changeSync = WallpaperEditorChangeSync(
        role: .editor, dependencies: .init(messaging: messaging, channel: channel))
    /// The settings the canvas runs with, read from the app's, and the process's own SceneScript
    /// services (`localStorage` is the app's folder; Now Playing registers per process).
    private lazy var sceneHost = Self.makeSceneHost()
    /// Theming's tint of the app's windows, which the editor's windows follow.
    private lazy var themeTint = ThemeTintSync(messaging: messaging, channel: channel)

    /// `messaging` nil: the login session's (`DistributedAppProcessMessaging`).
    init(initialFolder: URL?, messaging: AppProcessMessaging? = nil, channel: AppProcessChannel = .current) {
        self.initialFolder = initialFolder
        self.messaging = messaging ?? DistributedAppProcessMessaging()
        self.channel = channel
        super.init()
        OWELog.info(.app, "WallpaperEditorAppDelegate created (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    static func makeSceneHost() -> SceneWallpaperHost {
        SceneWallpaperHost(
            settings: GlobalSettingsViewModel(followsLaunch: false),
            scriptServices: SceneScriptServices(prelude: SceneScriptPrelude.load(),
                                                storage: SceneScriptStorage(directory: SceneScriptStorage.defaultDirectory),
                                                media: MacMediaSessionSource(),
                                                spectrum: { WallpaperServices.shared.audioSpectrumSnapshot }))
    }

    // MARK: NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        let plan = AppLaunchPlan.plan(for: .wallpaperEditor(initialFolder))
        if let policy = plan.activationPolicy { NSApp.setActivationPolicy(policy) }
        WallpaperEditorMenu.install(WallpaperEditorMenu.make(helpTarget: self, help: #selector(openHelp)))
        requests.start()
        // An MCP client's edit the app saved: the open window of the wallpaper takes it as an undo step.
        changeSync.onAppOverlay = { [weak self] folder, actionName, step in
            self?.editor(of: folder)?.adoptSavedOverlay(actionName: actionName, step: step)
        }
        changeSync.start()
        themeTint.follow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A test copy wears "TEST", a local build "Dev", on its Dock icon (`DockBadge`).
        DockBadge.current.apply()
        OWELog.info(.ui, "Wallpaper Editor started (pid \(ProcessInfo.processInfo.processIdentifier))")
        if let initialFolder { showEditor(of: initialFolder) }
        requests.announceReady()
        NSApp.activate(ignoringOtherApps: true)
        quitIfNothingIsOpen()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A click on the editor's Dock tile: its windows come back (Open Wallpaper Engine's tile is
    /// the app's own, another bundle).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let editor = editors.values.first { editor.window.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        requests.stop()
        changeSync.stop()
    }

    // MARK: Windows

    @discardableResult
    func showEditor(of folder: URL) -> Bool {
        let folder = folder.standardizedFileURL
        NSApp.activate(ignoringOtherApps: true)
        if let editor = editors[folder] {
            editor.window.makeKeyAndOrderFront(nil)
            return true
        }
        guard let wallpaper = InstalledLibrary.wallpaper(at: folder, hiding: []),
              WallpaperEditorController.canEdit(wallpaper) else {
            OWELog.error(.ui, "The Wallpaper Editor can't open \(folder.path): not a scene wallpaper")
            showCantOpen(title: folder.lastPathComponent)
            return false
        }
        do {
            let editor = try WallpaperEditorController(wallpaper: wallpaper, host: sceneHost, sync: changeSync)
            editor.onClose = { [weak self] in
                guard let self else { return }
                self.editors[folder] = nil
                self.quitIfNothingIsOpen()
            }
            editors[folder] = editor
            editor.window.makeKeyAndOrderFront(nil)
            return true
        } catch {
            OWELog.error(.ui, "The Wallpaper Editor can't open \(wallpaper.wallpaperDirectory.path): \(error)")
            showCantOpen(title: wallpaper.project.displayTitle)
            return false
        }
    }

    /// The open editor of the wallpaper in `folder`, however its path was spelt.
    private func editor(of folder: URL) -> WallpaperEditorController? {
        let path = folder.standardizedFileURL.path
        return editors.first { $0.key.standardizedFileURL.path == path }?.value
    }

    func closeEditor(of folder: URL) {
        editor(of: folder)?.window.close()
    }

    func controlTimeline(of folder: URL, command: String, seconds: Double?) {
        editor(of: folder)?.controlTimeline(command: command, seconds: seconds)
    }

    private func showCantOpen(title: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "The Wallpaper Editor can’t open “\(title)”.")
        alert.informativeText = String(localized: "Its scene can’t be read.")
        alert.runModal()
    }

    /// The editor quits with its last window, and when the wallpaper it was launched for couldn't
    /// be opened.
    private func quitIfNothingIsOpen() {
        guard editors.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.editors.isEmpty else { return }
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func openHelp() {
        NSWorkspace.shared.open(AppDelegate.helpURL)
    }
}
