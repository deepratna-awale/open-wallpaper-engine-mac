import AVFoundation
import WebKit
import XCTest
@testable import OpenWallpaperEngine

/// WebM (VP8/VP9) isn't decodable by AVFoundation; it plays through WebKit's `<video>`.
@MainActor
final class WebKitVideoPlaybackTests: XCTestCase {
    private let clip: URL = Fixtures.url("video/clip-vp9.webm")

    func testOnlyALocalWebMAVFoundationCantPlayTakesTheWebKitPath() throws {
        let playable: Bool = AVURLAsset.isPlayableExtendedMIMEType("video/webm")
        try XCTSkipIf(playable, "AVFoundation plays WebM on this system")
        XCTAssertTrue(WebKitVideoPlayer.handles(clip))
        XCTAssertFalse(WebKitVideoPlayer.handles(clip.deletingPathExtension().appendingPathExtension("mp4")))
        XCTAssertFalse(WebKitVideoPlayer.handles(try XCTUnwrap(URL(string: "https://example.com/a.webm"))))
    }

    func testWebMPlaysAndAdvances() async throws {
        let player = WebKitVideoPlayer(url: clip, readAccess: clip.deletingLastPathComponent())
        defer { player.stop() }
        let window = host(player)
        defer { window.close() }
        player.state = WebKitVideoPlayer.State(placement: .fit, paused: false, muted: true, volume: 0, rate: 1)
        let first = try await currentTime(player, after: 0)
        let later = try await currentTime(player, after: first + 0.2)
        XCTAssertGreaterThan(later, first, "the video advanced")
        let paused: Bool = try await evaluate(player, "document.querySelector('video').paused") as? Bool ?? true
        XCTAssertFalse(paused)
        let fit: String = try await evaluate(player, "document.querySelector('video').style.objectFit") as? String ?? ""
        XCTAssertEqual(fit, "contain")
        let loops: Bool = try await evaluate(player, "document.querySelector('video').loop") as? Bool ?? false
        XCTAssertTrue(loops)
    }

    func testPauseStopsTheVideo() async throws {
        let player = WebKitVideoPlayer(url: clip, readAccess: clip.deletingLastPathComponent())
        defer { player.stop() }
        let window = host(player)
        defer { window.close() }
        player.state = WebKitVideoPlayer.State(placement: .fill, paused: false, muted: true, volume: 0, rate: 1)
        _ = try await currentTime(player, after: 0.05)
        player.state.paused = true
        try await Task.sleep(for: .milliseconds(200))
        let paused: Bool = try await evaluate(player, "document.querySelector('video').paused") as? Bool ?? false
        XCTAssertTrue(paused)
    }

    /// A page plays only while in a window, as on a display.
    private func host(_ player: WebKitVideoPlayer) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 128, height: 128), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = player.webView
        return window
    }

    /// Waits up to 10 s for the video's time to pass `threshold`.
    private func currentTime(_ player: WebKitVideoPlayer, after threshold: Double) async throws -> Double {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let value = try? await evaluate(player, "(function(){var v=document.querySelector('video');return v?v.currentTime:-1;})()") // Optional: page may still be loading.
            if let time = value as? Double, time > threshold { return time }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("currentTime never passed \(threshold)")
        return threshold
    }

    private func evaluate(_ player: WebKitVideoPlayer, _ script: String) async throws -> Any? {
        try await player.webView.evaluateJavaScript(script)
    }
}
