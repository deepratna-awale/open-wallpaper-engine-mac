import AVFoundation
import CoreGraphics
import XCTest
@testable import OpenWallpaperEngine

final class LivePhotoTests: XCTestCase {
    private let landscape = SIMD2<Double>(1920, 1080)

    // MARK: Crop and scale

    func testDefaultDeviceIsTheLargest() {
        XCTAssertEqual(IPhoneModel.largest, .proMax)
        XCTAssertEqual(IPhoneModel.proMax.pixelSize, SIMD2(1320, 2868))
        XCTAssertEqual(IPhoneModel.pro.pixelSize, SIMD2(1206, 2622))
        XCTAssertEqual(IPhoneModel.standard.pixelSize, SIMD2(1179, 2556))
    }

    func testCoverFitIsTheTallestPortraitWindowInALandscapeScene() {
        let crop = LivePhotoCrop(sceneSize: landscape, outputPixels: IPhoneModel.proMax.pixelSize)
        XCTAssertEqual(crop.coverSize.y, 1080, accuracy: 1e-9)
        XCTAssertEqual(crop.coverSize.x, 1080 * 1320 / 2868, accuracy: 1e-9)
        XCTAssertEqual(crop.cropRect.midX, 960, accuracy: 1e-9)
        XCTAssertEqual(crop.cropRect.minY, 0, accuracy: 1e-9)
    }

    func testCoverFitInAPortraitSceneUsesItsWidth() {
        let crop = LivePhotoCrop(sceneSize: SIMD2(1000, 4000), outputPixels: IPhoneModel.proMax.pixelSize)
        XCTAssertEqual(crop.coverSize.x, 1000, accuracy: 1e-9)
        XCTAssertEqual(crop.coverSize.y, 1000 * 2868 / 1320, accuracy: 1e-9)
    }

