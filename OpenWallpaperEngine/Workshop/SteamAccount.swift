import Foundation
import SystemConfiguration

/// The user's Steam sign-in: a QR code scanned with the Steam mobile app, or an account name and
/// password with a Steam Guard code. The sign-in is kept in the keychain (`SteamLoginStore`) and
/// used for everything the app does on Steam, through the Steam helper (`SteamHelperClient`).
@MainActor
final class SteamAccount: ObservableObject {
    enum Status: Equatable {
        case signedOut
        /// Logging on with the saved sign-in at launch.
        case restoring(accountName: String)
        case signingIn(SignInStep)
        case signedIn(accountName: String)
    }

    enum SignInStep: Equatable {
        /// Waiting for Steam's first QR code, or for Steam to check a password.
        case starting
        case scanQRCode(URL)
        case guardCode(email: String?, previousCodeWasIncorrect: Bool)
        case confirmOnPhone
    }

    @Published private(set) var status: Status = .signedOut
    /// Why the last sign-in or logon failed, for the user.
    @Published private(set) var errorMessage: String?
    /// The sign-in requests use, from launch or a sign-in until it is forgotten; Workshop downloads
    /// use it too (`WorkshopDownloadService.useSteamLogin`).
    @Published private(set) var login: SteamLogin?

    let client: SteamHelperClient
    private let store: SteamLoginStore
    private let deviceName: String
    private var signInTask: Task<Void, Never>?

    init(client: SteamHelperClient = .app(), store: SteamLoginStore = .app(),
         deviceName: String = SteamAccount.defaultDeviceName) {
        self.client = client
        self.store = store
        self.deviceName = deviceName
    }

    /// How Steam lists this sign-in under the account's authorized devices.
    nonisolated static var defaultDeviceName: String {
        // The computer's name from Sharing settings; `Host.current()` can block on DNS.
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
        return "Open Wallpaper Engine (\(computerName))"
    }

    var isSignedIn: Bool {
        if case .signedIn = status { true } else { false }
    }

    var accountName: String? {
        switch status {
        case .signedIn(let name), .restoring(let name): name
        case .signedOut, .signingIn: nil
        }
    }

    /// Logs on with the saved sign-in, if any. Without a network the account stays signed in and
    /// later requests log on; a sign-in Steam no longer accepts is removed.
    func restore() async {
        guard let login = store.load() else { return }
        status = .restoring(accountName: login.accountName)
        await adopt(login)
        do {
            try await client.ensureLoggedOn()
            status = .signedIn(accountName: login.accountName)
        } catch let error as SteamHelperError where error.needsNewSignIn {
            OWELog.info(.workshop, "Steam no longer accepts the saved sign-in: \(error.message)")
            await forget(error)
        } catch {
            OWELog.error(.workshop, "Can't log on to Steam at launch: \(error)")
            status = .signedIn(accountName: login.accountName)
        }
    }

    func signInWithQR() {
        signIn { client, deviceName, onEvent in
            try await client.signInWithQR(deviceName: deviceName, onEvent: onEvent)
        }
    }

    func signIn(accountName: String, password: String) {
        signIn { client, deviceName, onEvent in
            try await client.signInWithCredentials(accountName: accountName, password: password,
                                                   deviceName: deviceName, onEvent: onEvent)
        }
    }

    func submitGuardCode(_ code: String) {
        status = .signingIn(.starting)
        Task {
            do {
                try await client.submitGuardCode(code)
            } catch {
                OWELog.error(.workshop, "Can't send the Steam Guard code: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func signOut() {
        signInTask?.cancel()
        Task { await forget(nil) }
    }

    // MARK: -

    private func signIn(_ start: @escaping @Sendable (SteamHelperClient, String,
                                                      @escaping @Sendable (SteamSignInEvent) async -> Void) async throws -> SteamLogin) {
        signInTask?.cancel()
        errorMessage = nil
        status = .signingIn(.starting)
        let client = client, deviceName = deviceName
        signInTask = Task {
            do {
                let login = try await start(client, deviceName) { [weak self] event in
                    await self?.show(event)
                }
                try store.save(login)
                await adopt(login)
                status = .signedIn(accountName: login.accountName)
                OWELog.info(.workshop, "Signed in to Steam as \(login.accountName)")
                try await client.ensureLoggedOn()
            } catch let error as SteamHelperError where error.code == .cancelled {
                status = .signedOut
            } catch is CancellationError {
                status = .signedOut
            } catch {
                OWELog.error(.workshop, "Steam sign-in failed: \(error)")
                if !isSignedIn { status = .signedOut }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func show(_ event: SteamSignInEvent) {
        guard case .signingIn = status else { return }
        switch event {
        case .qrChallenge(let url):
            status = .signingIn(.scanQRCode(url))
        case .guardCodeRequired(let email, let previousCodeWasIncorrect):
            status = .signingIn(.guardCode(email: email, previousCodeWasIncorrect: previousCodeWasIncorrect))
        case .deviceConfirmationRequired:
            status = .signingIn(.confirmOnPhone)
        }
    }

    /// Has the client log on with `login`, and forget it when Steam stops accepting it.
    private func adopt(_ login: SteamLogin) async {
        await client.setLoginRejectedHandler { [weak self] in
            await self?.loginRejected()
        }
        await client.use(login)
        self.login = login
    }

    /// Steam no longer accepts the login: it is forgotten, and the user is asked to log in again.
    func loginRejected() async {
        // Concurrent requests can each report it; the first forgets the login.
        guard isSignedIn, login != nil else { return }
        OWELog.info(.workshop, "Steam no longer accepts the saved login")
        await forget(SteamHelperError(code: .tokenRejected, message: "The saved login was rejected."))
    }

    /// Removes the saved sign-in; `reason` is shown when Steam ended it.
    private func forget(_ reason: SteamHelperError?) async {
        login = nil
        await client.use(nil)
        do {
            try store.remove()
        } catch {
            OWELog.error(.workshop, "Can't remove the saved Steam sign-in: \(error)")
        }
        status = .signedOut
        errorMessage = reason?.localizedDescription
    }
}
