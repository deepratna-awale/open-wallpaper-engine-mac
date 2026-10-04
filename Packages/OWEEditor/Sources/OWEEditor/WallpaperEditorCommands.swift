import Combine
import Foundation

/// The document actions the app's menu asks the editor window for (File › Save as Local
/// Wallpaper…, File › Revert…): the window answers them as its toolbar buttons do.
@MainActor
public final class WallpaperEditorCommands {
    public enum Command: Equatable, Sendable {
        /// Asks for a title, then saves a copy with the edits to the library.
        case saveAsLocalWallpaper
        /// Asks before dropping every edit (undoable).
        case revert
    }

    let requests = PassthroughSubject<Command, Never>()

    public init() {}

    public func send(_ command: Command) {
        requests.send(command)
    }
}
