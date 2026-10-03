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
        /// The recorded frame the loop starts on (`searchActiveSeam`; 0 for `decide`).
        var start: Int = 0
        /// The seam's score in dB (`seamScore`), when measured (`searchActiveSeam`).
        var score: Double?
    }

    /// The best loop length for `differences` (`differences[i]` compares frame `i` with frame
    /// 0) at `frameRate`: the index after `minimumSeconds` with the least difference (the
    /// earliest on a tie). Nil when no frame is late enough.
    ///
    /// With an `alignment` (seconds, e.g. the synthetic audio's bar), the best candidate on a
    /// multiple of it wins when it is nearly as good (`alignedTolerance`), so audio-driven motion
    /// lines up at the seam too.
    static func bestFrame(differences: [Double], frameRate: Int, minimumSeconds: Double = minimumSeconds,
                          alignment: Double? = nil) -> Int? {
        let first = max(Int((minimumSeconds * Double(frameRate)).rounded(.up)), 1)
        guard first < differences.count else { return nil }
        var best = first
        for index in first..<differences.count where differences[index] < differences[best] { best = index }
        guard let alignment, alignment > 0 else { return best }
        let step = Double(frameRate) * alignment
        var bestAligned: Int?
        var bar = 1
        while true {
            let index = Int((Double(bar) * step).rounded())
            guard index < differences.count else { break }
            if index >= first, bestAligned.map({ differences[index] < differences[$0] }) ?? true { bestAligned = index }
            bar += 1
        }
        guard let bestAligned else { return best }
        let good = differences[bestAligned] <= invisibleDifference
            || differences[bestAligned] <= differences[best] * alignedTolerance
        return good ? bestAligned : best
    }

    /// How much worse than the overall best match an aligned one may be and still be preferred.
    static let alignedTolerance = 1.25

    /// Whether the seam at a frame `difference` from frame 0 needs a crossfade, and how long.
    static func seam(difference: Double, frameRate: Int, loopFrames: Int) -> Seam {
        guard difference > invisibleDifference else { return .cut }
        let frames = min(max(Int((crossfadeSeconds * Double(frameRate)).rounded()), 1), loopFrames / 2)
        return frames > 0 ? .crossfade(frames: frames) : .cut
    }

    static func decide(differences: [Double], frameRate: Int, minimumSeconds: Double = minimumSeconds,
                       alignment: Double? = nil) -> Decision? {
        guard let best = bestFrame(differences: differences, frameRate: frameRate, minimumSeconds: minimumSeconds,
                                   alignment: alignment) else {
            return nil
        }
        return Decision(frames: best, seam: seam(difference: differences[best], frameRate: frameRate, loopFrames: best))
    }

    /// The weight of the scene's frame `index - (loopFrames - fade)` (one of the first `fade`
    /// frames, which the video skips) blended over the video's frame `index` of a loop of
    /// `loopFrames` frames fading over `fade`: 0 before the fade, rising to just under 1 on the
    /// last frame, so the next frame (the scene's frame `fade`, the video's first) completes it.
    static func crossfadeWeight(index: Int, loopFrames: Int, fade: Int) -> Double {
        let start = loopFrames - fade
        guard fade > 0, index >= start, index < loopFrames else { return 0 }
        return Double(index - start + 1) / Double(fade + 1)
    }
}

// MARK: Active segment and seam search (web pages)

