import AppKit
import Metal
import WebKit

/// A clone's or stretch's member display showing the page its source display loads, instead of
/// loading its own (`WebPageMirroring`): a WebKit page through a portal layer, a Chromium page's
/// frames through a Metal layer of its own. The source's page fills the view at the scale that
/// covers it (`WebPageMirroring.scale`), so a stretch member, sized to the canvas like the source
/// and offset in its window, shows its own rect of the one canvas-sized page.
final class WebPageMirrorView: NSView {
    let sourceScreenId: String
    private weak var registry: WebPageMirrorRegistry?
    /// The view showing the page on the source display, while there is one.
    private(set) weak var source: NSView?
    private var portal: CALayer?
    private var presenter: ChromiumFramePresenter?
    private weak var observedPage: ChromiumBrowserPage?
    private var frameObserver: NSObjectProtocol?

    init(registry: WebPageMirrorRegistry, sourceScreenId: String) {
        self.registry = registry
        self.sourceScreenId = sourceScreenId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { registry?.add(self) } else { registry?.remove(self) }
    }

    /// Shows `source`'s page, or nothing.
    func attach(_ source: NSView?) {
        guard source !== self.source || (source == nil && (portal != nil || presenter != nil)) else { return }
        detach()
        self.source = source
        if let webView = source as? WKWebView, let sourceLayer = webView.layer,
           let portal = WebPageMirroring.portal(of: sourceLayer) {
            portal.actions = Self.noAnimations
            layer?.addSublayer(portal)
            self.portal = portal
        } else if let pageView = source as? ChromiumPageView {
            let presenter = ChromiumFramePresenter(device: MTLCreateSystemDefaultDevice())
            // A clone of a differently shaped display shows the page as a scene does: covering it.
            presenter.layer.contentsGravity = .resizeAspectFill
            presenter.layer.actions = Self.noAnimations
            layer?.addSublayer(presenter.layer)
            self.presenter = presenter
            observedPage = pageView.page
            pageView.page.addFrameObserver(self) { [presenter] frame in presenter.enqueue(frame) }
        }
        if let source {
            source.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                                   object: source, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsLayout = true }
            }
        }
        needsLayout = true
    }

    private func detach() {
        portal?.removeFromSuperlayer()
        portal = nil
        presenter?.layer.removeFromSuperlayer()
        presenter = nil
        observedPage?.removeFrameObserver(self)
        observedPage = nil
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = nil
    }

    deinit {
        observedPage?.removeFrameObserver(self)
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    private static let noAnimations: [String: CAAction] = [
        "bounds": NSNull(), "position": NSNull(), "transform": NSNull(), "frame": NSNull(), "contents": NSNull(),
    ]

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let presenter {
            presenter.layer.frame = bounds
            presenter.layer.contentsScale = window?.backingScaleFactor ?? 1
        }
        if let portal, let source {
            // The portal draws the source layer at the portal's own geometry: its size, centred,
            // scaled to cover this view.
            let size = source.bounds.size
            let scale = WebPageMirroring.scale(source: size, mirror: bounds.size)
            portal.bounds = CGRect(origin: .zero, size: size)
            portal.position = CGPoint(x: bounds.midX, y: bounds.midY)
            portal.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    /// The screen point over the source page (whose view's frame on screen is `sourceFrame`) that
    /// shows what `screenPoint` shows here; nil when the point isn't over this view's window.
    func sourcePoint(_ screenPoint: NSPoint, sourceFrame: NSRect) -> NSPoint? {
        guard let window, window.frame.contains(screenPoint) else { return nil }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        guard frame.contains(screenPoint) else { return nil }
        return WebPageMirroring.sourcePoint(screenPoint, mirrorFrame: frame, sourceFrame: sourceFrame,
                                            mirroredIn: isMirroredOnScreen ? window.frame : nil)
    }
}
