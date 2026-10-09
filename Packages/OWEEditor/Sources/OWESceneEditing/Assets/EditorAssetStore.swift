import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The files the editor adds to a wallpaper (imported images, sounds and fonts, painted masks),
/// kept in the overlay's own folder beside its edits, never in the wallpaper (editor-plan notes
/// §3). Paths inside it are the scene's own (`materials/editor/…`, `models/editor/…`,
/// `sounds/editor/…`, `fonts/editor/…`, `materials/masks/…`), which the scene loader finds there
/// after the wallpaper's own files; Save as New Wallpaper copies them into the copy.
///
/// Every file is named by its content's hash, so an edit naming it always means the same bytes,
/// the scene cache key (which covers the overlay) changes with them, and importing twice writes once.
public struct EditorAssetStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public enum ImportError: Error, Equatable, LocalizedError {
        /// Not a file the editor can turn into the asset asked for.
        case unsupported(String)
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "“\(name)” isn’t a kind of file this can use."
            case .unreadable(let name): return "“\(name)” can’t be read."
            }
        }
    }

    /// An image imported for an image layer: its texture, material and model, and its size in pixels.
    public struct ImportedImage: Hashable, Sendable {
        /// `models/editor/<name>.json`, the layer's `image`.
        public var model: String
        /// `materials/editor/<name>.json`.
        public var material: String
        /// `editor/<name>`, the material's texture.
        public var texture: String
        public var size: SIMD2<Double>
        /// The file's name without its extension, for the layer's name.
        public var title: String
    }

    // MARK: Images

    /// Image types the renderer reads as they are (`SceneWallpaperViewModel.loadTexture`); any
    /// other image is converted to PNG.
    static let keptImageTypes: Set<String> = ["png", "jpg", "jpeg"]

    /// Imports an image for a new image layer: the texture (PNG or JPEG as it is, any other image
    /// converted to PNG), and the material and model WE's editor writes for one
    /// (`genericimage2`, translucent).
    public func importImage(from url: URL) throws -> ImportedImage {
        let title = url.deletingPathExtension().lastPathComponent
        let (data, fileExtension, size) = try Self.textureData(from: url)
        let name = Self.assetName(title, data: data)
        let texture = "editor/\(name)"
        try write(data, to: "materials/\(texture).\(fileExtension)")
        let material = "materials/editor/\(name).json"
        let materialJSON: [String: Any] = [
            "passes": [[
                "blending": "translucent", "cullmode": "nocull", "depthtest": "disabled", "depthwrite": "disabled",
                "shader": "genericimage2", "textures": [texture],
            ]],
        ]
        try write(try JSONSerialization.data(withJSONObject: materialJSON, options: [.prettyPrinted, .sortedKeys]), to: material)
        let model = "models/editor/\(name).json"
        let modelJSON: [String: Any] = ["autosize": true, "material": material]
        try write(try JSONSerialization.data(withJSONObject: modelJSON, options: [.prettyPrinted, .sortedKeys]), to: model)
        return ImportedImage(model: model, material: material, texture: texture, size: size, title: title)
    }

    /// The image's bytes as the renderer reads them, their extension and the image's size.
    static func textureData(from url: URL) throws -> (Data, String, SIMD2<Double>) {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportError.unsupported(name)
        }
        let size = SIMD2(Double(image.width), Double(image.height))
        let fileExtension = url.pathExtension.lowercased()
        // A single-frame PNG or JPEG is read as it is; anything else becomes a PNG of its first frame.
        if keptImageTypes.contains(fileExtension), CGImageSourceGetCount(source) == 1 {
            guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable(name) }
            return (data, fileExtension == "jpeg" ? "jpg" : fileExtension, size)
        }
        guard let png = pngData(image) else { throw ImportError.unreadable(name) }
        return (png, "png", size)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: Masks

    /// Saves a painted mask (a PNG) and returns its texture path (`masks/editor_<name>`), which an
    /// effect's texture slot takes.
    public func saveMask(_ png: Data, title: String) throws -> String {
        let name = "editor_" + Self.assetName(title, data: png)
        try write(png, to: "materials/masks/\(name).png")
        return "masks/\(name)"
    }

    /// Imports an image as a mask: converted to PNG unless it is one.
    public func importMask(from url: URL) throws -> String {
        let (data, fileExtension, _) = try Self.textureData(from: url)
        let name = "editor_" + Self.assetName(url.deletingPathExtension().lastPathComponent, data: data)
        try write(data, to: "materials/masks/\(name).\(fileExtension)")
        return "masks/\(name)"
    }

    // MARK: Sounds and fonts

    /// Sound files the app plays (`AVAudioFile`, and WE's own Ogg).
    public static let soundTypes: Set<String> = ["mp3", "wav", "ogg", "m4a", "aac", "aif", "aiff", "caf", "flac"]
    public static let fontTypes: Set<String> = ["ttf", "otf", "ttc"]

    /// Imports a sound for a sound layer; returns its path (`sounds/editor/<name>.<ext>`).
    public func importSound(from url: URL) throws -> String {
        try importFile(url, folder: "sounds/editor", allowed: Self.soundTypes)
    }

    /// Imports a font for a text layer; returns its path (`fonts/editor/<name>.<ext>`), the layer's `font`.
    public func importFont(from url: URL) throws -> String {
        try importFile(url, folder: "fonts/editor", allowed: Self.fontTypes)
    }

    private func importFile(_ url: URL, folder: String, allowed: Set<String>) throws -> String {
        let fileExtension = url.pathExtension.lowercased()
        guard allowed.contains(fileExtension) else { throw ImportError.unsupported(url.lastPathComponent) }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable(url.lastPathComponent) }
        let path = "\(folder)/\(Self.assetName(url.deletingPathExtension().lastPathComponent, data: data)).\(fileExtension)"
        try write(data, to: path)
        return path
    }

    // MARK: Listing

    /// One file of the store, by its scene path.
    public struct Asset: Hashable, Sendable, Identifiable {
        public var path: String
        public var url: URL
        public var id: String { path }
    }

    /// Everything imported, by scene path.
    public func assets() -> [Asset] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var result: [Asset] = []
        let root = directory.standardizedFileURL.path
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let path = String(url.standardizedFileURL.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            result.append(Asset(path: path, url: url))
        }
        return result.sorted { $0.path < $1.path }
    }

    /// The file at scene path `path`, when the store has it.
    public func url(for path: String) -> URL? {
        guard let url = try? LocalWallpaperWriter.contained(path, in: directory),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: Writing

    /// Keeps `data` at scene path `path` (a built-in effect's material or shader, copied into the
    /// project as WE's editor copies an added effect's dependencies). A file already there stays.
    public func store(_ data: Data, at path: String) throws {
        try write(data, to: path)
    }

    func write(_ data: Data, to path: String) throws {
        let url = try LocalWallpaperWriter.contained(path, in: directory)
        if FileManager.default.fileExists(atPath: url.path) { return } // Named by content: already there.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// `<title>-<hash>`: the title kept readable (letters, digits, `-`, `_`), the hash naming the content.
    static func assetName(_ title: String, data: Data) -> String {
        let hash = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        let cleaned = title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character($0) : "_" }
        var base = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if base.isEmpty { base = "asset" }
        return "\(base.prefix(48).lowercased())-\(hash)"
    }
}
