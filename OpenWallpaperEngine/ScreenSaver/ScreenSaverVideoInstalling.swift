import Foundation

extension ScreenSaverVideoStore {
    /// Moves `video` into the folder as `fileName` and makes it the one video the saver plays
    /// (a video wallpaper's own file set as the screen saver): the manifest is rewritten to list
    /// it (an atomic write: a rename over the old one), and only then is the previous video
    /// removed. A saver already playing the previous one keeps its open file until it stops.
    /// Blocking file IO: call it off the main thread.
    func install(_ video: URL, as fileName: String, pixelSize: SIMD2<Int>) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(fileName: fileName)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: video, to: destination)
        try writeManifest(ScreenSaverManifest(videos: [
            ScreenSaverManifest.Video(file: fileName, width: pixelSize.x, height: pixelSize.y),
        ]))
        retain([fileName])
    }
}
