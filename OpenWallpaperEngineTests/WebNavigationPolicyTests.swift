import XCTest
@testable import OpenWallpaperEngine

final class WebNavigationPolicyTests: XCTestCase {
    func testMainFrameStaysOnTheWallpaper() {
        let allowed = ["owe-wallpaper://local/index.html", "owe-wallpaper://local/sub/page.html?x=1#y",
                       "about:blank", "https://localhost/", "https://localhost"]
        for text in allowed {
            XCTAssertTrue(WebNavigationPolicy.allows(URL(string: text), isMainFrame: true), text)
        }
        let refused = ["https://example.com/", "http://localhost/", "https://localhost/admin",
                       "https://localhost:8080/", "https://localhost/?q=1", "owe-wallpaper://other/index.html",
                       "file:///etc/hosts", "data:text/html,hi", "javascript:alert(1)", "about:srcdoc"]
        for text in refused {
            XCTAssertFalse(WebNavigationPolicy.allows(URL(string: text), isMainFrame: true), text)
        }
        XCTAssertFalse(WebNavigationPolicy.allows(nil, isMainFrame: true))
    }

    func testFramesInsideThePageLoadAsBefore() {
        XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "https://www.youtube.com/embed/abc"), isMainFrame: false))
        XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "about:srcdoc"), isMainFrame: false))
    }
}
