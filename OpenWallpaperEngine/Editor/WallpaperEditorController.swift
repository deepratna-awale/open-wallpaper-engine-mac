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
        userPropertyUndo = EditorUserPropertyUndo(wallpaper: wallpaper, undoManager: session.undoManager,
                                                  coalescingInterval: session.coalescingInterval)
        let preview = WallpaperViewModel(persistsWallpapers: false)
        preview.setWallpaper(wallpaper, for: preview.selectedScreenId)
        preview.playVolume = 0
        // The canvas is framed to the scene's own aspect, so stretching is exact.
        preview.wallpaperPlacement = .stretch
        self.preview = preview
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
            })
        services.effectCatalog = { resources.effectCatalog(outline: session.authored) }
        services.effectSchema = { resources.effectSchema($0) }
        services.prepareEffect = { try resources.prepareEffect($0) }
        services.assetStore = resources.assets
        services.wallpaperAssets = { resources.wallpaperAssets() }
        services.texture = { resources.texture($0) }
        services.fonts = { resources.fonts() }
        services.userPropertyChoices = { resources.userPropertyChoices() }
        return services
    }

    /// Saves the overlay; the running instances of the wallpaper (the canvas and the desktop)
    /// reload with it.
    private func save(_ overlay: SceneEditOverlay) {
        do {
            try SceneEditOverlayFiles.save(overlay, for: identity, wallpaperDirectory: wallpaper.wallpaperDirectory,
                                           base: session.baseOutline)
        } catch {
            OWELog.error(.scene, "Can't save the editor overlay of \(wallpaper.project.title): \(error)")
        }
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
        let scene = try session.overlay.applied(to: source.scene)
        let folder = try LocalWallpaperWriter().save(writerSource, scene: scene, title: title,
                                                     into: FileManager.default.wallpapersDirectory)
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
