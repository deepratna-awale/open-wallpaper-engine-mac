import Foundation
import OWEControlProtocol

/// The control channel's requests for the system features OWE drives: iPhone and iPad Live Photo export, the screen saver and the lock-screen picture (`docs/mcp.md`).
@MainActor
final class SystemControlRequests: ControlRequestGroup {
    let methods: Set<String> = []

    static func make(app: AppDelegate, model: AppControlModel) -> SystemControlRequests {
        SystemControlRequests()
    }

    func result(for method: String, _ params: ControlParameters, lookup: ControlLookup) async throws -> JSONValue {
        throw ControlError(.unknownMethod, "The app doesn't know \"\(method)\".")
    }
}
