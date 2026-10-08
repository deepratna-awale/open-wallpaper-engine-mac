import Foundation

/// The layers of a scene that a recorded loop would freeze: the clock, day and date text layers
/// (`SceneClockLayers`, as the Live Photo export finds them) and the audio-reactive ones
/// (`SceneAudioReactiveLayers`). Set as Screen Saver from the library's and the Workshop's menus
/// records with them switched off in the screen saver's own values (`hiding(_:in:)`), never the
/// desktop's; the Screen Saver mode shows them off, and the user can switch them back on there.
enum ScreenSaverLiveLayers {
    /// The ids of `wallpaper`'s clock and audio-reactive layers; empty for anything but a scene,
    /// or a scene whose file can't be read. Blocking file IO: call it off the main thread.
    static func objectIDs(of wallpaper: WEWallpaper) -> Set<Int> {
        ThreadGuards.assertNotMainThread("screen saver live layer scan")
        guard ScreenSaverPlugin.isScene(wallpaper) else { return [] }
        let files = SceneFiles(wallpaper: wallpaper)
        guard let sceneData = files.read(wallpaper.project.file) else {
            OWELog.error(.app, "Screen saver: \(wallpaper.wallpaperDirectory.lastPathComponent) has no \(wallpaper.project.file) to scan for live layers")
            return []
        }
        return objectIDs(inScene: sceneData, read: files.read)
    }

    /// The clock and audio-reactive layers of the scene document `sceneData`, reading its other
    /// files through `read`.
    static func objectIDs(inScene sceneData: Data, read: @escaping SceneAudioReactiveLayers.Read) -> Set<Int> {
        var ids = SceneAudioReactiveLayers.ids(inScene: sceneData, read: read)
        do {
            let document = try JSONDecoder().decode(SceneJSON.self, from: sceneData)
            ids.formUnion(SceneClockLayers.ids(in: document).compactMap { Int($0) })
        } catch {
            OWELog.error(.app, "Screen saver: the scene can't be read for its clock layers: \(error)")
        }
        return ids
    }

    /// `values` with the layers `ids` switched off (the Scene Editor (Live)'s visibility keys).
    static func hiding(_ ids: Set<Int>, in values: [String: String]) -> [String: String] {
        var result = values
        for id in ids { result[sceneObjectVisibilityKey(objectID: id)] = "false" }
        return result
    }

    /// A scene's files as its load finds them: its package, its folder, the Workshop items it
    /// references, then WE's assets.
    private struct SceneFiles {
        let directory: URL
        let package: PKGParser?
        let workshop = WorkshopAssetResolver(roots: WorkshopAssetResolver.defaultRoots())
        let assets = WallpaperEngineAssets.searchDirectories

        init(wallpaper: WEWallpaper) {
            directory = wallpaper.wallpaperDirectory
            let packageURL = directory.appending(path: (wallpaper.project.file as NSString).deletingPathExtension + ".pkg")
            var package: PKGParser?
            if FileManager.default.fileExists(atPath: packageURL.path(percentEncoded: false)) {
                do { package = try PKGParser(url: packageURL) } catch {
                    OWELog.error(.app, "Screen saver: can't open \(packageURL.lastPathComponent) of \(directory.lastPathComponent): \(error)")
                }
            }
            self.package = package
        }

        func read(_ path: String) -> Data? {
            if let data = package?.extractFile(named: path) { return data }
            do {
                if let data = try AssetPathResolver.data(path, in: directory) { return data }
            } catch {
                OWELog.error(.app, "Screen saver: can't read \(path) in \(directory.lastPathComponent): \(error)")
            }
            if let data = workshop.data(for: path) { return data }
            guard let url = WallpaperEngineAssets.locate(SceneWallpaperViewModel.sharedAssetPaths(for: path), in: assets)
            else { return nil }
            do {
                return try AssetPathResolver.readRegularFile(at: url)
            } catch {
                OWELog.error(.app, "Screen saver: can't read the asset \(url.path): \(error)")
                return nil
            }
        }
    }
}
