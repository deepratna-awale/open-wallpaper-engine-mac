import WebKit
import XCTest
@testable import OpenWallpaperEngine

/// A web wallpaper's `getUserMedia` is refused without asking, so a page never brings up WebKit's
/// prompt or the Microphone permission (the app asks for that only when the user chooses a
/// recording device).
final class WebMediaCaptureTests: XCTestCase {
    func testEveryCaptureRequestIsRefused() {
        for type in [WKMediaCaptureType.camera, .microphone, .cameraAndMicrophone] {
            XCTAssertEqual(WebMediaCapture.decision(for: type), .deny, WebMediaCapture.name(of: type))
        }
    }

    func testThePageAsksTheViewModel() throws {
        let selector = #selector(WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:))
        XCTAssertTrue(WebWallpaperViewModel.instancesRespond(to: selector))
        let view = AppIdentityLintTests.repository.appending(path: "OpenWallpaperEngine/Web/WebWallpaperView.swift")
        let text = try String(contentsOf: view, encoding: .utf8)
        XCTAssertTrue(text.contains("nsView.uiDelegate = viewModel"), "the wallpaper page's UI delegate answers capture requests")
    }
}
