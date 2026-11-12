import Foundation

/// Where a web wallpaper's page may go. Wallpaper Engine keeps a wallpaper self-contained: its
/// links never open a browser, and the page itself never leaves the wallpaper. So the main frame
/// may only load the wallpaper's own files (`owe-wallpaper://local/…`), the https page a remote
/// embed is served at, and `about:blank`; frames inside the page (a YouTube or Vimeo player) load
/// as before. The Chromium helper applies the same rule (`request_on_before_browse`).
enum WebNavigationPolicy {
    /// The base URL `WebWallpaperView` loads a remote embed page with.
    static let embedPageURL = URL(string: "https://localhost/")!

    static func allows(_ url: URL?, isMainFrame: Bool) -> Bool {
        guard isMainFrame else { return true }
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case WebWallpaperSchemeHandler.scheme:
            return url.host == WebWallpaperSchemeHandler.host
        case "about":
            return url.absoluteString.lowercased() == "about:blank"
        case "https":
            return url.host?.lowercased() == embedPageURL.host && url.port == nil
                && ["", "/"].contains(url.path) && url.query == nil
        default:
            return false
        }
    }
}
