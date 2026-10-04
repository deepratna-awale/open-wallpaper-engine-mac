import Foundation

/// `.state.json`: which install is active and which one came before it.
struct VersionedInstallState: Codable, Equatable {
    var active: String?
    var previous: String?

    static let fileName = ".state.json"

    static func read(in root: URL) -> VersionedInstallState {
        guard let data = try? Data(contentsOf: root.appending(path: fileName)),
              let state = try? JSONDecoder().decode(Self.self, from: data) else { return VersionedInstallState() }
        return state
    }

    func write(in root: URL) throws {
        try JSONEncoder().encode(self).write(to: root.appending(path: Self.fileName), options: .atomic)
    }
}
