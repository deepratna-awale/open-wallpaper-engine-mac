import Foundation

/// The editor windows of the Wallpaper Editor's process.
@MainActor
protocol WallpaperEditorWindows: AnyObject {
    /// Opens the editor of the wallpaper in `folder`, or brings its window forward; false when it
    /// can't be opened (the user was told).
    @discardableResult
    func showEditor(of folder: URL) -> Bool
}

/// The Wallpaper Editor process's side of `WallpaperEditorLauncher`: it opens the wallpapers Open
/// Wallpaper Engine asks for in this process, one window each, and says when it is ready for them.
@MainActor
final class WallpaperEditorRequests {
    private let messaging: AppProcessMessaging
    private let channel: AppProcessChannel
    private let sender: String
    private weak var windows: WallpaperEditorWindows?
    private var token: AnyObject?

    init(messaging: AppProcessMessaging, channel: AppProcessChannel, sender: String = AppProcessChannel.processSender,
         windows: WallpaperEditorWindows) {
        self.messaging = messaging
        self.channel = channel
        self.sender = sender
        self.windows = windows
    }

    /// Takes open requests from now on.
    func start() {
        guard token == nil else { return }
        token = messaging.observe(channel.name(.openWallpaper)) { [weak self] sender, info in
            guard let self, sender != self.sender, let path = info[AppProcessChannel.folderKey], !path.isEmpty else { return }
            self.windows?.showEditor(of: URL(filePath: path, directoryHint: .isDirectory))
        }
    }

    /// Tells the app that launched this process that requests are taken now.
    func announceReady() {
        messaging.post(channel.name(.editorReady), sender: sender, userInfo: [:])
    }

    /// Asks the running Open Wallpaper Engine to show its window.
    func askAppToShowItsWindow() {
        messaging.post(channel.name(.showMainWindow), sender: sender, userInfo: [:])
    }

    func stop() {
        if let token { messaging.remove(token) }
        token = nil
    }
}
