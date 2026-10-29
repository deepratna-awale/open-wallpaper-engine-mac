import XCTest
@testable import OpenWallpaperEngine

/// The Steam login the app keeps: signing in, restoring at launch and logging out, against a fake helper.
@MainActor
final class SteamAccountTests: XCTestCase {
    private typealias Fake = FakeSteamHelperTransport

    private var store: SteamLoginStore!

    override func setUp() async throws {
        store = SteamLoginStore(secret: KeychainSecret(
            keychain: KeychainStore(service: "app.openwallpaperengine.tests.keychain.\(UUID().uuidString)"), account: "SteamLogin"))
    }

    /// `sleepUntil` for main-actor state.
    private func waitFor(_ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting for \(what)", file: file, line: line) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeAccount(respond: @escaping @Sendable (FakeSteamHelperRequest) -> [String]) -> (SteamAccount, Fake) {
        let fake = Fake(respond: respond)
        let account = SteamAccount(client: SteamHelperClient { fake }, store: store, deviceName: "Test Mac")
        return (account, fake)
    }

    func testQRSignInShowsTheCodeThenSavesTheLogin() async throws {
        let (account, fake) = makeAccount { request in
            switch request.method {
            case "signInWithQR": [Fake.event(request, "qrChallenge", #""url":"https://s.team/q/1/1""#)]
            default: [Fake.result(request)]
            }
        }
        account.signInWithQR()
        try await waitFor("the QR code") { account.status == .signingIn(.scanQRCode(URL(string: "https://s.team/q/1/1")!)) }
        XCTAssertNil(store.load(), "nothing is saved before the scan")

        let signIn = try XCTUnwrap(fake.requests.first { $0.method == "signInWithQR" })
        fake.emit(Fake.result(signIn, Fake.loginJSON))
        try await waitFor("the login") { account.isSignedIn }
        XCTAssertEqual(account.accountName, Fake.login.accountName)
        XCTAssertEqual(store.load(), Fake.login)
        try await waitFor("the logon") { fake.methods.contains("logOn") }
        XCTAssertNil(account.errorMessage)
    }

    func testCancellingTheSignInSavesNothing() async throws {
        let (account, fake) = makeAccount { request in
            switch request.method {
            case "signInWithQR": return [Fake.event(request, "qrChallenge", #""url":"https://s.team/q/1/1""#)]
            case "cancel":
                let id = (request.param("id") as? NSNumber)?.int64Value ?? -1
                return [Fake.error(FakeSteamHelperRequest(id: id, method: "", params: Data()), code: "cancelled")]
            default: return []
            }
        }
        account.signInWithQR()
        try await waitFor("the QR code") { if case .signingIn(.scanQRCode) = account.status { true } else { false } }
        account.cancelSignIn()
        try await waitFor("signed out") { account.status == .signedOut }
        XCTAssertNil(account.errorMessage)
        XCTAssertNil(store.load())
        XCTAssertTrue(fake.methods.contains("cancel"))
    }

    func testRestoreLogsOnWithTheSavedLogin() async throws {
        try store.save(Fake.login)
        let (account, fake) = makeAccount { [Fake.result($0)] }
        await account.restore()
        XCTAssertEqual(account.status, .signedIn(accountName: Fake.login.accountName))
        XCTAssertEqual(account.login, Fake.login, "downloads use it")
        XCTAssertEqual(fake.methods, ["logOn", "ownsApp"])
    }

    func testRestoreAsksWhetherTheAccountOwnsWallpaperEngine() async throws {
        try store.save(Fake.login)
        let (account, fake) = makeAccount { request in
            switch request.method {
            case "ownsApp": [Fake.result(request, #"{"owned":false}"#)]
            default: [Fake.result(request)]
            }
        }
        await account.restore()
        XCTAssertEqual(account.ownsWallpaperEngine, false)
        XCTAssertEqual(fake.requests.last?.param("appID") as? Int, 431960)
        account.signOut()
        try await waitFor("logged out") { account.status == .signedOut }
        XCTAssertNil(account.ownsWallpaperEngine)
    }

    func testRestoreForgetsALoginSteamRejects() async throws {
        try store.save(Fake.login)
        let (account, _) = makeAccount { [Fake.error($0, code: "tokenRejected", eresult: 5)] }
        await account.restore()
        XCTAssertEqual(account.status, .signedOut)
        XCTAssertNil(store.load())
        XCTAssertNil(account.login)
        XCTAssertEqual(account.errorMessage, SteamHelperError(code: .tokenRejected, message: "").errorDescription)
    }

    /// Steam refusing the login partway through a session signs the account out, as at launch.
    func testALoginSteamRejectsDuringASessionIsForgotten() async throws {
        try store.save(Fake.login)
        let (account, _) = makeAccount { request in
            switch request.method {
            case "logOn": [Fake.result(request, #"{"steamID":"76561190000000001"}"#)]
            case "ownsApp": [Fake.result(request, #"{"owned":true}"#)]
            default: [Fake.error(request, code: "tokenRejected", eresult: 5)]
            }
        }
        await account.restore()
        XCTAssertTrue(account.isSignedIn)

        _ = try? await account.client.webAPIResponse("PublishedFile.QueryFiles", parameters: [])
        try await waitFor("signed out") { account.status == .signedOut }
        XCTAssertNil(store.load())
        XCTAssertNil(account.login)
        XCTAssertEqual(account.errorMessage, SteamHelperError(code: .tokenRejected, message: "").errorDescription)
    }

    func testRestoreWithoutANetworkKeepsTheLogin() async throws {
        try store.save(Fake.login)
        let (account, _) = makeAccount { [Fake.error($0, code: "network")] }
        await account.restore()
        XCTAssertEqual(account.status, .signedIn(accountName: Fake.login.accountName))
        XCTAssertEqual(store.load(), Fake.login)
    }

    func testRestoreWithoutASavedLoginStartsNoHelper() async {
        let (account, fake) = makeAccount { [Fake.result($0)] }
        await account.restore()
        XCTAssertEqual(account.status, .signedOut)
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testLogOutRemovesTheLogin() async throws {
        try store.save(Fake.login)
        let (account, fake) = makeAccount { [Fake.result($0)] }
        await account.restore()
        account.signOut()
        try await waitFor("logged out") { account.status == .signedOut }
        XCTAssertNil(store.load())
        XCTAssertNil(account.login)
        try await waitFor("the helper's logOff") { fake.methods.contains("logOff") }
    }
}
