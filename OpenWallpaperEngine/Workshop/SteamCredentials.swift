import Foundation

/// The Steam secret this app keeps, in the keychain: the Steam sign-in (`SteamLogin`), the account
/// and the refresh token the Steam helper logs on with.
///
/// The Steam password and Steam Guard codes are never stored: they go to the helper once, and
/// Steam answers with the refresh token.
enum SteamCredentials {
    /// The secret's keychain service suffix (`KeychainSecret.service`) and account.
    static let steamLoginItem = (suffix: "steam-login", account: "SteamLogin")

    static func steamLogin() -> KeychainSecret {
        KeychainSecret(keychain: KeychainStore(service: KeychainSecret.service(steamLoginItem.suffix)),
                       account: steamLoginItem.account)
    }
}
