import Foundation

/// A wallpaper's own clock: seconds since its scene loaded, advanced by each frame's wall-clock
/// delta times the playback rate. Changing the rate changes how fast time runs from then on,
/// never where it is, so animations don't jump. Every consumer of scene time (keyframe
/// animations, `g_Time`, particles, scripts, camera shake and parallax) reads this one clock.
///
/// It follows `wallpaper64.exe`'s main loop:
/// 1. The frame's wall time (a stopwatch, 0x1400604d0) is clamped to 0.0001…0.25 s (0x140111355).
/// 2. It is multiplied by the playback rate: the wallpaper's `rate` setting ÷ 100, at least 0.1
///    (0x140114d58…0x140114d98), and clamped to 0.0001…0.25 s again (0x1401114c3…0x14011150f).
/// 3. The scene adds that to a double and keeps a float copy, the time the shaders (`g_Time`),
///    particles and camera shake read. Once the float passes 432 000 s (five days) both go back
///    to 0 (0x14017fcca…0x14017fcf6), so a float's precision never falls below 1/32 s.
///
/// WE also eases the rate to 0 when it pauses a wallpaper and back to 1 when it resumes it, by
/// min(6·dt, 1) of the gap a frame (0x14011137f…0x1401113d7); the app stops drawing instead.
struct SceneClock {
    /// Frames further apart than this (a stall, a sleep) advance the clock by this much only.
    static let maximumFrameDelta = 0.25
    /// The shortest step a frame takes, however close to the last it came.
    static let minimumFrameDelta = 0.0001
    /// The slowest playback rate WE allows.
    static let minimumRate = 0.1
    /// The scene time past which WE starts again from 0.
    static let wrapTime: Float = 432_000

    /// Scene seconds since load (or since the last wrap), rate applied.
    private(set) var time: Double = 0
    /// Scene seconds the last frame advanced by, rate applied.
    private(set) var delta: Double = 0
    private var lastWallTime: Double?

    /// Advances to `wallTime` (e.g. `CACurrentMediaTime()`) at the playback rate `speed`. The first
    /// call only anchors the clock, so the uptime it starts at never reaches the scene time.
    mutating func advance(to wallTime: Double, speed: Double) {
        // A wall time that isn't a number would poison the clock for good; the frame stands still.
        guard wallTime.isFinite else { delta = 0; return }
        defer { lastWallTime = wallTime }
        guard let lastWallTime else { delta = 0; return }
        let frame = Self.clamped(wallTime - lastWallTime)
        delta = Self.clamped(frame * Self.rate(speed))
        time += delta
        if Float(time) > Self.wrapTime { time = 0 }
    }

    /// The rate a speed runs the clock at: WE's floor of 0.1; a speed that isn't a number runs at 1.
    static func rate(_ speed: Double) -> Double {
        speed.isFinite ? max(speed, minimumRate) : 1
    }

    private static func clamped(_ seconds: Double) -> Double {
        min(max(seconds, minimumFrameDelta), maximumFrameDelta)
    }
}
