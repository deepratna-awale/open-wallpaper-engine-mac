import XCTest
@testable import OpenWallpaperEngine

final class SyntheticAudioSpectrumTests: XCTestCase {
    private let left = 0, right = 64
    private let kickBand = 2, snareBand = 22, hatBand = 52

    func testRepeatsExactlyEveryPeriod() {
        for frame in 0..<(8 * 30) {
            let t = Double(frame) / 30
            XCTAssertEqual(SyntheticAudioSpectrum.raw(at: t), SyntheticAudioSpectrum.raw(at: t + 8), "t = \(t)")
            XCTAssertEqual(SyntheticAudioSpectrum.raw(at: t), SyntheticAudioSpectrum.raw(at: t + 40), "t = \(t)")
            XCTAssertEqual(SyntheticAudioSpectrum.snapshot(at: t), SyntheticAudioSpectrum.snapshot(at: t + 8))
        }
    }

    func testDeterministic() {
        for t in stride(from: 0.0, to: 8, by: 0.37) {
            XCTAssertEqual(SyntheticAudioSpectrum.raw(at: t), SyntheticAudioSpectrum.raw(at: t))
        }
    }

    func testFrameFormat() {
        let raw = SyntheticAudioSpectrum.raw(at: 1.234)
        XCTAssertEqual(raw.count, 128)
        XCTAssertTrue(raw.allSatisfy { $0 >= 0 && $0 < 1 })
        let snapshot = SyntheticAudioSpectrum.snapshot(at: 1.234)
        XCTAssertEqual(snapshot.left16.count, 16)
        XCTAssertEqual(snapshot.right64.count, 64)
    }

    func testKickOnBeatsOneAndThree() {
        for beat in [0, 2, 4, 6] {
            let onBeat = SyntheticAudioSpectrum.raw(at: Double(beat) * 0.5 + 0.01)
            let offBeat = SyntheticAudioSpectrum.raw(at: Double(beat) * 0.5 + 0.51)
            XCTAssertGreaterThan(onBeat[left + kickBand], 0.6, "beat \(beat)")
            XCTAssertLessThan(offBeat[left + kickBand], 0.25, "beat \(beat)")
        }
        // ~200 ms decay: well down 400 ms after the hit.
        XCTAssertLessThan(SyntheticAudioSpectrum.raw(at: 0.41)[left + kickBand],
                          0.4 * SyntheticAudioSpectrum.raw(at: 0.01)[left + kickBand])
    }

    func testSnareOnBeatsTwoAndFour() {
        for beat in [1, 3, 5, 7] {
            let onBeat = SyntheticAudioSpectrum.raw(at: Double(beat) * 0.5 + 0.01)
            let before = SyntheticAudioSpectrum.raw(at: Double(beat) * 0.5 - 0.02)
            XCTAssertGreaterThan(onBeat[left + snareBand], before[left + snareBand] + 0.3, "beat \(beat)")
        }
    }

    func testHatsOnEighthsAreQuiet() {
        for eighth in 0..<16 {
            let t = Double(eighth) * 0.25
            let hit = SyntheticAudioSpectrum.raw(at: t + 0.005)[left + hatBand]
            let gap = SyntheticAudioSpectrum.raw(at: t + 0.2)[left + hatBand]
            XCTAssertGreaterThan(hit, gap + 0.1, "eighth \(eighth)")
            XCTAssertLessThan(hit, 0.5, "eighth \(eighth)")
        }
    }

    func testChannelsDiffer() {
        let raw = SyntheticAudioSpectrum.raw(at: 0.01)
        XCTAssertNotEqual(Array(raw[0..<64]), Array(raw[64..<128]))
    }

    func testLoopLengthIncludesThePeriod() {
        let timeline = ScreenSaverLoopLength.Period(numerator: 3, denominator: 1)!
        let periods = ScreenSaverLoopLength.recordingPeriods([timeline], readsAudio: true)
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop(periods)?.seconds, 24)
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop(
            ScreenSaverLoopLength.recordingPeriods([timeline], readsAudio: false))?.seconds, 3)
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop(
            ScreenSaverLoopLength.recordingPeriods([], readsAudio: true))?.seconds, 8)
        // Still capped: 7 s × 8 s = 56 s fits, 9 s × 8 s = 72 s doesn't.
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop(ScreenSaverLoopLength.recordingPeriods(
            [ScreenSaverLoopLength.Period(numerator: 7, denominator: 1)!], readsAudio: true))?.seconds, 56)
        XCTAssertNil(ScreenSaverLoopLength.periodicLoop(ScreenSaverLoopLength.recordingPeriods(
            [ScreenSaverLoopLength.Period(numerator: 9, denominator: 1)!], readsAudio: true)))
    }

    func testSeamPrefersBarBoundary() {
        var differences = [Double](repeating: 0.2, count: 30 * 20)
        differences[0] = 0
        differences[331] = 0.05 // best overall, off the bar
        differences[360] = 0.055 // 12 s, on a bar, nearly as good
        XCTAssertEqual(ScreenSaverSeamFinder.bestFrame(differences: differences, frameRate: 30), 331)
        XCTAssertEqual(ScreenSaverSeamFinder.bestFrame(differences: differences, frameRate: 30, alignment: 2), 360)
        differences[360] = 0.15 // much worse: the best match wins
        XCTAssertEqual(ScreenSaverSeamFinder.bestFrame(differences: differences, frameRate: 30, alignment: 2), 331)
    }
}
