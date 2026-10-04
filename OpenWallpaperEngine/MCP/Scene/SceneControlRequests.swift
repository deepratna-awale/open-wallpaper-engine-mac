import Foundation
import OWEControlProtocol

/// The control channel's requests for the scene and both editors: the edit model (headless edit sessions on the editor overlay), effects, particles, puppets, the timeline, SceneScript, the wallpaper's own user properties, depth maps and the editors' windows (`docs/mcp.md`).
@MainActor
final class SceneControlRequests: ControlRequestGroup {
    let methods: Set<String> = []

    static func make(app: AppDelegate, model: AppControlModel) -> SceneControlRequests {
        SceneControlRequests()
    }

    func result(for method: String, _ params: ControlParameters, lookup: ControlLookup) async throws -> JSONValue {
        throw ControlError(.unknownMethod, "The app doesn't know \"\(method)\".")
    }
}
