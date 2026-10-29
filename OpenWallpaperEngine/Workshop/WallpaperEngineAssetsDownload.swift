import Foundation

/// Where installing the Wallpaper Engine assets downloads the user's own copy (the parts the cache
/// keeps, `SteamHelperDownload.assetsFileList`), and how far along it is.
enum WallpaperEngineAssetsDownload {
    struct Progress: Equatable {
        var fraction: Double
        var downloadedBytes: Int64?
        var totalBytes: Int64?
    }

    static var appID: Int { WorkshopAPIService.wallpaperEngineAppId }

    /// The folder the download goes into, inside the Wallpaper Storage folder (the same volume as
    /// the cache, so nothing large lands on the startup disk). Deleted after the copy.
    static let downloadFolderName = ".owe-assets-download"

    static func downloadDirectory(in storage: URL) -> URL {
        storage.appending(path: downloadFolderName, directoryHint: .isDirectory)
    }
}
