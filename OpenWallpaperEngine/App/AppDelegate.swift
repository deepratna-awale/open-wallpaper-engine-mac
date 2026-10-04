//
//  AppDelegate.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/6.
//

import Cocoa
import Combine
import SwiftUI
import AVKit
import WebKit
import OWEInspectorKit

private final class WorkshopPreviewWindow: NSWindow {
    var onDismiss: (() -> Void)?

    override func performClose(_ sender: Any?) {
        orderOut(sender)
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isKeyWindow else { return }
            self.orderOut(nil)
            self.onDismiss?()
        }
    }
}

private struct WorkshopPreviewContent: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WallpaperView(
                viewModel: wallpaperViewModel,
                screenId: wallpaperViewModel.selectedScreenId
            )
            .id(wallpaperViewModel.currentWallpaper.wallpaperDirectory)

            // One small glass group over the live wallpaper.
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    if SceneWallpaperViewModel.isVideoType(wallpaperViewModel.currentWallpaper.project.type) {
                        let isPaused = wallpaperViewModel.playRate == 0
                        HStack(spacing: 8) {
                            Button {
                                wallpaperViewModel.playRate = isPaused ? max(wallpaperViewModel.lastPlayRate, 0.1) : 0
                            } label: {
                                Label(isPaused ? "Play" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                                    .labelStyle(.iconOnly)
                            }
                            .borderlessOnGlassButtonStyle()
                            .help(isPaused ? "Play" : "Pause")

                            NumericSliderInput(value: $wallpaperViewModel.playVolume, range: 0...1,
                                               defaultValue: 1, displayScale: 100, suffix: "%",
                                               fractionDigits: 0, sliderWidth: 110, fieldWidth: 36)
                        }
                        .glassBackground(in: Capsule(),
                                         padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)) { controls in
                            // Before glass: a frosted capsule keeps the controls legible over the video.
                            controls
                                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .background(.regularMaterial, in: Capsule())
                        }
                    }

                    Button("Set Wallpaper") {
                        AppDelegate.shared.applyWorkshopPreview()
                    }
                    .glassButtonStyle(.prominent)
                }
            }
            .padding()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow!
    
    var mainWindowController: MainWindowController!
    
    var wallpaperWindows: [String: NSWindow] = [:]
    private var workshopPreviewWindow: NSWindow?
    private var workshopPreviewViewModel: WallpaperViewModel?
    var sceneInspectorWindow: NSWindow?
    /// The Wallpaper Editor, a process of its own (`WallpaperEditorAppDelegate`): opening a
    /// wallpaper in it, and its edits reaching the wallpapers running here.
    private(set) lazy var wallpaperEditorLauncher: WallpaperEditorLauncher = {
        let launcher = WallpaperEditorLauncher(dependencies: .init(messaging: processMessaging, channel: .current))
        launcher.onLaunchFailure = { error in
            let alert = NSAlert()
            alert.messageText = String(localized: "The Wallpaper Editor couldn’t be opened.")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        return launcher
    }()
    private(set) lazy var editorChangeSync: WallpaperEditorChangeSync = {
        let sync = WallpaperEditorChangeSync(role: .app, dependencies: .init(messaging: processMessaging, channel: .current))
        sync.onLibraryChange = { [weak self] in self?.contentViewModel.refresh() }
        sync.onOpenSettings = { [weak self] in self?.openSettings(for: $0) }
        return sync
    }()
    private lazy var processMessaging: AppProcessMessaging = DistributedAppProcessMessaging()

    var contentViewModel = ContentViewModel()
    var wallpaperViewModel = WallpaperViewModel()
    var globalSettingsViewModel = GlobalSettingsViewModel()
    /// The settings window's tab and the setting a link or search result opens.
    let settingsNavigation = SettingsNavigation()
    lazy var safeRestart = SafeRestart()
    /// Each playlist's system-wide shortcut (`App/GlobalShortcuts`).
    lazy var playlistShortcuts = PlaylistShortcutController(viewModel: wallpaperViewModel)
    lazy var crashWatcher = CrashWatcher()
    private var processPriorityCancellable: AnyCancellable?
    private var crashWatcherCancellable: AnyCancellable?
    /// Hides the Dock icon while no window is open (`DockPresence`).
    let dockPresence = DockPresence()
    /// Sparkle, off in builds without an update signing key (`Core/Updates`).
    lazy var updater = AppUpdater(configuration: .main)
    /// The system's now-playing session, one for the process (MediaRemote registers per process):
    /// SceneScript's `media*` callbacks and web wallpapers' media listeners hear it.
    lazy var mediaSession = MacMediaSessionSource()
    /// What every scene's SceneScripts share: WE's prelude, `localStorage`, the one media session and
    /// the desktop's left clicks.
    /// Settings › Plugins › Screen Saver: the loop videos and the bundled saver.
    lazy var screenSaver = ScreenSaverPlugin()
    /// Settings › Plugins › MCP Server: MCP clients' control of the app while installed (`MCP/`).
    private(set) lazy var mcpServerPlugin: MCPServerPlugin = {
        let model = AppControlModel(app: self)
        let router = ControlRequestRouter(model: model, groups: [
            SceneControlRequests.make(app: self, model: model),
            LibraryControlRequests.make(app: self, model: model),
            SystemControlRequests.make(app: self, model: model),
        ])
        return MCPServerPlugin(handler: { request in await router.handle(request) })
    }()
    /// The Scene Editor (Live)'s Screen Saver mode's recordings, set as the screen saver.
    lazy var screenSaverRecordings = ScreenSaverRecordingService(plugin: screenSaver, environment: .init(
        screens: {
            NSScreen.screens.map { screen in
                (pixels: SIMD2(Int(screen.frame.width * screen.backingScaleFactor), Int(screen.frame.height * screen.backingScaleFactor)),
                 points: SIMD2(Int(screen.frame.width), Int(screen.frame.height)))
            }
        },
        renderResolution: { [unowned self] in globalSettingsViewModel.settings.renderResolution },
        isPluginEnabled: { [unowned self] in globalSettingsViewModel.settings.screenSaver },
        enablePlugin: { [unowned self] in globalSettingsViewModel.settings.screenSaver = true },
        desktopWallpaper: { [unowned self] in wallpaperViewModel.currentWallpaper }))
    /// The screen saver's daily re-recording, while the app runs.
    lazy var screenSaverSchedule = ScreenSaverDailyScheduler(service: screenSaverRecordings)
    lazy var sceneScriptServices: SceneScriptServices = {
        if !SceneScriptJIT.isEnabled {
            OWELog.info(.script, "JavaScriptCore runs without its JIT (no \(SceneScriptJIT.entitlement)): scripts run several times slower")
        }
        let clicks = DesktopClickMonitor()
        clicks.start()
        return SceneScriptServices(
            prelude: SceneScriptPrelude.load(),
            storage: SceneScriptStorage(directory: SceneScriptStorage.defaultDirectory),
            media: mediaSession,
            spectrum: { WallpaperServices.shared.audioSpectrumSnapshot },
            clicks: clicks)
    }()
    /// The Wallpaper Engine assets scenes need, from the user's own Steam copy (Settings › Assets).
    lazy var assets = WallpaperEngineAssetsService(steamCmd: contentViewModel.steamCmd)
    /// Installs Valve's SteamCMD when none is found; the new copy is picked up by detection.
    lazy var steamCmdInstaller = SteamCmdInstaller(onInstalled: { [weak contentViewModel] in
        contentViewModel?.steamCmd.detectSteamCmd()
    })
    private var assetsCancellable: AnyCancellable?
    /// Fetches the Workshop items shown wallpapers borrow assets from.
    lazy var workshopDependencies = WorkshopDependencyService(steamCmd: contentViewModel.steamCmd)
    private var workshopDependencyCancellable: AnyCancellable?
    /// The collection, subscription and Steam library imports, shared by the setup assistant and
    /// the Installed and Workshop tabs.
    lazy var onboardingImports = OnboardingImports(contentViewModel: contentViewModel,
                                                   wallpaperViewModel: wallpaperViewModel)
    private var audioOutputCancellable: AnyCancellable?
    private var syncPropertiesCancellable: AnyCancellable?
    private var displayFlipCancellable: AnyCancellable?
    private var mediaIntegrationCancellable: AnyCancellable?
    /// Follows the default output device: capture always restarts, wallpapers reload when the
    /// setting is on. `rebuildWallpaperWindows` is the same reload an asset change uses.
    private lazy var outputDeviceMonitor = OutputDeviceChangeMonitor(
        source: CoreAudioOutputDeviceSource(),
        schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
        reloadEnabled: { [weak self] in self?.globalSettingsViewModel.settings.reloadWhenChangingOutputDevice ?? false },
        restartCapture: { MainActor.assumeIsolated { WallpaperServices.shared.audioCapture.outputDeviceDidChange() } },
        reloadWallpapers: { [weak self] in MainActor.assumeIsolated { self?.rebuildWallpaperWindows() } })
    /// Settings › Performance › Playback, per display (`App/Playback`).
    private(set) lazy var displayPlaybackMonitor = makeDisplayPlaybackMonitor()
    /// Saved display profiles, which application rules' "Load profile" loads. None until display
    /// layouts can be saved; that feature sets its own here.
    var displayProfiles: any DisplayProfileLoading = UnavailableDisplayProfiles()
    /// Application rules' load actions, and the restore when no rule matches any more.
    private(set) lazy var applicationRuleLoader = makeApplicationRuleLoader()
    /// Advanced › "Pause when VRAM is exhausted", fed to `displayPlaybackMonitor`.
    private(set) lazy var videoMemoryWatch = makeVideoMemoryWatch()
    private var videoMemorySettingCancellable: AnyCancellable?
    
    var importOpenPanel: NSOpenPanel!
    
    var eventHandler: Any?
    
    private static let instance = AppDelegate()
    /// Open Wallpaper Engine's delegate, made on first use. Never in the Wallpaper Editor's process
    /// (`AppLaunchPlan`), whose code reaches the app through `WallpaperEditorChangeSync` instead.
    static var shared: AppDelegate {
        sharedAccessProbe?()
        return instance
    }
    /// Told of every use of `shared` (tests: the editor's services never reach the app's delegate).
    static var sharedAccessProbe: (() -> Void)?

    override init() {
        super.init()
        OWELog.info(.app, "AppDelegate created (pid \(ProcessInfo.processInfo.processIdentifier))")
        if AppLaunchMode.parse(CommandLine.arguments).isWallpaperEditor {
            let caller = Thread.callStackSymbols.prefix(12).joined(separator: "\n")
            OWELog.error(.app, "AppDelegate created in the Wallpaper Editor's process: something there reached AppDelegate.shared from\n\(caller)")
            // Debug builds stop here; a release keeps running with the app's delegate made.
            assertionFailure("AppDelegate.shared reached in the Wallpaper Editor's process")
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Animated previews are built in now; the old plugin's on/off is dropped.
        ThumbnailAnimation.removeRetiredPreference(from: .app)

        workshopDependencyCancellable = wallpaperViewModel.$wallpapers.sink { [weak self] wallpapers in
            for wallpaper in wallpapers.values {
                self?.workshopDependencies.ensureDependencies(for: wallpaper)
            }
            // After the change is applied, so the old wallpaper counts as no longer shown.
            DispatchQueue.main.async { self?.staleBundleRefresher?.shownWallpapersChanged() }
        }

        // New or removed assets: scripts, the library (default wallpapers) and every scene reload.
        assetsCancellable = assets.assetsChanged.sink { [weak self] in
            guard let self else { return }
            self.sceneScriptServices.reloadPrelude()
            self.contentViewModel.refresh()
            self.rebuildWallpaperWindows()
        }

        wallpaperViewModel.keepWorkshopPreview = { [steamCmd = contentViewModel.steamCmd] in try steamCmd.keepPreview($0) }

        // Settings › Optimizations › Audio Output silences every wallpaper (`WallpaperAudioRouting`).
        audioOutputCancellable = globalSettingsViewModel.$settings.map(\.audioOutput).removeDuplicates()
            .sink { [weak self] enabled in self?.wallpaperViewModel.audioOutputEnabled = enabled }
        // Settings › Optimizations: one set of user properties for every display, or each display's own.
        syncPropertiesCancellable = globalSettingsViewModel.$settings.map(\.syncPropertiesAcrossDisplays).removeDuplicates()
            .sink { [weak self] synced in self?.wallpaperViewModel.syncsPropertiesAcrossDisplays = synced }
        // Flipped clone displays mirror their window's content (`WallpaperWindowContentView`).
        displayFlipCancellable = wallpaperViewModel.$layoutResolution.map(\.flipped).removeDuplicates()
            .sink { [weak self] flipped in self?.applyDisplayFlips(flipped) }
        // Settings › Optimizations › Media integration support: whether wallpapers hear Now Playing.
        mediaIntegrationCancellable = globalSettingsViewModel.$settings.map(\.mediaIntegration).removeDuplicates()
            .sink { [weak self] enabled in self?.mediaSession.setIntegrationEnabled(enabled) }

        // Settings → Audio → Reload when changing output device (`OutputDeviceChangeMonitor`).
        outputDeviceMonitor.start()

        // Before the wallpaper windows exist, so a wallpaper behind an unclean exit never loads.
        safeRestart.attach(to: wallpaperViewModel)

        // The Wallpaper Editor's process: what it saves reaches the wallpapers running here.
        wallpaperEditorLauncher.start()
        editorChangeSync.start(watch: true) { [weak self] in
            guard let self else { return [] }
            var folders = self.wallpaperViewModel.wallpapers.values.map(\.wallpaperDirectory)
            if let preview = self.workshopPreviewViewModel { folders.append(preview.currentWallpaper.wallpaperDirectory) }
            return folders
        }

        // Settings › Process Priority: at launch, before any render thread starts, and on change.
        processPriorityCancellable = globalSettingsViewModel.$settings.map(\.processPiority).removeDuplicates()
            .sink { ProcessPriority.apply($0) }
        // Settings › Restart after crashing: the watcher that reopens the app after a crash.
        crashWatcherCancellable = globalSettingsViewModel.$settings.map(\.restartAfterCrashing).removeDuplicates()
            .sink { [weak self] enabled in self?.crashWatcher.update(enabled: enabled) }

        // 创建设置视窗
        setSettingsWindow()
        // Launched by the Wallpaper Editor on a Settings page (WE's assets, the depth map model).
        if let request = AppSettingsRequest.requested(by: CommandLine.arguments) {
            DispatchQueue.main.async { [weak self] in self?.openSettings(for: request) }
        }
        
        // 创建桌面壁纸视窗
        setWallpaperWindows()

        // 监听显示器连接/断开
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioCapturePermissionMissing),
            name: .audioCapturePermissionMissing, object: nil
        )
        
        // 创建化左上角菜单栏
        setMainMenu()
        
        // 创建化右上角常驻菜单栏
        setStatusMenu()
        
        // 创建主视窗
        self.mainWindowController = MainWindowController()
        
        // 将外部输入传递到壁纸窗口
        AppDelegate.shared.setEventHandler()

        observeMainWindowForWhatsNew()
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = self.statusItem.menu?.copy() as! NSMenu?
        dockMenu?.items.removeLast() // Remove `Quit` menu item
        return dockMenu
    }
    
