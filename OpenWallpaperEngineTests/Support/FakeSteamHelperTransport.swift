import Foundation
@testable import OpenWallpaperEngine

/// A request the app sent to a `FakeSteamHelperTransport`.
struct FakeSteamHelperRequest: Sendable {
    let id: Int64
    let method: String
    /// The request's `params` as JSON.
    let params: Data

    func param(_ key: String) -> Any? {
        // A test's own JSON; a decoding failure is a test failure at the caller.
        (try? JSONSerialization.jsonObject(with: params) as? [String: Any])?[key]
    }
}

/// A stand-in for `owe-steam-helper serve`: records each request and answers with the lines
/// `respond` returns for it (none leaves it waiting for `emit`).
final class FakeSteamHelperTransport: SteamHelperTransport, @unchecked Sendable {
    // `lock` owns every stored property.
    private let lock = NSLock()
    private var onLine: (@Sendable (Data) -> Void)?
    private var onExit: (@Sendable (Int32) -> Void)?
    private var recorded: [FakeSteamHelperRequest] = []
    private var hasExited = false
    private let respond: @Sendable (FakeSteamHelperRequest) -> [String]

    init(respond: @escaping @Sendable (FakeSteamHelperRequest) -> [String] = { _ in [] }) {
        self.respond = respond
    }

    var requests: [FakeSteamHelperRequest] { lock.withLock { recorded } }
    var methods: [String] { requests.map(\.method) }

    func start(onLine: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws {
        lock.withLock {
            self.onLine = onLine
            self.onExit = onExit
        }
    }

    func send(_ line: Data) throws {
        // Like a closed pipe after the real helper exits.
        if lock.withLock({ hasExited }) { throw POSIXError(.EPIPE) }
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] ?? [:]
        let request = FakeSteamHelperRequest(
            id: (object["id"] as? NSNumber)?.int64Value ?? -1, method: object["method"] as? String ?? "",
            params: try JSONSerialization.data(withJSONObject: object["params"] ?? [:]))
        lock.withLock { recorded.append(request) }
        for line in respond(request) { emit(line) }
    }

    /// Sends `json` as one line of the helper's output.
    func emit(_ json: String) {
        let onLine = lock.withLock { self.onLine }
        onLine?(Data(json.utf8))
    }

    /// The helper exits.
    func exit(status: Int32 = 0) {
        let onExit: (@Sendable (Int32) -> Void)? = lock.withLock {
            defer { self.onExit = nil }
            hasExited = true
            return self.onExit
        }
        onExit?(status)
    }

    func stop() {
        exit()
    }

    // MARK: Answers

    static func result(_ request: FakeSteamHelperRequest, _ json: String = "{}") -> String {
        #"{"id":\#(request.id),"result":\#(json)}"#
    }

    static func error(_ request: FakeSteamHelperRequest, code: String, eresult: Int? = nil) -> String {
        let eresult = eresult.map { #","eresult":\#($0)"# } ?? ""
        return #"{"id":\#(request.id),"error":{"code":"\#(code)","message":"\#(code) from the fake"\#(eresult)}}"#
    }

    static func event(_ request: FakeSteamHelperRequest, _ name: String, _ fields: String = "") -> String {
        #"{"event":"\#(name)","id":\#(request.id)\#(fields.isEmpty ? "" : "," + fields)}"#
    }

    static let login = SteamLogin(accountName: "owe_test", steamID: "76561190000000001", refreshToken: "test-refresh-token")

    static var loginJSON: String {
        #"{"accountName":"\#(login.accountName)","steamID":"\#(login.steamID)","refreshToken":"\#(login.refreshToken)","guardData":null}"#
    }
}
