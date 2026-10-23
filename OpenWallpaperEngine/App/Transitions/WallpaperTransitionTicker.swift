import Foundation
import QuartzCore

/// The display link's target: calls the player without keeping it alive.
@MainActor
final class WallpaperTransitionTicker: NSObject {
    private let action: @MainActor (CADisplayLink) -> Void

    init(_ action: @escaping @MainActor (CADisplayLink) -> Void) {
        self.action = action
    }

    @objc func tick(_ link: CADisplayLink) {
        action(link)
    }
}