/// A page can't be replayed, and may stop moving or fade to black after an intro: looping such a
/// recording from frame 0 to its best match after 5 s matches a dead tail and jumps back to the
/// motion. So a recording is searched as follows:
///
/// 1. **Active segment.** Each frame's activity is the mean absolute luma difference from the
///    frame before (on `ScreenSaverFrameSignature.searchLuma`, 32×18). A frame is dead when its
///    activity is under `staticActivity` or it is blank (`isBlank`: almost all near black, or flat).
///    Dead runs longer than `maximumDeadSeconds` split the recording; the longest live part is the
///    active segment. A recording that never moves but isn't blank is one (still) segment.
/// 2. **Seam pair.** Every start `a` in the segment's first `startSearchSeconds` and end `b` at
///    least `minimumSeconds` later, still in the segment, with similar activity at both ends
///    (`similarActivity`), is scored by the PSNR of frame `b` against frame `a`; the loop is frames
///    `a..<b`. A pair at or above `minimumSeamScore` cuts. Otherwise the seam is crossfaded over
///    `F` frames (at least `crossfadeSeconds`, at most `maximumCrossfadeSeconds`), which spreads
///    the jump over `F + 1` steps: the score becomes `PSNR + 20·log10(F + 1)`, and `F` is the least
///    that reaches the minimum. The pair with the least difference whose seam fits wins.
/// 3. **Nothing passes:** nil, and the page is reported as not looping smoothly rather than
///    shipping a jumping loop. (A ping-pong loop isn't tried: the intermediate video is read
///    forward only, and reversed motion reads as wrong on most pages.)
extension ScreenSaverSeamFinder {
    /// The seam score a loop must reach, in dB (PSNR of luma, 0…1, on `searchLuma`). 50 dB is a
    /// root-mean-square step of 0.3 % of full scale, under one 8-bit level: an invisible seam.
    static let minimumSeamScore = 50.0
    static let maximumCrossfadeSeconds = 1.0
    /// Activity (mean absolute luma difference per frame) under this is a still frame: about an
    /// eighth of one 8-bit level on average.
    static let staticActivity = 0.0005
    /// Dead (still or blank) runs longer than this are cut out of the loop.
    static let maximumDeadSeconds = 1.0
    /// How far into the active segment the loop's start is searched.
    static let startSearchSeconds = 2.0
    /// Near black: luma under this.
    static let darkLuma: Float = 0.04
    /// Blank: at least this fraction near black, or a luma standard deviation under `flatDeviation`.
    static let blankFraction = 0.98
    static let flatDeviation = 0.004

    static func meanSquaredError(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total: Double = 0
        for index in a.indices {
            let delta = Double(a[index] - b[index])
            total += delta * delta
        }
        return total / Double(a.count)
    }

    /// PSNR in dB of two luma frames (0…1); infinity when they are equal.
    static func psnr(_ a: [Float], _ b: [Float]) -> Double {
        let error = meanSquaredError(a, b)
        return error > 0 ? 10 * log10(1 / error) : .infinity
    }

    static func meanAbsoluteDifference(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total: Double = 0
        for index in a.indices { total += Double(abs(a[index] - b[index])) }
        return total / Double(a.count)
    }

