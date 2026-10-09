import Combine
import Foundation

/// The document actions the app's menu asks the editor window for (File › Save, Save as New
/// Wallpaper…, Revert to Saved…): the window answers them as its toolbar buttons do.
@MainActor
public final class WallpaperEditorCommands {
    public enum Command: Equatable, Sendable {
        /// Saves the draft as the wallpaper's edits (`WallpaperEditorDocument.save`).
        case save
        /// Asks for a title, then saves a new wallpaper with the edits to the library.
        case saveAsNewWallpaper
        /// Asks before going back to the last save (undoable).
        case revertToSaved
    }

    let requests = PassthroughSubject<Command, Never>()

    public init() {}

    public func send(_ command: Command) {
        requests.send(command)
    }
}
