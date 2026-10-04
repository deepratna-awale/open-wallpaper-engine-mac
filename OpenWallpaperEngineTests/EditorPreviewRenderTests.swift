import AVFoundation
import ImageIO
import OWEEditor
import OWESceneEditing
import XCTest
@testable import OpenWallpaperEngine

/// The Wallpaper Editor's previews, rendered through the real loader and renderer from WE's
/// assets (skipped without them): an effect on the test card, and a preset's particle system as a
/// loop on a dark background.
@MainActor
final class EditorPreviewRenderTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appending(path: "EditorPreviewRenderTests-\(UUID().uuidString)",
                                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch) // Optional: a scratch folder.
    }

    func testTheHelpersDoneLinesAreRead() {
        XCTAssertEqual(EditorPreviewJob.doneIndex(fromLine: Substring(EditorPreviewJob.doneLine(3).dropLast())), 3)
        XCTAssertNil(EditorPreviewJob.doneIndex(fromLine: "progress 3"))
        XCTAssertNil(EditorPreviewJob.doneIndex(fromLine: "done x"))
    }

    func testTheTestCardShipsWithTheApp() throws {
        let url = try XCTUnwrap(EditorPreviewResources.testCard)
        let image = try XCTUnwrap(image(at: url))
        XCTAssertEqual(image.width, EditorPreviewScene.effectFrame.width)
        XCTAssertEqual(image.height, EditorPreviewScene.effectFrame.height)
    }

    func testAnEffectsPreviewIsRendered() async throws {
        let assets = try Fixtures.assets()
        let file = try XCTUnwrap(EffectCatalog.builtInEffectFiles(in: assets).first { $0 == "effects/tint/effect.json" }
                                    ?? EffectCatalog.builtInEffectFiles(in: assets).first)
        let subject = EditorPreviewSubject.effect(file: file, wallpaper: nil)
        let cache = EditorPreviewCache(cachesDirectory: scratch, build: EditorPreviewCache.assetsBuild(of: assets))
        let url = try await EditorPreviewRenderer(scratch: scratch.appending(path: "work"))
            .render(subject, outputBase: cache.outputBase(for: subject))
        XCTAssertEqual(cache.cachedPreview(for: subject), url, "the cache finds what the renderer wrote")
        let picture: CGImage?
        if url.pathExtension == EditorPreviewCache.stillExtension {
            picture = image(at: url)
        } else {
            picture = try await firstFrame(of: url)
        }
        let frame = try XCTUnwrap(picture)
        XCTAssertEqual(frame.width, EditorPreviewScene.effectFrame.pixelWidth)
        XCTAssertEqual(frame.height, EditorPreviewScene.effectFrame.pixelHeight)
        XCTAssertGreaterThan(try colourSpread(frame), 0.1, "the test card shows through the effect")
    }

    func testAParticlePresetsPreviewIsALoop() async throws {
        let assets = try Fixtures.assets()
        let catalog = ParticleCatalog.load(assetsDirectory: assets, translate: { _ in nil })
        guard let item = catalog.items.first(where: { if case .preset = $0.source { return true }; return false }) else {
            throw XCTSkip("the assets have no particle presets")
        }
        let cache = EditorPreviewCache(cachesDirectory: scratch, build: EditorPreviewCache.assetsBuild(of: assets))
        let url = try await EditorPreviewRenderer(scratch: scratch.appending(path: "work"))
            .render(item.previewSubject, outputBase: cache.outputBase(for: item.previewSubject))
        XCTAssertEqual(url.pathExtension, EditorPreviewCache.movieExtension)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, Double(EditorPreviewRenderer.particleFrames) / Double(EditorPreviewRenderer.particleFrameRate),
                       accuracy: 0.1)
        let decoded = try await firstFrame(of: url)
        let frame = try XCTUnwrap(decoded)
        XCTAssertEqual(frame.width, EditorPreviewScene.particleFrame.pixelWidth)
    }

    // MARK: Helpers

    private func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func firstFrame(of url: URL) async throws -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: .zero).image
    }

    /// The largest difference between the image's darkest and brightest channel values, 0…1.
    private func colourSpread(_ image: CGImage) throws -> Double {
        let width = 32, height = 20
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        let channels = pixels.enumerated().filter { $0.offset % 4 != 3 }.map(\.element)
        return Double((channels.max() ?? 0) - (channels.min() ?? 0)) / 255
    }
}
