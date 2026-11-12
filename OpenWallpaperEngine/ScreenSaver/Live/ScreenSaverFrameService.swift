import Foundation
import IOSurface

/// The app's side of the screen saver extension's XPC transport: an anonymous listener whose
/// endpoint is registered with the broker (`owe-saver-broker`, a launchd agent; an app can't
/// publish a Mach service itself). Each extension process connects, attaches its views
/// (`LiveSaverServiceProtocol`), and gets the rings (`LiveSaverFramesMessage`, the surfaces as XPC
/// objects) and each frame's stamp. Its views' attaches and pings count as a saver showing
/// (`onAlive`). Without the broker (it isn't registered) nothing connects and the extension plays
/// its video. Thread-safe: XPC calls in on its own queues.
final class ScreenSaverFrameService: NSObject, NSXPCListenerDelegate, @unchecked Sendable { // `lock` owns `clients`, `latest`, the broker's fields.
    let listener = NSXPCListener.anonymous()
    /// A view attached or pinged (not a preview), on the main queue.
    var onAlive: (@MainActor () -> Void)?
    /// Whether the app draws for the screen saver now (the reply to an attach).
    var isDrawing: @Sendable () -> Bool = { false }
    private let lock = NSLock()
    private var clients: [ObjectIdentifier: Client] = [:]
    private var latest: LiveSaverFramesMessage?
    private var broker: NSXPCConnection?
    private var brokerService = ScreenSaverLiveNames.brokerService
    private var brokerFailures = 0
    /// Counts broker connections: a retry scheduled for an earlier one is dropped.
    private var brokerGeneration = 0
    private let brokerRetryBase: TimeInterval
    /// `invalidate` was called: nothing connects again.
    private var stopped = false
    /// Peers must be signed by the requirement this returns; nil accepts any (an unsigned build).
    /// Asked on the XPC queue when a peer connects, not in `init`: the default reads this app's
    /// signature (`ownTeamRequirement`), a dozen Security calls that don't belong on the main
    /// thread at launch, where the service is made.
    private let peerRequirement: @Sendable () -> String?

    init(peerRequirement: @escaping @Sendable () -> String? = { ScreenSaverFrameService.ownTeamRequirement },
         brokerRetryBase: TimeInterval = 0.5) {
        self.peerRequirement = peerRequirement
        self.brokerRetryBase = brokerRetryBase
        super.init()
        listener.delegate = self
        listener.resume()
    }

    /// Hands the endpoint to the broker. A broker that can't be looked up yet (the app connects
    /// before `SMAppService` has submitted the broker's agent, as on every relaunch) invalidates
    /// the connection: it is tried again after `brokerRetryDelay`, a few times. A broker that
    /// exits later interrupts it instead, and gets the endpoint again when launchd restarts it.
    func registerWithBroker(service: String = ScreenSaverLiveNames.brokerService) {
        lock.withLock {
            brokerService = service
            brokerFailures = 0
        }
        connectBroker()
    }

    /// The broker's agent can be looked up now (it was registered or allowed): registers again,
    /// unless it already has the endpoint.
    func brokerAvailable() {
        let connects = lock.withLock { () -> Bool in
            guard !stopped, broker == nil else { return false }
            brokerFailures = 0
            return true
        }
        if connects { connectBroker() }
    }

    /// How long after the `failures`th failed lookup in a row the broker is tried again: half a
    /// second, doubling to at most 30 s; nil once `brokerRetryLimit` lookups failed (the agent
    /// isn't registered or allowed: `brokerAvailable` tries again when it is).
    static func brokerRetryDelay(afterFailures failures: Int, base: TimeInterval = 0.5) -> TimeInterval? {
        guard failures >= 1, failures <= brokerRetryLimit else { return nil }
        return min(base * pow(2, Double(failures - 1)), 30)
    }

    static let brokerRetryLimit = 10

    /// Broker lookups that failed in a row since the last `registerWithBroker`/`brokerAvailable`.
    var brokerFailureCount: Int { lock.withLock { brokerFailures } }

