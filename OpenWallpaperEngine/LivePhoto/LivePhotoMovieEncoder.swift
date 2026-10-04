import AVFoundation
import CoreGraphics

/// A Live Photo's movie from the clip's frames: HEVC at the quality's bitrate for the device's
/// pixels, tagged Rec. 709 (the frames are rendered and drawn as sRGB, standard-range video's
/// tags), carrying the content identifier the still carries and the still-image-time track at the
/// key frame, so iOS shows exactly the still's frame when the motion isn't playing. The first and
/// last frames blend from and into the still over the screen saver's crossfade
/// (`ScreenSaverSeamFinder.crossfadeWeight`, run from both ends), so neither the start of the
/// motion nor its settling back on the still jumps.
enum LivePhotoMovieEncoder {
    enum Failure: Error { case writer, frame, finish }

    static let colorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ]

    /// Frames each blend spans: the screen saver's crossfade, at most a quarter of the clip.
    static func fadeFrames(frameCount: Int, frameRate: Int) -> Int {
        max(0, min(Int((ScreenSaverSeamFinder.crossfadeSeconds * Double(frameRate)).rounded()), frameCount / 4))
    }

    /// The still's weight over frame `index`: just under 1 on the first frame, falling to 0 after
    /// `fade` frames, and rising again over the last `fade` frames.
    static func stillWeight(index: Int, frameCount: Int, fade: Int) -> Double {
        let end = ScreenSaverSeamFinder.crossfadeWeight(index: index, loopFrames: frameCount, fade: fade)
        let start = ScreenSaverSeamFinder.crossfadeWeight(index: frameCount - 1 - index, loopFrames: frameCount, fade: fade)
        return max(start, end)
    }

    /// The movie time of frame `index`.
    static func time(ofFrame index: Int, frameRate: Int) -> CMTime {
        CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
    }

    /// Writes the movie of the `frameCount` frames `frame` gives in order, the still marked at
    /// `keyFrame`.
    static func write(to url: URL, pixelSize: SIMD2<Int>, frameRate: Int, frameCount: Int, keyFrame: Int, still: CGImage,
                      identifier: String, bitRate: Int, frame: (Int) throws -> CGImage?) throws {
        var stillAdaptor: AVAssetWriterInputMetadataAdaptor?
        guard let writer = HEVCWriter(url: url, pixelSize: pixelSize, frameRate: frameRate, bitRate: bitRate,
                                      colorProperties: colorProperties, prepare: { writer in
                                          writer.metadata = [LivePhotoMetadata.contentIdentifierItem(identifier)]
                                          stillAdaptor = try LivePhotoMetadata.addStillImageTimeInput(to: writer)
                                      }) else { throw Failure.writer }
        guard let stillAdaptor else {
            writer.cancel()
            throw Failure.writer
        }
        // The still's moment is known up front: written first, its track is done before the frames.
        let keyTime = time(ofFrame: keyFrame, frameRate: frameRate)
        guard stillAdaptor.append(LivePhotoMetadata.stillImageTimeGroup(at: keyTime, frameRate: frameRate)) else {
            writer.cancel()
            throw Failure.writer
        }
        stillAdaptor.assetWriterInput.markAsFinished()
        let fade = fadeFrames(frameCount: frameCount, frameRate: frameRate)
        do {
            for index in 0..<frameCount {
                guard let image = try frame(index) else { throw Failure.frame }
                let weight = stillWeight(index: index, frameCount: frameCount, fade: fade)
                guard writer.append(image, overlay: weight > 0 ? still : nil, weight: weight, frame: index) else {
                    throw Failure.frame
                }
            }
        } catch {
            writer.cancel()
            throw error
        }
        guard writer.finish() else { throw Failure.finish }
    }
}
