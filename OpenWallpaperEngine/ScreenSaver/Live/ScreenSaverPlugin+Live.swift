import AppKit

extension ScreenSaverPlugin {
    /// A loop of the screen saver's layout the app draws live: a scene wallpaper (web pages keep
    /// their recorded loop and video wallpapers their own file, which the saver plays), at the
    /// largest of its displays' sizes (a stretch's canvas), with the properties its first display
    /// runs it with.
    struct LiveLoop {
        var wallpaper: WEWallpaper
        var propertyScope: WallpaperPropertyScope
        var loop: ScreenSaverLayoutPlan.Loop
        var pixels: SIMD2<Int>
        var points: SIMD2<Int>
        /// The display it is paced by (its first).
        var screenId: String?
    }

    /// The scene loops of the screen saver's layout now, and every planned display's identity;
    /// nothing while the saver doesn't follow the desktop (`followsDesktop`).
    func liveLoops() -> (loops: [LiveLoop], displays: [String]) {
        guard followsDesktop, let viewModel else { return ([], []) }
        let (plan, wallpapers) = currentPlan(fallback: nil)
        let screens = Dictionary(viewModel.connectedDisplays().map { ($0.identity, $0.screenId) }, uniquingKeysWith: { first, _ in first })
        var loops: [LiveLoop] = []
        for loop in plan.loops {
            guard let wallpaper = wallpapers[loop.content.id], Self.isScene(wallpaper),
                  let pixels = loop.sizes.map(\.pixels).max(by: { $0.x * $0.y < $1.x * $1.y }),
                  let points = loop.sizes.map(\.points).max(by: { $0.x * $0.y < $1.x * $1.y }) else { continue }
            let screenId = loop.displays.first.flatMap { screens[$0] }
            let scope = screenId.map { viewModel.instanceKey(for: $0).properties } ?? .shared
            loops.append(LiveLoop(wallpaper: wallpaper, propertyScope: scope, loop: loop, pixels: pixels, points: points,
                                  screenId: screenId))
        }
        return (loops, plan.displays)
    }

    /// The live manifest's display entries for `loops` (ring `i` is `loops[i]`): one for any
    /// display when a whole loop plays on every display, else one per display, with its crop for
    /// a stretch. Displays not listed play their video.
    nonisolated static func liveDisplayEntries(_ loops: [ScreenSaverLayoutPlan.Loop], pixels: [SIMD2<Int>],
                                               displays: [String]) -> [ScreenSaverFramePublisher.DisplayEntry] {
        var entries: [ScreenSaverFramePublisher.DisplayEntry] = []
        for (ring, loop) in loops.enumerated() {
            if let canvas = loop.canvas, ring < pixels.count {
                let size = CGSize(width: pixels[ring].x, height: pixels[ring].y)
                for display in loop.displays {
                    guard let unit = loop.crops[display] else { continue }
                    entries.append(.init(display: display, ring: ring,
                                         crop: ScreenSaverManifest.Crop(unit, canvas: canvas.size, video: size)))
                }
            } else if !displays.isEmpty, Set(displays).isSubset(of: loop.displays) {
                entries.append(.init(display: nil, ring: ring))
            } else {
                entries += loop.displays.map { .init(display: $0, ring: ring) }
            }
        }
        return entries
    }
}
