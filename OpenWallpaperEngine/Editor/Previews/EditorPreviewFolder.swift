import Foundation
import OWEEditor
import OWESceneEditing

/// Writes the small wallpaper an editor preview is rendered from (`EditorPreviewScene`) into a
/// scratch folder, with the files it needs that WE's assets don't hold at their root: a built-in
/// effect's materials and shaders (WE's editor copies them into a project, `prepareEffect`), a
/// Workshop effect's files from the wallpaper that ships it, a preset's particle definitions and
/// materials (copied likewise), the test card and the generated inputs.
enum EditorPreviewFolder {
    enum Failure: LocalizedError {
        case noAssets
        case noTestCard
        case unreadable(String)
        case noVariant(String, Int)

        var errorDescription: String? {
            switch self {
            case .noAssets: return "Wallpaper Engine's assets aren't installed"
            case .noTestCard: return "the editor's test card is missing from the app"
            case .unreadable(let path): return "\(path) can't be read"
            case .noVariant(let preset, let variant): return "the preset \(preset) has no particle variant \(variant)"
            }
        }
    }

    /// Writes the subject's wallpaper into `folder` (an empty folder) and returns its frame.
    static func write(_ subject: EditorPreviewSubject, into folder: URL) throws -> EditorPreviewScene.Frame {
        switch subject {
        case .effect(let file, let wallpaper):
            try writeEffect(file, wallpaper: wallpaper.map { URL(filePath: $0, directoryHint: .isDirectory) }, into: folder)
            return EditorPreviewScene.effectFrame
        case .particleSystem(let path, let is3D):
            try store(EditorPreviewScene.particleFiles(objects: EditorPreviewScene.systemObjects(path: path, is3D: is3D),
                                                       is3D: is3D), in: folder)
            return EditorPreviewScene.particleFrame
        case .particlePreset(let directory, let index, let is3D):
            let presetFolder = URL(filePath: directory, directoryHint: .isDirectory)
            guard let preset = ParticlePresetCatalog.preset(in: presetFolder, translate: { _ in nil }),
                  let variant = preset.variants.first(where: { $0.id == index }) else {
                throw Failure.noVariant(presetFolder.lastPathComponent, index)
            }
            for dependency in variant.dependencies {
                // A preset may list a file it doesn't ship (`ParticleEditingModel.addPreset`).
                guard let source = AssetPathResolver.fileURL(dependency, in: presetFolder) else { continue }
                try copy(source, to: dependency, in: folder)
            }
            let objects = EditorPreviewScene.presetObjects(variant.objects, is3D: is3D)
            try store(EditorPreviewScene.particleFiles(objects: objects, is3D: is3D), in: folder)
            return EditorPreviewScene.particleFrame
        }
    }

    // MARK: Effects

    private static func writeEffect(_ file: String, wallpaper: URL?, into folder: URL) throws {
        if let wallpaper {
            let read = try wallpaperReader(wallpaper)
            for path in EditorPreviewScene.workshopFiles(effectFile: file, read: read) {
                guard let data = read(path) else { continue }
                try store([path: data], in: folder)
            }
        } else {
            guard let source = WallpaperEngineAssets.locate([file], in: WallpaperEngineAssets.searchDirectories) else {
                throw WallpaperEngineAssets.directory == nil ? Failure.noAssets : Failure.unreadable(file)
            }
            let effectFolder = (file as NSString).deletingLastPathComponent
            for dependency in EditorPreviewScene.builtInDependencies(effectJSON: try AssetPathResolver.readRegularFile(at: source)) {
                guard let url = WallpaperEngineAssets.locate(["\(effectFolder)/\(dependency)"],
                                                             in: WallpaperEngineAssets.searchDirectories) else {
                    OWELog.debug(.scene, "Editor preview: \(file) lists \(dependency), which WE's assets don't have")
                    continue
                }
                try copy(url, to: dependency, in: folder)
            }
        }
        let read = folderReader(folder)
        let passInputs = try inputs(of: file, read: read)
        for input in Set(passInputs.flatMap(\.values)) {
            guard let png = EditorPreviewScene.png(input) else { throw Failure.unreadable(input.file) }
            try store([input.file: png], in: folder)
        }
        guard let card = EditorPreviewResources.testCard else { throw Failure.noTestCard }
        try copy(card, to: EditorPreviewScene.testCardFile, in: folder)
        try store(EditorPreviewScene.effectFiles(effectFile: file, passInputs: passInputs), in: folder)
    }

