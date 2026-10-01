import Foundation

/// What the screen saver plays: the current wallpaper's loop videos, one per display pixel size.
/// The app writes it next to the videos (`ScreenSaverVideoStore`); the bundled `.saver` reads it.
/// Shared by both targets, so it uses Foundation only.
struct ScreenSaverManifest: Codable, Equatable {
    /// Bump when the format changes; the saver ignores a manifest of another revision.
    static let revision = 1
    static let fileName = "current.json"

    struct Video: Codable, Equatable {
        /// The video's file name in the manifest's folder.
        var file: String
        var width: Int
        var height: Int
    }

    var revision = ScreenSaverManifest.revision
    var videos: [Video] = []

    /// The folder the videos and the manifest live in, given a home folder: the Application
    /// Support folder of the system's screen saver host (`legacyScreenSaver`), whose sandbox lets a
    /// third-party saver read only its own container. The saver, running in that container, sees
    /// the same folder as its own Application Support.
    static func sharedFolder(home: URL) -> URL {
        home.appending(path: "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Open Wallpaper Engine/ScreenSaver",
                       directoryHint: .isDirectory)
    }

    /// The folder as the saver sees it from inside the container.
    static func folderInsideContainer(applicationSupport: URL) -> URL {
        applicationSupport.appending(path: "Open Wallpaper Engine/ScreenSaver", directoryHint: .isDirectory)
    }

    /// The video for a view of `pixels`: the same size, else the same aspect and the nearest
    /// area, else the nearest area.
    func video(forPixels pixels: (width: Int, height: Int)) -> Video? {
        func score(_ video: Video) -> (Double, Double) {
            guard pixels.width > 0, pixels.height > 0, video.width > 0, video.height > 0 else { return (.infinity, .infinity) }
            let aspect = abs(log(Double(video.width) / Double(video.height) / (Double(pixels.width) / Double(pixels.height))))
            let area = abs(log(Double(video.width * video.height) / Double(pixels.width * pixels.height)))
            return (aspect > 0.01 ? 1 : 0, area + aspect)
        }
        return videos.min { score($0) < score($1) }
    }
}
