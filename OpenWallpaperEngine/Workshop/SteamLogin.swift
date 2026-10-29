import Foundation

/// A Steam sign-in: the account and the refresh token the Steam helper logs on with (about 200
/// days; Steam can revoke it sooner). It never reaches a log: its descriptions leave the token out.
struct SteamLogin: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let accountName: String
    /// The 64-bit SteamID, in decimal.
    let steamID: String
    let refreshToken: String

    var description: String { "SteamLogin(\(accountName), \(steamID))" }
    var debugDescription: String { description }
}

/// The saved sign-in, one keychain item holding `SteamLogin` as JSON.
struct SteamLoginStore: Sendable {
    let secret: KeychainSecret

    static func app() -> SteamLoginStore { SteamLoginStore(secret: SteamCredentials.steamLogin()) }

    /// The saved sign-in, or nil when there is none or it can't be read.
    func load() -> SteamLogin? {
        guard let json = secret.load() else { return nil }
        do {
            return try JSONDecoder().decode(SteamLogin.self, from: Data(json.utf8))
        } catch {
            OWELog.error(.workshop, "Can't read the saved Steam sign-in: \(error)")
            return nil
        }
    }

    func save(_ login: SteamLogin) throws {
        try secret.save(String(decoding: try JSONEncoder().encode(login), as: UTF8.self))
    }

    func remove() throws {
        try secret.remove()
    }
}
