import Foundation

/// The header of a `.tex` file and where its first image's mipmaps are: what a writer needs to
/// copy or rewrite it (`TEXWriter`). `TEXParser` decodes the pictures.
///
/// ```
/// "TEXV0005\0" "TEXI0001\0"
/// u32 format, flags, texture width, texture height, image width, image height, colour
/// "TEXB000n\0"  u32 image count
/// TEXB0003: i32 FreeImage format   TEXB0004: i32 FreeImage format, u32 is-MP4
/// per image: u32 mipmap count, per mipmap: u32 width, height, [u32 compression, uncompressed size,] stored size, bytes
/// ```
struct TEXFileHeader: Equatable {
    struct Mipmap: Equatable {
        var width: Int
        var height: Int
        /// 0 stored as is, 1 LZ4.
        var compression: UInt32
        var uncompressedSize: Int
        /// The stored bytes' range in the file.
        var stored: Range<Int>
    }

    var format: UInt32
    var flags: UInt32
    var textureWidth: Int
    var textureHeight: Int
    var imageWidth: Int
    var imageHeight: Int
    /// The `TEXI` header's last word, kept as it is (WE writes the texture's colour there).
    var colorWord: UInt32
    /// 1…4, from `TEXB000n`.
    var containerVersion: Int
    var imageCount: Int
    /// The FreeImage format of an embedded picture (PNG, JPEG…); -1 for raw pixels.
    var freeImageFormat: Int32
    var isVideo: Bool
    var mipmaps: [Mipmap]
    /// Bytes after the first image's mipmaps (more images, a sprite sheet's frames).
    var trailingByteCount: Int

    /// The header of `data`; nil when it isn't a `.tex` this reads (video textures and multi-image
    /// files still give their header, without mipmaps past the first image).
    init?(_ data: Data) {
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
        isVideo = false
        if version >= 3 {
            guard let value = word() else { return nil }
            freeImageFormat = Int32(bitPattern: value)
        }
        if version == 4 {
            guard let value = word() else { return nil }
            isVideo = value == 1 || freeImageFormat == 35
        }
        mipmaps = []
        trailingByteCount = 0
        guard !isVideo, imageCount > 0, let count = word(), count < 64 else { return }
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
