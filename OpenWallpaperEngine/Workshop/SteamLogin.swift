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

    /// How long before `expiresAt` the app asks for a new login.
    static let renewalWarning: TimeInterval = 14 * 24 * 60 * 60

    /// When Steam stops accepting the refresh token: its JWT's `exp` claim. Nil when the token
    /// doesn't say. Steam never renews it, so the user logs in again before then.
    var expiresAt: Date? { Self.expiry(ofJWT: refreshToken) }

    /// Whether the login ends within `renewalWarning` of `now`.
    func endsSoon(now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < Self.renewalWarning
    }

    /// The `exp` claim of a JWT, unverified: Steam checks the token at every logon.
    static func expiry(ofJWT jwt: String) -> Date? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        struct Claims: Decodable { let exp: TimeInterval? }
        do {
            return try JSONDecoder().decode(Claims.self, from: data).exp.map { Date(timeIntervalSince1970: $0) }
        } catch {
            OWELog.error(.workshop, "Can't read the Steam login's expiry: \(error)")
            return nil
        }
    }
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
