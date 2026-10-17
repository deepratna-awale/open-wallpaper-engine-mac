import Foundation

/// The header of a `.tex` file and where its first image's mipmaps are: what a writer needs to
/// copy or rewrite it (`TEXWriter`). `TEXParser` decodes the pictures.
///
/// ```
/// "TEXV0005\0" "TEXI0001\0"
/// u32 format, flags, texture width, texture height, image width, image height, colour
/// "TEXB000n\0"  u32 image count
/// TEXB0003: i32 FreeImage format   TEXB0004: i32 FreeImage format, u32 variant count (`TEXVariants`)
/// per image: u32 mipmap count, per mipmap: u32 width, height, [u32 compression, uncompressed size,] stored size, bytes
/// ```
public struct TEXFileHeader: Equatable {
    public struct Mipmap: Equatable {
        public var width: Int
        public var height: Int
        /// 0 stored as is, 1 LZ4.
        public var compression: UInt32
        public var uncompressedSize: Int
        /// The stored bytes' range in the file.
        public var stored: Range<Int>

        public init(width: Int, height: Int, compression: UInt32, uncompressedSize: Int, stored: Range<Int>) {
            self.width = width
            self.height = height
            self.compression = compression
            self.uncompressedSize = uncompressedSize
            self.stored = stored
        }
    }

    public var format: UInt32
    public var flags: UInt32
    public var textureWidth: Int
    public var textureHeight: Int
    public var imageWidth: Int
    public var imageHeight: Int
    /// The `TEXI` header's last word, kept as it is (WE writes the texture's colour there).
    public var colorWord: UInt32
    /// 1…4, from `TEXB000n`.
    public var containerVersion: Int
    public var imageCount: Int
    /// The FreeImage format of an embedded picture (PNG, JPEG…); -1 for raw pixels.
    public var freeImageFormat: Int32
    public var isVideo: Bool
    /// The texture variants `TEXB0004` declares (`TEXVariants`); with any, the mipmaps aren't
    /// listed, as variant patches follow each one.
    public var variantCount: Int
    public var mipmaps: [Mipmap]
    /// Bytes after the first image's mipmaps (more images, a sprite sheet's frames).
    public var trailingByteCount: Int

    /// The header of `data`; nil when it isn't a `.tex` this reads (video textures and multi-image
    /// files still give their header, without mipmaps past the first image).
    public init?(_ data: Data) {
        let bytes = [UInt8](data)
        var cursor = 0
        func word() -> UInt32? {
            guard cursor + 4 <= bytes.count else { return nil }
            defer { cursor += 4 }
            return UInt32(bytes[cursor]) | UInt32(bytes[cursor + 1]) << 8 | UInt32(bytes[cursor + 2]) << 16 | UInt32(bytes[cursor + 3]) << 24
        }
        func tag() -> String? {
            guard let end = bytes[cursor...].firstIndex(of: 0) else { return nil }
            defer { cursor = end + 1 }
            return String(decoding: bytes[cursor..<end], as: UTF8.self)
        }
        guard tag() == "TEXV0005", tag() == "TEXI0001",
              let format = word(), let flags = word(), let textureWidth = word(), let textureHeight = word(),
              let imageWidth = word(), let imageHeight = word(), let colorWord = word(),
              let container = tag(), container.hasPrefix("TEXB"), let version = Int(container.dropFirst(4)),
              (1...4).contains(version), let imageCount = word() else { return nil }
        self.format = format
        self.flags = flags
        self.textureWidth = Int(textureWidth)
        self.textureHeight = Int(textureHeight)
        self.imageWidth = Int(imageWidth)
        self.imageHeight = Int(imageHeight)
        self.colorWord = colorWord
        containerVersion = version
        self.imageCount = Int(imageCount)
        freeImageFormat = -1
        // WE marks a video texture with the TEXI flag, not the FreeImage format (-1 in library
        // video textures, `TEXFlags.video`).
        isVideo = flags & TEXFlags.video.rawValue != 0
        variantCount = 0
        if version >= 3 {
            guard let value = word() else { return nil }
            freeImageFormat = Int32(bitPattern: value)
        }
        if version == 4 {
            guard let value = word() else { return nil }
            variantCount = Int(value)
        }
        mipmaps = []
        trailingByteCount = 0
        guard !isVideo, variantCount == 0, imageCount > 0, let count = word(), count < 64 else { return }
        for _ in 0..<count {
            guard let width = word(), let height = word() else { return nil }
            var compression: UInt32 = 0, uncompressed = 0
            if version != 1 {
                guard let value = word(), let size = word() else { return nil }
                compression = value
                uncompressed = Int(size)
            }
            guard let stored = word(), Int(stored) <= bytes.count - cursor else { return nil }
            mipmaps.append(Mipmap(width: Int(width), height: Int(height), compression: compression,
                                  uncompressedSize: uncompressed, stored: cursor..<(cursor + Int(stored))))
            cursor += Int(stored)
        }
        trailingByteCount = bytes.count - cursor
    }
}
