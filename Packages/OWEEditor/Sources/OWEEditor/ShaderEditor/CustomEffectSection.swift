import SwiftUI
import OWESceneEditing

/// An editable effect's Shaders in the inspector (WE's `ui_editor_properties_shaders` with an
/// Edit button beside each shader, `editablefile`): each material's vertex and fragment shader,
/// opened in the shader editor. Only for the wallpaper's own editable effects (My Effects).
struct CustomEffectSection: View {
    @ObservedObject var session: SceneEditSession
    @EnvironmentObject private var shaders: ShaderEditorModel
    let layer: SceneLayer
    let effect: SceneLayerEffect

    var body: some View {
        if let effectInfo = CustomEffectInfo.read(effect.file, model: shaders) {
            Text(L("Shaders")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(effectInfo.materials, id: \.path) { material in
                ForEach([ShaderDiagnostic.Stage.vertex, .fragment], id: \.self) { stage in
                    LabeledContent(stage == .vertex ? L("Vertex Shader") : L("Fragment Shader")) {
                        HStack(spacing: 6) {
                            Text("\((material.shader as NSString).lastPathComponent).\(stage.rawValue)")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button(L("Edit")) {
                                shaders.open(effectFile: effect.file, title: effectInfo.title, shader: material.shader, stage: stage,
                                             layerID: layer.id, effectKey: effect.key)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// What the inspector shows of an editable effect: its title and each material with its shader.
struct CustomEffectInfo {
    struct Material {
        /// The editor's file of the material (`effects/<id>/materials/effects/<id>.json`).
        var path: String
        var shader: String
    }

    var title: String
    var materials: [Material]

    /// The effect at `file` when it is one the editor can edit: made in the editor, or the
    /// wallpaper's own with `editable` set (WE's `localeffects`).
    @MainActor
    static func read(_ file: String, model: ShaderEditorModel) -> CustomEffectInfo? {
        guard let text = model.text(at: file),
              let json = try? WETolerantJSON.object(from: Data(text.utf8)) as? [String: Any] else { return nil }
        let madeHere = model.session.overlay.effectFile(file) != nil
        guard madeHere || json["editable"] as? Bool == true else { return nil }
        let directory = (file as NSString).deletingLastPathComponent
        var materials: [Material] = []
        for pass in json["passes"] as? [[String: Any]] ?? [] {
            guard let relative = pass["material"] as? String else { continue }
            let path = model.resolvedPath(relative, in: directory)
            guard !materials.contains(where: { $0.path == path }), let materialText = model.text(at: path),
                  let material = try? WETolerantJSON.object(from: Data(materialText.utf8)) as? [String: Any],
                  let shader = (material["passes"] as? [[String: Any]])?.first?["shader"] as? String else { continue }
            materials.append(Material(path: path, shader: shader))
        }
        return CustomEffectInfo(title: json["name"] as? String ?? (directory as NSString).lastPathComponent, materials: materials)
    }
}
