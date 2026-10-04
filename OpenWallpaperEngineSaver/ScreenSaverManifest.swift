import Foundation

/// What the screen saver plays: the loop videos, each for some displays (or any) and pixel size,
/// a stretched one with the rect of it each display shows. The app writes it next to the videos
/// (`ScreenSaverVideoStore`); the bundled `.saver` reads it. Shared by both targets, so it uses
/// Foundation only.
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
        /// The identities (`CGDisplayCreateUUIDFromDisplayID`) of the displays that play it; nil
        /// for any display.
        var displays: [String]? = nil
        /// The rect of the video the display shows (a stretch); nil for the whole video.
        var crop: Crop? = nil
    }

    /// A rect of a video, as fractions of it from its top-left.
    struct Crop: Codable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// `unit`, a rect of a canvas of `canvas` size, in a video of `video` size that fills
        /// the canvas (aspect kept, centred, as the desktop places it).
        init(_ unit: CGRect, canvas: CGSize, video: CGSize) {
            var fit = CGSize(width: 1, height: 1)
            if canvas.width > 0, canvas.height > 0, video.width > 0, video.height > 0 {
                let scale = max(canvas.width / video.width, canvas.height / video.height)
                fit = CGSize(width: canvas.width / scale / video.width, height: canvas.height / scale / video.height)
            }
            self.init(x: (1 - fit.width) / 2 + unit.minX * fit.width, y: (1 - fit.height) / 2 + unit.minY * fit.height,
                      width: unit.width * fit.width, height: unit.height * fit.height)
        }

        /// Where a layer showing the whole video goes in a view of `bounds` (origin bottom-left)
        /// so this rect of it fills the view.
        func playerFrame(in bounds: CGRect) -> CGRect {
            guard width > 0, height > 0 else { return bounds }
            let size = CGSize(width: bounds.width / width, height: bounds.height / height)
            return CGRect(x: bounds.minX - x * size.width, y: bounds.minY - (1 - y - height) * size.height,
                          width: size.width, height: size.height)
        }
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

    /// The video for the display `display` (its identity; nil when unknown) in a view of
    /// `pixels`: among the videos listing it, else those for any display, else those showing
    /// a whole video, the one `video(forPixels:in:)` picks.
    func video(forDisplay display: String?, pixels: (width: Int, height: Int)) -> Video? {
        let listing = display.map { display in videos.filter { $0.displays?.contains(display) == true } } ?? []
        let candidates = [listing, videos.filter { $0.displays == nil }, videos.filter { $0.crop == nil }, videos]
            .first { !$0.isEmpty } ?? []
        return Self.video(forPixels: pixels, in: candidates)
    }

    /// The video for a view of `pixels`: the same size, else the same aspect and the nearest
    /// area, else the nearest area (of the shown rect, for a cropped one).
    func video(forPixels pixels: (width: Int, height: Int)) -> Video? {
        Self.video(forPixels: pixels, in: videos)
    }

    private static func video(forPixels pixels: (width: Int, height: Int), in videos: [Video]) -> Video? {
        func score(_ video: Video) -> (Double, Double) {
            let width = Double(video.width) * (video.crop?.width ?? 1), height = Double(video.height) * (video.crop?.height ?? 1)
            guard pixels.width > 0, pixels.height > 0, width > 0, height > 0 else { return (.infinity, .infinity) }
            let aspect = abs(log(width / height / (Double(pixels.width) / Double(pixels.height))))
            let area = abs(log(width * height / Double(pixels.width * pixels.height)))
            return (aspect > 0.01 ? 1 : 0, area + aspect)
        }
        return videos.min { score($0) < score($1) }
    }
}
