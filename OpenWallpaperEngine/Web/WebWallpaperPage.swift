import AppKit
import WebKit

/// The page a web wallpaper's WE bridge talks to, whichever engine renders it: a `WKWebView`, or a
/// Chromium browser in owe-chromium-helper (`ChromiumBrowserPage`). `WebWallpaperViewModel` drives
/// properties, audio, media, pause and mute through this alone, so both engines behave the same.
///
/// Every member is used on the main actor. The protocol itself isn't `@MainActor`, so a conformer
/// that also serves other threads (`ChromiumBrowserPage`, called from XPC's queue) keeps its own
/// isolation.
protocol WebWallpaperPage: AnyObject {
    /// Runs `script` in the page's main frame; the result is not needed.
    @MainActor func evaluate(_ script: String)
    /// Runs `script`, an expression, and hands its JSON-compatible result back on the main thread
    /// (nil when it threw or the page isn't ready).
    @MainActor func evaluate(_ script: String, completion: @escaping (Any?) -> Void)
    /// Silences or restores the whole page (media elements and Web Audio).
    @MainActor func setPageMuted(_ muted: Bool)
    /// The playback rules paused or resumed the page; the bridge's scripts have already run.
    @MainActor func setPagePaused(_ paused: Bool)
    /// Whether the engine should stop the page while it can't be seen: `muted` pages are
    /// suspended outright, audible ones only throttled, as Wallpaper Engine keeps a covered
    /// wallpaper's sound.
    @MainActor func applySchedulingPolicy(muted: Bool, visible: Bool)
    /// The window the page shows in, for occlusion.
    @MainActor var hostWindow: NSWindow? { get }
    /// The page as an image, for the menu bar tint.
    @MainActor func snapshot(completion: @escaping (CGImage?) -> Void)
}

extension WKWebView: WebWallpaperPage {
    func evaluate(_ script: String) {
        evaluateJavaScript(script, completionHandler: nil)
    }

    func evaluate(_ script: String, completion: @escaping (Any?) -> Void) {
        evaluateJavaScript(script) { result, _ in completion(result) }
    }

    func setPageMuted(_ muted: Bool) {
        WebPageAudio.setMuted(muted, on: self)
    }

    func setPagePaused(_ paused: Bool) {
        setAllMediaPlaybackSuspended(paused, completionHandler: nil)
    }

    /// WebKit judges visibility itself (its window's occlusion); only the policy is set.
    func applySchedulingPolicy(muted: Bool, visible: Bool) {
        configuration.preferences.inactiveSchedulingPolicy = muted ? .suspend : .throttle
    }

    var hostWindow: NSWindow? { window }

    func snapshot(completion: @escaping (CGImage?) -> Void) {
        takeSnapshot(with: nil) { image, error in
            if let error { OWELog.error(.web, "Menu bar tint snapshot failed: \(error)") }
            completion(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }
}
