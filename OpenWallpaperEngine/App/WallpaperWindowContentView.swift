import AppKit

/// A wallpaper window's content: the display's wallpaper view, mirrored horizontally while the
/// display is a flipped clone (WE's "Flip clone display"). The mirror is a layer transform, so the
/// compositor flips the frame the display shows anyway: nothing renders again.
final class WallpaperWindowContentView: NSView {
    var isMirrored = false {
        didSet { if isMirrored != oldValue { applyMirror() } }
    }

    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        applyMirror()
    }

    /// The wallpaper's view, where a web wallpaper's page takes the desktop's mouse events.
    var content: NSView? { subviews.first }

    private func applyMirror() {
        // A view's backing layer has its anchor at the origin: mirror about x = 0, then move back.
        layer?.sublayerTransform = isMirrored
            ? CATransform3DTranslate(CATransform3DMakeScale(-1, 1, 1), -bounds.width, 0, 0)
            : CATransform3DIdentity
    }
}
