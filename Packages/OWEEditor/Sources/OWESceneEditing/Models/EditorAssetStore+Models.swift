import Foundation
import ImageIO

/// An imported 3D model in the edits' files (docs/model-import.md), laid out as WE's importer
/// lays one out in a project, in a folder named by the source's content:
///
/// - `models/<folder>/<name>.<fbx|obj>`: the source (and an OBJ's `.mtl`), which the Model
///   Editor compiles again;
/// - `models/<folder>/<name>.json`: its configuration (`ModelImportConfig`);
/// - `models/<folder>/<name>.mdl`: the compiled model, which a model layer's `model` names;
/// - `materials/models/<folder>/<material>.json` and its texture beside it.
///
/// The store never overwrites a file, so a model the Model Editor compiles with other settings
/// is `<name>-<hash>.json` and `<name>-<hash>.mdl`, the hash naming the configuration.
public struct ImportedModel: Equatable, Sendable {
    /// `models/<folder>/<name>.mdl` (or `<name>-<hash>.mdl`), a model layer's `model`.
    public var model: String
    /// The configuration it was compiled with.
    public var config: String
    /// The source file (`models/<folder>/<name>.fbx`).
    public var source: String
    /// The name the layer gets: the file's name without its extension.
    public var title: String
    /// Textures the source names that weren't found (the material draws WE's white instead).
    public var missingTextures: [String]
    public var animations: [ModelCompiler.AnimationInfo]
    public var bones: [String]
    public var boundsMin: SIMD3<Float>
    public var boundsMax: SIMD3<Float>
}

extension EditorAssetStore {
    /// The folder of a model's files: `<name>-<hash of the source>`.
    public static func modelFolder(title: String, source: Data) -> String {
        assetName(title, data: source)
    }

    /// Keeps a compiled model and its source in the edits' files: the source file and the
    /// other files it needs (`companions`, by name: an OBJ's `.mtl`, more animation files), the
    /// configuration, the `.mdl`, and each material with its texture.
    /// `folder` is the model's folder (`modelFolder`); `revision` names a configuration other
    /// than the first one (the Model Editor's), nil for the import's own.
    public func storeModel(_ output: ModelCompiler.Output, sourceURL: URL, companions: [URL] = [], config: ModelImportConfig,
                           folder: String, title: String, revision: String? = nil) throws -> ImportedModel {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard let sourceData = try? Data(contentsOf: sourceURL) else { throw ImportError.unreadable(sourceURL.lastPathComponent) }
        let base = ModelCompiler.fileName(title)
        let source = "models/\(folder)/\(base).\(fileExtension)"
        try write(sourceData, to: source)
        for companion in companions {
            guard let data = try? Data(contentsOf: companion) else { continue }
            try write(data, to: "models/\(folder)/\(ModelCompiler.fileName(companion.lastPathComponent))")
        }
        let stem = revision.map { "\(base)-\($0)" } ?? base
        let configPath = "models/\(folder)/\(stem).json"
        try write(try config.jsonData(), to: configPath)
        let model = "models/\(folder)/\(stem).mdl"
        try write(output.mdl, to: model)

        var missing: [String] = []
        let directory = sourceURL.deletingLastPathComponent()
        for material in output.materials {
            var textures: [String] = []
            if let albedo = material.albedo {
                if let written = try storeModelTexture(albedo, near: directory, as: "materials/\(material.texturePath)") {
                    textures.append(written)
                } else {
                    missing.append(albedo.path)
                }
            }
            if let normal = material.normalMap,
               let written = try storeModelTexture(normal, near: directory, as: "materials/\(material.texturePath)_normal") {
                if textures.isEmpty { textures.append("util/white") }
                textures.append(written)
            }
            var json = ModelCompiler.materialJSON(texture: textures.first)
            if textures.count > 1, case .array(var passes)? = json["passes"], case .object(var pass) = passes[0] {
                pass["textures"] = .array(textures.map { .string($0) })
                passes[0] = .object(pass)
                json["passes"] = .array(passes)
            }
            let data = try JSONSerialization.data(withJSONObject: SceneJSONValue.object(json).any, options: [.prettyPrinted, .sortedKeys])
            try write(data, to: material.path)
        }
        return ImportedModel(model: model, config: configPath, source: source, title: title, missingTextures: missing,
                             animations: output.animations, bones: output.bones, boundsMin: output.boundsMin,
                             boundsMax: output.boundsMax)
    }

    /// Writes a texture a model names as `<path>.png` or `.jpg` and returns its texture path
    /// (without `materials/` and the extension); nil when neither the file nor its bytes are
    /// found. The file is looked for where the model names it, then by its name beside the
    /// model (WE's importer: "make sure its texture files are placed in the same directory").
    func storeModelTexture(_ texture: ModelSource.Texture, near directory: URL, as path: String) throws -> String? {
        var data = texture.embedded
        var name = (texture.path.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        if data == nil {
            let candidates = [URL(fileURLWithPath: texture.path.replacingOccurrences(of: "\\", with: "/")),
                              directory.appending(path: texture.path.replacingOccurrences(of: "\\", with: "/")),
                              directory.appending(path: name)]
            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                data = try? Data(contentsOf: url)
                if data != nil { break }
            }
            // A different case of the same name (a Windows-made model).
            if data == nil, let match = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
                .first(where: { $0.lowercased() == name.lowercased() }) {
                data = try? Data(contentsOf: directory.appending(path: match))
                name = match
            }
        }
        guard let data else { return nil }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        let texturePath = String(path.dropFirst("materials/".count))
        if Self.keptImageTypes.contains(fileExtension) {
            try write(data, to: "\(path).\(fileExtension == "jpeg" ? "jpg" : fileExtension)")
            return texturePath
        }
        // Anything else ImageIO reads (TGA, BMP, PSD, TIFF…) becomes a PNG of its first image.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = Self.pngData(image) else { return nil }
        try write(png, to: "\(path).png")
        return texturePath
    }

    /// The configuration beside a model the store holds (`<model>.json`), when there is one.
    public func modelConfig(for model: String) -> ModelImportConfig? {
        let path = (model as NSString).deletingPathExtension + ".json"
        guard let url = url(for: path), let data = try? Data(contentsOf: url) else { return nil }
        return try? ModelImportConfig(json: data)
    }

    /// The source a model the store holds was compiled from: the FBX or OBJ in its folder whose
    /// name the model's starts with.
    public func modelSource(for model: String) -> URL? {
        let folder = (model as NSString).deletingLastPathComponent
        guard let directory = url(for: folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        let stem = ((model as NSString).lastPathComponent as NSString).deletingPathExtension
        return names.sorted { $0.count > $1.count }.first { name in
            let ext = (name as NSString).pathExtension.lowercased()
            let base = (name as NSString).deletingPathExtension
            return ["fbx", "obj"].contains(ext) && (stem == base || stem.hasPrefix(base + "-"))
        }.map { directory.appending(path: $0) }
    }

    /// The `.mdl` files the store holds (imported models), by scene path.
    public func importedModels() -> [String] {
        assets().map(\.path).filter { $0.lowercased().hasPrefix("models/") && $0.lowercased().hasSuffix(".mdl") }
    }
}
