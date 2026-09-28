//
//  WebKitVideoPlayer.swift
//  Open Wallpaper Engine
//

import AVFoundation
import WebKit

/// Plays a local video AVFoundation can't decode (WebM: VP8/VP9) through WebKit's `<video>`.
/// The file is opened as WebKit's media document with read access limited to its wallpaper
/// folder; no network is involved. Music-sync effects don't apply on this path.
@MainActor
final class WebKitVideoPlayer: NSObject, WKNavigationDelegate {
    struct State: Equatable {
        var placement: WallpaperPlacement = .fill
        var paused = false
        var muted = true
        var volume: Float = 1
        var rate: Float = 1
    }

    /// Whether `url` goes through WebKit: a local WebM that AVFoundation reports it can't play.
    /// Other types, and a WebM once AVFoundation plays it, stay on the AVFoundation paths.
    static func handles(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "webm" else { return false }
        return !AVURLAsset.isPlayableExtendedMIMEType("video/webm")
    }

    let webView: WKWebView
    private let url: URL
    /// Bumped per state change, so a retry for an older state stops.
    private var generation = 0
    private var stopped = false
    var state = State() {
        didSet { if state != oldValue { apply() } }
    }

    init(url: URL, readAccess: URL) {
        self.url = url
        let configuration = WKWebViewConfiguration()
        // The media document autoplays with sound unless playback waits for a gesture; the script
        // `apply()` evaluates counts as one, so the video starts muted or not as the state says.
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        OWELog.info(.library, "Playing \(url.lastPathComponent) through WebKit; music-sync zoom/tilt/saturation/pace don't apply to it")
        // WebKit shows the file as its media document; `apply()` styles and drives its `<video>`.
        webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        apply()
    }

    func stop() {
        stopped = true
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){v.pause();v.removeAttribute('src');v.load();})")
        webView.stopLoading()
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { logFailure(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { logFailure(error) }
    }

    private func logFailure(_ error: Error) {
        OWELog.error(.library, "WebKit video \(url.lastPathComponent) failed to load: \(error.localizedDescription)")
    }

    /// Applies `state` to the page's `<video>`, retrying until the media document has one (a
    /// media document reports no navigation finish to rely on).
    private func apply() {
        generation += 1
        attempt(generation)
    }

    private func attempt(_ generation: Int) {
        guard !stopped, generation == self.generation else { return }
        webView.evaluateJavaScript(Self.script(for: state)) { [weak self] result, _ in
            // An error here is the page still loading; the retry covers it.
            guard (result as? Bool) != true else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MainActor.assumeIsolated { self?.attempt(generation) }
            }
        }
    }

    /// Styles the media document's `<video>` like the AVKit view's gravity and applies playback.
    static func script(for state: State) -> String {
        let objectFit: String
        switch state.placement {
        case .stretch: objectFit = "fill"
        case .fill, .zoom: objectFit = "cover"
        case .fit, .center: objectFit = "contain"
        }
        let volume: Float = min(1, max(0, state.volume))
        let rate: Float = max(0, state.rate)
        let paused: Bool = state.paused || rate <= 0
        return """
        (function(){var v=document.querySelector('video');if(!v)return false;
        v.controls=false;v.loop=true;
        v.style.cssText='position:fixed;left:0;top:0;width:100vw;height:100vh;max-width:none;max-height:none;margin:0;object-fit:\(objectFit);object-position:center';
        v.muted=\(state.muted);v.volume=\(volume);
        if(\(rate)>0){v.defaultPlaybackRate=\(rate);v.playbackRate=\(rate);}
        if(\(paused)){v.pause();}else if(v.paused){v.play().catch(function(){});}
        return true;})()
        """
    }
}
