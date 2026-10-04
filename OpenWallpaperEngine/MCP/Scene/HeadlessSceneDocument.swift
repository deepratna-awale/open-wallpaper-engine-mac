import Foundation
import OWEControlProtocol
import OWEEditor
import OWESceneEditing

/// One wallpaper edited without a window: an edit session (`SceneEditSession`) over the
/// wallpaper's editor overlay, as the Wallpaper Editor's window holds one, with its own undo
/// stack. Every change is saved and applied as the window saves it (`WallpaperEditorController`):
/// the running instances draw a value change live or reload, a particle document change rebuilds
/// only its systems, and `announce` tells the Wallpaper Editor's process, whose open window of the
/// wallpaper takes the change as an undo step of its own.
///
/// An overlay saved by someone else since (an editor window, or its Undo) is adopted at the next
/// request with a fresh undo history (`refresh`), so an MCP Undo never undoes the user's work.
@MainActor
final class HeadlessSceneDocument {
    struct Dependencies {
        var store: SceneEditOverlayStore
        /// This process's own notifications: the running instances listen there.
        var center: NotificationCenter
        /// Tells the Wallpaper Editor's process (and the app's change sync) that the overlay of the
        /// wallpaper in `folder` was saved here, with the undo step's name and whether it was that
        /// step, or its Undo or Redo.
        var announce: @MainActor (_ folder: URL, _ overlay: SceneEditOverlay, _ actionName: String,
                                  _ step: AppProcessChannel.OverlayStep) -> Void
        var particleSchema: () throws -> ParticleEditorSchema
    }

    let wallpaper: ControlWallpaper
    let resources: SceneEditResources
    let timelineIndex: TimelineSceneIndex
    private(set) var session: SceneEditSession
    private let authoredOutline: SceneOutline
    private let dependencies: Dependencies
    /// The overlay as last saved here or adopted: a change of anything else is someone else's.
    private var savedOverlay: SceneEditOverlay
    private var savedSceneDigest: String
    /// The name of the step being saved, for the editor window that takes it.
    private var pendingActionName: String?
    /// Whether the change being saved is a new step, or an Undo or Redo of one.
    private var pendingStep: AppProcessChannel.OverlayStep = .edit
    /// Depth maps generated but not applied yet, by layer (`sceneDepthKey` for the scene).
    private var depthModels: [Int: DepthMapSectionModel] = [:]
    static let sceneDepthKey = Int.min

    /// The name of an MCP client's change in an editor's Edit menu.
    nonisolated static var defaultActionName: String {
        String(localized: "MCP Edit", comment: "Undo menu: a change an MCP client made to the wallpaper (Undo MCP Edit)")
    }

    init(wallpaper: ControlWallpaper, resources: SceneEditResources, dependencies: Dependencies) throws {
        self.wallpaper = wallpaper
        self.resources = resources
        self.dependencies = dependencies
        do {
            authoredOutline = try SceneOutline(sceneData: resources.sceneData)
        } catch {
            throw ControlError(.failed, "The scene of \"\(wallpaper.title)\" can't be read: \(error.localizedDescription)")
        }
        timelineIndex = Self.timelineIndex(resources.sceneData, title: wallpaper.title)
        let overlay = try Self.storedOverlay(resources.identity, store: dependencies.store, title: wallpaper.title)
        savedOverlay = overlay
        savedSceneDigest = Self.sceneDigest(overlay)
        session = Self.session(authoredOutline, overlay)
        attach(session)
    }

    private static func timelineIndex(_ scene: Data, title: String) -> TimelineSceneIndex {
        do {
            return try TimelineSceneIndex(sceneData: scene)
        } catch {
            OWELog.error(.scene, "MCP: the timelines of \(title) can't be read: \(error)")
            return .empty
        }
    }

    private static func storedOverlay(_ identity: WallpaperSettingsIdentity, store: SceneEditOverlayStore,
                                      title: String) throws -> SceneEditOverlay {
        do {
            return try store.overlay(for: identity.rawValue) ?? SceneEditOverlay()
        } catch {
            throw ControlError(.failed, "The edits of \"\(title)\" can't be read: \(error.localizedDescription)")
        }
    }

    /// A session whose undo steps are its commits: a request has no event loop turn of its own to
    /// group by, so each change (one request's list, a revert) is one step, as one control is in an editor.
    private static func session(_ outline: SceneOutline, _ overlay: SceneEditOverlay) -> SceneEditSession {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return SceneEditSession(outline: outline, overlay: overlay, undoManager: undoManager)
    }

    private func attach(_ session: SceneEditSession) {
        session.onChange = { [weak self] overlay in self?.save(overlay) }
    }

    // MARK: Someone else's edits

