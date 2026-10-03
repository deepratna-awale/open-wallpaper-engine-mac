import Foundation

/// A music-like spectrum for loop recordings (screen saver videos), so audio-reactive wallpapers
/// show what they look like with music instead of fading out in silence. It is a pure function of
/// time: no randomness, the same frame for the same `t` on every run, and the whole pattern
/// repeats exactly every `periodSeconds`, so a recording's audio-driven motion can loop.
///
/// The pattern is a 4/4 bar at 120 BPM (2 s), four bars to a phrase (8 s): a kick on beats 1 and 3
/// (low bands), a snare on 2 and 4 (mids), hi-hats on the eighths (highs, quiet) and a pad across
/// the mids that changes chord every bar. Levels peak around 0.85, like WE's normalised capture
/// during loud music, so nothing pins at 1. Live playback never uses it.
enum SyntheticAudioSpectrum {
    /// Bands per channel, as WE's capture (`AudioSpectrumBlockTransform.bandCount`).
    static let bandCount = 64
    static let beatSeconds = 0.5
    /// A 4-beat bar at 120 BPM.
    static let barSeconds = 2.0
    /// The whole pattern: four bars.
    static let periodSeconds = 8.0
    /// The pattern's period as a loop period.
    static let period = ScreenSaverLoopLength.Period(numerator: 8, denominator: 1)!

    /// The 128 values WE hands web pages (64 left, then 64 right) at `t` seconds.
    static func raw(at t: Double) -> [Float] {
        // Work in whole milliseconds of the phrase, so t and t + 8 s give the same bits.
        let phrase = Int(periodSeconds * 1000)
        let milliseconds = ((Int((t * 1000).rounded()) % phrase) + phrase) % phrase
        let local = Double(milliseconds) / 1000
        let beat = Int(local / beatSeconds)               // 0…15
        let sinceBeat = local - Double(beat) * beatSeconds
        let eighth = Int(local / (beatSeconds / 2))       // 0…31
        let sinceEighth = local - Double(eighth) * (beatSeconds / 2)
        let bar = beat / 4
        let beatInBar = beat % 4                          // 0 = beat 1

        let kick = beatInBar % 2 == 0 ? envelope(sinceBeat, attack: 0.005, decay: 0.2) : 0
        let snare = beatInBar % 2 == 1 ? envelope(sinceBeat, attack: 0.005, decay: 0.15) : 0
        let hat = envelope(sinceEighth, attack: 0.002, decay: 0.06) * (eighth % 2 == 1 ? 1 : 0.7)
        // The pad's chord: one centre band per bar, swelling over the bar.
        let padCentre = [20.0, 24.0, 18.0, 27.0][bar]
        let padSwell = 0.75 + 0.25 * sin(Double.pi * (local - Double(bar) * barSeconds) / barSeconds)

        var values = [Float](repeating: 0, count: 2 * bandCount)
        for channel in 0..<2 {
            // Right is a touch softer on the kick and brighter on the hats, as a stereo mix is.
            let tilt = channel == 0 ? 1.0 : 0.92
            let brighten = channel == 0 ? 1.0 : 1.1
            for band in 0..<bandCount {
                let b = Double(band)
                var level = 0.0
                level += 0.85 * tilt * kick * bump(b, centre: 2, width: 3)
                level += 0.6 * (2 - tilt) * snare * bump(b, centre: 22, width: 9)
                level += 0.32 * brighten * hat * bump(b, centre: 52, width: 8)
                level += 0.22 * padSwell * bump(b, centre: padCentre + Double(channel), width: 6)
                level += 0.05 * bump(b, centre: 10, width: 20) // a quiet floor: music never reads as silence
                values[channel * bandCount + band] = Float(min(level, 0.95))
            }
        }
        return values
    }

    /// The scene arrays (`g_AudioSpectrum*`, SceneScript buffers) at `t` seconds.
    static func snapshot(at t: Double) -> AudioSpectrumSnapshot {
        AudioSpectrumSmoothing.snapshot(raw(at: t))
    }

    /// A hit: rises over `attack`, then falls exponentially with time constant `decay`.
    private static func envelope(_ since: Double, attack: Double, decay: Double) -> Double {
        since < attack ? since / attack : exp(-(since - attack) / decay)
    }

    private static func bump(_ band: Double, centre: Double, width: Double) -> Double {
        let x = (band - centre) / width
        return exp(-x * x)
    }
}

/// A recording's virtual time, in seconds from its frame 0, which `SyntheticAudioSpectrum` follows.
final class SyntheticAudioClock: @unchecked Sendable {
    var seconds = 0.0
}
