import Foundation

/// How a playlist's wallpaper duration (stored in seconds) is stepped and shown.
enum PlaylistDurationFormat {
    static let range: ClosedRange<Double> = 5...3600

    /// 5 s steps below a minute, 15 s steps from a minute on, clamped to `range`.
    static func snapped(_ seconds: Double) -> Double {
        let step: Double = seconds < 60 ? 5 : 15
        let value = (seconds / step).rounded() * step
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// "45s" below a minute; "1m", "1m15s" from a minute on (a zero seconds part is dropped);
    /// "1h" for a full hour.
    static func label(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total >= 3600, total % 3600 == 0 { return "\(total / 3600)h" }
        let minutes = total / 60
        let rest = total % 60
        return rest == 0 ? "\(minutes)m" : "\(minutes)m\(rest)s"
    }
}
