import QuartzCore

/// How a clone's or stretch's other displays show the one page their source display loads, as
/// WE mirrors a clone's render (DirectComposition clones) instead of running it again.
///
/// - **Chromium:** the browser's frames are IOSurfaces, so each mirror blits the same frame into
///   its own Metal layer (`ChromiumPageView.page`'s frame observers).
/// - **WebKit:** a `WKWebView` draws in its own window only, and a snapshot reads the page back
///   on the CPU every frame. Core Animation's portal layer (`CAPortalLayer`, the class behind
///   UIKit's portal views) has the window server draw the page's layers again in another window,
///   GPU only. It is looked up at run time; where it is missing each display loads its own page.
///   Only a clone mirrors a WebKit page: a canvas-sized page drawn once in the source's window
///   cost more CPU than a page per display (WebKit keeps the tiles outside its window up to date
///   at the display's rate), so a stretch keeps a page per display there.
enum WebPageMirroring {
    /// Core Animation's portal layer class, if this macOS has it.
    static let portalLayerClass: CALayer.Type? = {
        guard let type = NSClassFromString("CAPortalLayer") as? CALayer.Type,
              type.instancesRespond(to: NSSelectorFromString("setSourceLayer:")) else { return nil }
        return type
    }()

    /// Whether a display can mirror a page on `engine` instead of loading its own, in a stretch
    /// (`stretched`) or a clone.
    static func canMirror(_ engine: WebEngine, stretched: Bool,
                          portalAvailable: Bool = portalLayerClass != nil) -> Bool {
        switch engine {
        case .chromium: return true
        case .webKit: return portalAvailable && !stretched
        }
    }

    /// A layer that draws `source` (and its sublayers, a web view's remote layers included) where
    /// it is placed, in any window; nil without the portal class.
    static func portal(of source: CALayer) -> CALayer? {
        guard let type = portalLayerClass else { return nil }
        let portal = type.init()
        portal.setValue(source, forKey: "sourceLayer")
        // Drawn on any display, at the portal's own place and size, at full opacity.
        portal.setValue(true, forKey: "crossDisplay")
        portal.setValue(false, forKey: "matchesPosition")
        portal.setValue(false, forKey: "matchesTransform")
        portal.setValue(false, forKey: "matchesOpacity")
        return portal
    }

    /// The scale a mirror shows its source at: the source's frame covering the mirror's, centred
    /// (1 for a stretch's members, all the canvas's size, and for a clone of equal displays).
    static func scale(source: CGSize, mirror: CGSize) -> CGFloat {
        guard source.width > 0, source.height > 0, mirror.width > 0, mirror.height > 0 else { return 1 }
        return max(mirror.width / source.width, mirror.height / source.height)
    }

    /// The screen point over the source page that shows what `point`, over the mirror whose frame
    /// on screen is `mirrorFrame`, shows. `mirroredIn` is the window a flipped clone display
    /// mirrors its content in (`NSView.isMirroredOnScreen`).
    static func sourcePoint(_ point: CGPoint, mirrorFrame: CGRect, sourceFrame: CGRect,
                            mirroredIn window: CGRect? = nil) -> CGPoint {
        var point = point
        if let window { point.x = window.minX + window.maxX - point.x }
        let scale = scale(source: sourceFrame.size, mirror: mirrorFrame.size)
        return CGPoint(x: sourceFrame.midX + (point.x - mirrorFrame.midX) / scale,
                       y: sourceFrame.midY + (point.y - mirrorFrame.midY) / scale)
    }
}
