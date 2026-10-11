import Foundation

/// Whether a saver shows the app's live frames or its fallback (the loop video, or black without
/// one): live once frames arrive steadily, back to the fallback as soon as they stop (the app
/// quit, crashed, paused or stopped drawing for the screen saver). Times are seconds on one
/// monotonic clock.
struct LiveFrameFallback: Equatable {
    enum Mode: Equatable {
        case live
        case fallback
    }

    /// Frames further apart than this are stale: the app has stopped drawing.
    static let staleAfter: TimeInterval = 0.5
    /// Fresh frames in a row before the saver switches from the fallback to live, so a single
    /// late frame doesn't flash the live picture in and out.
    static let framesToGoLive = 3

    /// The interval the saver checks at: a parked view checks once a second, so frames it sees are
    /// that far apart however fast they come.
    var tickInterval: TimeInterval = 0
    private(set) var mode: Mode = .fallback
    private(set) var lastFrame: TimeInterval?
    private var freshRun = 0

    /// Frames further apart than this are stale, at the interval checked at.
    var staleAfter: TimeInterval { max(Self.staleAfter, tickInterval * 2) }

    /// A new frame (a newer stamp) arrived at `now`.
    mutating func frameArrived(at now: TimeInterval) {
        if let lastFrame, now - lastFrame <= staleAfter {
            freshRun += 1
        } else {
            freshRun = 1
        }
        lastFrame = now
        if mode == .fallback, freshRun >= Self.framesToGoLive { mode = .live }
    }

    /// The mode at `now`: live frames that stopped arriving fall back.
    @discardableResult
    mutating func update(at now: TimeInterval) -> Mode {
        if mode == .live, lastFrame.map({ now - $0 > staleAfter }) ?? true {
            mode = .fallback
            freshRun = 0
        }
        return mode
    }

    /// The source went away (the manifest emptied, the connection ended): fall back at once.
    mutating func reset() {
        mode = .fallback
        lastFrame = nil
        freshRun = 0
    }
}
