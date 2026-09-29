import WebKit
import XCTest
@testable import OpenWallpaperEngine

@MainActor
final class WebProcessGroupTests: XCTestCase {
    private let pageA = URL(fileURLWithPath: "/tmp/a/index.html")
    private let pageB = URL(fileURLWithPath: "/tmp/b/index.html")

    func testSecondPageOfSameWallpaperIsRelated() {
        let group = WebProcessGroup()
        let first = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        group.register(first, for: pageA)
        XCTAssertTrue(group.relatedWebView(for: pageA) === first)
        XCTAssertNil(group.relatedWebView(for: pageB))

        let configuration = WKWebViewConfiguration()
        // The private key may be missing; then the page falls back to its own process.
        if group.relate(configuration, to: pageA) {
            let second = WKWebView(frame: .zero, configuration: configuration)
            XCTAssertFalse(second.configuration.userContentController === first.configuration.userContentController)
        }
        XCTAssertFalse(group.relate(WKWebViewConfiguration(), to: pageB))
    }

    func testReregisterMovesPageAndClosedPagesDrop() {
        let group = WebProcessGroup()
        var view: WKWebView? = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        group.register(view!, for: pageA)
        group.register(view!, for: pageB)
        XCTAssertNil(group.relatedWebView(for: pageA))
        XCTAssertNotNil(group.relatedWebView(for: pageB))
        view = nil
        XCTAssertNil(group.relatedWebView(for: pageB))
    }
}
