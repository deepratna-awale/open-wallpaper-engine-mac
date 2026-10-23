import Metal
import OWESceneEditing
import XCTest
@testable import OpenWallpaperEngine

/// A video texture's variant against Wallpaper Engine's own output (capture 550 (c), WE 2.8.0.42,
/// `Tests/Fixtures/TextureVariants/550c`): `vid_base.mp4` (512 × 256, 4 s) imported as an image
/// layer, then Texture Properties › Add Variant Group "clip" › Add Option `vid_opt.mp4` (same
/// size), Replace, Condition `shapesel` = 1. WE's `vid_base.tex` stores both MP4s as they are, the
/// base as the mipmap and the option as its one patch; with `shapesel` 1 the option video replaces
/// the base and plays.
final class TEXVariantVideoCaptureTests: XCTestCase {
    private static let folder = "TextureVariants/550c"

    private func fixture(_ name: String) throws -> Data { try Fixtures.data("\(Self.folder)/\(name)") }

    private func resolved(_ data: Data, shapesel: String) -> Data {
        UserPropertyBindingTable().resolvedData(data, path: "materials/vid_base.tex", properties: { $0 == "shapesel" ? shapesel : nil })
    }

    /// The `.tex` as WE wrote it: header, option record, the base MP4 as the mipmap, the option's
    /// as one patch of no rectangle.
    private func layout(_ data: Data) throws -> (header: TEXHeader, words: [UInt32], base: Data, option: Data) {
        var reader = try XCTUnwrap(TEXReader(data))
        let header = reader.header
        let options = try XCTUnwrap(reader.options(count: header.variantCount))
        XCTAssertEqual(options, [TEXVariants.Option(group: 1, id: 1, blend: .wholeMipmap, condition: .equals(property: "shapesel", value: "1"))])
        XCTAssertEqual(try XCTUnwrap(reader.word()), 1, "one mipmap")
        let mipmap = try XCTUnwrap(reader.mipmap())
        var words = [UInt32(mipmap.width), UInt32(mipmap.height), mipmap.compression, UInt32(mipmap.uncompressedSize)]
        let base = data.subdata(in: mipmap.stored)
        words += try (0..<10).map { _ in try XCTUnwrap(reader.word()) }
        let option = try XCTUnwrap(reader.range(Int(words.last!)))
        XCTAssertEqual(reader.cursor, reader.bytes.count, "nothing after the patch")
        return (header, words, base, data.subdata(in: option))
    }

    // MARK: The player reads WE's file

    func testWEsVideoTextureStoresBothMoviesAsTheyAre() throws {
        let data = try fixture("vid_base.tex")
        let (header, words, base, option) = try layout(data)
        XCTAssertTrue(header.isVideo)
        XCTAssertEqual(header.format, 0)
        XCTAssertEqual(header.freeImageFormat, -1)
        XCTAssertEqual([header.imageWidth, header.imageHeight], [512, 256])
        // The mipmap (512 × 256, stored, no uncompressed size), one group of one patch: group 1,
        // option 1, a rectangle of zeros, FreeImage -1, then the option's size.
        XCTAssertEqual(Array(words.prefix(4)), [512, 256, 0, 0])
        XCTAssertEqual(Array(words.dropFirst(4)), [1, 1, 1, 1, 0, 0, 0, 0, UInt32(bitPattern: -1), UInt32(option.count)])
        // `ftypisom` at 157 and 258327, the option byte for byte the file Add Option took.
        XCTAssertEqual(data[157..<165], Data("ftypisom".utf8))
        XCTAssertEqual(data[258327..<258335], Data("ftypisom".utf8))
        XCTAssertEqual(option, try fixture("vid_opt.mp4"))
        XCTAssertEqual(MP4TrackSize.pictureSize(of: base)?.width, 512)
    }

    /// `shapesel` 0 plays the base, 1 the option in its place.
    func testTheOptionVideoReplacesTheBaseWhenSelected() throws {
        let data = try fixture("vid_base.tex")
        let (_, _, base, option) = try layout(data)
        XCTAssertEqual(TEXParser(data: resolved(data, shapesel: "0")).extractVideoData(), base)
        XCTAssertEqual(TEXParser(data: resolved(data, shapesel: "2")).extractVideoData(), base)
        let selected = try XCTUnwrap(TEXParser(data: resolved(data, shapesel: "1")).extractVideoData())
        XCTAssertEqual(selected, option)
        // It plays as the layer's video texture (`IVideoTexture`).
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let stream = try XCTUnwrap(VideoTextureStream.embedded(mp4: selected, device: device))
        stream.stop()
    }

    // MARK: The editor writes what WE writes

    /// The base imported as the editor imports a movie, the option compiled from WE's `.tex-json`:
    /// every byte is WE's.
    func testTheEditorWritesWEsVideoTexture() throws {
        let theirs = try fixture("vid_base.tex")
        let (_, _, movie, _) = try layout(theirs)
        let base = EditorTEXEncoder.videoTexture(movie, width: 512, height: 256)
        let document = try XCTUnwrap(TextureVariantDocument(json: try fixture("vid_base.tex-json"), texture: "vid_base"))
        XCTAssertEqual(document.groups.map(\.name), ["clip"])
        XCTAssertEqual(document.groups[0].options.map(\.file), ["materials/vid_opt.mp4"])
        let inputs = try document.compiledOptions.map { group, id, option in
            TextureVariantInput(group: group, id: id, alphaBlend: option.blend == .alphaBlend,
                                condition: option.condition?.compiledJSON ?? "{}", file: try fixture("vid_opt.mp4"))
        }
        let ours = try EditorTEXEncoder().texture(base, withVariants: inputs)
        XCTAssertEqual(ours.count, theirs.count)
        XCTAssertEqual(ours, theirs)
        // An image option on the video is refused (WE: "cannot mix images and videos in a texture").
        let png = try XCTUnwrap(TEXVariantWriter.pngData([UInt8](repeating: 255, count: 512 * 256 * 4), width: 512, height: 256))
        XCTAssertThrowsError(try EditorTEXEncoder().texture(base, withVariants: [
            TextureVariantInput(group: 1, id: 1, alphaBlend: false, condition: inputs[0].condition, file: Data(png)),
        ])) { XCTAssertEqual($0 as? TextureVariantError, .incompatible(optionID: 1)) }
    }
}
