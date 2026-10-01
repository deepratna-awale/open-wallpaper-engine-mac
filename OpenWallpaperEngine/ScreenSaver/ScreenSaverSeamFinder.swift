import CoreGraphics
import Foundation

/// Finds where a scene without known periods loops: the scene is rendered up to `maximumSeconds`,
/// each frame is compared with frame 0 by `ScreenSaverFrameSignature`, and the loop ends just
/// before the frame most like frame 0 after `minimumSeconds` (so the video doesn't loop on the
/// first second, which always looks like frame 0). When even that frame differs visibly, the last
/// `crossfadeFrames` frames are blended into frames 0… so the seam fades instead of jumping.
enum ScreenSaverSeamFinder {
    static let minimumSeconds = 5.0
    static let maximumSeconds = 60.0
    /// A difference (`ScreenSaverFrameSignature.difference`, 0…1) at or below this is invisible.
    static let invisibleDifference = 0.012
    static let crossfadeSeconds = 0.25

    enum Seam: Equatable {
        /// The loop ends cleanly: frame `frames` would equal frame 0.
        case cut
        /// Blend the last `frames` frames into the loop's first ones.
        case crossfade(frames: Int)
    }

    struct Decision: Equatable {
        /// Frames in the loop (the best match is the frame after the last).
        var frames: Int
        var seam: Seam
    }

    /// The best loop length for `differences` (`differences[i]` compares frame `i` with frame
    /// 0) at `frameRate`: the index after `minimumSeconds` with the least difference (the
    /// earliest on a tie). Nil when no frame is late enough.
    static func bestFrame(differences: [Double], frameRate: Int, minimumSeconds: Double = minimumSeconds) -> Int? {
        let first = max(Int((minimumSeconds * Double(frameRate)).rounded(.up)), 1)
        guard first < differences.count else { return nil }
        var best = first
        for index in first..<differences.count where differences[index] < differences[best] { best = index }
        return best
    }

    /// Whether the seam at a frame `difference` from frame 0 needs a crossfade, and how long.
    static func seam(difference: Double, frameRate: Int, loopFrames: Int) -> Seam {
        guard difference > invisibleDifference else { return .cut }
        let frames = min(max(Int((crossfadeSeconds * Double(frameRate)).rounded()), 1), loopFrames / 2)
        return frames > 0 ? .crossfade(frames: frames) : .cut
    }

    static func decide(differences: [Double], frameRate: Int, minimumSeconds: Double = minimumSeconds) -> Decision? {
        guard let best = bestFrame(differences: differences, frameRate: frameRate, minimumSeconds: minimumSeconds) else {
            return nil
        }
        return Decision(frames: best, seam: seam(difference: differences[best], frameRate: frameRate, loopFrames: best))
    }

    /// The weight of frame `index - (loopFrames - fade)` (one of the first frames) blended over
    /// frame `index` of a loop of `loopFrames` frames fading over `fade`: 0 before the fade, rising
    /// to just under 1 on the last frame, so the next frame (frame 0) completes it.
    static func crossfadeWeight(index: Int, loopFrames: Int, fade: Int) -> Double {
        let start = loopFrames - fade
        guard fade > 0, index >= start, index < loopFrames else { return 0 }
        return Double(index - start + 1) / Double(fade + 1)
    }
}

/// A small perceptual fingerprint of a frame: its luma and chroma at 64×36, blurred by the
/// downscale, so noise and grain don't count and a moved object does.
struct ScreenSaverFrameSignature: Equatable {
    static let width = 64
    static let height = 36
    /// Interleaved Y, Cb, Cr per pixel, 0…1.
    let values: [Float]

    init(values: [Float]) { self.values = values }

    init?(_ image: CGImage) {
        let (width, height) = (Self.width, Self.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var values = [Float]()
        values.reserveCapacity(width * height * 3)
        for pixel in 0..<(width * height) {
            let r = Float(pixels[pixel * 4]) / 255, g = Float(pixels[pixel * 4 + 1]) / 255, b = Float(pixels[pixel * 4 + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            values.append(y)
            values.append((b - y) * 0.5)
            values.append((r - y) * 0.5)
        }
        self.values = values
    }

    /// The mean absolute difference, luma weighted twice chroma: 0 for the same picture, 1 at most.
    func difference(_ other: ScreenSaverFrameSignature) -> Double {
        guard values.count == other.values.count, !values.isEmpty else { return 1 }
        var total: Double = 0
        for index in values.indices {
            let weight: Double = index % 3 == 0 ? 2 : 1
            total += weight * Double(abs(values[index] - other.values[index]))
        }
        return total / (Double(values.count / 3) * 4)
    }
}
