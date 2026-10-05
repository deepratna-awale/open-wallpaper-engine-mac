import AppKit
import IOSurface

/// A transition over a display's wallpaper: a layer whose contents are the transition's frames
/// (the player's IOSurfaces, premultiplied), which the compositor lays over the incoming
/// wallpaper's view. It sits in the display options' transform with the wallpaper's view, so it
/// lands where the picture does, and takes no mouse events.
final class WallpaperTransitionOverlayView: NSView {
    init(frame: CGRect, contentsRect: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        layer.isOpaque = false
        layer.contentsGravity = .resize
        layer.contentsRect = contentsRect
        // Contents set each frame, not animated.
        layer.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows a rendered frame.
    func show(_ surface: IOSurface) {
        layer?.contents = surface
    }
}
