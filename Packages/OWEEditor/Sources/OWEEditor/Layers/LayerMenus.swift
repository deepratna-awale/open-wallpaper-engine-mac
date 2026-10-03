import SwiftUI
import OWESceneEditing

/// The toolbar's Add menu: the layers WE's editor adds.
struct AddLayerMenu: View {
    let actions: LayerActions

    var body: some View {
        Menu {
            Button { actions.chooseImages() } label: { Label(L("Image…"), systemImage: "photo") }
                .disabled(actions.services.assetStore == nil)
            Menu {
                Button(L("Text")) { actions.addText() }
                Button(L("Clock")) { actions.addText(script: .clock) }
                Button(L("Date")) { actions.addText(script: .date) }
            } label: {
                Label(L("Text"), systemImage: "textformat")
            }
            Button { actions.addSolid() } label: { Label(L("Solid Color"), systemImage: "square.fill") }
            Button { actions.addComposition() } label: { Label(L("Composition Layer"), systemImage: "square.on.square.dashed") }
            Button { actions.addFullscreen() } label: { Label(L("Fullscreen Layer"), systemImage: "rectangle.inset.filled") }
            Divider()
            Button { actions.chooseSounds() } label: { Label(L("Sound…"), systemImage: "speaker.wave.2") }
                .disabled(actions.services.assetStore == nil)
        } label: {
            Label(L("Add Layer"), systemImage: "plus")
        }
        .help(L("Add a layer to the scene"))
    }
}

/// A layer's context menu in the list and on the canvas.
struct LayerContextMenu: View {
    @ObservedObject var session: SceneEditSession
    let layer: SceneLayer
    let actions: LayerActions

    var body: some View {
        Button(L("Rename")) { actions.tools.renaming = layer.id }
            .disabled(!session.isEditable("name", of: layer.id))
        Button(L("Duplicate")) { actions.duplicate(layer.id) }
        Button(L("Delete"), role: .destructive) { actions.delete(layer.id) }
        Divider()
        Menu(L("Arrange")) {
            Button(L("Bring to Front")) { actions.bringToFront(layer.id) }
            Button(L("Bring Forward")) { actions.bringForward(layer.id) }
            Button(L("Send Backward")) { actions.sendBackward(layer.id) }
            Button(L("Send to Back")) { actions.sendToBack(layer.id) }
        }
        if layer.isPlanar, session.outline.size != nil {
            Menu(L("Align to Scene")) {
                AlignmentButtons(actions: actions, layerID: layer.id)
            }
        }
        Divider()
        Button(L("Group")) { actions.group(layer.id) }
        if !session.outline.children(of: layer.id).isEmpty {
            Button(L("Ungroup")) { actions.ungroup(layer.id) }
        }
        if layer.parentID.flatMap(session.outline.layer) != nil {
            Button(L("Move Out of Group")) { actions.unparent(layer.id) }
        }
        let groups: [SceneLayer] = session.outline.layers.filter { (candidate: SceneLayer) -> Bool in
            guard candidate.id != layer.id else { return false }
            let isGroupLike: Bool = candidate.kind == .group || candidate.kind == .other
            return isGroupLike && session.canParent(layer.id, to: candidate.id)
        }
        if !groups.isEmpty {
            Menu(L("Move Into Group")) {
                ForEach(groups) { group in
                    Button(group.title) { actions.parent(layer.id, to: group.id) }
                }
            }
        }
    }
}

/// Align to the scene's edges and centre lines.
struct AlignmentButtons: View {
    let actions: LayerActions
    let layerID: Int

    var body: some View {
        Button { actions.align(layerID, horizontal: 0) } label: { Label(L("Align Left Edges"), systemImage: "align.horizontal.left") }
        Button { actions.align(layerID, horizontal: 1) } label: { Label(L("Align Horizontal Centers"), systemImage: "align.horizontal.center") }
        Button { actions.align(layerID, horizontal: 2) } label: { Label(L("Align Right Edges"), systemImage: "align.horizontal.right") }
        Divider()
        Button { actions.align(layerID, vertical: 2) } label: { Label(L("Align Top Edges"), systemImage: "align.vertical.top") }
        Button { actions.align(layerID, vertical: 1) } label: { Label(L("Align Vertical Centers"), systemImage: "align.vertical.center") }
        Button { actions.align(layerID, vertical: 0) } label: { Label(L("Align Bottom Edges"), systemImage: "align.vertical.bottom") }
        Divider()
        Button { actions.align(layerID, horizontal: 1, vertical: 1) } label: { Label(L("Center on Scene"), systemImage: "plus.viewfinder") }
    }
}
