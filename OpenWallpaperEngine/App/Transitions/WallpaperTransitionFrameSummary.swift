import QuartzCore

/// What `WallpaperTransitionMetrics` measured for one transition.
struct WallpaperTransitionFrameSummary: Equatable, CustomStringConvertible {
    var frames: Int
    /// From the first presented frame to the last.
    var span: CFTimeInterval
    var p50: CFTimeInterval
    var p95: CFTimeInterval
    var maxInterval: CFTimeInterval
    /// Refreshes that showed no new frame: an interval of n refreshes drops n - 1.
    var dropped: Int
    var refreshInterval: CFTimeInterval
    /// Main-thread stalls of a refresh or more: how many, the longest and their sum.
    var stallCount: Int
    var stallMax: CFTimeInterval
    var stallTotal: CFTimeInterval

    init(presents: [CFTimeInterval], stalls: [CFTimeInterval], refreshInterval: CFTimeInterval) {
        let intervals = zip(presents.dropFirst(), presents).map { $0 - $1 }.sorted()
        frames = presents.count
        span = (presents.last ?? 0) - (presents.first ?? 0)
        p50 = Self.percentile(intervals, 0.5)
        p95 = Self.percentile(intervals, 0.95)
        maxInterval = intervals.last ?? 0
        dropped = intervals.reduce(0) { $0 + max(Int(($1 / refreshInterval).rounded()) - 1, 0) }
        self.refreshInterval = refreshInterval
        stallCount = stalls.count
        stallMax = stalls.max() ?? 0
        stallTotal = stalls.reduce(0, +)
    }

    /// The nearest-rank percentile of sorted `values`; 0 when there are none.
    static func percentile(_ values: [CFTimeInterval], _ fraction: Double) -> CFTimeInterval {
        guard !values.isEmpty else { return 0 }
        let rank = Int((fraction * Double(values.count)).rounded(.up))
        return values[min(max(rank, 1), values.count) - 1]
    }

    var description: String {
        func ms(_ value: CFTimeInterval) -> String { String(format: "%.1f", value * 1000) }
        return "\(frames) frames over \(ms(span)) ms, interval p50 \(ms(p50)) p95 \(ms(p95)) max \(ms(maxInterval)) ms, "
            + "\(dropped) dropped (refresh \(ms(refreshInterval)) ms); main thread: \(stallCount) stalls, "
            + "max \(ms(stallMax)) ms, total \(ms(stallTotal)) ms"
    }
}
