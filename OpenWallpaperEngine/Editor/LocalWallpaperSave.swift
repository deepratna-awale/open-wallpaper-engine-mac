import Foundation
import OWESceneEditing

/// Save as Local Wallpaper: a copy of the wallpaper in the library with an overlay's edits baked
/// into its scene.json, its puppets as `.mdl` files, its user properties in project.json and the
/// particle editor's documents as files; the wallpaper itself isn't touched. The editor window's
/// File menu and an MCP client's `scene_save_as_local_wallpaper` both save through here.
enum LocalWallpaperSave {
    /// Saves the copy into the library; returns its folder.
    static func save(_ wallpaper: WEWallpaper, overlay: SceneEditOverlay, assetsDirectory: URL, title: String) throws -> URL {
        let source = try WallpaperEditorSource.read(wallpaper)
        var writerSource = LocalWallpaperWriter.Source(directory: wallpaper.wallpaperDirectory,
                                                       sceneFile: wallpaper.project.file,
                                                       assetsDirectory: assetsDirectory)
        if let package = source.package {
            var files: [String: Data] = [:]
            for path in package.fileList where files[path] == nil {
                if let data = package.extractFile(named: path) { files[path] = data }
            }
            writerSource.packageFiles = files
            writerSource.packageName = source.packageName
        }
        let authoring = overlay.authoring
        // The editor's puppets become `.mdl` files and the layers' references (`PuppetSceneBake`).
        let read = EditorPuppetAssets.make(for: wallpaper).readFile
        let baked = try PuppetSceneBake.bake(overlay, into: try overlay.applied(to: source.scene), readFile: read)
        // The user properties as authored in the editor go into the copy's project.json; the
        // particle editor's documents (definitions, materials) are files of the copy.
        let folder = try LocalWallpaperWriter().save(writerSource, scene: baked.scene, title: title,
                                                     into: FileManager.default.wallpapersDirectory,
                                                     editProject: { authoring?.applyProperties(to: &$0) },
                                                     files: baked.files,
                                                     additionalFiles: try overlay.particles?.assetFiles() ?? [:])
        OWELog.info(.library, "Saved \(wallpaper.project.title) with its editor edits as \(folder.path)")
        return folder
    }
}
