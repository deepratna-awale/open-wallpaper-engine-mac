import Foundation

/// Writes a single-image `.tex` (`TEXFileHeader` has the layout) in WE's newest container,
/// `TEXB0004` with no FreeImage picture and no video, as WE's mobile export writes the textures
/// it converts.
enum TEXWriter {
    struct Mipmap: Equatable {
        var width: Int
        var height: Int
        /// 0 stored as is, 1 LZ4.
        var compression: UInt32
        var uncompressedSize: Int
        var stored: Data
    }

    struct Texture: Equatable {
        var format: UInt32
        var flags: UInt32
        var textureWidth: Int
        var textureHeight: Int
        var imageWidth: Int
        var imageHeight: Int
        var colorWord: UInt32
        var mipmaps: [Mipmap]
    }

    static func data(_ texture: Texture) -> Data {
        var data = Data()
        func word(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func tag(_ text: String) { data.append(contentsOf: Array(text.utf8) + [0]) }
        tag("TEXV0005")
        tag("TEXI0001")
        for value in [texture.format, texture.flags, UInt32(texture.textureWidth), UInt32(texture.textureHeight),
                      UInt32(texture.imageWidth), UInt32(texture.imageHeight), texture.colorWord] { word(value) }
        tag("TEXB0004")
        word(1)
        word(UInt32(bitPattern: -1))
        word(0)
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
}
