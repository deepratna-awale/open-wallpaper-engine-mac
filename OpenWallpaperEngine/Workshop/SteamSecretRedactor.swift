import Foundation

/// Strips Steam secrets from text before it is logged or shown: every literal secret passed in
/// (the refresh token, a password, a Steam Guard code).
enum SteamSecretRedactor {
    static let placeholder = "<redacted>"

    static func redact(_ text: String, secrets: [String] = []) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }
        return result
    }
}
