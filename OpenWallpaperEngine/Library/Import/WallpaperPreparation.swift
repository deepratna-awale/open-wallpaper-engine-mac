import Foundation

/// The work done once for a wallpaper that joins the library (an import, a download, a kept
/// preview), so the first play doesn't have to: a scene's `.pkg` is converted to loose files.
/// Reads and writes files: call it off the main thread.
enum WallpaperPreparation {
    static func prepare(wallpaperDirectory: URL) {
        WallpaperPackageConverter.convertIfNeeded(wallpaperDirectory: wallpaperDirectory)
    }
}
