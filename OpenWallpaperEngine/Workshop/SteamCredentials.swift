import Foundation

/// The Steam secrets this app keeps, all in the keychain.
///
/// - The Web API key (Workshop browse/search and `GetPlayerSummaries`).
/// - The steamcmd account name, so the cached steamcmd session can be reused at launch.
///
/// The Steam password and Steam Guard codes are never stored: they are piped to steamcmd once,
/// and steamcmd keeps its own login token for later sessions (it never stores the password).
enum SteamCredentials {
    /// Each secret's keychain service suffix (`KeychainSecret.service`) and account.
    static let webAPIKeyItem = (suffix: "steam-web-api-key", account: "SteamWebAPIKey")
    static let steamCmdAccountItem = (suffix: "steamcmd-account", account: "SteamLastUsername")
    static let keychainItems = [webAPIKeyItem, steamCmdAccountItem]

    static func webAPIKey(defaults: UserDefaults = .app) -> KeychainSecret {
        KeychainSecret(
            keychain: KeychainStore(service: KeychainSecret.service(webAPIKeyItem.suffix)),
            account: webAPIKeyItem.account,
            legacyDefaultsKey: "SteamWebAPIKey",
            defaults: defaults
        )
    }

    static func steamCmdAccount(defaults: UserDefaults = .app) -> KeychainSecret {
        KeychainSecret(
            keychain: KeychainStore(service: KeychainSecret.service(steamCmdAccountItem.suffix)),
            account: steamCmdAccountItem.account,
            legacyDefaultsKey: "SteamLastUsername",
            defaults: defaults
        )
    }
}
