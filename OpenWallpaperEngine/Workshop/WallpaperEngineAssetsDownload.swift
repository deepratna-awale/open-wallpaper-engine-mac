import Foundation

/// How far along installing the Wallpaper Engine assets from the user's own Steam copy is. The
/// download goes straight into the folder the assets are read from (`WallpaperEngineAssets.cacheDirectory`).
enum WallpaperEngineAssetsDownload {
    struct Progress: Equatable {
        var fraction: Double
        var downloadedBytes: Int64?
        var totalBytes: Int64?
    }

    static var appID: Int { WorkshopAPIService.wallpaperEngineAppId }
}
