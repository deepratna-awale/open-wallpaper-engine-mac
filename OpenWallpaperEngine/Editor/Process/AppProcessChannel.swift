import Foundation

/// The messages Open Wallpaper Engine and its Wallpaper Editor process exchange, through the
/// login session's distributed notification centre. A message is a name and, at most, a
/// wallpaper's folder as its key: never the edits or any other data, which each process reads
/// from the files and defaults they share.
///
/// Names carry the process's isolation (`AppStorageLocation`): an isolated copy only talks to
/// processes isolated under the same tag, never to the user's own app.
struct AppProcessChannel: Equatable {
    enum Message: String, CaseIterable {
        /// The editor saved a wallpaper's overlay (`SceneEditOverlayFiles`).
        case overlayDidSave = "editor.overlayDidSave"
        /// A gizmo drag in progress: the editor wrote it beside the overlay (`SceneEditLiveFiles`).
        case overlayPreview = "editor.overlayPreview"
        /// The particle editor restarts systems (their ids beside the overlay).
        case particlesRestart = "editor.particlesRestart"
        /// A wallpaper's user properties were saved (`Notification.Name.wallpaperPropertiesDidSave`).
        case propertiesDidSave = "properties.didSave"
        /// A wallpaper was added to the library (Save as Local Wallpaper).
        case libraryDidChange = "library.didChange"
        /// Open (or bring forward) the editor window of a wallpaper.
        case openWallpaper = "editor.open"
        /// The editor process is ready for `openWallpaper`.
        case editorReady = "editor.ready"
        /// Show the app's setup of WE's assets (Settings › Assets), which the editor's browsers offer.
        case openAssetsSettings = "app.openAssetsSettings"
    }

    /// The `userInfo` key of the wallpaper's folder.
    static let folderKey = "folder"

    let prefix: String

    init(isolationTag: String?, bundleIdentifier: String = AppStorageLocation.realBundleIdentifier) {
        prefix = isolationTag.map { "\(bundleIdentifier).isolated.\($0)" } ?? bundleIdentifier
    }

    static var current: AppProcessChannel { AppProcessChannel(isolationTag: AppStorageLocation.current.isolationTag) }

    func name(_ message: Message) -> Notification.Name {
        Notification.Name("\(prefix).\(message.rawValue)")
    }

    /// This process, as the sender of what it posts (so it can pass over its own messages).
    static var processSender: String { String(ProcessInfo.processInfo.processIdentifier) }
}

/// Where the processes' messages go: the session's distributed notification centre, or an
/// in-memory one in tests.
@MainActor
protocol AppProcessMessaging: AnyObject {
    func post(_ name: Notification.Name, sender: String, userInfo: [String: String])
    /// `handler` gets the sender and the `userInfo` of every `name` posted, on the main queue.
    func observe(_ name: Notification.Name,
                 _ handler: @escaping @MainActor (_ sender: String?, _ userInfo: [String: String]) -> Void) -> AnyObject
    func remove(_ token: AnyObject)
}

/// The login session's `DistributedNotificationCenter`. Posts are delivered at once even to an
/// inactive app (which AppKit otherwise holds them for): the editor's edits reach the desktop
/// while the user works in the editor.
@MainActor
final class DistributedAppProcessMessaging: AppProcessMessaging {
    private let center = DistributedNotificationCenter.default()

    func post(_ name: Notification.Name, sender: String, userInfo: [String: String]) {
        center.postNotificationName(name, object: sender, userInfo: userInfo, deliverImmediately: true)
    }

    func observe(_ name: Notification.Name,
                 _ handler: @escaping @MainActor (String?, [String: String]) -> Void) -> AnyObject {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            let sender = notification.object as? String
            let info = notification.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { handler(sender, info) }
        }
        return token as AnyObject
    }

    func remove(_ token: AnyObject) {
        center.removeObserver(token)
    }
}