    /// The generated inputs of each of the effect's passes, by texture slot, from the samplers
    /// its shaders declare (as the editor lists an effect's texture slots).
    private static func inputs(of file: String, read: @escaping (String) -> Data?) throws -> [[Int: EditorPreviewScene.Input]] {
        guard let data = read(file) else { throw Failure.unreadable(file) }
        let effect = try decodeTolerant(EffectDocument.self, from: data)
        let loader = ShaderSourceLoader(readFile: read)
        return effect.passes.map { pass -> [Int: EditorPreviewScene.Input] in
            // A pass without a material (a copy) or with one that can't be read has no inputs; the load logs it.
            guard let materialPath = pass.material, let materialData = read(materialPath),
                  let material = try? decodeTolerant(MaterialDocument.self, from: materialData),
                  let shader = material.passes.first?.shader else { return [:] }
            var inputs: [Int: EditorPreviewScene.Input] = [:]
            for stage in ShaderStage.allCases {
                // Optional: a stage the shader doesn't have declares nothing.
                guard let source = try? loader.load(shader, stage: stage) else { continue }
                for sampler in source.samplers {
                    guard let slot = sampler.textureSlot, slot > 0, inputs[slot] == nil,
                          let input = EditorPreviewScene.input(mode: sampler.annotation["mode"] as? String, combo: sampler.combo,
                                                               defaultTexture: sampler.defaultTexture,
                                                               hidden: sampler.annotation["hidden"] as? Bool == true)
                    else { continue }
                    inputs[slot] = input
                }
            }
            return inputs
        }
    }

    // MARK: Files

    /// The wallpaper's files: its package, else its folder.
    private static func wallpaperReader(_ directory: URL) throws -> (String) -> Data? {
        guard let wallpaper = InstalledLibrary.wallpaper(at: directory, hiding: []) else {
            throw Failure.unreadable(directory.path(percentEncoded: false))
        }
        let package = try WallpaperEditorSource.read(wallpaper).package
        return { path in
            if let data = package?.extractFile(named: path) { return data }
            // A missing loose file is an ordinary miss: the effect's file isn't the wallpaper's.
            return (try? AssetPathResolver.data(path, in: directory)) ?? nil
        }
    }

    /// The preview folder's files, then WE's assets, as the loader finds them.
    private static func folderReader(_ folder: URL) -> (String) -> Data? {
        { path in
            // Optional lookups: each source may not have the file.
            if let data = (try? AssetPathResolver.data(path, in: folder)) ?? nil { return data }
            guard let url = WallpaperEngineAssets.locate([path], in: WallpaperEngineAssets.searchDirectories) else { return nil }
            return try? AssetPathResolver.readRegularFile(at: url)
        }
    }

    private static func store(_ files: [String: Data], in folder: URL) throws {
        for (path, data) in files {
            let url = try destination(path, in: folder)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private static func copy(_ source: URL, to path: String, in folder: URL) throws {
        try store([path: try AssetPathResolver.readRegularFile(at: source)], in: folder)
    }

    /// `path` inside `folder`; a path leaving it (`..`) is refused.
    private static func destination(_ path: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: path).standardizedFileURL
        guard url.path(percentEncoded: false).hasPrefix(folder.standardizedFileURL.path(percentEncoded: false)) else {
            throw Failure.unreadable(path)
        }
        return url
    }
}