// MARK: - delegate methods
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A test copy wears "TEST", a local build "Dev", on its Dock icon (`DockBadge`).
        DockBadge.current.apply()
        saveCurrentWallpaper()
        AppDelegate.shared.setPlacehoderWallpaper(with: wallpaperViewModel.currentWallpaper)

        // 显示桌面壁纸
        for (_, window) in self.wallpaperWindows {
            window.orderFront(nil)
        }
        
        safeRestart.showPendingNotice()
        updater.willRelaunch = { [unowned self] in self.captureUpdateRelaunchState().save(to: .app) }
        updater.start()
        displayPlaybackMonitor.start(settings: globalSettingsViewModel.$settings)
        videoMemorySettingCancellable = globalSettingsViewModel.$settings
            .map(\.pauseOnVRAMExhausted)
            .removeDuplicates()
            .sink { [weak self] enabled in MainActor.assumeIsolated { self?.videoMemoryWatch.setEnabled(enabled) } }

        // After an update relaunch, what was open before; otherwise the setup assistant if due.
        if !restoreUpdateRelaunchState(),
           globalSettingsViewModel.isFirstLaunch || globalSettingsViewModel.needsLegalNotice {
            self.mainWindowController.window.center()
            self.mainWindowController.window.makeKeyAndOrderFront(nil)
        }

        // Registers the playlists' global shortcuts.
        _ = playlistShortcuts

        // MCP clients connect once the app is set up, while the MCP Server plugin is installed.
        mcpServerPlugin.start()

        // Launched into the menu bar only, the Dock icon goes until a window opens.
        dockPresence.start()

        // The screen saver's daily re-recording: catches up a run missed while the app was quit.
        screenSaverSchedule.start()

        // Workshop downloads need SteamCMD; set it up from Valve in the background when it's missing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.steamCmdInstaller.detectThenAutoInstall(self.contentViewModel.steamCmd)
        }

        DispatchQueue.global(qos: .utility).async {
            WallpaperPackageConverter.convertInstalledLibrary()
            if UserDefaults.app.bool(forKey: "ReclaimOriginalPackages") {
                WallpaperPackageConverter.reclaimEligibleSources()
            }
            // Bundles left on an older conversion with no package to redo it from.
            let stale = StaleBundleScanner.scan(storage: FileManager.default.wallpapersDirectory)
            guard !stale.isEmpty else { return }
            // Later, so the cached SteamCMD login restored at launch has had its turn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.refreshStaleBundles(stale)
            }
        }
    }
    
    private var staleBundleRefresher: StaleBundleRefresher?
    private var staleBundleNotice: SafeRestartNotice?

    private func refreshStaleBundles(_ stale: [StaleBundle]) {
        let refresher = StaleBundleRefresher(
            downloader: contentViewModel.steamCmd,
            isShown: { [weak self] directory in
                self?.wallpaperViewModel.wallpapers.values.contains {
                    $0.wallpaperDirectory.standardizedFileURL == directory.standardizedFileURL
                } ?? false
            },
            notify: { [weak self] titles in
                guard let self else { return }
                self.staleBundleNotice?.close()
                self.staleBundleNotice = SafeRestartNotice(
                    message: StaleBundleRefresher.noticeMessage(for: titles), onRetry: nil,
                    onDismiss: { [weak self] in
                        self?.staleBundleNotice?.close()
                        self?.staleBundleNotice = nil
                    })
                self.staleBundleNotice?.show()
            })
        staleBundleRefresher = refresher
        refresher.run(stale)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        contentViewModel.isApplicationActive = true
        // Picks up a steamcmd installed meanwhile, e.g. with Homebrew.
        if !steamCmdInstaller.isBusy {
            contentViewModel.steamCmd.detectSteamCmd()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        contentViewModel.isApplicationActive = false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !self.mainWindowController.window.isVisible && !settingsWindow.isVisible {
            self.mainWindowController.window?.makeKeyAndOrderFront(nil)
        }
        
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // What an application rule loaded isn't the user's choice: the saved wallpapers and
        // playlist go back to theirs before they are stored for the next launch.
        if applicationRuleLoader.isHoldingRestorePoint { applicationRuleLoader.update(nil) }
        safeRestart.applicationWillTerminate()
        crashWatcher.applicationWillTerminate()
        mcpServerPlugin.stop()
        updater.stopShaderPrewarm()
        // The lock-screen pictures go back to each display's own picture, the rest to the one saved
        // at launch.
        LockScreenPicture.restore(synchronously: true)
        if DesktopSnapshotCache.mayChangeDesktopPicture, let wallpaper = UserDefaults.app.url(forKey: "OSWallpaper") {
            for screen in NSScreen.screens
            where NSWorkspace.shared.desktopImageURL(for: screen).map(DesktopSnapshotCache.current.isSnapshot) ?? true {
                try? NSWorkspace.shared.setDesktopImageURL(wallpaper, for: screen)
            }
        }
        
        // The user's pictures are back: OWE's snapshots (only its own folder) go, and any
        // full-screen TIFFs earlier versions left in Caches go to the Trash.
        let snapshots = DesktopSnapshotCache.current
        snapshots.removeAll()
        snapshots.trashLegacySnapshots()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

// MARK: - misc methods
    @objc func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow.makeKeyAndOrderFront(nil)
    }
    
    /// Opens Settings on `tab`, scrolled to the section `anchor` names when given.
    func openSettings(_ tab: SettingsTab, anchor: String? = nil) {
        settingsNavigation.show(tab, anchor: anchor)
        openSettingsWindow()
    }

    /// Settings › Assets, where the assets scenes need are installed.
    @objc func openAssetsSettings() {
        openSettings(.assets, anchor: SettingsAnchor.assets)
    }

    /// The Settings page the Wallpaper Editor asked for.
    func openSettings(for request: AppSettingsRequest) {
        switch request {
        case .assets: openAssetsSettings()
        case .depthMaps: openSettings(.plugins, anchor: SettingsAnchor.depthMaps)
        }
    }

    /// The Workshop tab, where Steam's login form is.
    @objc func openSteamLogin() {
        contentViewModel.topTabBarSelection = 1
        openMainWindow()
    }

    @objc func openMainWindow() {
        self.mainWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor @objc func toggleFilter() {
        self.contentViewModel.toggleFilter()
    }

    /// Posted at most once per launch by `AudioCapturePermissionGate`, and never after
    /// "Don't Ask Again".
    @objc func audioCapturePermissionMissing() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Audio Visualizers Need Permission")
        alert.informativeText = PermissionHelper.usesSystemAudioRecording
            ? String(localized: """
            Open Wallpaper Engine needs System Audio Recording permission to read system audio \
            for audio bars and other audio-reactive wallpapers. Audio capture starts on its own once \
            the permission is granted.
            """, comment: "System Audio Recording is the name of the macOS privacy setting")
            : String(localized: """
            Open Wallpaper Engine needs Screen & System Audio Recording permission to read system audio \
            for audio bars and other audio-reactive wallpapers. Audio capture starts on its own once \
            the permission is granted.
            """, comment: "Screen & System Audio Recording is the name of the macOS privacy setting")
        alert.addButton(withTitle: String(localized: "Grant Access"))
        alert.addButton(withTitle: String(localized: "Open Permissions Page"))
        alert.addButton(withTitle: String(localized: "Later"))
        alert.addButton(withTitle: String(localized: "Don't Ask Again"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            PermissionHelper.grantAudioCaptureAccess { WallpaperServices.shared.recheckCapturePermission() }
        case .alertSecondButtonReturn:
            openSettings(.permissions)
        case .alertThirdButtonReturn:
            break
        default:
            GlobalSettingsViewModel.isAudioPermissionAlertDismissed = true
        }
    }

// MARK: Set Settings Window
    /// The bare settings window: resizable to any width, with no minimum width.
    static func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsTab.toolbarFittingWidth(), height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = String(localized: "Settings")
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        return window
    }

    func setSettingsWindow() {
        self.settingsWindow = Self.makeSettingsWindow()

        self.settingsWindow.delegate = self
        
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        
        toolbar.selectedItemIdentifier = settingsNavigation.tab.toolbarIdentifier
        settingsNavigation.toolbar = toolbar

        self.settingsWindow.toolbar = toolbar
        let ruleLibrary = ApplicationRuleLibrary(
            wallpapers: { [weak self] in self?.contentViewModel.allWallpapers ?? [] },
            playlists: { [weak self] in self?.wallpaperViewModel.playlists ?? [] },
            profiles: { [weak self] in self?.displayProfiles ?? UnavailableDisplayProfiles() })
        self.settingsWindow.contentView = NSHostingView(rootView: SettingsView()
            .environmentObject(self.globalSettingsViewModel)
            .environmentObject(settingsNavigation)
            .environment(\.applicationRuleLibrary, ruleLibrary))

        // A saved frame is the size and place the user left the window at; only the first open
        // gets the computed size. The frame autosaves into UserDefaults.standard, which an
        // isolated copy must not write.
        let autosaveName = "SettingsWindow"
        let isIsolated = AppStorageLocation.current.isIsolated
        let restored = !isIsolated && self.settingsWindow.setFrameUsingName(autosaveName)
        if !isIsolated { self.settingsWindow.setFrameAutosaveName(autosaveName) }
        if !restored, let screen = self.settingsWindow.screen ?? NSScreen.main {
            let size = SettingsTab.initialWindowSize(visibleFrame: screen.visibleFrame)
            self.settingsWindow.setFrame(NSRect(origin: .zero, size: size), display: false)
            self.settingsWindow.center()
        }
    }
    
// MARK: Set Wallpaper Windows - One per screen
    func setWallpaperWindows() {
        for screen in NSScreen.screens {
            let screenId = WallpaperViewModel.screenId(for: screen)
            guard wallpaperViewModel.isScreenEnabled(screenId) else { continue }

            let window = WallpaperWindow()
            window.styleMask = [.borderless, .fullSizeContentView]
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.stationary, .canJoinAllSpaces]
            window.setFrame(screen.frame, display: true)
            window.isMovable = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.isOpaque = true
            window.canHide = false
            window.canBecomeVisibleWithoutLogin = true
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true
            let content = WallpaperWindowContentView(content: NSHostingView(rootView:
                WallpaperView(viewModel: self.wallpaperViewModel, screenId: screenId)
            ))
            content.isMirrored = wallpaperViewModel.isFlipped(screenId)
            window.contentView = content
            wallpaperWindows[screenId] = window
        }
    }

    /// Mirrors the windows of flipped clone displays and only those.
    private func applyDisplayFlips(_ flipped: Set<String>) {
        for (screenId, window) in wallpaperWindows {
            (window.contentView as? WallpaperWindowContentView)?.isMirrored = flipped.contains(screenId)
        }
    }

    /// Rebuild wallpaper windows without changing enabled state.
    func rebuildWallpaperWindows() {
        for (_, window) in wallpaperWindows {
            // `isReleasedWhenClosed` is false, so the hosting view (and the video players inside
            // it) survives a plain close and keeps playing.
            window.contentView = nil
            window.close()
        }
        wallpaperWindows.removeAll()
        setWallpaperWindows()
        orderWallpaperWindowsFront()
    }

    @MainActor
    func showWorkshopPreview(_ wallpaper: WEWallpaper) {
        if let previewViewModel = workshopPreviewViewModel,
           let window = workshopPreviewWindow {
            previewViewModel.setWallpaper(wallpaper, for: previewViewModel.selectedScreenId)
            previewViewModel.playRate = wallpaperViewModel.playRate
            previewViewModel.playVolume = wallpaperViewModel.playVolume
            window.title = wallpaper.project.title
            window.makeKeyAndOrderFront(nil)
            return
        }

        let previewViewModel = WallpaperViewModel(persistsWallpapers: false)
        previewViewModel.setWallpaper(wallpaper, for: previewViewModel.selectedScreenId)
        previewViewModel.playRate = wallpaperViewModel.playRate
        previewViewModel.playVolume = wallpaperViewModel.playVolume

        let window = WorkshopPreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.onDismiss = { [weak self] in
            // Hiding the window leaves its wallpaper view — and that view's video players — alive,
            // so the preview has to be torn down rather than just paused.
            guard let self else { return }
            self.workshopPreviewViewModel?.playRate = 0
            self.workshopPreviewViewModel?.playVolume = 0
            self.workshopPreviewWindow?.contentView = nil
            self.workshopPreviewWindow = nil
            self.workshopPreviewViewModel = nil
        }
        window.title = wallpaper.project.title
        window.contentView = NSHostingView(rootView: WorkshopPreviewContent(
            wallpaperViewModel: previewViewModel
        ))
        window.center()
        window.makeKeyAndOrderFront(nil)

        workshopPreviewViewModel = previewViewModel
        workshopPreviewWindow = window
    }

    @MainActor
    func applyWorkshopPreview() {
        guard let wallpaper = workshopPreviewViewModel?.currentWallpaper else { return }
        wallpaperViewModel.inspect(wallpaper)
        wallpaperViewModel.applyInspectedWallpaper()
    }

    /// Called when monitors connect/disconnect — auto-enables newly connected screens.
    @objc func screensChanged() {
        let connectedIds = Set(NSScreen.screens.map { WallpaperViewModel.screenId(for: $0) })
        for id in connectedIds where !wallpaperViewModel.enabledScreens.contains(id) {
            wallpaperViewModel.enabledScreens.insert(id)
        }
        // Groups whose displays came back wake up; those left with one display go dormant.
        wallpaperViewModel.refreshDisplayLayout()
        rebuildWallpaperWindows()
    }
    
    func windowWillClose(_ notification: Notification) {
        globalSettingsViewModel.reset()
    }
    
    func setEventHandler() {
        // Only monitor event types we actually handle — .any causes main thread starvation
        let relevantEvents: NSEvent.EventTypeMask = [
            .scrollWheel, .mouseMoved, .mouseEntered, .mouseExited,
            .leftMouseUp, .rightMouseUp, .leftMouseDown,
            .leftMouseDragged, .rightMouseDragged
        ]
        self.eventHandler = NSEvent.addGlobalMonitorForEvents(matching: relevantEvents) { [weak self] event in
            guard let self = self,
                  let frontmostApplication = NSWorkspace.shared.frontmostApplication,
                  frontmostApplication.bundleIdentifier == "com.apple.finder" else { return }

            // Find the WKWebView in whichever wallpaper window the event lands on
            let mouseLocation = NSEvent.mouseLocation
            guard let targetWindow = self.wallpaperWindows.values.first(where: { $0.frame.contains(mouseLocation) }),
                  let webview = (targetWindow.contentView as? WallpaperWindowContentView)?.content?.subviews.first?.subviews.first,
                  webview is WKWebView else { return }

            switch event.type {
            case .scrollWheel:
                webview.scrollWheel(with: event)
            case .mouseMoved:
                webview.mouseMoved(with: event)
            case .mouseEntered:
                webview.mouseEntered(with: event)
            case .mouseExited:
                webview.mouseExited(with: event)
            case .leftMouseUp, .rightMouseUp:
                webview.mouseUp(with: event)
            case .leftMouseDown:
                webview.mouseDown(with: event)
            case .leftMouseDragged, .rightMouseDragged:
                webview.mouseDragged(with: event)
            default:
                break
            }
        }
    }
    
    func saveCurrentWallpaper() {
        guard DesktopSnapshotCache.mayChangeDesktopPicture, let mainScreen = NSScreen.main else { return }
        var wallpaper: URL {
            var osWallpaper: URL { NSWorkspace.shared.desktopImageURL(for: mainScreen)! }
            if let wallpaper = UserDefaults.app.url(forKey: "OSWallpaper") {
                if wallpaper != osWallpaper {
                    if !DesktopSnapshotCache.current.isSnapshot(wallpaper) {
                        return wallpaper
                    }
                }
            }
            return osWallpaper
        }
        UserDefaults.app.set(wallpaper, forKey: "OSWallpaper")
    }
    
    func setPlacehoderWallpaper(with wallpaper: WEWallpaper) {
        let settings = globalSettingsViewModel.settings
        screenSaver.update(enabled: settings.screenSaver, wallpaper: wallpaper)
        if settings.lockScreenPicture { LockScreenPicture.apply(wallpaper) }
        switch wallpaper.project.type {
        case "video":
            let asset = AVAsset(url: wallpaper.wallpaperDirectory.appending(component: wallpaper.project.file))
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let time = CMTimeMake(value: 1, timescale: 1) // 第一帧的时间
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let error = error {
                    OWELog.error(.app, "Video thumbnail for desktop picture failed: \(error)")
                } else if let cgImage = cgImage {
                    DispatchQueue.main.async {
                        DesktopSnapshotCache.setDesktopPicture(cgImage, for: NSScreen.screens)
                    }
                }
            }
        default:
            return
        }
    }
}
