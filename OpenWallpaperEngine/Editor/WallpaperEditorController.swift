import AppKit
import SwiftUI
import OWEEditor
import OWESceneEditing

/// One Wallpaper Editor window: the editor module's view (`WallpaperEditorView`) over the app's
/// own pieces. The canvas is the wallpaper running through the real renderer, in a preview of its
/// own (as the Workshop preview runs one); edits are an overlay saved beside the wallpaper
/// (`SceneEditOverlayFiles`), which every running instance of it reloads with: this process's
/// directly, Open Wallpaper Engine's through `sync` (the editor runs in a process of its own,
/// `WallpaperEditorAppDelegate`).
@MainActor
final class WallpaperEditorController: NSObject, NSWindowDelegate {
    let wallpaper: WEWallpaper
    let window: NSWindow
    let session: SceneEditSession
    /// The window closed; its owner lets go of the controller.
    var onClose: (() -> Void)?
    private let identity: WallpaperSettingsIdentity
    /// Hands saves, drags, particle restarts and library additions to Open Wallpaper Engine's
    /// process; nil keeps them in this one.
    private let sync: WallpaperEditorChangeSync?
    /// File › Save as Local Wallpaper… and Revert… for this window.
    private let commands = WallpaperEditorCommands()
    /// The canvas's own wallpaper model, as the Workshop preview has: one display, muted.
    private let preview: WallpaperViewModel
    private let userPropertyUndo: EditorUserPropertyUndo
    /// The effects, files, fonts and properties the editor offers.
    private let resources: EditorWallpaperResources
    /// The timeline (docs/editor-plan.md P4) and the canvas it drives.
    let timeline: SceneTimelineEditor
    private let timelineCanvas: EditorTimelineCanvas
    /// What the wallpaper's scripts log, for the script editor's console.
    private let scriptConsole: SceneScriptConsoleFeed
    private var consoleToken: UUID?
    /// The overlay's scene digest as last saved: a save that doesn't change it (a lock, the user
    /// properties, which only Save as Local Wallpaper writes, a puppet) doesn't reload the wallpaper.
    private var savedSceneDigest: String
    /// The files the particle editor reads (the wallpaper's, WE's), its textures and presets.
    private let particleAssets: WallpaperEditorParticleAssets
    /// The overlay as last saved, which tells a particle document change from a scene change.
    private var savedOverlay: SceneEditOverlay
    /// Taking an overlay Open Wallpaper Engine saved (`adoptSavedOverlay`): applied here, not saved.
    private var isAdopting = false

