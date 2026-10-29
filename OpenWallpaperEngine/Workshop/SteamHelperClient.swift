import Foundation

/// What the Steam helper says while a sign-in waits on the user.
enum SteamSignInEvent: Equatable, Sendable {
    /// Show `url` as a QR code for the Steam mobile app; it replaces the previous one.
    case qrChallenge(URL)
    /// Steam wants a Steam Guard code: from the mobile app (`email` nil) or sent to `email`.
    case guardCodeRequired(email: String?, previousCodeWasIncorrect: Bool)
    /// Steam asked the mobile app to approve the sign-in.
    case deviceConfirmationRequired
}

/// Wallpaper Engine's build and depots on Steam (`appInfo`).
struct SteamAppInfo: Decodable, Equatable, Sendable {
    struct Depot: Decodable, Equatable, Sendable {
        let id: UInt32
        let oslist: String?
    }

    let appID: UInt32
    let publicBuildID: String?
    let depots: [Depot]
}

/// The app's connection to Steam: one `owe-steam-helper serve` (SteamHelper/README.md), started
/// on the first request and again after it exits. Requests run concurrently and each waits for
/// its own answer. After `use(_:)`, requests that need Steam log on with that sign-in first, and
/// again after the helper restarts; the helper itself logs on again after Steam disconnects it.
actor SteamHelperClient {
    typealias TransportFactory = @Sendable () throws -> any SteamHelperTransport

    private struct Pending {
        let continuation: CheckedContinuation<Data, any Error>
        let onEvent: (@Sendable (SteamSignInEvent) async -> Void)?
    }

    private let makeTransport: TransportFactory
    private var transport: (any SteamHelperTransport)?
    private var readTask: Task<Void, Never>?
    private var nextID: Int64 = 0
    private var pending: [Int64: Pending] = [:]
    private var login: SteamLogin?
    /// Whether the running helper is logged on with `login`.
    private var isLoggedOn = false
    private var logOnTask: Task<Void, any Error>?
    /// Told when Steam no longer accepts the login (`tokenRejected`), so it can be forgotten.
    private var onLoginRejected: (@Sendable () async -> Void)?

    init(makeTransport: @escaping TransportFactory) {
        self.makeTransport = makeTransport
    }

    /// The bundled helper, or `helperMissing` on the first request when there is none.
    static func app() -> SteamHelperClient {
        SteamHelperClient {
            guard let executable = SteamHelperLocator.executable() else {
                throw SteamHelperError(code: .helperMissing, message: "No Steam helper in this build.")
            }
            return ProcessSteamHelperTransport(executable: executable)
        }
    }

    // MARK: Requests

    func ping() async throws -> String {
        struct Version: Decodable { let version: String? }
        return try await request("ping", NoParams(), as: Version.self).version ?? ""
    }

    func signInWithQR(deviceName: String,
                      onEvent: @escaping @Sendable (SteamSignInEvent) async -> Void) async throws -> SteamLogin {
        struct Params: Encodable { let deviceName: String }
        return try await request("signInWithQR", Params(deviceName: deviceName), as: SteamLogin.self, onEvent: onEvent)
    }

    func signInWithCredentials(accountName: String, password: String, deviceName: String,
                               onEvent: @escaping @Sendable (SteamSignInEvent) async -> Void) async throws -> SteamLogin {
        struct Params: Encodable { let accountName, password, deviceName: String }
        return try await request("signInWithCredentials",
                                 Params(accountName: accountName, password: password, deviceName: deviceName),
                                 as: SteamLogin.self, onEvent: onEvent)
    }

    /// Answers a running credentials sign-in's `guardCodeRequired`.
    func submitGuardCode(_ code: String) async throws {
        struct Params: Encodable { let code: String }
        _ = try await request("submitGuardCode", Params(code: code), as: Empty.self)
    }

    /// The sign-in later requests log on with; nil logs off.
    func use(_ login: SteamLogin?) async {
        guard login != self.login else { return }
        let wasLoggedOn = isLoggedOn
        self.login = login
        isLoggedOn = false
        logOnTask = nil
        if wasLoggedOn, transport != nil {
            do {
                _ = try await request("logOff", NoParams(), as: Empty.self)
            } catch {
                OWELog.error(.workshop, "Steam helper logOff failed: \(error)")
            }
        }
    }

    /// Whether requests have a login to log on with (`use(_:)`).
    var hasLogin: Bool { login != nil }

    func setLoginRejectedHandler(_ handler: @escaping @Sendable () async -> Void) {
        onLoginRejected = handler
    }

    /// Logs on with the sign-in from `use(_:)` unless the running helper already is.
    /// `tokenRejected` means the user must sign in again.
    func ensureLoggedOn() async throws {
        guard !isLoggedOn else { return }
        guard let login else { throw SteamHelperError(code: .notLoggedOn, message: "Not signed in to Steam.") }
        if let logOnTask { return try await logOnTask.value }
        struct Params: Encodable { let accountName, refreshToken: String }
        let task = Task {
            _ = try await self.request("logOn", Params(accountName: login.accountName, refreshToken: login.refreshToken),
                                       as: Empty.self)
        }
        logOnTask = task
        defer { if self.login == login { logOnTask = nil } }
        do {
            try await task.value
        } catch let error as SteamHelperError where error.needsNewSignIn {
            if self.login == login { await onLoginRejected?() }
            throw error
        }
        if self.login == login { isLoggedOn = true }
    }

    /// Runs `body` logged on. The helper logs on again by itself after Steam disconnects it, so a
    /// login Steam refuses then fails `body`; that is reported like one `ensureLoggedOn` finds.
    private func loggedOn<Value: Sendable>(_ body: () async throws -> Value) async throws -> Value {
        try await ensureLoggedOn()
        let login = login
        do {
            return try await body()
        } catch let error as SteamHelperError where error.needsNewSignIn {
            if self.login == login {
                isLoggedOn = false
                await onLoginRejected?()
            }
            throw error
        }
    }

    /// One of the helper's Steam service methods (`PublishedFile.QueryFiles`…), logged on.
    func call<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String, body: Body, as type: Response.Type) async throws -> Response {
        try await loggedOn {
            try await request("call", CallParams(method: method, body: body), as: Response.self)
        }
    }

    /// A Steam service method with the Web API's parameters for it, answered as the Web API
    /// answers it: `{"response": …}`, so the app reads both the same way.
    func webAPIResponse(_ method: String, parameters: [URLQueryItem]) async throws -> Data {
        let line = try await loggedOn {
            try await requestLine("call", CallParams(method: method, body: SteamServiceBody(parameters)))
        }
        do {
            let message = try JSONSerialization.jsonObject(with: line) as? [String: Any]
            return try JSONSerialization.data(withJSONObject: ["response": message?["result"] ?? [String: Any]()])
        } catch {
            throw SteamHelperError(code: .badResponse, message: "\(method): \(error)")
        }
    }

    func appInfo(appID: UInt32) async throws -> SteamAppInfo {
        struct Params: Encodable { let appID: UInt32 }
        return try await loggedOn {
            try await request("appInfo", Params(appID: appID), as: SteamAppInfo.self)
        }
    }

    /// Whether one of the account's licenses grants `appID`.
    func ownsApp(appID: UInt32) async throws -> Bool {
        struct Params: Encodable { let appID: UInt32 }
        struct Owned: Decodable { let owned: Bool }
        try await loggedOn { try await request("ownsApp", Params(appID: appID), as: Owned.self).owned }
    }

    /// Ends the helper; the next request starts it again.
    func stop() {
        transport?.stop()
    }

    // MARK: Protocol

    private struct NoParams: Encodable {}
    private struct CallParams<Body: Encodable>: Encodable {
        let method: String
        let body: Body
    }
    private struct Empty: Decodable {}

    private struct Outgoing<Params: Encodable>: Encodable {
        let id: Int64
        let method: String
        let params: Params
    }

    /// What every line has: a response's `id` and `error`, or an event's name and request `id`.
    private struct Incoming: Decodable {
        struct Failure: Decodable {
            let code: String
            let message: String
            let eresult: Int?
        }

        let id: Int64?
        let event: String?
        let error: Failure?
        // Events' fields.
        let url: String?
        let email: String?
        let kind: String?
        let previousCodeWasIncorrect: Bool?
        let eresult: Int?
    }

    private struct Success<Value: Decodable>: Decodable {
        let result: Value
    }

    private func request<Params: Encodable, Value: Decodable>(
        _ method: String, _ params: Params, as type: Value.Type,
        onEvent: (@Sendable (SteamSignInEvent) async -> Void)? = nil) async throws -> Value {
        let response = try await requestLine(method, params, onEvent: onEvent)
        do {
            return try JSONDecoder().decode(Success<Value>.self, from: response).result
        } catch {
            throw SteamHelperError(code: .badResponse, message: "\(method): \(error)")
        }
    }

    /// Sends one request and waits for its answer: the response's whole line.
    private func requestLine<Params: Encodable>(
        _ method: String, _ params: Params,
        onEvent: (@Sendable (SteamSignInEvent) async -> Void)? = nil) async throws -> Data {
        try Task.checkCancellation()
        let transport = try startIfNeeded()
        nextID += 1
        let id = nextID
        let line = try JSONEncoder().encode(Outgoing(id: id, method: method, params: params))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = Pending(continuation: continuation, onEvent: onEvent)
                do {
                    try transport.send(line)
                } catch {
                    pending.removeValue(forKey: id)?.continuation.resume(
                        throwing: SteamHelperError(code: .helperExited, message: "Can't write to the Steam helper: \(error)"))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    /// Asks the helper to stop request `id`, which then fails with `cancelled`.
    private func cancel(_ id: Int64) {
        guard pending[id] != nil, let transport else { return }
        struct Params: Encodable { let id: Int64 }
        nextID += 1
        do {
            try transport.send(JSONEncoder().encode(Outgoing(id: nextID, method: "cancel", params: Params(id: id))))
        } catch {
            OWELog.error(.workshop, "Can't cancel Steam helper request \(id): \(error)")
        }
    }

    private func startIfNeeded() throws -> any SteamHelperTransport {
        if let transport { return transport }
        let transport = try makeTransport()
        let (lines, continuation) = AsyncStream.makeStream(of: Data.self)
        try transport.start(onLine: { continuation.yield($0) }, onExit: { status in
            OWELog.info(.workshop, "Steam helper exited with status \(status)")
            continuation.finish()
        })
        self.transport = transport
        isLoggedOn = false
        logOnTask = nil
        readTask = Task { [weak self] in
            for await line in lines {
                await self?.receive(line)
            }
            await self?.helperExited(transport)
        }
        return transport
    }

    private func receive(_ line: Data) async {
        let message: Incoming
        do {
            message = try JSONDecoder().decode(Incoming.self, from: line)
        } catch {
            OWELog.error(.workshop, "Unreadable line from the Steam helper: \(error)")
            return
        }
        if let event = message.event {
            await deliver(event, message)
        } else if let id = message.id, let request = pending.removeValue(forKey: id) {
            if let failure = message.error {
                request.continuation.resume(throwing: SteamHelperError(
                    code: SteamHelperError.Code(rawValue: failure.code) ?? .internal,
                    message: failure.message, eresult: failure.eresult))
            } else {
                request.continuation.resume(returning: line)
            }
        }
    }

    private func deliver(_ name: String, _ message: Incoming) async {
        let event: SteamSignInEvent?
        switch name {
        case "qrChallenge":
            event = message.url.flatMap(URL.init(string:)).map(SteamSignInEvent.qrChallenge)
        case "guardCodeRequired":
            event = .guardCodeRequired(email: message.kind == "email" ? message.email ?? "" : nil,
                                       previousCodeWasIncorrect: message.previousCodeWasIncorrect ?? false)
        case "deviceConfirmationRequired":
            event = .deviceConfirmationRequired
        case "loggedOff":
            // The helper logs on again by itself on the next request; a rejected token fails that request.
            OWELog.info(.workshop, "Steam logged the helper off (EResult \(message.eresult.map { String($0) } ?? "none"))")
            event = nil
        case "disconnected":
            OWELog.info(.workshop, "The Steam helper lost its connection to Steam")
            event = nil
        default:
            OWELog.debug(.workshop, "Steam helper event \(name)")
            event = nil
        }
        guard let event, let id = message.id, let onEvent = pending[id]?.onEvent else { return }
        await onEvent(event)
    }

    private func helperExited(_ exited: any SteamHelperTransport) {
        guard transport === exited else { return }
        transport = nil
        readTask = nil
        isLoggedOn = false
        logOnTask = nil
        let failed = pending
        pending = [:]
        for request in failed.values {
            request.continuation.resume(throwing: SteamHelperError(code: .helperExited, message: "The Steam helper exited."))
        }
    }
}
