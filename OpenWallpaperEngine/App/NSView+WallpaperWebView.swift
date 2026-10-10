import AppKit
import WebKit

extension NSView {
    /// The web wallpaper page under `screenPoint` among this view's descendants: a split display
    /// has a page per region, and a stretched page is the canvas's size, larger than its window.
    func webView(at screenPoint: CGPoint) -> WKWebView? {
        guard let window else { return nil }
        return webView(containing: window.convertPoint(fromScreen: screenPoint))
    }

    /// The mirror of another display's page (`WebPageMirrorView`) under `screenPoint` among this
    /// view's descendants.
    func pageMirror(at screenPoint: CGPoint) -> WebPageMirrorView? {
        guard let window else { return nil }
        return pageMirror(containing: window.convertPoint(fromScreen: screenPoint))
    }

    private func pageMirror(containing windowPoint: CGPoint) -> WebPageMirrorView? {
        for subview in subviews {
            if let mirror = subview as? WebPageMirrorView {
                if mirror.convert(mirror.bounds, to: nil).contains(windowPoint) { return mirror }
                continue
            }
            if let mirror = subview.pageMirror(containing: windowPoint) { return mirror }
        }
        return nil
    }

    private func webView(containing windowPoint: CGPoint) -> WKWebView? {
        for subview in subviews {
            if let page = subview as? WKWebView {
                if page.convert(page.bounds, to: nil).contains(windowPoint) { return page }
                continue
            }
            if let page = subview.webView(containing: windowPoint) { return page }
        }
        return nil
    }
}
