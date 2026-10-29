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
        try await sleepUntil("the QR code") { account.status == .signingIn(.scanQRCode(URL(string: "https://s.team/q/1/1")!)) }
        XCTAssertNil(store.load(), "nothing is saved before the scan")

        let signIn = try XCTUnwrap(fake.requests.first { $0.method == "signInWithQR" })
        fake.emit(Fake.result(signIn, Fake.loginJSON))
        try await sleepUntil("the login") { account.isSignedIn }
        XCTAssertEqual(account.accountName, Fake.login.accountName)
        XCTAssertEqual(store.load(), Fake.login)
        try await sleepUntil("the logon") { fake.methods.contains("logOn") }
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
        try await sleepUntil("the QR code") { if case .signingIn(.scanQRCode) = account.status { true } else { false } }
        account.cancelSignIn()
        try await sleepUntil("signed out") { account.status == .signedOut }
        XCTAssertNil(account.errorMessage)
        XCTAssertNil(store.load())
        XCTAssertTrue(fake.methods.contains("cancel"))
    }

    func testRestoreLogsOnWithTheSavedLogin() async throws {
        try store.save(Fake.login)
        let (account, fake) = makeAccount { [Fake.result($0)] }
        await account.restore()
        XCTAssertEqual(account.status, .signedIn(accountName: Fake.login.accountName))
        XCTAssertEqual(fake.methods, ["logOn"])
    }

    func testRestoreForgetsALoginSteamRejects() async throws {
        try store.save(Fake.login)
        let (account, _) = makeAccount { [Fake.error($0, code: "tokenRejected", eresult: 5)] }
        await account.restore()
        XCTAssertEqual(account.status, .signedOut)
        XCTAssertNil(store.load())
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
        try await sleepUntil("logged out") { account.status == .signedOut }
        XCTAssertNil(store.load())
        try await sleepUntil("the helper's logOff") { fake.methods.contains("logOff") }
    }
}
