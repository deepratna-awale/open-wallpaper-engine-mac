import SwiftUI
import OWESceneEditing

/// A field's scripting and binding actions beside its control in the inspector, as WE's editor
/// offers them on every property: add or edit a script, bind it to a user property, or undo
/// either. The menu's symbol says what drives the field now.
struct FieldAuthoringModifier: ViewModifier {
    @EnvironmentObject private var authoring: EditorAuthoringModel
    let target: FieldTarget

    func body(content: Content) -> some View {
        let drivers = authoring.session.drivers(target.path, of: target.layer)
        HStack(spacing: 4) {
            content
            Menu {
                FieldAuthoringMenuItems(authoring: authoring, target: target, drivers: drivers)
            } label: {
                Image(systemName: Self.symbol(drivers))
                    .foregroundStyle(drivers.script != nil || drivers.user != nil ? Color.accentColor : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Self.help(drivers))
            .accessibilityLabel(L("Script and Binding"))
        }
        .contextMenu {
            FieldAuthoringMenuItems(authoring: authoring, target: target, drivers: drivers)
        }
    }

    static func symbol(_ drivers: SceneFieldDrivers) -> String {
        if drivers.script != nil { return "curlybraces.square.fill" }
        if drivers.user != nil { return "link.circle.fill" }
        return "ellipsis.circle"
    }

    static func help(_ drivers: SceneFieldDrivers) -> String {
        if let user = drivers.user, drivers.script != nil {
            return L("A script and the user property “\(user.name)” set this field")
        }
        if drivers.script != nil { return L("A script sets this field") }
        if let user = drivers.user { return L("Set by the user property “\(user.name)”") }
        return L("Add a script or bind a user property")
    }
}

extension View {
    /// The field's script and binding menu (`FieldAuthoringModifier`).
    func fieldAuthoring(layer: Int, path: SceneFieldPath) -> some View {
        modifier(FieldAuthoringModifier(target: FieldTarget(layer: layer, path: path)))
    }
}

struct FieldAuthoringMenuItems: View {
    @ObservedObject var authoring: EditorAuthoringModel
    let target: FieldTarget
    let drivers: SceneFieldDrivers

    var body: some View {
        if drivers.script != nil {
            Button(L("Edit Script…")) { authoring.editScript(target) }
            Button(L("Remove Script"), role: .destructive) { authoring.removeScript(target) }
        } else {
            Button(L("Add Script…")) { authoring.editScript(target) }
            let templates = SceneScriptTemplate.templates(for: target.path.name).filter { $0.id != .empty }
            if !templates.isEmpty {
                Menu(L("Add Script from Template")) {
                    ForEach(templates) { template in
                        Button(template.id.title) { authoring.editScript(target, template: template.id) }
                    }
                }
            }
        }
        if EditorAuthoringModel.propertyKind(for: target.path) != nil {
            Divider()
            if let user = drivers.user {
                Button(L("Change User Property…")) { authoring.bindingTarget = target }
                Button(L("Unbind “\(user.name)”")) {
                    authoring.session.unbind(target.path, of: target.layer, actionName: L("Unbind User Property"))
                }
            } else {
                Button(L("Bind to User Property…")) { authoring.bindingTarget = target }
            }
        }
    }
}

/// The scripts of the selected layer: each field that runs one, and Add Script for the others.
struct LayerScriptsSection: View {
    @EnvironmentObject private var authoring: EditorAuthoringModel
    let layer: SceneLayer

    var body: some View {
        let scripted = authoring.session.scriptedFields(of: layer.id)
        Section {
            if scripted.isEmpty {
                Text(L("No scripts")).foregroundStyle(.secondary)
            }
            ForEach(scripted, id: \.self) { path in
                let target = FieldTarget(layer: layer.id, path: path)
                HStack {
                    Label(EditorAuthoringModel.fieldTitle(path, layer: layer), systemImage: "curlybraces")
                    Spacer()
                    let errors = authoring.console?.diagnostics(of: layer.id, path).count ?? 0
                    if errors > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(L("The script reported errors"))
                    }
                    Button(L("Edit")) { authoring.editScript(target) }
                        .buttonStyle(.borderless)
                }
                .contextMenu {
                    Button(L("Edit Script…")) { authoring.editScript(target) }
                    Button(L("Remove Script"), role: .destructive) { authoring.removeScript(target) }
                }
            }
            let available = authoring.scriptableFields(of: layer).filter { !scripted.contains($0) }
            if !available.isEmpty {
                Menu {
                    ForEach(available, id: \.self) { path in
                        Button(path == .objectScript ? L("Object Script")
                               : EditorAuthoringModel.fieldTitle(path, layer: layer)) {
                            authoring.editScript(FieldTarget(layer: layer.id, path: path))
                        }
                    }
                } label: {
                    Label(L("Add Script"), systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } header: {
            Text(L("Scripts"))
        }
    }
}
