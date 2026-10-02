import Foundation

/// How long the screen saver's loop video of a scene is, when the scene's motion has known
/// periods: its timelines (`length / fps`, twice that when mirrored) and its sprite sheets (the
/// sum of their frame times). The loop is the least common multiple of the periods, so every one
/// of them is back at its start on the loop's last frame + 1, which is frame 0.
///
/// Periods are exact fractions of a second (a timeline's frame count over its fps), so the least
/// common multiple is exact too; a loop is only taken when it is a whole number of video frames
/// and no longer than `maximumSeconds`. Anything else (particles, scripts, a random or one-shot
/// timeline) has no known period, and the loop is found by looking instead (`ScreenSaverSeamFinder`).
enum ScreenSaverLoopLength {
    /// The longest periodic loop rendered.
    static let maximumSeconds = 60.0
    /// The video frame rates tried, preferred first.
    static let frameRates = [30, 60, 24, 25]

    /// A non-negative fraction, reduced.
    struct Period: Equatable, Hashable {
        let numerator: Int
        let denominator: Int

        init?(numerator: Int, denominator: Int) {
            guard numerator > 0, denominator > 0 else { return nil }
            let divisor = gcd(numerator, denominator)
            self.numerator = numerator / divisor
            self.denominator = denominator / divisor
        }

        /// A timeline of `length` frames at `fps` (WE stores fps as a float; it is rounded to
        /// 1/1000, which every authored fps is). Mirrored timelines go there and back.
        init?(timelineLength length: Int32, fps: Float, mirrored: Bool) {
            guard fps.isFinite, fps > 0 else { return nil }
            let milliFPS = Int((Double(fps) * 1000).rounded())
            self.init(numerator: Int(length) * 1000 * (mirrored ? 2 : 1), denominator: milliFPS)
        }

        /// A sprite sheet's frame times, in seconds, rounded to the millisecond.
        init?(frameTimes: [Float]) {
            let milliseconds = frameTimes.reduce(0) { $0 + Int((Double($1) * 1000).rounded()) }
            self.init(numerator: milliseconds, denominator: 1000)
        }

        var seconds: Double { Double(numerator) / Double(denominator) }
    }

    struct Loop: Equatable {
        var frames: Int
        var frameRate: Int
        var seconds: Double { Double(frames) / Double(frameRate) }
    }

    /// The least common multiple of `periods`; nil when there are none or it overflows.
    static func leastCommonMultiple(_ periods: [Period]) -> Period? {
        guard var result = periods.first else { return nil }
        for period in periods.dropFirst() {
            // lcm(a/b, c/d) = lcm(a, c) / gcd(b, d) for reduced fractions.
            let (product, overflow) = (result.numerator / gcd(result.numerator, period.numerator))
                .multipliedReportingOverflow(by: period.numerator)
            guard !overflow, let next = Period(numerator: product,
                                               denominator: gcd(result.denominator, period.denominator)) else { return nil }
            result = next
        }
        return result
    }

    /// The loop for `periods`: their least common multiple as a whole number of frames at the
    /// first of `frameRates` that makes it one, or nil when there is no period, the multiple is
    /// longer than `maximumSeconds`, or no frame rate cuts it exactly.
    static func periodicLoop(_ periods: [Period], maximumSeconds: Double = maximumSeconds,
                             frameRates: [Int] = frameRates) -> Loop? {
        guard let period = leastCommonMultiple(Array(Set(periods))), period.seconds <= maximumSeconds + 1e-9 else {
            return nil
        }
        for rate in frameRates where (period.numerator * rate) % period.denominator == 0 {
            return Loop(frames: period.numerator * rate / period.denominator, frameRate: rate)
        }
        return nil
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (abs(a), abs(b))
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }
}
