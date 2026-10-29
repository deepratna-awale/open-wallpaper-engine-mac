import Foundation

/// Whether "Update from Steam" needs to download: the current public build of Wallpaper Engine
/// (the Steam helper's app info; nothing is downloaded) against the build the assets cache was
/// filled from.
enum WallpaperEngineAssetsUpdateCheck {
    enum Decision: Equatable {
        /// The installed assets are the current build and complete.
        case upToDate(build: String)
        case download
    }

    /// Whether to look the build up before downloading: only for a complete Steam copy of a known
    /// build. Anything else downloads straight away, as does "Re-download".
    static func needsLookup(force: Bool, installed: WallpaperEngineAssetsCache.Info?, assetsComplete: Bool) -> Bool {
        !force && assetsComplete && installed?.origin == .steam && !(installed?.steamBuildID ?? "").isEmpty
    }

    /// Skips the download when the installed build is the current one and the files are there.
    static func decision(installed: WallpaperEngineAssetsCache.Info?, assetsComplete: Bool, currentBuild: String) -> Decision {
        guard assetsComplete, installed?.origin == .steam, let build = installed?.steamBuildID, build == currentBuild else {
            return .download
        }
        return .upToDate(build: build)
    }
}
