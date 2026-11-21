import Foundation

/// The work done once for a wallpaper that joins the library (an import, a download, a kept
/// preview), so the first play doesn't have to: a video AVFoundation refuses as it is gets its
/// repaired copy (`RepairedVideoCache`). A scene plays from its `.pkg` as downloaded.
/// Reads and writes files: call it off the main thread.
enum WallpaperPreparation {
    static func prepare(wallpaperDirectory: URL) {
        prepareVideo(wallpaperDirectory: wallpaperDirectory)
    }

    /// Makes the repaired copy of a local video wallpaper's file when it needs one.
    static func prepareVideo(wallpaperDirectory: URL) {
        let projectURL = WEProject.url(in: wallpaperDirectory)
        let project: WEProject
        do {
            project = try WEProject.read(in: wallpaperDirectory)
        } catch {
            OWELog.error(.importer, "Can't read \(projectURL.path(percentEncoded: false)) to prepare it: \(error)")
            return
        }
        guard project.type.lowercased() == "video" else { return }
        let wallpaper = WEWallpaper(using: project, where: wallpaperDirectory)
        guard !wallpaper.isRemoteMedia else { return }
        _ = RepairedVideoCache.current.playableURL(for: wallpaper.mediaURL)
    }
}
