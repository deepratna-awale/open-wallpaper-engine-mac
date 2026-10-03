import AppKit
import SwiftUI
import OWEEditor
import OWESceneEditing

extension AppDelegate {
    /// Opens `wallpaper` in the Wallpaper Editor (docs/editor-plan.md), its own window, one per
    /// wallpaper; the Scene Inspector stays as it is. Scene wallpapers only.
    func showWallpaperEditor(for wallpaper: WEWallpaper) {
        guard WallpaperEditorController.canEdit(wallpaper) else { return }
        let key = wallpaper.wallpaperDirectory.standardizedFileURL
        if let editor = wallpaperEditors[key] {
            editor.window.makeKeyAndOrderFront(nil)
            return
        }
        do {
            let editor = try WallpaperEditorController(wallpaper: wallpaper)
            editor.onClose = { [weak self] in self?.wallpaperEditors[key] = nil }
            wallpaperEditors[key] = editor
            editor.window.makeKeyAndOrderFront(nil)
        } catch {
            OWELog.error(.ui, "The Wallpaper Editor can't open \(wallpaper.wallpaperDirectory.path): \(error)")
            let alert = NSAlert()
            alert.messageText = String(localized: "The Wallpaper Editor can’t open “\(wallpaper.project.displayTitle)”.")
            alert.informativeText = String(localized: "Its scene can’t be read.")
            alert.runModal()
        }
    }
}

/// One Wallpaper Editor window: the editor module's view (`WallpaperEditorView`) over the app's
/// own pieces. The canvas is the wallpaper running through the real renderer, in a preview of its
/// own (as the Workshop preview runs one); edits are an overlay saved beside the wallpaper
/// (`SceneEditOverlayFiles`), which every running instance of it reloads with.
@MainActor
final class WallpaperEditorController: NSObject, NSWindowDelegate {
    let wallpaper: WEWallpaper
    let window: NSWindow
    let session: SceneEditSession
    /// The window closed; its owner lets go of the controller.
    var onClose: (() -> Void)?
    private let identity: WallpaperSettingsIdentity
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

    /// Only scene wallpapers have layers to edit.
    static func canEdit(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    init(wallpaper: WEWallpaper) throws {
        self.wallpaper = wallpaper
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
        }
        timeline.onCanvasTime = { [weak self] seconds in self?.timelineCanvas.show(seconds) }
        let content = NSHostingView(rootView: WallpaperEditorView(session: session, services: makeServices()))
        content.sizingOptions = [.minSize]
        window.contentView = content
        window.center()
        window.setFrameAutosaveName("WallpaperEditor")
    }

    private func makeServices() -> WallpaperEditorServices {
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
        services.depthMaps = DepthMapPlugin.services(for: wallpaper, resources: resources)
        let assets = particleAssets, directory = wallpaper.wallpaperDirectory
        do {
            services.particles = try ParticleEditorServices.make(
                session: session, readAsset: { assets.data($0) }, presets: assets.presets(labels: labels),
                textures: assets.textures(), thumbnail: { assets.thumbnail($0) },
                restart: { layerID in
                    // The system is built again from nothing; the rest of the scene keeps running.
                    SceneEditOverlayFiles.postParticles(session.overlay, wallpaperDirectory: directory, objectIDs: [layerID])
                })
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
        } catch {
            OWELog.error(.scene, "Can't save the editor overlay of \(wallpaper.project.title): \(error)")
        }
    }

    private static func sceneDigest(_ overlay: SceneEditOverlay) -> String {
        overlay.hasSceneEdits ? overlay.digest : ""
    }

    /// Save as Local Wallpaper: a copy in the library with the edits in its scene.json; the
    /// wallpaper itself isn't touched.
    private func saveAsLocalWallpaper(title: String) throws -> String {
        let source = try WallpaperEditorSource.read(wallpaper)
        var writerSource = LocalWallpaperWriter.Source(directory: wallpaper.wallpaperDirectory,
                                                       sceneFile: wallpaper.project.file,
                                                       assetsDirectory: resources.assets.directory)
        if let package = source.package {
            var files: [String: Data] = [:]
            for path in package.fileList where files[path] == nil {
                if let data = package.extractFile(named: path) { files[path] = data }
            }
            writerSource.packageFiles = files
            writerSource.packageName = source.packageName
        }
        let authoring = session.overlay.authoring
        // The editor's puppets become `.mdl` files and the layers' references (`PuppetSceneBake`).
        let read = EditorPuppetAssets.make(for: wallpaper).readFile
        let baked = try PuppetSceneBake.bake(session.overlay, into: try session.overlay.applied(to: source.scene),
                                             readFile: read)
        // The user properties as authored in the editor go into the copy's project.json; the
        // particle editor's documents (definitions, materials) are files of the copy.
        let folder = try LocalWallpaperWriter().save(writerSource, scene: baked.scene, title: title,
                                                     into: FileManager.default.wallpapersDirectory,
                                                     editProject: { authoring?.applyProperties(to: &$0) },
                                                     files: baked.files,
                                                     additionalFiles: try session.overlay.particles?.assetFiles() ?? [:])
        OWELog.info(.library, "Saved \(wallpaper.project.title) with its editor edits as \(folder.path)")
        AppDelegate.shared.contentViewModel.refresh()
        return title
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
