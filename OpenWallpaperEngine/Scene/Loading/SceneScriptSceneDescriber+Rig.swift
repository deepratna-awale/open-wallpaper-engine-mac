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
        guard let data = file(puppet) else {
            OWELog.error(.script, "Puppet rig \(puppet) of \(path) is missing; its bone and animation-layer API is inert")
            return nil
        }
        let mdl: MDLModel
        do {
            mdl = try MDLModel(data: data)
        } catch {
            OWELog.error(.script, "Puppet rig \(puppet) of \(path) can't be read; its bone and animation-layer API is inert: \(error)")
            return nil
        }
        var layers: [WEAnimationLayer] = []
        if let animationLayers, let text = Self.jsonText(animationLayers) {
            do {
                layers = try JSONDecoder().decode([Failable<WEAnimationLayer>].self, from: Data(text.utf8)).compactMap(\.value)
            } catch {
                OWELog.error(.script, "The animation layers of \(path) can't be read: \(error)")
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
