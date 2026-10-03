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
        /// Playback speed; nil plays at 1. Set for a video wallpaper played at another speed.
        var rate: Float? = nil
    }

    var revision = ScreenSaverManifest.revision
    var videos: [Video] = []

    /// The folder the videos and the manifest live in, given the user's home folder: OWE's own
    /// Application Support. The app can't write into the screen saver host's (`legacyScreenSaver`)
    /// container (macOS protects other apps' containers), but that host's sandbox may read any
    /// path (`files.absolute-path.read-only: /`), so the saver reads the videos where the app writes them.
    static func sharedFolder(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Open Wallpaper Engine/ScreenSaver", directoryHint: .isDirectory)
    }

    /// The user's real home folder. Inside the saver's sandbox `homeDirectoryForCurrentUser` is the
    /// host's container, so the saver asks the user database.
    static var userHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
