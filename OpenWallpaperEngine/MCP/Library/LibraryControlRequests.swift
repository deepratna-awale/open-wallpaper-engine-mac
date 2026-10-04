import Foundation
import OWEControlProtocol

/// The control channel's requests for the library and the app: playlists, favourites, deleting wallpapers, displays, the app's settings and plugin status (`docs/mcp.md`).
@MainActor
final class LibraryControlRequests: ControlRequestGroup {
    let methods: Set<String> = []

    static func make(app: AppDelegate, model: AppControlModel) -> LibraryControlRequests {
        LibraryControlRequests()
    }

    func result(for method: String, _ params: ControlParameters, lookup: ControlLookup) async throws -> JSONValue {
        throw ControlError(.unknownMethod, "The app doesn't know \"\(method)\".")
    }
}
