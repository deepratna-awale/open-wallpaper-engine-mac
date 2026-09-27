import Foundation

extension SceneScriptSceneDescriber {
    /// A Puppet Warp image's rig for scripts: model JSON → `puppet` `.mdl`, played by the object's
    /// `animationlayers`. Nil for an image without a rig.
    func rig(model path: String, animationLayers: SceneJSON?) -> SceneScriptRigDescription? {
        guard let modelData = file(path),
              case .object(let model)? = try? decodeTolerant(SceneJSON.self, from: modelData),
              case .string(let puppet)? = model["puppet"] else {
            // Optional: most images have no rig.
            return nil
        }
        return rig(mdl: puppet, of: path, animationLayers: animationLayers)
    }

    /// A model object's rig for scripts (docs/models-plan.md §2.8): its `.mdl`'s skeleton, clips and
    /// attachment points, played by the object's `animationlayers`. Scripts get its animation-layer
    /// and attachment API; models have no bone API (0x140227814). Nil for a model without bones.
    func rig(modelObject path: String, animationLayers: SceneJSON?) -> SceneScriptRigDescription? {
        guard let description = rig(mdl: path, of: path, animationLayers: animationLayers),
              !description.bones.isEmpty else { return nil }
        return description
    }

    /// The rig of `.mdl` `path` (named by `owner`), played by `animationLayers`.
    private func rig(mdl path: String, of owner: String, animationLayers: SceneJSON?) -> SceneScriptRigDescription? {
        guard let data = file(path) else {
            OWELog.error(.script, "Rig \(path) of \(owner) is missing; its bone and animation-layer API is inert")
            return nil
        }
        let mdl: MDLModel
        do {
            mdl = try MDLModel(data: data)
        } catch {
            OWELog.error(.script, "Rig \(path) of \(owner) can't be read; its bone and animation-layer API is inert: \(error)")
            return nil
        }
        var layers: [WEAnimationLayer] = []
        if let animationLayers, let text = Self.jsonText(animationLayers) {
            do {
                layers = try JSONDecoder().decode([Failable<WEAnimationLayer>].self, from: Data(text.utf8)).compactMap(\.value)
            } catch {
                OWELog.error(.script, "The animation layers of \(owner) can't be read: \(error)")
            }
        }
        return SceneScriptRigDescription(model: mdl, layers: layers)
    }
}

/// One array element that may fail to decode on its own.
private struct Failable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        do {
            value = try Value(from: decoder)
        } catch {
            // Element by element: the loader logs a bad layer when it builds the scene.
            value = nil
        }
    }
}
