import SwiftUI
import OWESceneEditing

/// A layer and the layers parented to it, as the list nests them.
struct LayerNode: Identifiable {
    let id: Int
    let layer: SceneLayer
    let children: [LayerNode]?

    /// The scene's layers as a tree, the topmost (drawn last) first at every level, as Photoshop,
    /// Pixelmator Pro, Motion and Figma list layers.
    static func tree(_ outline: SceneOutline) -> [LayerNode] {
        var placed = Set<Int>()
        func nodes(under parent: Int?) -> [LayerNode] {
            outline.children(of: parent).reversed().compactMap { layer in
                guard placed.insert(layer.id).inserted else { return nil }
                let children = nodes(under: layer.id)
                return LayerNode(id: layer.id, layer: layer, children: children.isEmpty ? nil : children)
            }
        }
        return nodes(under: nil)
    }
}

/// The layer hierarchy (scene.json's objects and their parents), with visibility and lock.
struct LayerListView: View {
    @ObservedObject var session: SceneEditSession
    @State private var tree: [LayerNode] = []

    var body: some View {
        List(selection: $session.selection) {
            Section {
                OutlineGroup(tree, children: \.children) { node in
                    LayerRow(session: session, layer: node.layer)
                        .tag(node.id)
                }
            } header: {
                Text(L("Layers"))
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if tree.isEmpty {
                Text(L("This scene has no layers."))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { tree = LayerNode.tree(session.outline) }
    }
}

private struct LayerRow: View {
    @ObservedObject var session: SceneEditSession
    let layer: SceneLayer
    @State private var isHovering = false

    var body: some View {
        let visible = session.isVisible(layer.id)
        let locked = session.isLocked(layer.id)
        HStack(spacing: 6) {
            Image(systemName: layer.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityLabel(layer.kind.title)
            Text(layer.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(visible ? .primary : .secondary)
            if session.isEdited(layer.id) {
                Circle()
                    .fill(.tint)
                    .frame(width: 6, height: 6)
                    .help(L("Edited"))
                    .accessibilityLabel(L("Edited"))
            }
            Spacer(minLength: 4)
            Button {
                session.setLocked(!locked, layer.id, actionName: locked ? L("Unlock Layer") : L("Lock Layer"))
            } label: {
                Label(locked ? L("Unlock Layer") : L("Lock Layer"), systemImage: locked ? "lock.fill" : "lock.open")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .opacity(locked || isHovering ? 1 : 0)
            .help(locked ? L("Unlock Layer") : L("Lock Layer"))
            visibilityButton(visible: visible)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private func visibilityButton(visible: Bool) -> some View {
        let editable = session.isEditable("visible", of: layer.id)
        Button {
            session.setVisible(!visible, layer.id, actionName: visible ? L("Hide Layer") : L("Show Layer"))
        } label: {
            Label(visible ? L("Hide Layer") : L("Show Layer"), systemImage: visible ? "eye" : "eye.slash")
                .labelStyle(.iconOnly)
                .foregroundStyle(visible ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .disabled(!editable)
        .help(editable ? (visible ? L("Hide Layer") : L("Show Layer")) : boundHelp)
    }

    private var boundHelp: String {
        if case .userProperty(let name) = session.binding("visible", of: layer.id) {
            return L("Set by the user property “\(name)”")
        }
        return ""
    }
}
