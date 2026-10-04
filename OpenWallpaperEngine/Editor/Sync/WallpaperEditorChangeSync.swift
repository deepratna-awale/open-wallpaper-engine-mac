import Foundation
import OWESceneEditing

/// Keeps Open Wallpaper Engine and the Wallpaper Editor's process (docs/editor-plan.md,
/// "Separate process") showing the same wallpaper: what one saves, the other's running
/// wallpapers apply as if it had been saved in their own process.
///
/// - **Editor → app.** The editor saves overlays where it always did (`SceneEditOverlayFiles`) and
///   says so with a message naming the wallpaper (`AppProcessChannel`). The app reads the overlay
///   and posts this process's `sceneEditOverlayDidChange` / `sceneEditParticlesDidChange` with it,
///   so its instances draw the change live or reload, exactly as before. A drag in progress goes
///   through a file beside the overlay (`SceneEditLiveFiles`), at most `previewInterval` apart.
///   The app also watches the overlay folder (`DirectoryChangeWatcher`), so a save whose message
///   was missed still arrives; the same overlay twice is applied once.
/// - **App → editor.** An MCP client's edit, which the app saves and applies itself
///   (`HeadlessSceneDocument`), is announced (`appOverlayDidSave`, with the undo step's name); the
///   editor's open window of the wallpaper takes it as an undo step of its own, so Undo there
///   undoes it, and that Undo comes back to the app as any editor save does.
/// - **Both ways.** A wallpaper's saved user properties (`wallpaperPropertiesDidSave`) reach the
///   other process's running store, and a wallpaper added to the library (Save as Local
///   Wallpaper) refreshes the app's library.
@MainActor
final class WallpaperEditorChangeSync {
    struct Dependencies {
        var messaging: AppProcessMessaging
        var channel: AppProcessChannel
        /// This process, as the messages' sender.
        var sender: String = AppProcessChannel.processSender
        var store: SceneEditOverlayStore = SceneEditOverlayFiles.defaultStore
        /// This process's own notifications (the instances, the library).
        var local: NotificationCenter = .default
        var defaults: UserDefaults = .app
        /// The wallpaper's scene.json as it ships, to measure a drag against (`baseOutline`).
        var readScene: (URL) -> Data? = WallpaperEditorChangeSync.shippedScene
        /// A running store's user properties, and setting some of them (`WallpaperServices`).
        var runningProperties: (String) -> [String: String] = { WallpaperServices.shared.userProperties(wallpaper: $0) }
        var setRunningProperties: ([String: String], String) -> Void = {
            WallpaperServices.shared.setUserProperties($0, wallpaper: $1, replacing: false)
        }
        /// When a throttled preview may go out.
        var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        }
        var now: () -> Date = Date.init
        /// Whether Open Wallpaper Engine (isolated as this process is) runs.
        var appIsRunning: () -> Bool = {
            let app = AppBundleLayout.appIdentifier(for: Bundle.main.bundleIdentifier ?? AppStorageLocation.realBundleIdentifier)
            return !AppProcessList.running(.main, bundleIdentifier: app).isEmpty
        }
        /// Launches Open Wallpaper Engine on one of its Settings pages.
        var launchAppOnSettings: (AppSettingsRequest) -> Void = WallpaperEditorChangeSync.launchApp(on:)
    }

    /// What the process applies of the other's messages.
    struct Role: OptionSet {
        let rawValue: Int
        /// Overlays the editor saved, and its drags and particle restarts (the app).
        static let appliesEditorChanges = Role(rawValue: 1 << 0)
        /// Library additions (the app).
        static let refreshesLibrary = Role(rawValue: 1 << 1)
        /// User properties the other process saved (both).
        static let appliesProperties = Role(rawValue: 1 << 2)
        /// Requests for a Settings page (Assets, Plugins › Depth Map Generation: the app).
        static let opensSettings = Role(rawValue: 1 << 3)
        /// Overlays Open Wallpaper Engine saved for an MCP client, which an open window takes as an
        /// undo step (the editor).
        static let adoptsAppEdits = Role(rawValue: 1 << 4)

        static let app: Role = [.appliesEditorChanges, .refreshesLibrary, .appliesProperties, .opensSettings]
        static let editor: Role = [.appliesProperties, .adoptsAppEdits]
    }

    /// The gap between two drag previews another process draws.
    static let previewInterval: TimeInterval = 1.0 / 30

    private let dependencies: Dependencies
    private let role: Role
    private let liveFiles: SceneEditLiveFiles
    private var tokens: [AnyObject] = []
    private var localObservers: [NSObjectProtocol] = []
    private var watcher: DirectoryChangeWatcher?
    /// The folders of the scenes running here, which a change of the overlay folder may concern.
    private var runningFolders: () -> [URL] = { [] }
    /// The library gained a wallpaper.
    var onLibraryChange: (() -> Void)?
    /// The editor asked for a Settings page.
    var onOpenSettings: ((AppSettingsRequest) -> Void)?
    /// Open Wallpaper Engine saved the overlay of the wallpaper in the folder for an MCP client, as
    /// the named undo step, or as its Undo or Redo (the editor's process).
    var onAppOverlay: ((URL, String, AppProcessChannel.OverlayStep) -> Void)?

    private var identities: [URL: WallpaperSettingsIdentity] = [:]
    /// Each wallpaper's overlay as last applied here: a message and the folder watcher reporting
    /// the same save apply it once.
    private var applied: [URL: SceneEditOverlay] = [:]
    /// The last base measured per wallpaper, by the structure it was read with.
    private var bases: [URL: (structure: SceneEditOverlay, base: SceneOutline)] = [:]
    /// The drag to send, and when the last one went.
    private var pendingPreview: (overlay: SceneEditOverlay, folder: URL, identity: WallpaperSettingsIdentity)?
    private var previewScheduled = false
    private var lastPreview: Date = .distantPast
    /// A property save this process posts for the other's: not sent back.
    private var isApplyingRemoteProperties = false

    init(role: Role, dependencies: Dependencies) {
        self.role = role
        self.dependencies = dependencies
        liveFiles = SceneEditLiveFiles(store: dependencies.store)
    }

    /// Listens for the other process's messages and forwards this one's property saves.
    /// `runningFolders`: the wallpapers running here, for the overlay folder watcher (`watch`).
    func start(watch: Bool = false, runningFolders: @escaping () -> [URL] = { [] }) {
        guard tokens.isEmpty else { return }
        self.runningFolders = runningFolders
        let messaging = dependencies.messaging, channel = dependencies.channel
        func on(_ message: AppProcessChannel.Message, _ handle: @escaping @MainActor (WallpaperEditorChangeSync, URL?) -> Void) {
            tokens.append(messaging.observe(channel.name(message)) { [weak self] sender, info in
                guard let self, sender != self.dependencies.sender else { return }
                handle(self, info[AppProcessChannel.folderKey].map { URL(filePath: $0, directoryHint: .isDirectory) })
            })
        }
        if role.contains(.appliesEditorChanges) {
            on(.overlayDidSave) { sync, folder in folder.map { sync.applySavedOverlay(of: $0) } }
            on(.overlayPreview) { sync, folder in folder.map { sync.applyPreview(of: $0) } }
            on(.particlesRestart) { sync, folder in folder.map { sync.applyParticleRestart(of: $0) } }
            if watch {
                let watcher = DirectoryChangeWatcher(directory: dependencies.store.directory) { [weak self] in
                    self?.overlayFolderChanged()
                }
                watcher.start()
                self.watcher = watcher
            }
        }
        if role.contains(.refreshesLibrary) {
            on(.libraryDidChange) { sync, _ in sync.onLibraryChange?() }
        }
        if role.contains(.opensSettings) {
            for request in AppSettingsRequest.allCases {
                on(request.message) { sync, _ in sync.onOpenSettings?(request) }
            }
        }
        if role.contains(.adoptsAppEdits) {
            tokens.append(messaging.observe(channel.name(.appOverlayDidSave)) { [weak self] sender, info in
                guard let self, sender != self.dependencies.sender, let path = info[AppProcessChannel.folderKey] else { return }
                let step = info[AppProcessChannel.stepKey].flatMap(AppProcessChannel.OverlayStep.init(rawValue:)) ?? .edit
                self.onAppOverlay?(URL(filePath: path, directoryHint: .isDirectory), info[AppProcessChannel.actionKey] ?? "", step)
            })
        }
        if role.contains(.appliesProperties) {
            on(.propertiesDidSave) { sync, folder in folder.map { sync.applySavedProperties(of: $0) } }
        }
        // This process's property saves, for the other process's running wallpapers. Delivered as
        // posted, so a save this sync posts for the other process is told apart and not sent back.
        localObservers.append(dependencies.local.addObserver(forName: .wallpaperPropertiesDidSave, object: nil,
                                                             queue: nil) { [weak self] notification in
            guard let path = notification.object as? String else { return }
            let forward = {
                MainActor.assumeIsolated {
                    guard let self, !self.isApplyingRemoteProperties else { return }
                    // What was just saved is in the shared defaults before the other process reads it.
                    self.dependencies.defaults.synchronize()
                    self.send(.propertiesDidSave, folder: URL(filePath: path, directoryHint: .isDirectory))
                }
            }
            if Thread.isMainThread { forward() } else { DispatchQueue.main.async(execute: forward) }
        })
    }

    func stop() {
        for token in tokens { dependencies.messaging.remove(token) }
        tokens = []
        for observer in localObservers { dependencies.local.removeObserver(observer) }
        localObservers = []
        watcher?.stop()
        watcher = nil
    }

    // MARK: Sending (the editor)

    /// The editor saved `folder`'s overlay: a drag still waiting is dropped, the saved overlay wins.
    func overlayDidSave(folder: URL, identity: WallpaperSettingsIdentity) {
        if pendingPreview?.folder == Self.normalized(folder) { pendingPreview = nil }
        liveFiles.remove(for: identity, previewOnly: true)
        send(.overlayDidSave, folder: folder)
    }

    /// A drag in progress, drawn by the other process at most `previewInterval` apart; the last
    /// one always goes.
    func preview(_ overlay: SceneEditOverlay, folder: URL, identity: WallpaperSettingsIdentity) {
        pendingPreview = (overlay, Self.normalized(folder), identity)
        guard !previewScheduled else { return }
        let wait = lastPreview.addingTimeInterval(Self.previewInterval).timeIntervalSince(dependencies.now())
        guard wait > 0 else { return flushPreview() }
        previewScheduled = true
        dependencies.schedule(wait) { [weak self] in
            guard let self else { return }
            self.previewScheduled = false
            self.flushPreview()
        }
    }

    private func flushPreview() {
        guard let preview = pendingPreview else { return }
        pendingPreview = nil
        lastPreview = dependencies.now()
        do {
            try liveFiles.writePreview(preview.overlay, for: preview.identity)
            send(.overlayPreview, folder: preview.folder)
        } catch {
            OWELog.error(.scene, "Can't hand the editor's drag of \(preview.folder.path) to Open Wallpaper Engine: \(error)")
        }
    }

    /// The particle editor restarts systems `objectIDs`.
    func restartParticles(_ objectIDs: Set<Int>, folder: URL, identity: WallpaperSettingsIdentity) {
        do {
            try liveFiles.writeRestart(objectIDs, for: identity)
            send(.particlesRestart, folder: folder)
        } catch {
            OWELog.error(.scene, "Can't hand the particle restart of \(folder.path) to Open Wallpaper Engine: \(error)")
        }
    }

    /// Open Wallpaper Engine saved `folder`'s overlay for an MCP client and applied it to its own
    /// instances (`HeadlessSceneDocument`): the same overlay from the folder watcher isn't applied
    /// again, and the editor's open window of the wallpaper takes it as the undo step `actionName`
    /// (the client's Undo or Redo, `step`: undoes or redoes that step).
    func appOverlayDidSave(folder: URL, overlay: SceneEditOverlay, actionName: String,
                           step: AppProcessChannel.OverlayStep = .edit) {
        applied[Self.normalized(folder)] = overlay
        send(.appOverlayDidSave, folder: folder,
             extra: [AppProcessChannel.actionKey: actionName, AppProcessChannel.stepKey: step.rawValue])
    }

    /// A wallpaper was added to the library.
    func libraryDidChange() {
        send(.libraryDidChange, folder: nil)
    }

    /// Shows one of the app's Settings pages: the running app's, else the app, launched to show it.
    func openSettings(_ request: AppSettingsRequest) {
        if dependencies.appIsRunning() {
            send(request.message, folder: nil)
        } else {
            dependencies.launchAppOnSettings(request)
        }
    }

    nonisolated static func launchApp(on request: AppSettingsRequest) {
        let tag = AppStorageLocation.current.isolationTag
        var arguments = [request.launchArgument]
        var environment: [String: String] = [:]
        if let tag {
            arguments += [AppStorageLocation.argumentKey, tag]
            environment[AppStorageLocation.environmentKey] = tag
        }
        let app = AppBundleLayout.appBundle.bundleURL
        WallpaperEditorLauncher.openApp(at: app, arguments: arguments, environment: environment) { error in
            if let error { OWELog.error(.ui, "Can't open Open Wallpaper Engine at \(app.path) on its Settings: \(error)") }
        }
    }

    /// The editor window of `folder` closed: what it left for the other process goes.
    func editorDidClose(identity: WallpaperSettingsIdentity) {
        pendingPreview = nil
        liveFiles.remove(for: identity)
    }

    private func send(_ message: AppProcessChannel.Message, folder: URL?, extra: [String: String] = [:]) {
        var info = extra
        if let folder { info[AppProcessChannel.folderKey] = Self.normalized(folder).path }
        dependencies.messaging.post(dependencies.channel.name(message), sender: dependencies.sender, userInfo: info)
    }

    // MARK: Applying (the app)

    /// Applies `folder`'s saved overlay as the editor's own process does after saving it: values
    /// drawn live, particle documents rebuilding their systems, anything else a reload. Nothing
    /// when it is the overlay already applied, or a change the running scene doesn't show (a lock,
    /// a puppet: `SceneEditOverlay.digest`).
    func applySavedOverlay(of folder: URL) {
        let folder = Self.normalized(folder)
        let overlay = SceneEditOverlayFiles.overlay(for: identity(of: folder), store: dependencies.store) ?? SceneEditOverlay()
        let previous = applied[folder]
        guard previous != overlay else { return }
        applied[folder] = overlay
        if let previous {
            if case .particleAssets(let paths) = overlay.liveChange(from: previous) {
                SceneEditOverlayFiles.postParticles(overlay, wallpaperDirectory: folder, paths: paths,
                                                    center: dependencies.local)
                return
            }
            guard Self.sceneDigest(overlay) != Self.sceneDigest(previous) else { return }
        }
        SceneEditOverlayFiles.post(overlay, base: base(of: folder, for: overlay), wallpaperDirectory: folder,
                                   transient: false, center: dependencies.local)
    }

    func applyPreview(of folder: URL) {
        let folder = Self.normalized(folder)
        let overlay: SceneEditOverlay?
        do {
            overlay = try liveFiles.preview(for: identity(of: folder))
        } catch {
            OWELog.error(.scene, "The editor's drag of \(folder.path) can't be read: \(error)")
            return
        }
        // Gone: the drag ended and its save follows.
        guard let overlay, let base = base(of: folder, for: overlay) else { return }
        SceneEditOverlayFiles.post(overlay, base: base, wallpaperDirectory: folder, transient: true,
                                   center: dependencies.local)
    }

    func applyParticleRestart(of folder: URL) {
        let folder = Self.normalized(folder)
        let identity = self.identity(of: folder)
        do {
            let objectIDs = try liveFiles.restart(for: identity)
            guard !objectIDs.isEmpty else { return }
            let overlay = SceneEditOverlayFiles.overlay(for: identity, store: dependencies.store) ?? SceneEditOverlay()
            SceneEditOverlayFiles.postParticles(overlay, wallpaperDirectory: folder, objectIDs: objectIDs,
                                                center: dependencies.local)
        } catch {
            OWELog.error(.scene, "The editor's particle restart of \(folder.path) can't be read: \(error)")
        }
    }

    /// The overlay folder changed: every running wallpaper's overlay is read again (the same
    /// overlay as applied changes nothing).
    private func overlayFolderChanged() {
        for folder in Set(runningFolders().map(Self.normalized)) { applySavedOverlay(of: folder) }
    }

    /// The other process saved `folder`'s user properties: the running shared store takes what
    /// changed (as the Details panel publishes them), and the displays regroup.
    func applySavedProperties(of folder: URL) {
        let folder = Self.normalized(folder)
        let values = identity(of: folder).stored(.userProperties, scope: .shared, defaults: dependencies.defaults)
            as? [String: String] ?? [:]
        let key = WallpaperPropertyScope.shared.runtimeKey(directory: folder)
        let running = dependencies.runningProperties(key)
        // A store that doesn't run here is loaded with the saved values when it starts.
        if !running.isEmpty {
            let changed = WallpaperPropertyTargets.changes(values, from: running, defaults: [:])
            if !changed.isEmpty { dependencies.setRunningProperties(changed, key) }
        }
        isApplyingRemoteProperties = true
        dependencies.local.post(name: .wallpaperPropertiesDidSave, object: folder.path)
        isApplyingRemoteProperties = false
    }

    // MARK: Reading

    private func identity(of folder: URL) -> WallpaperSettingsIdentity {
        if let identity = identities[folder] { return identity }
        let identity = WallpaperSettingsIdentity.resolve(directory: folder, defaults: dependencies.defaults)
        identities[folder] = identity
        return identity
    }

    /// The scene with `overlay`'s structure, which a running instance measures the overlay's
    /// values against; nil when the scene can't be read (the instance then reloads).
    private func base(of folder: URL, for overlay: SceneEditOverlay) -> SceneOutline? {
        let structure = overlay.structureOnly
        if let cached = bases[folder], cached.structure == structure { return cached.base }
        guard let scene = dependencies.readScene(folder) else { return nil }
        do {
            let base = try SceneEditSession.baseOutline(sceneData: scene, overlay: overlay)
            bases[folder] = (structure, base)
            return base
        } catch {
            OWELog.error(.scene, "The scene of \(folder.path) can't be read with the editor's structure: \(error)")
            return nil
        }
    }

    /// One URL per folder, however it was spelt (a trailing slash, `..`): what the processes'
    /// messages and the caches are keyed by.
    nonisolated static func normalized(_ folder: URL) -> URL {
        URL(filePath: folder.standardizedFileURL.path, directoryHint: .isDirectory)
    }

    static func sceneDigest(_ overlay: SceneEditOverlay) -> String {
        overlay.hasSceneEdits ? overlay.digest : ""
    }

    /// scene.json as the wallpaper in `folder` ships it.
    nonisolated static func shippedScene(_ folder: URL) -> Data? {
        guard let wallpaper = InstalledLibrary.wallpaper(at: folder, hiding: []) else { return nil }
        do {
            return try WallpaperEditorSource.read(wallpaper).scene
        } catch {
            OWELog.error(.scene, "Can't read the scene of \(folder.path): \(error)")
            return nil
        }
    }
}
