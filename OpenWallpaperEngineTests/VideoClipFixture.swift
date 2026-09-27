import AVFoundation
import CoreVideo
import XCTest

/// A short H.264 clip written on the fly, for tests that need a real movie to play.
enum VideoClipFixture {
    /// `frames` frames at `fps`, 64×64, each a flat grey that brightens frame by frame.
    static func make(frames: Int, fps: Int32 = 30, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var created: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
            let buffer = try XCTUnwrap(created)
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
            let value: Int32 = Int32(index * 255 / max(1, frames - 1))
            memset(base, value, CVPixelBufferGetBytesPerRow(buffer) * 64)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(index), timescale: fps)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: time))
        }
        input.markAsFinished()
        let done = XCTestExpectation(description: "clip written")
        writer.finishWriting { done.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed)
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return url
    }
}