    private func connectBroker() {
        let connection = NSXPCConnection(machServiceName: lock.withLock { brokerService })
        connection.remoteObjectInterface = LiveSaverFramesMessage.brokerInterface()
        connection.interruptionHandler = { [weak self] in
            // The broker exited (launchd starts it again on demand): register again.
            OWELog.info(.app, "Live screen saver: the broker restarted; registering again")
            self?.sendEndpoint()
        }
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in self?.brokerInvalidated(id) }
        let (connects, previous) = lock.withLock { () -> (Bool, NSXPCConnection?) in
            guard !stopped else { return (false, nil) }
            defer {
                broker = connection
                brokerGeneration += 1
            }
            return (true, broker)
        }
        previous?.invalidate()
        guard connects else { return connection.invalidate() }
        connection.resume()
        sendEndpoint()
    }

    private enum BrokerRetry {
        /// An older connection, or the service was invalidated.
        case ignore
        case giveUp
        case after(TimeInterval, generation: Int)
    }

    private func brokerInvalidated(_ id: ObjectIdentifier) {
        let retry = lock.withLock { () -> BrokerRetry in
            guard let broker, ObjectIdentifier(broker) == id else { return .ignore }
            self.broker = nil
            guard !stopped else { return .ignore }
            brokerFailures += 1
            guard let delay = Self.brokerRetryDelay(afterFailures: brokerFailures, base: brokerRetryBase) else { return .giveUp }
            return .after(delay, generation: brokerGeneration)
        }
        switch retry {
        case .ignore:
            break
        case .giveUp:
            OWELog.info(.app, "Live screen saver: no broker (the screen saver extension can't reach the app)")
        case let .after(delay, generation):
            OWELog.info(.app, "Live screen saver: the broker can't be reached yet; trying again in \(delay) s")
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                let current = self.lock.withLock { !self.stopped && self.broker == nil && self.brokerGeneration == generation }
                if current { self.connectBroker() }
            }
        }
    }

    private func sendEndpoint() {
        guard let broker = lock.withLock({ broker }) else { return }
        let proxy = broker.remoteObjectProxyWithErrorHandler { error in
            OWELog.info(.app, "Live screen saver: the broker didn't take the endpoint: \(error.localizedDescription)")
        } as? LiveSaverBrokerProtocol
        proxy?.register(listener.endpoint)
    }

    func invalidate() {
        listener.invalidate()
        let (all, broker) = lock.withLock {
            stopped = true
            return (Array(clients.values), self.broker)
        }
        broker?.invalidate()
        all.forEach { $0.connection.invalidate() }
    }

    // MARK: Frames (any thread)

    /// New rings (or none): every client gets them.
    func use(_ message: LiveSaverFramesMessage) {
        let all = lock.withLock {
            latest = message
            return Array(clients.values)
        }
        for client in all { client.proxy?.use(message) }
    }

    func show(ring: Int, stamp: UInt64) {
        let all = lock.withLock { clients.values.filter(\.isAttached) }
        for client in all { client.proxy?.show(ring: ring, stamp: stamp) }
    }

    var connectedClients: Int { lock.withLock { clients.count } }

    // MARK: Connections

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let requirement = peerRequirement() { connection.setCodeSigningRequirement(requirement) }
        let client = Client(connection: connection, service: self)
        connection.exportedInterface = LiveSaverFramesMessage.serviceInterface()
        connection.exportedObject = client
        connection.remoteObjectInterface = LiveSaverFramesMessage.clientInterface()
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in
            self?.lock.withLock { self?.clients[id] = nil }
            OWELog.info(.app, "Live screen saver: an extension disconnected")
        }
        client.proxy = connection.remoteObjectProxyWithErrorHandler { error in
            OWELog.info(.app, "Live screen saver: an extension call failed: \(error.localizedDescription)")
        } as? LiveSaverClientProtocol
        lock.withLock { clients[id] = client }
        connection.resume()
        OWELog.info(.app, "Live screen saver: an extension connected (pid \(connection.processIdentifier))")
        return true
    }

    fileprivate func attached(_ client: Client, isPreview: Bool) {
        let latest = lock.withLock { self.latest }
        if let latest { client.proxy?.use(latest) }
        if !isPreview { alive() }
    }

    fileprivate func alive() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onAlive?() }
        }
    }

    /// Peers signed by this app's team; nil for an unsigned or ad-hoc build. Lazy, so it's read
    /// once, on the first connection's queue.
    static let ownTeamRequirement: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }()

    /// One extension process: its views and its proxy.
    fileprivate final class Client: NSObject, LiveSaverServiceProtocol, @unchecked Sendable { // `lock` owns `views`.
        let connection: NSXPCConnection
        weak var service: ScreenSaverFrameService?
        var proxy: LiveSaverClientProtocol?
        private let lock = NSLock()
        private var views: [String: Bool] = [:]

        init(connection: NSXPCConnection, service: ScreenSaverFrameService) {
            self.connection = connection
            self.service = service
        }

        var isAttached: Bool { lock.withLock { !views.isEmpty } }

        func attach(viewID: String, display: String?, isPreview: Bool, reply: @escaping (Bool) -> Void) {
            lock.withLock { views[viewID] = isPreview }
            OWELog.info(.app, "Live screen saver: extension view \(viewID) attached (display \(display ?? "unknown"), preview \(isPreview))")
            service?.attached(self, isPreview: isPreview)
            reply(service?.isDrawing() ?? false)
        }

        func ping(viewID: String) {
            guard lock.withLock({ views[viewID] }) == false else { return }
            service?.alive()
        }

        func detach(viewID: String) {
            lock.withLock { views[viewID] = nil }
        }
    }
}
