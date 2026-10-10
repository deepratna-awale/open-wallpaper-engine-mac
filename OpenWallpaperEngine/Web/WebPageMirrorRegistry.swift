import AppKit

/// The pages a clone's or stretch's displays share: each source display's page view (a
/// `WKWebView` or a `ChromiumPageView`) and the mirrors showing it on the other displays. A mirror
/// follows its source as the source's view is made again (another wallpaper, the other engine).
@MainActor
final class WebPageMirrorRegistry {
    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var sources: [String: WeakView] = [:]
    private var mirrors: [String: [WebPageMirrorView]] = [:]

    /// `view` shows `screenId`'s page; its mirrors show it from now on.
    func setSource(_ view: NSView, for screenId: String) {
        sources[screenId] = WeakView(view)
        mirrors[screenId]?.forEach { $0.attach(view) }
    }

    /// `view` no longer shows `screenId`'s page (a newer view may already).
    func removeSource(_ view: NSView, for screenId: String) {
        guard sources[screenId]?.view === view else { return }
        sources[screenId] = nil
        mirrors[screenId]?.forEach { $0.attach(nil) }
    }

    func source(for screenId: String) -> NSView? { sources[screenId]?.view }

    func add(_ mirror: WebPageMirrorView) {
        var list = mirrors[mirror.sourceScreenId] ?? []
        guard !list.contains(where: { $0 === mirror }) else { return }
        list.append(mirror)
        mirrors[mirror.sourceScreenId] = list
        mirror.attach(source(for: mirror.sourceScreenId))
    }

    func remove(_ mirror: WebPageMirrorView) {
        mirrors[mirror.sourceScreenId]?.removeAll { $0 === mirror }
        if mirrors[mirror.sourceScreenId]?.isEmpty == true { mirrors[mirror.sourceScreenId] = nil }
        mirror.attach(nil)
    }

    /// The mirrors showing `screenId`'s page.
    func mirrors(of screenId: String) -> [WebPageMirrorView] { mirrors[screenId] ?? [] }
}
