//
//  WebWallpaperView.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/13.
//

import Cocoa
import SwiftUI
import WebKit

struct WebWallpaperView: NSViewRepresentable {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @StateObject var viewModel: WebWallpaperViewModel
    let screenId: String

    init(wallpaperViewModel: WallpaperViewModel, screenId: String) {
        self.wallpaperViewModel = wallpaperViewModel
        self.screenId = screenId
        self._viewModel = StateObject(wrappedValue: WebWallpaperViewModel(wallpaper: wallpaperViewModel.wallpaper(for: screenId),
                                                                          propertyScope: wallpaperViewModel.propertyScope(for: screenId),
                                                                          media: AppDelegate.shared.mediaSession))
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        Self.enableFileAccess(on: configuration)
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        viewModel.installBridge(on: configuration.userContentController)
        configuration.setURLSchemeHandler(viewModel.schemeHandler, forURLScheme: WebWallpaperSchemeHandler.scheme)
        viewModel.renderWatchdog = wallpaperViewModel.renderWatchdog
        // The related page only lends its process; this page's configuration stays its own.
        let pageURL = Self.pageURL(of: viewModel.currentWallpaper)
        wallpaperViewModel.webProcessGroup.relate(configuration, to: pageURL)

        let nsView = WKWebView(frame: .zero, configuration: configuration)
        wallpaperViewModel.webProcessGroup.register(nsView, for: pageURL)
        nsView.navigationDelegate = viewModel
        viewModel.webView = nsView
        viewModel.applySchedulingPolicy()
        Self.loadWallpaper(nsView, viewModel: viewModel)
        return nsView
    }

    static func pageURL(of wallpaper: WEWallpaper) -> URL {
        wallpaper.wallpaperDirectory.appending(path: wallpaper.project.file)
    }

    /// Load wallpaper — uses loadHTMLString for URL-based wallpapers (YouTube/Vimeo)
    /// so the origin isn't file://, or loadFileURL for local wallpapers.
    private static func loadWallpaper(_ webView: WKWebView, viewModel: WebWallpaperViewModel) {
        viewModel.pageWillLoad()
        let fileUrl = viewModel.fileUrl
        // Check if the HTML contains a redirect/embed to an external URL
        if let html = try? String(contentsOf: fileUrl, encoding: .utf8),
           html.contains("youtube.com") || html.contains("vimeo.com") {
            // Load as HTML string with https origin so YouTube/Vimeo embeds work
            webView.loadHTMLString(html, baseURL: URL(string: "https://localhost"))
        } else if let patches = viewModel.compatPatches,
                  let url = WebWallpaperSchemeHandler.url(forRelativePath: viewModel.currentWallpaper.project.file) {
            OWELog.info(.web, "Serving \(viewModel.currentWallpaper.project.title) with WE's compatibility patches")
            viewModel.schemeHandler.directory = viewModel.readAccessURL
            viewModel.schemeHandler.patches = patches
            webView.load(URLRequest(url: url))
        } else {
            webView.loadFileURL(fileUrl, allowingReadAccessTo: viewModel.readAccessURL)
        }
    }

    /// Enable file:// cross-origin access for WebGL wallpapers.
    /// Tries multiple private WebKit key variants, catching ObjC exceptions for each.
    private static func enableFileAccess(on configuration: WKWebViewConfiguration) {
        let prefs = configuration.preferences

        // Key variants across macOS versions
        let fileAccessKeys = ["allowFileAccessFromFileURLs", "_allowFileAccessFromFileURLs"]
        let universalAccessKeys = ["allowUniversalAccessFromFileURLs", "_allowUniversalAccessFromFileURLs"]

        for key in fileAccessKeys {
            if ObjCExceptionCatcher.performSafe({ prefs.setValue(true, forKey: key) }) { break }
        }

        for key in universalAccessKeys {
            if ObjCExceptionCatcher.performSafe({ prefs.setValue(true, forKey: key) }) { break }
        }
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let selectedWallpaper = wallpaperViewModel.wallpaper(for: screenId)
        let currentWallpaper = viewModel.currentWallpaper

        if selectedWallpaper.wallpaperDirectory.appending(path: selectedWallpaper.project.file) != currentWallpaper.wallpaperDirectory.appending(path: currentWallpaper.project.file) {
            viewModel.currentWallpaper = selectedWallpaper
            // The process was chosen at creation; only later pages of the new wallpaper join this one.
            wallpaperViewModel.webProcessGroup.register(nsView, for: Self.pageURL(of: selectedWallpaper))
            viewModel.stopAudio()
            Self.loadWallpaper(nsView, viewModel: viewModel)
        }
        applyPlacement(wallpaperViewModel.wallpaperPlacement, to: nsView)
        WebPageScale.apply(standardResolution: AppDelegate.shared.globalSettingsViewModel.settings.webStandardResolution,
                           to: nsView)
        // A page per display, so only the one on the wallpaper's audible display plays sound. The
        // playback rules pause each display's page on its own, and silence the wallpaper only when
        // every display showing it is muted, paused or stopped.
        let key = WallpaperInstanceKey(selectedWallpaper)
        viewModel.setPaused(!wallpaperViewModel.playback(onScreen: screenId).rendersFrames)
        viewModel.setMuted(!wallpaperViewModel.shouldPlayAudio(on: screenId) || wallpaperViewModel.playVolume == 0
                           || !wallpaperViewModel.wallpaperPlayback(of: key).playsSound)
    }

    private func applyPlacement(_ placement: WallpaperPlacement, to webView: WKWebView) {
        let objectFit: String
        switch placement {
        case .stretch:
            objectFit = "fill"
        case .fill, .zoom:
            objectFit = "cover"
        case .fit, .center:
            objectFit = "contain"
        }
        let javascript = "document.documentElement.style.width='100%';document.documentElement.style.height='100%';document.body.style.margin='0';document.body.style.width='100%';document.body.style.height='100%';document.querySelectorAll('video,img,canvas').forEach(function(element){element.style.width='100%';element.style.height='100%';element.style.objectFit='\(objectFit)';});"
        webView.evaluateJavaScript(javascript, completionHandler: nil)
    }
}

/// "Render web wallpapers at standard resolution": on a Retina display the page renders with a
/// device scale factor of 1, so a page that sizes its canvas by `devicePixelRatio` draws a quarter
/// of the pixels. WebKit's `_overrideDeviceScaleFactor` (0 = the window's own) has no public
/// equivalent; where it is missing the page keeps its full resolution.
enum WebPageScale {
    private static let setOverride = NSSelectorFromString("_setOverrideDeviceScaleFactor:")

    static func scaleFactor(standardResolution: Bool, backingScale: CGFloat) -> CGFloat {
        standardResolution && backingScale > 1 ? 1 : 0
    }

    static func apply(standardResolution: Bool, to webView: WKWebView) {
        let backingScale = webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let factor = scaleFactor(standardResolution: standardResolution, backingScale: backingScale)
        guard webView.responds(to: setOverride), let method = webView.method(for: setOverride) else { return }
        typealias SetOverride = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        if (webView.value(forKey: "_overrideDeviceScaleFactor") as? CGFloat) == factor { return }
        unsafeBitCast(method, to: SetOverride.self)(webView, setOverride, factor)
    }
}