    /// Only scene wallpapers have layers to edit.
    nonisolated static func canEdit(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    /// `host`: the settings and script services the canvas runs with (nil: the app's).
    init(wallpaper: WEWallpaper, host: SceneWallpaperHost? = nil, sync: WallpaperEditorChangeSync? = nil) throws {
        self.wallpaper = wallpaper
        self.sync = sync
        let identity = WallpaperSettingsIdentity.resolve(directory: wallpaper.wallpaperDirectory)
        self.identity = identity
        let source = try WallpaperEditorSource.read(wallpaper)
        let session = SceneEditSession(outline: try SceneOutline(sceneData: source.scene),
                                       overlay: SceneEditOverlayFiles.overlay(for: identity) ?? SceneEditOverlay())
        self.session = session
        resources = EditorWallpaperResources(wallpaper: wallpaper, package: source.package,
                                             assets: SceneEditOverlayFiles.assets(for: identity))
        savedSceneDigest = Self.sceneDigest(session.overlay)
        savedOverlay = session.overlay
        particleAssets = WallpaperEditorParticleAssets(wallpaper: wallpaper, package: source.package)
        let scriptConsole = SceneScriptConsoleFeed(
            wallpaperID: SceneScriptStorageKey.key(forWallpaperDirectory: wallpaper.wallpaperDirectory))
        self.scriptConsole = scriptConsole
        consoleToken = SceneScriptConsoleTap.listen(to: scriptConsole.wallpaperID) { [weak scriptConsole] line in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    scriptConsole?.append(level: line.isError ? .error : .log, message: line.message,
                                          scriptID: line.scriptID, line: line.line)
                }
            }
        }
        userPropertyUndo = EditorUserPropertyUndo(wallpaper: wallpaper, undoManager: session.undoManager,
                                                  coalescingInterval: session.coalescingInterval)
        let preview = WallpaperViewModel(persistsWallpapers: false)
        preview.sceneHost = host
        preview.setWallpaper(wallpaper, for: preview.selectedScreenId)
        preview.playVolume = 0
        // The canvas is framed to the scene's own aspect, so stretching is exact.
        preview.wallpaperPlacement = .stretch
        self.preview = preview
        timeline = SceneTimelineEditor(session: session, index: (try? TimelineSceneIndex(sceneData: source.scene)) ?? .empty)
        timelineCanvas = EditorTimelineCanvas(preview: preview)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 840),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = wallpaper.project.displayTitle
        window.subtitle = String(localized: "Wallpaper Editor")
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.delegate = self
        session.onChange = { [weak self] overlay in self?.save(overlay) }
        // A gizmo drag is drawn live by the running wallpaper while it lasts.
        session.onLivePreview = { [weak self] overlay in
            guard let self else { return }
            SceneEditOverlayFiles.preview(overlay, base: self.session.baseOutline,
                                          wallpaperDirectory: self.wallpaper.wallpaperDirectory)
            self.sync?.preview(overlay, folder: self.wallpaper.wallpaperDirectory, identity: self.identity)
        }
        timeline.onCanvasTime = { [weak self] seconds in self?.timelineCanvas.show(seconds) }
        let content = NSHostingView(rootView: WallpaperEditorView(session: session, services: makeServices()))
        content.sizingOptions = [.minSize]
        window.contentView = content
        window.center()
        window.setFrameAutosaveName("WallpaperEditor")
    }

    /// Internal for tests (`WallpaperEditorProcessTests`).
    func makeServices() -> WallpaperEditorServices {
        let labels = WallpaperEngineLabels.load()
        let preview = self.preview, wallpaper = self.wallpaper, userPropertyUndo = self.userPropertyUndo
        let resources = self.resources, session = self.session
        var services = WallpaperEditorServices(
            makeCanvas: { AnyView(WallpaperView(viewModel: preview, screenId: preview.selectedScreenId)) },
            userProperties: { AnyView(EditorUserProperties(wallpaper: wallpaper, undo: userPropertyUndo)) },
            blendModeTitle: SceneBlendModeOptions.title(labels: labels),
            blendModes: SceneBlendModeOptions.options(labels: labels),
            effectHelp: { SceneHelp.effect($0) },
            suggestedLocalTitle: String(localized: "\(wallpaper.project.displayTitle) (Edited)",
                                        comment: "Wallpaper Editor: the suggested title of a wallpaper saved with its edits"),
            saveAsLocalWallpaper: { [weak self] title in
                guard let self else { return title }
                return try self.saveAsLocalWallpaper(title: title)
            },
            projectJSON: try? Data(contentsOf: wallpaper.wallpaperDirectory.appending(path: "project.json")),
            scriptConsole: scriptConsole)
        services.effectCatalog = { resources.effectCatalog(outline: session.authored) }
        services.effectSchema = { resources.effectSchema($0) }
        services.prepareEffect = { try resources.prepareEffect($0) }
        services.assetStore = resources.assets
        services.wallpaperAssets = { resources.wallpaperAssets() }
        services.texture = { resources.texture($0) }
        services.fonts = { resources.fonts() }
        services.userPropertyChoices = { resources.userPropertyChoices() }
        services.timeline = timeline
        services.puppetAssets = EditorPuppetAssets.make(for: wallpaper)
        services.commands = commands
        // In the editor's own process the app's Settings are another process's (`sync`).
        let openSettings: @MainActor (AppSettingsRequest) -> Void = { [sync] request in
            if let sync { sync.openSettings(request) } else { AppDelegate.shared.openSettings(for: request) }
        }
        services.depthMaps = DepthMapPlugin.services(for: wallpaper, resources: resources,
                                                     openPlugins: { openSettings(.depthMaps) })
        // The browsers' previews, rendered for the WE assets in use when the window opened.
        let previews = EditorPreviewHelper.provider()
        let hasWEAssets = { WallpaperEngineAssets.directory != nil }
        let openAssetsSetup = { openSettings(.assets) }
        services.previews = previews
        services.hasWEAssets = hasWEAssets
        services.openAssetsSetup = openAssetsSetup
        let assets = particleAssets, directory = wallpaper.wallpaperDirectory
        let sync = self.sync, identity = self.identity
        do {
            let particles = try ParticleEditorServices.make(
                session: session, readAsset: { assets.data($0) }, catalog: { assets.catalog(labels: labels) },
                textures: assets.textures(), thumbnail: { assets.thumbnail($0) },
                restart: { layerID in
                    // The system is built again from nothing; the rest of the scene keeps running.
                    SceneEditOverlayFiles.postParticles(session.overlay, wallpaperDirectory: directory, objectIDs: [layerID])
                    sync?.restartParticles([layerID], folder: directory, identity: identity)
                })
            particles.previews = previews
            particles.hasWEAssets = hasWEAssets
            particles.openAssetsSetup = openAssetsSetup
            services.particles = particles
        } catch {
            OWELog.error(.ui, "The Wallpaper Editor runs without its particle editor: its schema can't be read: \(error)")
        }
        return services
    }

    /// Saves the overlay; the running instances of the wallpaper (the canvas and the desktop)
    /// reload with it.
    private func save(_ overlay: SceneEditOverlay) {
        let digest = Self.sceneDigest(overlay)
        // A change of particle documents alone builds only the systems that read them.
        let change = overlay.liveChange(from: savedOverlay)
        savedOverlay = overlay
        if isAdopting {
            // The app saved it and applied it to its own instances; the canvas applies it here.
            if digest != savedSceneDigest {
                switch change {
                case .scene:
                    SceneEditOverlayFiles.post(overlay, base: session.baseOutline, wallpaperDirectory: wallpaper.wallpaperDirectory,
                                               transient: false)
                case .particleAssets(let paths):
                    SceneEditOverlayFiles.postParticles(overlay, wallpaperDirectory: wallpaper.wallpaperDirectory, paths: paths)
                }
            }
            savedSceneDigest = digest
            return
        }
        do {
            // A puppet edit doesn't change the running scene (`SceneEditOverlay.digest`): no reload.
            if digest == savedSceneDigest {
                try SceneEditOverlayFiles.defaultStore.save(overlay, for: identity.rawValue)
            } else {
                // Scripts applied here run from this reload (the runtime has no in-place swap of
                // one script: a site's id is only free again after its `destroy()`).
                try SceneEditOverlayFiles.save(overlay, for: identity, wallpaperDirectory: wallpaper.wallpaperDirectory,
                                               base: session.baseOutline, change: change)
            }
            savedSceneDigest = digest
            // Open Wallpaper Engine's instances read it and decide the same way.
            sync?.overlayDidSave(folder: wallpaper.wallpaperDirectory, identity: identity)
        } catch {
            OWELog.error(.scene, "Can't save the editor overlay of \(wallpaper.project.title): \(error)")
        }
    }

    private static func sceneDigest(_ overlay: SceneEditOverlay) -> String {
        overlay.hasSceneEdits ? overlay.digest : ""
    }

    /// Open Wallpaper Engine saved an overlay of this wallpaper for an MCP client and applied it to
    /// its own instances (`HeadlessSceneDocument`): the window takes it as the undo step
    /// `actionName`, so Undo here undoes it (and that Undo is saved and reaches the app as any edit).
    /// The client's Undo or Redo (`step`) of a step the window took undoes or redoes it here, so
    /// the history stays one step per client edit.
    func adoptSavedOverlay(actionName: String, step: AppProcessChannel.OverlayStep = .edit) {
        let stored: SceneEditOverlay
        do {
            stored = try SceneEditOverlayFiles.defaultStore.overlay(for: identity.rawValue) ?? SceneEditOverlay()
        } catch {
            OWELog.error(.scene, "The Wallpaper Editor can't read the edits Open Wallpaper Engine saved for \(wallpaper.project.title): \(error)")
            return
        }
        guard stored != session.overlay else { return }
        let name = actionName.isEmpty ? HeadlessSceneDocument.defaultActionName : actionName
        isAdopting = true
        defer { isAdopting = false }
        if follow(step, named: name, to: stored) { return }
        session.edit(actionName: name) { $0 = stored }
    }

    /// Undoes (or redoes) the window's next step when it is the client's step `name` and leads to
    /// `stored`; true when it did. Anything else (the user's own step on top) is left as it was.
    private func follow(_ step: AppProcessChannel.OverlayStep, named name: String, to stored: SceneEditOverlay) -> Bool {
        let undoManager = session.undoManager
        switch step {
        case .edit:
            return false
        case .undo:
            guard session.canUndo, undoManager.undoActionName == name else { return false }
            session.undo()
            if session.overlay == stored { return true }
            session.redo()
        case .redo:
            guard session.canRedo, undoManager.redoActionName == name else { return false }
            session.redo()
            if session.overlay == stored { return true }
            session.undo()
        }
        return false
    }

    /// An MCP client's timeline command (`play`, `pause`, `seek` to `seconds`).
    func controlTimeline(command: String, seconds: Double?) {
        switch command {
        case "play": timeline.isActive = true; timeline.play()
        case "pause": timeline.pause()
        case "seek":
            timeline.isActive = true
            timeline.setPlayhead(seconds ?? 0)
        default: OWELog.error(.ui, "The Wallpaper Editor got an unknown timeline command \(command)")
        }
    }

    /// Save as Local Wallpaper: a copy in the library with the edits in its scene.json; the
    /// wallpaper itself isn't touched.
    private func saveAsLocalWallpaper(title: String) throws -> String {
        _ = try LocalWallpaperSave.save(wallpaper, overlay: session.overlay, assetsDirectory: resources.assets.directory, title: title)
        // Open Wallpaper Engine's library lists it.
        sync?.libraryDidChange()
        return title
    }

    // MARK: Menu

    /// File › Save as Local Wallpaper…
    @objc func saveAsLocalWallpaper(_ sender: Any?) {
        commands.send(.saveAsLocalWallpaper)
    }

    /// File › Revert…
    @objc func revertEdits(_ sender: Any?) {
        commands.send(.revert)
    }

    // MARK: NSWindowDelegate

    /// ⌘Z and ⇧⌘Z in the window undo the editor's edits.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        session.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        // The timeline lets go of the canvas's clock (and its playback timer).
        timeline.isActive = false
        if let consoleToken { SceneScriptConsoleTap.stop(consoleToken) }
        consoleToken = nil
        // A drag or restart left for Open Wallpaper Engine goes with the window.
        sync?.editorDidClose(identity: identity)
        // The canvas's instance stops with its view.
        preview.playRate = 0
        window.contentView = nil
        // Let go once AppKit has finished closing the window.
        let onClose = onClose
        DispatchQueue.main.async { onClose?() }
    }
}

/// The wallpaper's user properties, as the Details panel shows them, rebuilt after an undo
/// changed one under them.
private struct EditorUserProperties: View {
    let wallpaper: WEWallpaper
    @ObservedObject var undo: EditorUserPropertyUndo

    var body: some View {
        SceneUserPropertiesView(wallpaper: wallpaper, scopes: [.shared])
            .id(undo.revision)
    }
}
