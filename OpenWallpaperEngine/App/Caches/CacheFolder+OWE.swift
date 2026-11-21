import Foundation

/// The app's caches, in the order Settings and `caches_get` list them.
extension CacheFolder {
    /// OWE's caches for the store `location`.
    static func ownCaches(location: AppStorageLocation) -> [CacheFolder] {
        let caches = location.cachesDirectory.appending(path: "Open Wallpaper Engine", directoryHint: .isDirectory)
        return [
            CacheFolder(id: .loadingSnapshots, root: SceneLoadingSnapshotStore.root(in: location.cachesDirectory), expires: true),
            CacheFolder(id: .editorPreviews, root: caches.appending(path: "EditorPreviews", directoryHint: .isDirectory), expires: true),
            CacheFolder(id: .videoTextures, root: EmbeddedVideoFiles.folder(in: location.cachesDirectory), expires: true),
            CacheFolder(id: .repairedVideos, root: RepairedVideoCache.root(in: location.cachesDirectory), expires: true),
            CacheFolder(id: .displayPictures, root: caches.appending(path: "DisplayPictures", directoryHint: .isDirectory), expires: false),
            CacheFolder(id: .shaderVariants, root: location.appCachesDirectory.appending(path: "shader-variants", directoryHint: .isDirectory),
                        expires: false),
            CacheFolder(id: .pipelineArchives, root: location.appCachesDirectory.appending(path: "pipeline-archives", directoryHint: .isDirectory),
                        expires: false),
        ]
    }

    /// This process's caches.
    static var current: [CacheFolder] {
        ownCaches(location: .current)
    }
}
