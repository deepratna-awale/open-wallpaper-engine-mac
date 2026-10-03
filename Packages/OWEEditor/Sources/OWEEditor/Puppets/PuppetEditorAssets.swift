import CoreGraphics
import Foundation
import OWESceneEditing

/// The puppet editor's text, from its own table (`Resources/Puppets.xcstrings`), in every
/// language the app ships.
func PL(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Puppets", bundle: .module)
}

/// What the puppet editor reads of the wallpaper, from the app: its files (from its package or
/// folder) and an image layer's picture, decoded as the renderer decodes it.
public struct PuppetEditorAssets {
    /// A file of the wallpaper by its path (`models/foo.json`); nil when it has none.
    public var readFile: (String) -> Data?
    /// The picture an image layer's model draws (its material's first texture), by the model's path.
    public var image: (String) -> CGImage?

    public init(readFile: @escaping (String) -> Data?, image: @escaping (String) -> CGImage?) {
        self.readFile = readFile
        self.image = image
    }
}

extension PuppetImage {
    /// The picture as 8-bit premultiplied RGBA, top row first.
    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 4 * width * height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 4 * width, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// The image as a `CGImage`.
    var cgImage: CGImage? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * width,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// An image layer's puppet as the wallpaper has it: its model, the rig the model names, the
/// picture and the layer's animation layers.
struct PuppetSource {
    /// The layer's `image`: its model JSON.
    var modelPath: String
    /// The model's `material`.
    var material: String
    /// The model's `puppet`, when it has one.
    var rigPath: String?
    var image: CGImage?
    var texture: PuppetImage?
    /// The picture's size in pixels (the layer's `size` when the picture can't be read).
    var imageSize: SIMD2<Float>
    /// The rig as the wallpaper has it, with the layer's animation layers.
    var document: PuppetDocument?
    /// Why the rig couldn't be read.
    var error: String?

    static func load(layer: SceneLayer, assets: PuppetEditorAssets) -> PuppetSource? {
        guard let modelPath = layer.fields["image"]?.stringValue else { return nil }
        let model = assets.readFile(modelPath).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let image = assets.image(modelPath)
        let size = SceneVector.components(layer.fields["size"].flatMap { SceneFieldBinding.literal(of: $0) })
        var imageSize = SIMD2<Float>(Float(size.first ?? 512), Float(size.count > 1 ? size[1] : 512))
        if let image { imageSize = SIMD2(Float(image.width), Float(image.height)) }
        var source = PuppetSource(modelPath: modelPath, material: model["material"] as? String ?? "",
                                  rigPath: model["puppet"] as? String, image: image, texture: image.flatMap(PuppetImage.init),
                                  imageSize: imageSize)
        if let rigPath = source.rigPath {
            do {
                guard let data = assets.readFile(rigPath) else {
                    throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: rigPath])
                }
                var document = try PuppetMDLReader.read(data, imageSize: imageSize, sourcePath: rigPath)
                if case .array(let layers)? = layer.fields["animationlayers"] {
                    document.layers = layers.enumerated().compactMap { PuppetAnimationLayer(json: $0.element, fallbackID: $0.offset + 1) }
                }
                source.document = document
            } catch {
                source.error = error.localizedDescription
            }
        }
        return source
    }
}
