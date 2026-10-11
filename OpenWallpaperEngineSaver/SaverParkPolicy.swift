import CoreGraphics
import Foundation

/// How fast a saver view draws. macOS 14 to 27 keep saver views that are never shown (stacked
/// instances, hidden full-screen hosts), so a view ticks at full rate only while its frames are
/// presented (`MTLDrawable.presentedTime` non-zero), for a grace period after it starts, and parks
/// at `parkedRate` otherwise. Times are seconds on one monotonic clock.
struct SaverParkPolicy: Equatable {
    /// Full rate for this long after the view starts, before any frame could be presented.
    static let startGrace: TimeInterval = 3
    /// Full rate while a frame was presented within this long.
    static let presentedGrace: TimeInterval = 2
    static let parkedRate = 1

    var startedAt: TimeInterval
    var lastPresented: TimeInterval?

    init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    func isParked(at now: TimeInterval) -> Bool {
        guard now - startedAt > Self.startGrace else { return false }
        return lastPresented.map { now - $0 > Self.presentedGrace } ?? true
    }

    /// The rate to tick at, given the rate frames come at.
    func rate(at now: TimeInterval, fullRate: Int) -> Int {
        isParked(at: now) ? min(Self.parkedRate, max(fullRate, 1)) : max(fullRate, 1)
    }

    mutating func presented(at now: TimeInterval) { lastPresented = now }

    /// Whether a frame that came at `now` is drawn: every one at full rate, one a second parked.
    func mayDraw(at now: TimeInterval, lastDrawn: TimeInterval?) -> Bool {
        guard isParked(at: now), let lastDrawn else { return true }
        return now - lastDrawn >= 1 / Double(Self.parkedRate)
    }

    /// Whether a view is the System Settings preview: its flag, which is unreliable from macOS 26
    /// (the preview and the real run go through the same host), or a frame too small for a screen.
    static func isPreview(flag: Bool, size: CGSize) -> Bool {
        flag || size.width < 600 || size.height < 400
    }
}
