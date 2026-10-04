import AppKit
import OWETheming

/// A wallpaper window's content: the display's wallpaper view, mirrored horizontally while the
/// display is a flipped clone (WE's "Flip clone display"). The mirror is a layer transform, so the
/// compositor flips the frame the display shows anyway: nothing renders again. While the display
/// is in a stretch it names the stretch's canvas, which a scene's view reads
/// (`NSView.stretchCanvasOnScreen`) to show its rect of the one frame.
final class WallpaperWindowContentView: NSView, StretchCanvasHosting {
    var isMirrored = false {
        didSet { if isMirrored != oldValue { applyMirror() } }
    }

    var stretchCanvas: CGRect?

    /// Theming's menu bar strip (Settings › Theming › Menu Bar): the window's top filled with the
    /// colour, as tall as the display's menu bar. The menu bar is transparent over the wallpaper
    /// window, which covers the desktop picture, so this is what it shows. A plain layer above the
    /// wallpaper: the compositor draws it and nothing renders again.
    var menuBarStrip: MenuBarStripFill? {
        didSet { if menuBarStrip != oldValue { layoutStrip() } }
    }

    private var stripView: NSView?

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
        layoutStrip()
    }

    /// The wallpaper's view, where a web wallpaper's page takes the desktop's mouse events.
    var content: NSView? { subviews.first }

    private func layoutStrip() {
        guard let strip = menuBarStrip, strip.height > 0 else {
            stripView?.removeFromSuperview()
            stripView = nil
            return
        }
        let view = stripView ?? {
            let view = NSView()
            view.wantsLayer = true
            addSubview(view, positioned: .above, relativeTo: nil)
            stripView = view
            return view
        }()
        view.frame = NSRect(x: 0, y: bounds.height - strip.height, width: bounds.width, height: strip.height)
        view.layer?.backgroundColor = strip.cgColor
    }

    private func applyMirror() {
        // A view's backing layer has its anchor at the origin: mirror about x = 0, then move back.
        layer?.sublayerTransform = isMirrored
            ? CATransform3DTranslate(CATransform3DMakeScale(-1, 1, 1), -bounds.width, 0, 0)
            : CATransform3DIdentity
    }
}

/// A wallpaper window's menu bar strip: the colour and the menu bar's height in points.
struct MenuBarStripFill: Equatable {
    var color: ThemeColor
    var height: CGFloat

    /// `display`'s strip in `strips`; nil without one (no strips, or no menu bar on the display).
    init?(_ strips: DesktopPictureStrips?, display: CGDirectDisplayID?) {
        guard let strips, let display, let geometry = strips.displays[display], geometry.menuBarHeight > 0 else {
            return nil
        }
        color = strips.color
        height = geometry.menuBarHeight
    }

    var cgColor: CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}
