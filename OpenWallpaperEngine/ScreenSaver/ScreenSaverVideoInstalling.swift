import Foundation

/// Puts a finished recording in place as the screen saver's video (`ScreenSaverRecorder`).
protocol ScreenSaverVideoInstalling: Sendable {
    /// Moves `recording` into place as `fileName` and makes it the video the saver plays, at once:
    /// the saver plays either the previous video or this one, never a missing or partial file.
    /// Blocking file IO: call it off the main thread.
    func install(_ recording: URL, as fileName: String, pixelSize: SIMD2<Int>) throws
}

extension ScreenSaverVideoStore: ScreenSaverVideoInstalling {
    /// The recording moves into the folder under its own new name, the manifest is rewritten to
    /// list it (an atomic write: a rename over the old one), and only then is the previous video
    /// removed. A saver already playing the previous one keeps its open file until it stops.
    func install(_ recording: URL, as fileName: String, pixelSize: SIMD2<Int>) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(fileName: fileName)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: recording, to: destination)
        try writeManifest(ScreenSaverManifest(videos: [
            ScreenSaverManifest.Video(file: fileName, width: pixelSize.x, height: pixelSize.y),
        ]))
        retain([fileName])
    }

    /// A recording's name: the loop's (`fileName(wallpaperKey:…)`) with the time it was recorded,
    /// so each re-recording is a new file the manifest switches to.
    static func recordedFileName(_ loopFileName: String, at date: Date) -> String {
        let base = (loopFileName as NSString).deletingPathExtension
        return "\(base)-rec\(Int(date.timeIntervalSince1970)).\(fileExtension)"
    }
}
