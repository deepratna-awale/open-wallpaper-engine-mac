import AppKit

/// The Wallpaper Editor as its own process (`--wallpaper-editor [<folder>]`, `AppLaunchPlan`):
/// only editor windows, a regular Dock icon and menu bar of its own, named "Wallpaper Editor".
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
    private lazy var sceneHost = SceneWallpaperHost(
        settings: GlobalSettingsViewModel(followsLaunch: false),
        scriptServices: SceneScriptServices(prelude: SceneScriptPrelude.load(),
                                            storage: SceneScriptStorage(directory: SceneScriptStorage.defaultDirectory),
                                            media: MacMediaSessionSource(),
                                            spectrum: { WallpaperServices.shared.audioSpectrumSnapshot }))

    init(initialFolder: URL?, messaging: AppProcessMessaging = DistributedAppProcessMessaging(),
         channel: AppProcessChannel = .current) {
        self.initialFolder = initialFolder
        self.messaging = messaging
        self.channel = channel
    }

    // MARK: NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        let plan = AppLaunchPlan.plan(for: .wallpaperEditor(initialFolder))
        if let policy = plan.activationPolicy { NSApp.setActivationPolicy(policy) }
        if let name = plan.displayName { ProcessDisplayName.set(name) }
        WallpaperEditorMenu.install(WallpaperEditorMenu.make(helpTarget: self, help: #selector(openHelp)))
        requests.start()
        changeSync.start()
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

    /// The app's bundle was opened while this process ran (Finder, Spotlight, a relaunch after an
    /// update or a crash): LaunchServices hands that to a running instance, which may be this one.
    /// A click on this process's own Dock icon brings its windows back; anything else means Open
    /// Wallpaper Engine, which starts normally, or shows its window when it already runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if WallpaperEditorReopen.isFromDock(NSAppleEventManager.shared().currentAppleEvent) { return true }
        if AppProcessList.running(.main).isEmpty {
            openMainApp()
        } else {
            requests.askAppToShowItsWindow()
        }
        return false
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

    /// Open Wallpaper Engine as a new instance (this process already is one of the bundle),
    /// isolated as this process is.
    private func openMainApp() {
        var arguments: [String] = []
        var environment: [String: String] = [:]
        if let tag = AppStorageLocation.current.isolationTag {
            arguments = [AppStorageLocation.argumentKey, tag]
            environment[AppStorageLocation.environmentKey] = tag
        }
        WallpaperEditorLauncher.launchNewInstance(arguments: arguments, environment: environment) { error in
            if let error { OWELog.error(.ui, "Can't open Open Wallpaper Engine from the Wallpaper Editor: \(error)") }
        }
    }

    @objc private func openHelp() {
        NSWorkspace.shared.open(AppDelegate.helpURL)
    }
}

/// Where a reopen request (`applicationShouldHandleReopen`) came from.
enum WallpaperEditorReopen {
    /// The Apple event attribute holding the sender's process id (`keySenderPIDAttr`, 'spid').
    static let senderPIDKeyword: AEKeyword = 0x7370_6964
    static let dockBundleIdentifier = "com.apple.dock"

    /// Whether `event` came from the Dock (a click on the process's own icon).
    static func isFromDock(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let pid = event?.attributeDescriptor(forKeyword: senderPIDKeyword)?.int32Value, pid > 0 else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == dockBundleIdentifier
    }
}
