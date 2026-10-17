import Foundation

/// Writes a single-image `.tex` (`TEXFileHeader` has the layout) with no FreeImage picture: in
/// WE's newest container, `TEXB0004` with no video, as WE's mobile export writes the textures it
/// converts, or in `TEXB0003`, as WE's editor writes a painted effect mask (`effectMask`).
public enum TEXWriter {
    /// The `TEXB` container: `TEXB0004` has a video word after the FreeImage format.
    public enum Container: Equatable {
        case b0003, b0004
    }

    public struct Mipmap: Equatable {
        public var width: Int
        public var height: Int
        /// 0 stored as is, 1 LZ4.
        public var compression: UInt32
        public var uncompressedSize: Int
        public var stored: Data

        public init(width: Int, height: Int, compression: UInt32, uncompressedSize: Int, stored: Data) {
            self.width = width
            self.height = height
            self.compression = compression
            self.uncompressedSize = uncompressedSize
            self.stored = stored
        }
    }

    public struct Texture: Equatable {
        public var format: UInt32
        public var flags: UInt32
        public var textureWidth: Int
        public var textureHeight: Int
        public var imageWidth: Int
        public var imageHeight: Int
        public var colorWord: UInt32
        public var mipmaps: [Mipmap]

        public init(format: UInt32, flags: UInt32, textureWidth: Int, textureHeight: Int, imageWidth: Int, imageHeight: Int, colorWord: UInt32, mipmaps: [Mipmap]) {
            self.format = format
            self.flags = flags
            self.textureWidth = textureWidth
            self.textureHeight = textureHeight
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
            self.colorWord = colorWord
            self.mipmaps = mipmaps
        }
    }

    public static func data(_ texture: Texture, container: Container = .b0004) -> Data {
        var data = Data()
        func word(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func tag(_ text: String) { data.append(contentsOf: Array(text.utf8) + [0]) }
        tag("TEXV0005")
        tag("TEXI0001")
        for value in [texture.format, texture.flags, UInt32(texture.textureWidth), UInt32(texture.textureHeight),
                      UInt32(texture.imageWidth), UInt32(texture.imageHeight), texture.colorWord] { word(value) }
        tag(container == .b0004 ? "TEXB0004" : "TEXB0003")
        word(1)
        word(UInt32(bitPattern: -1))
        if container == .b0004 { word(0) }
        word(UInt32(texture.mipmaps.count))
        for mipmap in texture.mipmaps {
            for value in [mipmap.width, mipmap.height] { word(UInt32(value)) }
            word(mipmap.compression)
            word(UInt32(mipmap.uncompressedSize))
            word(UInt32(mipmap.stored.count))
            data.append(mipmap.stored)
        }
        return data
    }

    /// An effect mask as WE's editor writes one (`materials/masks/<effect>_mask_<hash>.tex` in
    /// Workshop scenes): one 8-bit channel (`FORMAT_R8`, format 9), clamped UVs, the texture the
    /// image's own size (no power-of-two padding), one LZ4 mipmap in a `TEXB0003` container.
    /// `pixels`: `width` × `height` grey values, rows top to bottom.
    public static func effectMask(_ pixels: [UInt8], width: Int, height: Int) -> Data {
        precondition(pixels.count == width * height, "a mask has one byte per pixel")
        return data(Texture(format: UInt32(TEXImageFormat.r8.rawValue), flags: TEXFlags.clampUVs.rawValue,
                            textureWidth: width, textureHeight: height, imageWidth: width, imageHeight: height,
                            colorWord: 0xFF00_0000,
                            mipmaps: [Mipmap(width: width, height: height, compression: 1, uncompressedSize: pixels.count,
                                             stored: Data(LZ4BlockEncoder.compress(pixels)))]),
                    container: .b0003)
    }
}
