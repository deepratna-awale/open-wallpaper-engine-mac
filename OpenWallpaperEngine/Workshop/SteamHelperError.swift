import Foundation

/// A failed Steam helper request: the helper's error (`SteamHelper/README.md`), or the helper
/// itself missing, exiting or answering something unreadable.
struct SteamHelperError: Error, Equatable, LocalizedError {
    enum Code: String, Sendable {
        // The helper's codes.
        case invalidRequest, unknownMethod, notLoggedOn, tokenRejected, wrongPassword, cancelled, network, steam, `internal`
        // The app's own.
        /// No helper in this build (`SteamHelperLocator`).
        case helperMissing
        /// The helper exited or couldn't be started.
        case helperExited
        /// The helper's answer couldn't be read.
        case badResponse
    }

    let code: Code
    /// The helper's message, in English, for the log.
    let message: String
    /// Steam's EResult, when Steam gave one.
    var eresult: Int?

    /// The saved sign-in no longer works: the user signs in again.
    var needsNewSignIn: Bool { code == .tokenRejected }

    var errorDescription: String? {
        switch code {
        case .tokenRejected:
            String(localized: "Steam ended your login. Log in to Steam again.")
        case .wrongPassword:
            String(localized: "The account name or password is wrong.")
        case .network:
            String(localized: "Can't reach Steam. Check your internet connection and try again.")
        case .helperMissing:
            String(localized: "This copy of Open Wallpaper Engine has no Steam helper. Install a release build.",
                   comment: "The Steam helper is the program that connects the app to Steam")
        default:
            String(localized: "Steam reported an error: \(message)",
                   comment: "%@ is Steam's or the helper's message, in English")
        }
    }
}