    /// Adopts an overlay saved elsewhere since this document last saved or read it; its undo
    /// history starts again. True when there was one.
    @discardableResult
    func refresh() throws -> Bool {
        let stored = try Self.storedOverlay(resources.identity, store: dependencies.store, title: wallpaper.title)
        guard stored != savedOverlay else { return false }
        savedOverlay = stored
        savedSceneDigest = Self.sceneDigest(stored)
        depthModels = [:]
        session = Self.session(authoredOutline, stored)
        attach(session)
        return true
    }

    // MARK: Editing

    /// Applies `edits` in order, all or nothing, as one undo step named `actionName`: they run on a
    /// copy of the session first, through the same session calls the editor's controls make, and
    /// only a list that went through whole changes the wallpaper. Returns each edit's result.
    func apply(_ edits: [ControlParameters], actionName: String?) throws -> [JSONValue] {
        let scratch = SceneEditSession(outline: authoredOutline, overlay: session.overlay)
        let context = SceneEditOperationContext(session: scratch, resources: resources, timelineIndex: timelineIndex,
                                                particleSchema: dependencies.particleSchema)
        var results: [JSONValue] = []
        for (index, edit) in edits.enumerated() {
            // Optional: only names the edit in the message; a wrong type is reported by the edit itself.
            let op = try? edit.string("op")
            do {
                results.append(try SceneEditOperations.apply(edit, in: context))
            } catch let error as ControlError {
                throw ControlError(error.code, "edits[\(index)]" + (op.map { " (\($0))" } ?? "") + ": \(error.message) Nothing was changed.")
            }
        }
        let next = scratch.overlay
        guard next != session.overlay else { return results }
        let name = actionName.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultActionName
        pendingActionName = name
        session.edit(actionName: name) { $0 = next }
        pendingActionName = nil
        return results
    }

    /// Runs `change` on the session itself (depth maps, which generate before they edit).
    func edit<Result>(actionName: String = HeadlessSceneDocument.defaultActionName,
                      _ change: (SceneEditSession) async throws -> Result) async rethrows -> Result {
        pendingActionName = actionName
        defer { pendingActionName = nil }
        return try await change(session)
    }

    /// Undoes the last step; an open editor window of the wallpaper undoes the same step (`announce`).
    func undo() -> Bool {
        guard session.canUndo else { return false }
        move(.undo, named: session.undoManager.undoActionName) { $0.undo() }
        return true
    }

    /// Redoes the last undone step, as an open editor window of the wallpaper does.
    func redo() -> Bool {
        guard session.canRedo else { return false }
        move(.redo, named: session.undoManager.redoActionName) { $0.redo() }
        return true
    }

    private func move(_ step: AppProcessChannel.OverlayStep, named name: String, _ change: (SceneEditSession) -> Void) {
        pendingStep = step
        pendingActionName = name.isEmpty ? nil : name
        defer {
            pendingStep = .edit
            pendingActionName = nil
        }
        change(session)
    }

    /// Drops every edit (locks stay), one undo step, as File › Revert does.
    func revert() {
        pendingActionName = String(localized: "Revert", comment: "Undo menu: dropping every edit of the wallpaper")
        session.revert(actionName: pendingActionName ?? "")
        pendingActionName = nil
    }

    /// The depth map section's model for `layer` (nil: the scene), kept until the next refresh so a
    /// depth map generated by one request is applied by the next.
    func depthModel(layer: Int?) -> DepthMapSectionModel? {
        let key = layer ?? Self.sceneDepthKey
        if let model = depthModels[key], model.session === session { return model }
        guard let services = resources.depthMapServices() else { return nil }
        let model = DepthMapSectionModel(session: session, layerID: layer, services: services)
        depthModels[key] = model
        return model
    }

    // MARK: Saving

    /// Saves the overlay and has the running instances apply it, as the editor window saves it; then
    /// the Wallpaper Editor's process hears of it.
    private func save(_ overlay: SceneEditOverlay) {
        let previous = savedOverlay
        let digest = Self.sceneDigest(overlay)
        let change = overlay.liveChange(from: previous)
        do {
            try dependencies.store.save(overlay, for: resources.identity.rawValue)
        } catch {
            OWELog.error(.scene, "MCP: can't save the editor overlay of \(wallpaper.title): \(error)")
            return
        }
        savedOverlay = overlay
        // A puppet edit or a lock doesn't change the running scene (`SceneEditOverlay.digest`).
        if digest != savedSceneDigest {
            switch change {
            case .scene:
                SceneEditOverlayFiles.post(overlay, base: session.baseOutline, wallpaperDirectory: resources.folder,
                                           transient: false, center: dependencies.center)
            case .particleAssets(let paths):
                SceneEditOverlayFiles.postParticles(overlay, wallpaperDirectory: resources.folder, paths: paths,
                                                    center: dependencies.center)
            }
        }
        savedSceneDigest = digest
        dependencies.announce(resources.folder, overlay, pendingActionName ?? Self.defaultActionName, pendingStep)
    }

    private static func sceneDigest(_ overlay: SceneEditOverlay) -> String {
        overlay.hasSceneEdits ? overlay.digest : ""
    }
}
