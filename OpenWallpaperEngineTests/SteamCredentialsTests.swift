import Security
import XCTest
@testable import OpenWallpaperEngine

/// Keychain storage of the Steam login, keeping secrets out of logs, and the Workshop's need for the login. The test host's
/// `KeychainStore` keeps its items in memory (`AppStorageIsolationTests`), so these never call the keychain.
final class SteamCredentialsTests: XCTestCase {
    private var keychain: KeychainStore!

    override func setUpWithError() throws {
        keychain = KeychainStore(service: "app.openwallpaperengine.tests.keychain.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        for account in ["token", "SteamLogin"] {
            try keychain.removeValue(forAccount: account)
        }
        StubURLProtocol.handler = nil
    }

    // MARK: Keychain store

    func testKeychainStoreRoundTripsReplacesAndRemoves() throws {
        try requireKeychain()
        XCTAssertNil(try keychain.string(forAccount: "token"))

        try keychain.set("first", forAccount: "token")
        XCTAssertEqual(try keychain.string(forAccount: "token"), "first")

        try keychain.set("second", forAccount: "token")
        XCTAssertEqual(try keychain.string(forAccount: "token"), "second")

        try keychain.removeValue(forAccount: "token")
        XCTAssertNil(try keychain.string(forAccount: "token"))
        XCTAssertNoThrow(try keychain.removeValue(forAccount: "token"), "removing a missing value succeeds")
    }

    func testKeychainAccountsAreIndependent() throws {
        try requireKeychain()
        try keychain.set("a", forAccount: "token")
        XCTAssertNil(try keychain.string(forAccount: "SteamLogin"))
        XCTAssertNil(try KeychainStore(service: keychain.service + ".other").string(forAccount: "token"))
    }

    func testSaveAndRemove() throws {
        try requireKeychain()
        try secret.save("NEW")
        XCTAssertEqual(secret.load(), "NEW")

        try secret.remove()
        XCTAssertNil(secret.load())
    }

    func testCredentialServicesLiveUnderTheIsolatedPrefix() {
        // Under XCTest the prefix is the isolated suite, so no test can touch the real items.
        let bundleId = AppStorageLocation.current.keychainServicePrefix
        XCTAssertTrue(bundleId.contains(".isolated."), bundleId)
        XCTAssertEqual(SteamCredentials.steamLogin().keychain.service, "\(bundleId).steam-login")
    }

    // MARK: Redaction

    func testRedactsLiteralSecrets() {
        XCTAssertEqual(SteamSecretRedactor.redact("token hunter2 / 12345", secrets: ["hunter2", "12345", ""]),
                       "token <redacted> / <redacted>")
        XCTAssertEqual(SteamSecretRedactor.redact("nothing secret"), "nothing secret")
    }

    // MARK: The Workshop needs the Steam login

    func testSearchWithoutTheLoginFailsBeforeAnyRequest() async throws {
        StubURLProtocol.handler = { _ in
            XCTFail("no request without the login")
            return (500, Data())
        }
        do {
            _ = try await service.searchItems()
            XCTFail("search needs the login")
        } catch WorkshopAPIError.notLoggedIn {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: Keyless author names

    func testParsesPersonaNameAndAvatarFromTheProfileXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><profile>
        <steamID64>76561197960287930</steamID64>
        <steamID><![CDATA[Rabscuttle]]></steamID>
        <avatarFull><![CDATA[https://avatars.akamai.steamstatic.com/abc_full.jpg]]></avatarFull>
        <groups><group><groupID64>1</groupID64><steamID><![CDATA[Not the name]]></steamID></group></groups>
        </profile>
        """
        let player = try XCTUnwrap(SteamProfileXMLParser.player(from: Data(xml.utf8), steamId: "76561197960287930"))
        XCTAssertEqual(player.personaName, "Rabscuttle")
        XCTAssertEqual(player.steamId, "76561197960287930")
        XCTAssertEqual(player.avatarURL?.absoluteString, "https://avatars.akamai.steamstatic.com/abc_full.jpg")
    }

    func testMissingProfileParsesToNil() {
        let xml = #"<?xml version="1.0"?><response><error><![CDATA[The specified profile could not be found.]]></error></response>"#
        XCTAssertNil(SteamProfileXMLParser.player(from: Data(xml.utf8), steamId: "1"))
    }

    // MARK: Helpers

    private var secret: KeychainSecret {
        KeychainSecret(keychain: keychain, account: "SteamLogin")
    }

    private var service: WorkshopAPIService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return WorkshopAPIService(session: URLSession(configuration: configuration))
    }

    /// Skips on a machine without a usable keychain (a headless runner with no login keychain).
    private func requireKeychain() throws {
        do {
            try keychain.set("probe", forAccount: "token")
            try keychain.removeValue(forAccount: "token")
        } catch let failure as KeychainStore.Failure
            where [errSecNoSuchKeychain, errSecInteractionNotAllowed, errSecNotAvailable].contains(failure.status) {
            throw XCTSkip("No usable keychain: \(failure)")
        }
    }
}

private final class StubURLProtocol: URLProtocol {
    // Set by one test before it awaits its request and cleared in tearDown; tests run serially.
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
