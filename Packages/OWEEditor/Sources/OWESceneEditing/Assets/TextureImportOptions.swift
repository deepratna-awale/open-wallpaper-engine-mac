import CoreGraphics
import Foundation

/// What WE's image importer lets the author choose for a texture (its import dialog,
/// `material.config`; the texture-format page of WE's docs, `en_scene_performance_texture`):
/// the format, Pixel Art Optimization (`nointerpolation`), No Mip Maps (`nomip`), Clamp UVs
/// (`clampuvs`), Crop transparent area (`croptransparent` with `croppadding`), a normal map, and
/// an image sequence's frame duration (`imageListDuration`). WE's defaults: RGBA 8888, mipmapped,
/// bilinear, clamped, uncropped.
public struct TextureImportOptions: Hashable, Sendable {
    /// WE's import formats, in its dialog's order.
    public enum Format: String, CaseIterable, Sendable {
        /// "High Quality - Uncompressed (RGBA 8888)", WE's default.
        case rgba8888
        /// "Good Performance - Minor Compression (DXT5)".
        case dxt5
        /// "High Performance - Medium Compression (DXT1)": no alpha beyond one bit.
        case dxt1
        /// "High Quality - Uncompressed Dual Channel (RG 88)".
        case rg88
        /// "High Quality - Uncompressed Single Channel (R 8)".
        case r8

        /// The `.tex` header's format word (the shaders' `FORMAT_*`).
        public var texFormat: UInt32 {
            switch self {
            case .rgba8888: return 0
            case .dxt5: return 4
            case .dxt1: return 7
            case .rg88: return 8
            case .r8: return 9
            }
        }
    }

    public var format: Format = .rgba8888
    /// Nearest filtering (`TEXFlags` bit 0).
    public var pixelArt = false
    /// Only the full-size image, no smaller copies.
    public var noMipmaps = false
    /// Clamp to the edge instead of repeating (`TEXFlags` bit 1).
    public var clampUVs = true
    /// Crop the image to its non-transparent pixels, `cropPadding` pixels around them kept.
    public var cropTransparency = false
    public var cropPadding = 0
    /// A normal map for the image, imported beside it (WE's `rg88n`) as its material's second texture.
    public var normalMap: URL?
    /// Seconds each image of an imported sequence shows.
    public var frameDuration = 0.1

    public init() {}

    /// The texture is what a PNG or JPEG gives the renderer as it is: WE's RGBA 8888 picture,
    /// bilinear, mipmapped and clamped, so the file is kept rather than rewritten as a `.tex`.
    public var keepsPicture: Bool { format == .rgba8888 && !pixelArt && !noMipmaps && clampUVs }

    /// The `.tex` flags these options give (`TEXFlags`): point filtering, clamping, a sprite sheet.
    public func texFlags(spriteSheet: Bool = false) -> UInt32 {
        (pixelArt ? 1 : 0) | (clampUVs ? 2 : 0) | (spriteSheet ? 4 : 0)
    }
}

/// One image of an animated texture and how long it shows.
public struct TextureImportFrame: @unchecked Sendable {
    public var image: CGImage
    public var duration: Double

    public init(image: CGImage, duration: Double) {
        self.image = image
        self.duration = duration
    }
}

/// Writes WE's `.tex` files for the importer; the app's `.tex` writer (`EditorTEXEncoder`).
public protocol EditorTextureEncoding: Sendable {
    /// A still image in the options' format, flags and mipmaps.
    func texture(_ image: CGImage, options: TextureImportOptions) throws -> Data
    /// A normal map as WE imports one (`rg88n`: its red and green, clamped, mipmapped).
    func normalMap(_ image: CGImage) throws -> Data
    /// The frames as one sprite sheet with its frame table (`TEXS0003`); returns the sheet's size.
    func spriteSheet(_ frames: [TextureImportFrame], options: TextureImportOptions) throws -> (data: Data, size: SIMD2<Double>)
    /// An MP4 as a video texture (WE 2.2's video image layer); returns the video's size.
    func video(_ url: URL) throws -> (data: Data, size: SIMD2<Double>)
}
