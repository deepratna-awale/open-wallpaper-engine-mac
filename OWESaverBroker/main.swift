import AppKit
import Foundation
import notify
import os
import XPC

// owe-saver-broker: the live screen saver's rendezvous, and the app's launcher while a saver
// shows. An app can't publish a Mach service of its own (launchd owns them), and the screen saver
// extension's sandbox can only reach a named service, so this launchd agent holds the Open
// Wallpaper Engine app's frame service endpoint (an anonymous XPC listener) and hands it to the
// extension. Launched on demand by launchd: for its Mach service (the extension), or for the
// `.saver`'s Darwin `saverAlive` notification (`LaunchEvents`, com.apple.notifyd.matching), since
// the `.saver`'s host can't reach a Mach service. When a saver shows and the app isn't running, it
// launches the app in the background (`LiveSaverLaunchPolicy`). It keeps nothing on disk; when it
// exits the app registers again.

let brokerLog = Logger(subsystem: "app.openwallpaper.engine.saverlab", category: "broker")

/// Holds the endpoint, launches the app; peers are checked against the broker's own team when it
/// has one. Its state is the main queue's: XPC calls hop there.
final class Broker: NSObject, NSXPCListenerDelegate, LiveSaverBrokerProtocol, @unchecked Sendable {
    /// How long an extension's ask for the endpoint waits for a launched app to register.
    static let endpointWait: TimeInterval = 20

    private var registered: NSXPCListenerEndpoint?
    /// The connection the endpoint came over: when it ends, the app has quit.
    private weak var registrar: NSXPCConnection?
    private var waiting: [(NSXPCListenerEndpoint?) -> Void] = []
    private var launchPolicy = LiveSaverLaunchPolicy()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let requirement = Self.peerRequirement { connection.setCodeSigningRequirement(requirement) }
        connection.exportedInterface = LiveSaverFramesMessage.brokerInterface()
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async { self?.ended(connection) }
        }
        connection.resume()
        brokerLog.notice("peer pid=\(connection.processIdentifier)")
        return true
    }

    func register(_ endpoint: NSXPCListenerEndpoint) {
        let connection = NSXPCConnection.current()
        DispatchQueue.main.async { self.registered(endpoint, over: connection) }
    }

    func endpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        DispatchQueue.main.async { self.answer(reply) }
    }

    private func registered(_ endpoint: NSXPCListenerEndpoint, over connection: NSXPCConnection?) {
        registered = endpoint
        registrar = connection
        brokerLog.notice("the app registered its frame service")
        let replies = waiting
        waiting = []
        replies.forEach { $0(endpoint) }
    }

    private func answer(_ reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        if let registered {
            brokerLog.notice("endpoint asked: registered")
            reply(registered)
            return
        }
        // No app: launch it, and answer once it registers.
        brokerLog.notice("endpoint asked: none yet")
        launchAppIfNeeded(reason: "the extension")
        waiting.append(reply)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.endpointWait) { [weak self] in
            guard let self, !self.waiting.isEmpty else { return }
            let replies = self.waiting
            self.waiting = []
            replies.forEach { $0(nil) }
        }
    }

    private func ended(_ connection: NSXPCConnection?) {
        guard registered != nil, registrar == nil || registrar === connection else { return }
        brokerLog.notice("the app's connection ended")
        registered = nil
        registrar = nil
    }

    /// A `.saver` shows (its Darwin notification launched or reached the broker).
    func saverAlive() {
        guard registered == nil else { return }
        launchAppIfNeeded(reason: "the legacy saver")
    }

    private func launchAppIfNeeded(reason: String) {
        guard let app = Self.appURL, let bundleID = Bundle(url: app)?.bundleIdentifier else {
            brokerLog.error("no app around the broker to launch")
            return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        guard launchPolicy.shouldLaunch(at: ProcessInfo.processInfo.systemUptime, appRunning: running) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.arguments = [ScreenSaverLiveNames.launchArgument]
        brokerLog.notice("launching \(app.path, privacy: .public) for \(reason, privacy: .public)")
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { launched, error in
            if let error {
                brokerLog.error("launch failed: \(error.localizedDescription, privacy: .public)")
            } else {
                brokerLog.notice("launched pid=\(launched?.processIdentifier ?? 0)")
            }
        }
    }

    /// The app the broker ships in (`<app>/Contents/Helpers/owe-saver-broker`).
    static let appURL: URL? = {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }()

    /// Peers signed by the broker's own team (the app and its extension); none for an unsigned
    /// or ad-hoc build, which has no team to compare.
    static let peerRequirement: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }()
}

let broker = Broker()

// launchd's Darwin notification events (`LaunchEvents`) must be taken, or launchd launches the
// broker again and again. Each is a `.saver` showing.
xpc_set_event_stream_handler("com.apple.notifyd.matching", DispatchQueue.main) { event in
    let name = xpc_dictionary_get_string(event, XPC_EVENT_KEY_NAME).map { String(cString: $0) } ?? "?"
    brokerLog.notice("launch event \(name, privacy: .public)")
    broker.saverAlive()
}
// While it runs, the notifications themselves (launchd's event only starts the job).
var aliveToken: Int32 = 0
notify_register_dispatch(ScreenSaverLiveNames.saverAlive, &aliveToken, DispatchQueue.main) { _ in broker.saverAlive() }

let listener = NSXPCListener(machServiceName: ScreenSaverLiveNames.brokerService)
listener.delegate = broker
listener.resume()
brokerLog.notice("broker listening on \(ScreenSaverLiveNames.brokerService, privacy: .public) team requirement=\(Broker.peerRequirement != nil) app=\(Broker.appURL?.path ?? "none", privacy: .public)")
RunLoop.main.run()
