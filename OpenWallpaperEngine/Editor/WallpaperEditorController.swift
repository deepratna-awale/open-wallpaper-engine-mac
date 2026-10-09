import AppKit
import SwiftUI
import OWEEditor
import OWESceneEditing

/// One Wallpaper Editor window: the editor module's view (`WallpaperEditorView`) over the app's
/// own pieces. It edits a draft of the wallpaper (`WallpaperEditorDraft`), never the wallpaper
/// itself: the canvas is the wallpaper running the draft through the real renderer, in a preview
/// of its own (`WallpaperPropertyScope.editorDraft`), and nothing else runs the draft. File › Save
/// makes the draft the wallpaper's overlay (`SceneEditOverlayFiles`), which every running instance
/// of it reloads with once: Open Wallpaper Engine's through `sync` (the editor runs in a process of
/// its own, `WallpaperEditorAppDelegate`).
@MainActor
final class WallpaperEditorController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    let wallpaper: WEWallpaper
    let window: NSWindow
    let session: SceneEditSession
    /// The window closed; its owner lets go of the controller.
    var onClose: (() -> Void)?
    private let identity: WallpaperSettingsIdentity
    /// Hands saves and library additions to Open Wallpaper Engine's process; nil keeps them in this one.
    private let sync: WallpaperEditorChangeSync?
    /// File › Save, Save as New Wallpaper… and Revert to Saved… for this window.
    private let commands = WallpaperEditorCommands()
    /// What the window edits: its overlay and user properties, on disk as they change.
    let draft: WallpaperEditorDraft
    /// The draft's state for the toolbar (and the close button's dot), Save and Revert to Saved.
    let document = WallpaperEditorDocument()
    /// The canvas's own wallpaper model, as the Workshop preview has: one display, muted.
    private let preview: WallpaperViewModel
    private let userPropertyUndo: EditorUserPropertyUndo
    /// The effects, files, fonts and properties the editor offers.
    private let resources: EditorWallpaperResources
    /// The timeline (editor-plan notes P4) and the canvas it drives.
    let timeline: SceneTimelineEditor
    private let timelineCanvas: EditorTimelineCanvas
    /// What the wallpaper's scripts log, for the script editor's console.
    private let scriptConsole: SceneScriptConsoleFeed
    private var consoleToken: UUID?
    /// The draft's scene digest as the canvas last took it: a change that doesn't change it (a
    /// lock, the user properties, which only Save as New Wallpaper writes, a puppet) doesn't
    /// reload the canvas.
    private var appliedSceneDigest: String
    /// The files the particle editor reads (the wallpaper's, WE's), its textures and presets.
    private let particleAssets: WallpaperEditorParticleAssets
    /// The draft as the canvas last took it, which tells a particle document change from a scene change.
    private var appliedOverlay: SceneEditOverlay
    /// The wallpaper's overlay as last saved: the draft is measured against it, Revert to Saved
    /// goes back to it.
    private(set) var savedOverlay: SceneEditOverlay
    /// Taking a draft Open Wallpaper Engine wrote for an MCP client (`adoptSavedOverlay`): applied
    /// here, not written again.
    private var isAdopting = false

    /// Whether the window has changes File › Save hasn't saved.
    var isEdited: Bool { document.isEdited }

    /// Only scene wallpapers have layers to edit.
    nonisolated static func canEdit(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    /// `host`: the settings and script services the canvas runs with (nil: the app's).
    /// `resumesDraft`: a draft left from an earlier session is edited on (else it is discarded and
    /// the window starts from the wallpaper as last saved).
    init(wallpaper: WEWallpaper, host: SceneWallpaperHost? = nil, sync: WallpaperEditorChangeSync? = nil,
         resumesDraft: Bool = true) throws {
        self.wallpaper = wallpaper
        self.sync = sync
        let identity = WallpaperSettingsIdentity.resolve(directory: wallpaper.wallpaperDirectory)
        self.identity = identity
        let source = try WallpaperEditorSource.read(wallpaper)
        let draft = WallpaperEditorDraft(wallpaper: wallpaper)
        if !resumesDraft { Self.discard(draft, title: wallpaper.project.title) }
        draft.startProperties(resuming: resumesDraft)
        self.draft = draft
        savedOverlay = draft.savedOverlay
        let session = SceneEditSession(outline: try SceneOutline(sceneData: source.scene),
                                       overlay: SceneEditOverlayFiles.editedOverlay(for: identity) ?? SceneEditOverlay())
        self.session = session
        resources = EditorWallpaperResources(wallpaper: wallpaper, package: source.package,
                                             assets: SceneEditOverlayFiles.assets(for: identity))
        appliedSceneDigest = Self.sceneDigest(session.overlay)
        appliedOverlay = session.overlay
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
        userPropertyUndo = EditorUserPropertyUndo(wallpaper: wallpaper, scope: .editorDraft, undoManager: session.undoManager,
                                                  coalescingInterval: session.coalescingInterval)
        let preview = WallpaperViewModel(persistsWallpapers: false)
        preview.sceneHost = host
        // The canvas runs the draft: its properties' store, and its overlay (`SceneWallpaperViewModel`).
        preview.previewPropertyScope = .editorDraft
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
        session.onChange = { [weak self] overlay in self?.draftDidChange(overlay) }
        // A gizmo drag is drawn live by the canvas while it lasts.
        session.onLivePreview = { [weak self] overlay in
            guard let self else { return }
            SceneEditOverlayFiles.post(overlay, base: self.session.baseOutline, wallpaperDirectory: self.wallpaper.wallpaperDirectory,
                                       transient: true, draft: true)
        }
        userPropertyUndo.onChange = { [weak self] in self?.refreshEditedState() }
        document.save = { [weak self] in try self?.saveDraft() }
        document.revertToSaved = { [weak self] in self?.revertToSaved() }
        timeline.onCanvasTime = { [weak self] seconds in self?.timelineCanvas.show(seconds) }
        let content = NSHostingView(rootView: WallpaperEditorView(session: session, services: makeServices())
            .appAccentTint())
        content.sizingOptions = [.minSize]
        window.contentView = content
        window.center()
        window.setFrameAutosaveName("WallpaperEditor")
        refreshEditedState()
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
            suggestedNewTitle: String(localized: "\(wallpaper.project.displayTitle) (Edited)",
                                      comment: "Wallpaper Editor: the suggested title of a wallpaper saved with its edits"),
            saveAsNewWallpaper: { [weak self] title in
                guard let self else { return title }
                return try self.saveAsNewWallpaper(title: title)
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
        services.document = document
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
        do {
            let particles = try ParticleEditorServices.make(
                session: session, readAsset: { assets.data($0) }, catalog: { assets.catalog(labels: labels) },
                textures: assets.textures(), thumbnail: { assets.thumbnail($0) },
                restart: { layerID in
                    // The canvas builds the system again from nothing; the rest of the scene keeps running.
                    SceneEditOverlayFiles.postParticles(session.overlay, wallpaperDirectory: directory, objectIDs: [layerID],
                                                        draft: true)
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

    /// Every change of the draft: kept on disk (as the editor's autosave, so a crash keeps it)
    /// and run by the canvas alone, a value drawn live, particle documents rebuilding their
    /// systems, anything else a reload of the canvas.
    private func draftDidChange(_ overlay: SceneEditOverlay) {
        let digest = Self.sceneDigest(overlay)
        // A change of particle documents alone builds only the systems that read them.
        let change = overlay.liveChange(from: appliedOverlay)
        appliedOverlay = overlay
        // A draft Open Wallpaper Engine wrote is on disk already.
        if !isAdopting {
            do {
                try draft.saveOverlay(overlay)
            } catch {
                OWELog.error(.scene, "Can't keep the Wallpaper Editor's draft of \(wallpaper.project.title): \(error)")
            }
        }
        // A puppet edit doesn't change the running scene (`SceneEditOverlay.digest`): no reload.
        if digest != appliedSceneDigest {
            switch change {
            case .scene:
                // Scripts applied here run from this reload (the runtime has no in-place swap of
                // one script: a site's id is only free again after its `destroy()`).
                SceneEditOverlayFiles.post(overlay, base: session.baseOutline, wallpaperDirectory: wallpaper.wallpaperDirectory,
                                           transient: false, draft: true)
            case .particleAssets(let paths):
                SceneEditOverlayFiles.postParticles(overlay, wallpaperDirectory: wallpaper.wallpaperDirectory, paths: paths,
                                                    draft: true)
            }
        }
        appliedSceneDigest = digest
        refreshEditedState()
    }

    /// The window's edited state, from the draft against the wallpaper as last saved.
    private func refreshEditedState() {
        let edited = session.overlay != savedOverlay || draft.propertiesDiffer
        if document.isEdited != edited { document.isEdited = edited }
        window.isDocumentEdited = edited
    }

    /// File › Save: the draft becomes the wallpaper's (its overlay, its user properties), and every
    /// running instance of it reloads once: Open Wallpaper Engine's through `sync`, any here
    /// directly. The canvas already shows it.
    func saveDraft() throws {
        let overlay = session.overlay
        try draft.saveOverlay(overlay)
        let previous = savedOverlay
        if let saved = try draft.commit() {
            savedOverlay = saved
            SceneEditOverlayFiles.postSaved(saved, previous: previous, base: session.baseOutline,
                                            wallpaperDirectory: wallpaper.wallpaperDirectory)
            sync?.overlayDidSave(folder: wallpaper.wallpaperDirectory)
        }
        refreshEditedState()
    }

    /// File › Revert to Saved: the draft back to the last save, the layer edits and the Details
    /// panel's user properties alike, as one undo step.
    func revertToSaved() {
        let name = String(localized: "Revert to Saved", comment: "Wallpaper Editor: Undo menu name of going back to the last save")
        session.revert(to: savedOverlay, actionName: name)
        userPropertyUndo.revert(to: draft.savedPropertyValues, actionName: name)
        refreshEditedState()
    }

    /// Open Wallpaper Engine saved this wallpaper's draft for an MCP client (`wallpaper_editor_save`):
    /// what it saved is the window's last save from now on.
    func draftWasSaved() {
        savedOverlay = draft.savedOverlay
        refreshEditedState()
    }

    /// Don't Save or Discard: the draft goes; logged when it can't.
    private static func discard(_ draft: WallpaperEditorDraft, title: String) {
        do {
            try draft.discard()
        } catch {
            OWELog.error(.scene, "Can't discard the Wallpaper Editor's draft of \(title): \(error)")
        }
    }

    private static func sceneDigest(_ overlay: SceneEditOverlay) -> String {
        overlay.hasSceneEdits ? overlay.digest : ""
    }

    /// Open Wallpaper Engine changed this wallpaper's draft for an MCP client (`HeadlessSceneDocument`):
    /// the window takes it as the undo step `actionName`, so Undo here undoes it (and that Undo
    /// goes into the draft as any edit does).
    /// The client's Undo or Redo (`step`) of a step the window took undoes or redoes it here, so
    /// the history stays one step per client edit.
    func adoptSavedOverlay(actionName: String, step: AppProcessChannel.OverlayStep = .edit) {
        let stored: SceneEditOverlay
        do {
            stored = try draft.store.overlay(for: identity.rawValue)
        } catch {
            OWELog.error(.scene, "The Wallpaper Editor can't read the draft Open Wallpaper Engine wrote for \(wallpaper.project.title): \(error)")
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

    /// An MCP client's `particles_restart`: the canvas builds the systems `layers` again from
    /// nothing, as the particle editor's Restart does, from the draft.
    func restartParticles(_ layers: Set<Int>) {
        SceneEditOverlayFiles.postParticles(session.overlay, wallpaperDirectory: wallpaper.wallpaperDirectory, objectIDs: layers,
                                            draft: true)
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

    /// Save as New Wallpaper: a new wallpaper in the library with the draft in its scene.json; the
    /// wallpaper and its draft aren't touched, and the window goes on editing them.
    private func saveAsNewWallpaper(title: String) throws -> String {
        _ = try LocalWallpaperSave.save(wallpaper, overlay: session.overlay, assetsDirectory: resources.assets.directory, title: title)
        // Open Wallpaper Engine's library lists it.
        sync?.libraryDidChange()
        return title
    }

    // MARK: Menu

    /// File › Save
    @objc func saveDocument(_ sender: Any?) {
        commands.send(.save)
    }

    /// File › Save as New Wallpaper…
    @objc func saveAsNewWallpaper(_ sender: Any?) {
        commands.send(.saveAsNewWallpaper)
    }

    /// File › Revert to Saved…
    @objc func revertToSaved(_ sender: Any?) {
        commands.send(.revertToSaved)
    }

    /// Save and Revert to Saved need something unsaved.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        return action == WallpaperEditorMenu.save || action == WallpaperEditorMenu.revertToSaved ? isEdited : true
    }

    // MARK: Unsaved changes

    /// Asks whether to save the window's changes, as a document's window asks when it closes:
    /// Save, Don't Save or Cancel (`resolveUnsavedChanges`). Nothing to save answers true at once.
    func confirmUnsavedChanges(_ done: @escaping @MainActor (Bool) -> Void) {
        guard isEdited else { return done(true) }
        let alert = WallpaperEditorDraftAlerts.unsavedChanges(title: wallpaper.project.displayTitle)
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated { done(self?.resolveUnsavedChanges(response) ?? false) }
        }
    }

    /// The answer to the unsaved-changes question: Save (true once saved; a failure says why),
    /// Don't Save (the draft goes; true) or Cancel (false). Internal for tests.
    func resolveUnsavedChanges(_ response: NSApplication.ModalResponse) -> Bool {
        switch response {
        case .alertFirstButtonReturn:
            do {
                try saveDraft()
                return true
            } catch {
                OWELog.error(.scene, "Can't save the Wallpaper Editor's draft of \(wallpaper.project.title): \(error)")
                WallpaperEditorDraftAlerts.saveFailed(error).beginSheetModal(for: window, completionHandler: nil)
                return false
            }
        case .alertThirdButtonReturn:
            // The window closes next: the draft goes with it.
            Self.discard(draft, title: wallpaper.project.title)
            return true
        default:
            return false
        }
    }

    // MARK: NSWindowDelegate

    /// ⌘Z and ⇧⌘Z in the window undo the editor's edits.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        session.undoManager
    }

    /// Unsaved changes ask first (`confirmUnsavedChanges`).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isEdited else { return true }
        confirmUnsavedChanges { [weak self] close in
            if close { self?.window.close() }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // The timeline lets go of the canvas's clock (and its playback timer).
        timeline.isActive = false
        if let consoleToken { SceneScriptConsoleTap.stop(consoleToken) }
        consoleToken = nil
        // Nothing unsaved: the draft's store of properties goes. A window closed without asking
        // (an MCP client's `editor_close`) leaves its draft, offered again when the wallpaper opens.
        if !isEdited { draft.endProperties() }
        // The canvas's instance stops with its view.
        preview.playRate = 0
        window.contentView = nil
        // Let go once AppKit has finished closing the window.
        let onClose = onClose
        DispatchQueue.main.async { onClose?() }
    }
}

/// The draft's user properties, as the Details panel shows a wallpaper's, rebuilt after an undo
/// changed one under them.
private struct EditorUserProperties: View {
    let wallpaper: WEWallpaper
    @ObservedObject var undo: EditorUserPropertyUndo

    var body: some View {
        SceneUserPropertiesView(wallpaper: wallpaper, scopes: [.editorDraft])
            .id(undo.revision)
    }
}
