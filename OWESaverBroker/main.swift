import CoreGraphics
import Foundation
import os

// owe-saver-broker: the live screen saver's rendezvous. An app can't publish a Mach service of
// its own (launchd owns them), and the screen saver extension's sandbox can only reach a named
// service, so this launchd agent holds the Open Wallpaper Engine app's frame service endpoint
// (an anonymous XPC listener) and hands it to the extension. Launched on demand by launchd
// (`MachServices`), it keeps nothing on disk; when it exits the app registers again.

let brokerLog = Logger(subsystem: "app.openwallpaper.engine.saverlab", category: "broker")

/// Holds the endpoint; peers are checked against the broker's own team when it has one.
final class Broker: NSObject, NSXPCListenerDelegate, LiveSaverBrokerProtocol {
    private let lock = NSLock()
    private var registered: NSXPCListenerEndpoint?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let requirement = Self.peerRequirement { connection.setCodeSigningRequirement(requirement) }
        connection.exportedInterface = LiveSaverFramesMessage.brokerInterface()
        connection.exportedObject = self
        connection.resume()
        brokerLog.notice("peer pid=\(connection.processIdentifier)")
        return true
    }

    func register(_ endpoint: NSXPCListenerEndpoint) {
        lock.withLock { registered = endpoint }
        brokerLog.notice("the app registered its frame service")
    }

    func endpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        let endpoint = lock.withLock { registered }
        brokerLog.notice("endpoint asked: \(endpoint == nil ? "none" : "registered", privacy: .public)")
        reply(endpoint)
    }

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
let listener = NSXPCListener(machServiceName: ScreenSaverLiveNames.brokerService)
listener.delegate = broker
listener.resume()
brokerLog.notice("broker listening on \(ScreenSaverLiveNames.brokerService, privacy: .public) team requirement=\(Broker.peerRequirement != nil)")
RunLoop.main.run()
