import XCTest
@testable import OpenWallpaperEngine

/// The app's side of the Steam helper's protocol (SteamHelper/README.md), against a fake helper.
final class SteamHelperClientTests: XCTestCase {
    private typealias Fake = FakeSteamHelperTransport

    /// Collects what a test's callbacks receive, in order.
    private final class Box<Value: Sendable>: @unchecked Sendable { // `lock` owns `values`.
        private let lock = NSLock()
        private var stored: [Value] = []
        var values: [Value] { lock.withLock { stored } }
        func append(_ value: Value) { lock.withLock { stored.append(value) } }
    }

    private func makeClient(_ transports: Box<Fake>, respond: @escaping @Sendable (FakeSteamHelperRequest) -> [String]) -> SteamHelperClient {
        SteamHelperClient {
            let transport = Fake(respond: respond)
            transports.append(transport)
            return transport
        }
    }

    func testResponsesReachTheirOwnRequests() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { _ in [] }
        async let first = client.ping()
        async let second = client.ping()
        try await sleepUntil("both requests") { transports.values.first?.requests.count == 2 }
        let fake = try XCTUnwrap(transports.values.first)
        let requests = fake.requests
        // Answered in reverse.
        fake.emit(Fake.result(requests[1], #"{"version":"second"}"#))
        fake.emit(Fake.result(requests[0], #"{"version":"first"}"#))
        let versions = try await [first, second]
        XCTAssertEqual(Set(versions), ["first", "second"])
        XCTAssertEqual(transports.values.count, 1, "one helper serves both")
    }

    func testQRSignInShowsEachCodeInOrderAndReturnsTheLogin() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { request in
            guard request.method == "signInWithQR" else { return [] }
            XCTAssertEqual(request.param("deviceName") as? String, "Test Mac")
            return [Fake.event(request, "qrChallenge", #""url":"https://s.team/q/1/1""#),
                    Fake.event(request, "qrChallenge", #""url":"https://s.team/q/1/2""#),
                    Fake.result(request, Fake.loginJSON)]
        }
        let events = Box<SteamSignInEvent>()
        let login = try await client.signInWithQR(deviceName: "Test Mac") { events.append($0) }
        XCTAssertEqual(login, Fake.login)
        XCTAssertEqual(events.values, [.qrChallenge(URL(string: "https://s.team/q/1/1")!),
                                       .qrChallenge(URL(string: "https://s.team/q/1/2")!)])
    }

    func testPasswordSignInAsksForTheGuardCode() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { request in
            switch request.method {
            case "signInWithCredentials":
                return [Fake.event(request, "guardCodeRequired", #""kind":"email","email":"o***@example.com","previousCodeWasIncorrect":false"#)]
            default:
                return [Fake.result(request)]
            }
        }
        let events = Box<SteamSignInEvent>()
        async let login = client.signInWithCredentials(accountName: "owe_test", password: "pw", deviceName: "Test Mac") {
            events.append($0)
        }
        try await sleepUntil("the guard code question") { !events.values.isEmpty }
        XCTAssertEqual(events.values, [.guardCodeRequired(email: "o***@example.com", previousCodeWasIncorrect: false)])
        try await client.submitGuardCode("ABCDE")
        let fake = try XCTUnwrap(transports.values.first)
        let submit = try XCTUnwrap(fake.requests.last)
        XCTAssertEqual(submit.method, "submitGuardCode")
        XCTAssertEqual(submit.param("code") as? String, "ABCDE")
        let signIn = try XCTUnwrap(fake.requests.first)
        fake.emit(Fake.result(signIn, Fake.loginJSON))
        let result = try await login
        XCTAssertEqual(result, Fake.login)
    }

    func testCallsLogOnFirstAndAgainAfterTheHelperRestarts() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { request in
            switch request.method {
            case "logOn":
                XCTAssertEqual(request.param("refreshToken") as? String, Fake.login.refreshToken)
                return [Fake.result(request, #"{"steamID":"76561190000000001"}"#)]
            case "call":
                return [Fake.result(request, #"{"total":3}"#)]
            default:
                return [Fake.result(request)]
            }
        }
        struct Body: Encodable, Sendable { let appid = 431960 }
        struct Response: Decodable, Sendable { let total: Int }
        await client.use(Fake.login)

        let first = try await client.call("PublishedFile.QueryFiles", body: Body(), as: Response.self)
        XCTAssertEqual(first.total, 3)
        _ = try await client.call("PublishedFile.QueryFiles", body: Body(), as: Response.self)
        let fake = try XCTUnwrap(transports.values.first)
        XCTAssertEqual(fake.methods, ["logOn", "call", "call"])
        XCTAssertEqual(fake.requests[1].param("method") as? String, "PublishedFile.QueryFiles")
        XCTAssertEqual((fake.requests[1].param("body") as? [String: Any])?["appid"] as? Int, 431960)

        fake.exit(status: 1)
        try await sleepUntil("the client to notice the exit") {
            do {
                _ = try await client.call("PublishedFile.QueryFiles", body: Body(), as: Response.self)
                return true
            } catch {
                return false
            }
        }
        XCTAssertEqual(transports.values.count, 2)
        XCTAssertEqual(transports.values.last?.methods, ["logOn", "call"])
    }

    func testRejectedTokenFailsTheLogOn() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { request in
            [Fake.error(request, code: "tokenRejected", eresult: 5)]
        }
        await client.use(Fake.login)
        do {
            try await client.ensureLoggedOn()
            XCTFail("logged on with a rejected token")
        } catch let error as SteamHelperError {
            XCTAssertEqual(error.code, .tokenRejected)
            XCTAssertEqual(error.eresult, 5)
            XCTAssertTrue(error.needsNewSignIn)
        }
    }

    func testHelperExitFailsWaitingRequests() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { _ in [] }
        async let version = client.ping()
        try await sleepUntil("the request") { transports.values.first?.requests.count == 1 }
        transports.values.first?.exit(status: 134)
        do {
            _ = try await version
            XCTFail("a request survived the helper")
        } catch let error as SteamHelperError {
            XCTAssertEqual(error.code, .helperExited)
        }
    }

    func testCancellingARequestAsksTheHelperToStopIt() async throws {
        let transports = Box<Fake>()
        let signInID = Box<Int64>()
        let client = makeClient(transports) { request in
            switch request.method {
            case "signInWithQR":
                signInID.append(request.id)
                return [Fake.event(request, "qrChallenge", #""url":"https://s.team/q/1/1""#)]
            case "cancel":
                let target = FakeSteamHelperRequest(id: signInID.values.first ?? -1, method: "signInWithQR", params: Data())
                return [Fake.error(target, code: "cancelled")]
            default:
                return []
            }
        }
        let task = Task { try await client.signInWithQR(deviceName: "Test Mac") { _ in } }
        try await sleepUntil("the sign-in") { !signInID.values.isEmpty }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("the sign-in wasn't cancelled")
        } catch let error as SteamHelperError {
            XCTAssertEqual(error.code, .cancelled)
        }
        let cancel = try XCTUnwrap(transports.values.first?.requests.last)
        XCTAssertEqual(cancel.method, "cancel")
        XCTAssertEqual((cancel.param("id") as? NSNumber)?.int64Value, signInID.values.first)
    }

    func testMissingHelperFailsRequests() async {
        let client = SteamHelperClient { throw SteamHelperError(code: .helperMissing, message: "none") }
        do {
            _ = try await client.ping()
            XCTFail("pinged a missing helper")
        } catch let error as SteamHelperError {
            XCTAssertEqual(error.code, .helperMissing)
            XCTAssertNotNil(error.errorDescription)
        } catch {
            XCTFail("\(error)")
        }
    }

    /// A service call made from Web API parameters comes back the Web API's way, `{"response": …}`.
    func testWebAPIResponseWrapsTheResultAndTypesTheParameters() async throws {
        let transports = Box<Fake>()
        let client = makeClient(transports) { request in
            switch request.method {
            case "call": [Fake.result(request, #"{"total":7,"publishedfiledetails":[{"publishedfileid":"123"}]}"#)]
            default: [Fake.result(request)]
            }
        }
        await client.use(Fake.login)
        let data = try await client.webAPIResponse("PublishedFile.QueryFiles", parameters: [
            URLQueryItem(name: "search_text", value: "2024"), URLQueryItem(name: "numperpage", value: "30"),
            URLQueryItem(name: "return_tags", value: "true"), URLQueryItem(name: "requiredtags[1]", value: "Anime"),
            URLQueryItem(name: "requiredtags[0]", value: "Scene"), URLQueryItem(name: "cursor", value: "*"),
        ])
        let response = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["response"] as? [String: Any])
        XCTAssertEqual(response["total"] as? Int, 7)
        let call = try XCTUnwrap(transports.values.first?.requests.last)
        XCTAssertEqual(call.param("method") as? String, "PublishedFile.QueryFiles")
        let body = try XCTUnwrap(call.param("body") as? [String: Any])
        XCTAssertEqual(body["search_text"] as? String, "2024", "search text stays text")
        XCTAssertEqual(body["numperpage"] as? Int, 30)
        XCTAssertEqual(body["return_tags"] as? Bool, true)
        XCTAssertEqual(body["requiredtags"] as? [String], ["Scene", "Anime"], "in index order")
        XCTAssertEqual(body["cursor"] as? String, "*")
    }

    func testWebAPIResponseNeedsALogin() async {
        let client = makeClient(Box<Fake>()) { [Fake.result($0)] }
        let hasLogin = await client.hasLogin
        XCTAssertFalse(hasLogin)
        do {
            _ = try await client.webAPIResponse("PublishedFile.QueryFiles", parameters: [])
            XCTFail("called without a login")
        } catch let error as SteamHelperError {
            XCTAssertEqual(error.code, .notLoggedOn)
        } catch {
            XCTFail("\(error)")
        }
    }

    /// Steam refusing the token tells the account, which forgets it.
    func testARejectedTokenCallsTheHandler() async throws {
        let client = makeClient(Box<Fake>()) { [Fake.error($0, code: "tokenRejected", eresult: 5)] }
        let calls = Box<Int>()
        await client.setLoginRejectedHandler { calls.append(1) }
        await client.use(Fake.login)
        do {
            try await client.ensureLoggedOn()
            XCTFail("logged on with a rejected token")
        } catch {}
        XCTAssertEqual(calls.values.count, 1)
    }

    // MARK: Locator and login

    func testLocatorUsesTheEnvironmentOverrideOnlyWhenItRuns() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SteamHelperClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: folder) } catch { XCTFail("\(error)") }
        }
        let helper = folder.appending(path: "owe-steam-helper")
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        XCTAssertNil(SteamHelperLocator.executable(environment: [SteamHelperLocator.environmentKey: helper.path], app: folder),
                     "not executable yet")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        XCTAssertEqual(SteamHelperLocator.executable(environment: [SteamHelperLocator.environmentKey: helper.path], app: folder),
                       helper)
        XCTAssertNil(SteamHelperLocator.executable(environment: [:], app: folder), "no helper in the app")
        XCTAssertEqual(AppBundleLayout.steamHelperURL(inApp: URL(filePath: "/Applications/OWE.app"), architecture: "arm64").path,
                       "/Applications/OWE.app/Contents/Helpers/owe-steam-helper-arm64")
    }

    func testLoginNeverPrintsItsToken() {
        for text in [String(describing: Fake.login), String(reflecting: Fake.login), "\(Fake.login)"] {
            XCTAssertFalse(text.contains(Fake.login.refreshToken), text)
            XCTAssertTrue(text.contains(Fake.login.accountName), text)
        }
    }

    /// A JWT whose payload is `claims`, as Steam's refresh tokens are (base64url, unpadded).
    private func jwt(_ claims: String) -> String {
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJFZERTQSJ9.\(payload).c2lnbmF0dXJl"
    }

    func testLoginExpiryComesFromTheTokensExpClaim() {
        let login = SteamLogin(accountName: "owe_test", steamID: "76561190000000001",
                               refreshToken: jwt(#"{"iss":"steam","sub":"76561190000000001","exp":1800000000}"#))
        XCTAssertEqual(login.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertFalse(login.endsSoon(now: Date(timeIntervalSince1970: 1_800_000_000 - 15 * 86_400)))
        XCTAssertTrue(login.endsSoon(now: Date(timeIntervalSince1970: 1_800_000_000 - 13 * 86_400)))
        XCTAssertTrue(login.endsSoon(now: Date(timeIntervalSince1970: 1_800_000_001)), "already ended")
    }

    func testLoginWithoutAReadableExpiryNeverEndsSoon() {
        XCTAssertNil(Fake.login.expiresAt)
        XCTAssertFalse(Fake.login.endsSoon())
        let noExp = SteamLogin(accountName: "a", steamID: "1", refreshToken: jwt(#"{"sub":"1"}"#))
        XCTAssertNil(noExp.expiresAt)
    }

    func testLoginStoreRoundTrips() throws {
        let store = SteamLoginStore(secret: KeychainSecret(
            keychain: KeychainStore(service: "app.openwallpaperengine.tests.keychain.\(UUID().uuidString)"), account: "SteamLogin"))
        XCTAssertNil(store.load())
        try store.save(Fake.login)
        XCTAssertEqual(store.load(), Fake.login)
        try store.remove()
        XCTAssertNil(store.load())
        XCTAssertEqual(SteamCredentials.steamLogin().keychain.service,
                       "\(AppStorageLocation.current.keychainServicePrefix).steam-login")
    }
}