    /// Whether a luma frame is black or flat.
    static func isBlank(_ luma: [Float]) -> Bool {
        guard !luma.isEmpty else { return true }
        let count = Double(luma.count)
        let dark = Double(luma.reduce(0) { $0 + ($1 < darkLuma ? 1 : 0) })
        if dark / count >= blankFraction { return true }
        let mean = luma.reduce(0) { $0 + Double($1) } / count
        let variance = luma.reduce(0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / count
        return variance.squareRoot() < flatDeviation
    }

    /// `activity[i]`: frame `i` against frame `i - 1` (frame 0 takes frame 1's).
    static func activity(_ frames: [[Float]]) -> [Double] {
        guard frames.count > 1 else { return frames.map { _ in 0 } }
        var result = [Double](repeating: 0, count: frames.count)
        for index in 1..<frames.count { result[index] = meanAbsoluteDifference(frames[index], frames[index - 1]) }
        result[0] = result[1]
        return result
    }

    /// The active segment's frames (see above), or nil when every frame is blank.
    static func activeSegment(activity: [Double], blank: [Bool], frameRate: Int,
                              maximumDeadSeconds: Double = maximumDeadSeconds) -> Range<Int>? {
        let count = min(activity.count, blank.count)
        guard count > 0 else { return nil }
        let dead = (0..<count).map { blank[$0] || activity[$0] < staticActivity }
        if !dead.contains(false) {
            // Never moves: a still page loops anywhere; a blank one has nothing to show.
            return blank.prefix(count).contains(false) ? 0..<count : nil
        }
        let longestDead = max(Int((maximumDeadSeconds * Double(frameRate)).rounded()), 1)
        var best: Range<Int>?
        var segmentStart: Int?
        var lastLive = -1
        func close() {
            guard let start = segmentStart else { return }
            let end = lastLive + 1
            if best.map({ end - start > $0.count }) ?? true { best = start..<end }
            segmentStart = nil
        }
        for index in 0..<count {
            if dead[index] {
                if segmentStart != nil, index - lastLive > longestDead { close() }
            } else {
                if segmentStart == nil { segmentStart = index }
                lastLive = index
            }
        }
        close()
        return best
    }

    /// The score of a seam whose ends differ by `psnr` dB, crossfaded over `fade` frames.
    static func seamScore(psnr: Double, fade: Int) -> Double {
        psnr + 20 * log10(Double(max(fade, 0) + 1))
    }

    /// Whether two activities are alike: within a factor of 2, or both still.
    static func similarActivity(_ a: Double, _ b: Double) -> Bool {
        max(a, b) <= 2 * min(a, b) + staticActivity
    }

    /// The best seam in `frames` (one `searchLuma` per recorded frame), or nil when the page has
    /// no active segment long enough or no seam reaches `minimumSeamScore`.
    static func searchActiveSeam(frames: [[Float]], frameRate: Int, minimumSeconds: Double = minimumSeconds,
                                 maximumSeconds: Double = maximumSeconds, alignment: Double? = nil) -> Decision? {
        let activity = activity(frames)
        guard !activity.isEmpty,
              let segment = activeSegment(activity: activity, blank: frames.map(isBlank), frameRate: frameRate) else {
            return nil
        }
        // Activity around a frame, so one quiet frame doesn't decide whether the ends match.
        let smoothed: [Double] = activity.indices.map { index in
            let window = activity[max(index - 2, 0)...min(index + 2, activity.count - 1)]
            return window.reduce(0, +) / Double(window.count)
        }
        let minimumFrames = max(Int((minimumSeconds * Double(frameRate)).rounded(.up)), 1)
        let maximumFrames = max(Int(maximumSeconds * Double(frameRate)), minimumFrames)
        let baseFade = max(Int((crossfadeSeconds * Double(frameRate)).rounded()), 1)
        let longestFade = max(Int((maximumCrossfadeSeconds * Double(frameRate)).rounded()), baseFade)
        let lastStart = min(segment.lowerBound + Int(startSearchSeconds * Double(frameRate)), segment.upperBound - 1)
        // With an `alignment` (seconds, e.g. the synthetic audio's bar), the best loop whose length
        // is a whole number of it wins when nearly as good (`alignedTolerance`), so audio-driven
        // motion lines up at the seam too.
        let step = alignment.map { Double(frameRate) * $0 } ?? 0
        func isAligned(_ frames: Int) -> Bool {
            guard step >= 1 else { return false }
            return abs(Double(frames) - (Double(frames) / step).rounded() * step) < 0.5
        }
        var best: (error: Double, decision: Decision)?
        var bestAligned: (error: Double, decision: Decision)?
        func consider(_ error: Double, _ decision: Decision) {
            if best.map({ error < $0.error }) ?? true { best = (error, decision) }
            if isAligned(decision.frames), bestAligned.map({ error < $0.error }) ?? true {
                bestAligned = (error, decision)
            }
        }
        for a in segment.lowerBound...lastStart {
            let firstEnd = a + minimumFrames
            let lastEnd = min(a + maximumFrames, segment.upperBound - 1)
            guard firstEnd <= lastEnd else { break }
            for b in firstEnd...lastEnd where similarActivity(smoothed[a], smoothed[b]) {
                let error = meanSquaredError(frames[a], frames[b])
                if let best, error >= best.error, !isAligned(b - a) || (bestAligned.map { error >= $0.error } ?? false) {
                    continue
                }
                let score = error > 0 ? 10 * log10(1 / error) : .infinity
                let loopFrames = b - a
                if score >= minimumSeamScore {
                    consider(error, Decision(frames: loopFrames, seam: .cut, start: a, score: score))
                    continue
                }
                // The least fade that reaches the minimum: 20·log10(F + 1) ≥ minimum − score.
                let needed = Int((pow(10, (minimumSeamScore - score) / 20) - 1).rounded(.up))
                let fade = max(needed, baseFade)
                // The fade blends the frames after the loop's last one: they must be live too.
                guard fade <= longestFade, fade <= loopFrames / 2, b + fade <= segment.upperBound else { continue }
                consider(error, Decision(frames: loopFrames, seam: .crossfade(frames: fade), start: a,
                                         score: seamScore(psnr: score, fade: fade)))
            }
        }
        if let bestAligned, let best, bestAligned.error <= best.error * alignedTolerance { return bestAligned.decision }
        return best?.decision
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

    /// The luma at half size (32×18, 2×2 averaged): the frame `ScreenSaverSeamFinder.searchActiveSeam` compares.
    var searchLuma: [Float] {
        let (width, height) = (Self.width, Self.height)
        guard values.count == width * height * 3 else { return [] }
        var result = [Float]()
        result.reserveCapacity(width * height / 4)
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let sum = values[(y * width + x) * 3] + values[(y * width + x + 1) * 3]
                    + values[((y + 1) * width + x) * 3] + values[((y + 1) * width + x + 1) * 3]
                result.append(sum / 4)
            }
        }
        return result
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