    func testPanIsClampedInsideTheScene() {
        var crop = LivePhotoCrop(sceneSize: landscape, outputPixels: IPhoneModel.proMax.pixelSize)
        crop.pan(by: SIMD2(-10_000, -10_000))
        XCTAssertEqual(crop.cropRect.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(crop.cropRect.minY, 0, accuracy: 1e-9)
        crop.pan(by: SIMD2(10_000, 10_000))
        XCTAssertEqual(crop.cropRect.maxX, 1920, accuracy: 1e-9)
        XCTAssertEqual(crop.cropRect.maxY, 1080, accuracy: 1e-9)
    }

    func testZoomIsClampedAndShrinksTheWindow() {
        var crop = LivePhotoCrop(sceneSize: landscape, outputPixels: IPhoneModel.proMax.pixelSize)
        crop.setZoom(0.2)
        XCTAssertEqual(crop.zoom, 1)
        crop.setZoom(10)
        XCTAssertEqual(crop.zoom, LivePhotoCrop.maximumZoom)
        XCTAssertEqual(crop.cropSize.y, 360, accuracy: 1e-9)
        // Zooming at an edge keeps the window inside.
        crop.setZoom(1)
        crop.pan(by: SIMD2(10_000, 0))
        crop.setZoom(2)
        XCTAssertLessThanOrEqual(crop.cropRect.maxX, 1920 + 1e-9)
    }

    func testRenderScaleIsNeverBelowAuthoredNorThePhonesPixels() {
        for device in IPhoneModel.allCases {
            for zoom in [1.0, 1.5, 2, 3] {
                let crop = LivePhotoCrop(sceneSize: landscape, outputPixels: device.pixelSize, zoom: zoom)
                XCTAssertGreaterThanOrEqual(crop.renderScale, 1)
                let rect = crop.renderCropRect
                XCTAssertGreaterThanOrEqual(Double(rect.height) + 1, Double(device.pixelSize.y), "\(device) \(zoom)")
                XCTAssertGreaterThanOrEqual(Double(rect.width) + 1, Double(device.pixelSize.x), "\(device) \(zoom)")
            }
        }
        // A scene far larger than the phone renders at its authored size.
        let large = LivePhotoCrop(sceneSize: SIMD2(7680, 4320), outputPixels: IPhoneModel.proMax.pixelSize)
        XCTAssertEqual(large.renderScale, 1)
        XCTAssertEqual(large.renderPixelSize, SIMD2(7680, 4320))
    }

    func testOutputIsExactlyTheDevicesPixels() throws {
        let crop = LivePhotoCrop(sceneSize: SIMD2(64, 36), outputPixels: SIMD2(33, 71), zoom: 2)
        let size = crop.renderPixelSize
        let context = try XCTUnwrap(CGContext(data: nil, width: size.x, height: size.y, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.x, height: size.y))
        let frame = try XCTUnwrap(context.makeImage())
        let output = try XCTUnwrap(crop.outputImage(from: frame))
        XCTAssertEqual(output.width, 33)
        XCTAssertEqual(output.height, 71)
    }

    // MARK: Clip

    func testClipStartIsClampedAndTheStillIsTheMiddleFrame() {
        var clip = LivePhotoClip(start: -4)
        XCTAssertEqual(clip.start, 0)
        clip.setStart(1_000)
        XCTAssertEqual(clip.start, LivePhotoClip.timelineLength - LivePhotoClip.duration)
        XCTAssertEqual(clip.end, LivePhotoClip.timelineLength)
        clip.setStart(.nan)
        XCTAssertEqual(clip.start, 0)
        clip.setStart(2)
        XCTAssertEqual(clip.frameCount, 90)
        XCTAssertEqual(clip.leadInFrames, 60)
        XCTAssertEqual(clip.keyFrameIndex, 45)
        XCTAssertEqual(clip.keyFrameSeconds, 1.5, accuracy: 1e-9)
    }

    // MARK: Render policy

    func testExportHidesClockLayersIsMutedAndRendersAtFullDetail() {
        XCTAssertTrue(LivePhotoRenderer.Policy.hidesClockLayers)
        XCTAssertTrue(LivePhotoRenderer.Policy.muted)
        var settings = GlobalSettings()
        settings.sceneDetail = .matchDisplay
        settings.upscaling = GSUpscaling.allCases.last ?? .off
        settings.renderResolution = .display
        let render = LivePhotoRenderer.renderSettings(from: settings)
        XCTAssertEqual(render.sceneDetail, .full)
        XCTAssertEqual(render.upscaling, .off)
        XCTAssertEqual(render.textureReduction, 1)
        XCTAssertEqual(render.drawnScale, 1)
    }

    func testClockTextLayersAreFound() throws {
        let json = """
        {"objects":[{"id":3,"text":{"script":"export function update(){ return new Date().getHours(); }"}},
                    {"id":4,"text":{"script":"export function update(){ return 'hi'; }"}}]}
        """
        let document = try JSONDecoder().decode(SceneJSON.self, from: Data(json.utf8))
        XCTAssertEqual(SceneClockLayers.ids(in: document), ["3"])
    }

    // MARK: Pairing metadata

    func testStillAndMovieArePairedWithAStillImageTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "livephoto-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = UUID().uuidString
        let size = SIMD2(64, 128)
        let image = try Self.solidImage(size)

        let still = directory.appending(path: "test.HEIC")
        try LivePhotoMetadata.writeStill(image, to: still, identifier: identifier)
        XCTAssertEqual(LivePhotoMetadata.stillIdentifier(at: still), identifier)

        let movie = directory.appending(path: "test.MOV")
        var adaptor: AVAssetWriterInputMetadataAdaptor?
        let writer = try XCTUnwrap(HEVCWriter(url: movie, pixelSize: size, frameRate: 30) { writer in
            writer.metadata = [LivePhotoMetadata.contentIdentifierItem(identifier)]
            adaptor = try LivePhotoMetadata.addStillImageTimeInput(to: writer)
        })
        let stillTime = CMTime(value: 4, timescale: 30)
        XCTAssertTrue(try XCTUnwrap(adaptor).append(LivePhotoMetadata.stillImageTimeGroup(at: stillTime, frameRate: 30)))
        adaptor?.assetWriterInput.markAsFinished()
        for frame in 0..<9 {
            XCTAssertTrue(writer.append(image, overlay: nil, weight: 0, frame: frame))
        }
        XCTAssertTrue(writer.finish())

        let movieIdentifier = try await LivePhotoMetadata.movieIdentifier(at: movie)
        XCTAssertEqual(movieIdentifier, identifier)
        let time = try await LivePhotoMetadata.movieStillImageTime(at: movie)
        XCTAssertEqual(time.map(CMTimeGetSeconds) ?? -1, CMTimeGetSeconds(stillTime), accuracy: 1e-6)
    }

    private static func solidImage(_ size: SIMD2<Int>) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: size.x, height: size.y, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                  | CGBitmapInfo.byteOrder32Little.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.x, height: size.y))
        return try XCTUnwrap(context.makeImage())
    }
}
