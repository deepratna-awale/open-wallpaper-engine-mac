import AVFoundation
import XCTest
@testable import OpenWallpaperEngine

/// The web recorder's frame pipeline on a tiny local page (`ScreenSaverWebLoopTestPage.html`):
/// load through the scheme handler, stepped page time, snapshot, seam search and HEVC encode.
@MainActor
final class ScreenSaverWebLoopRecorderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "owe-web-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder) // Optional: a scratch folder.
    }

    private func webWallpaper(page: String) throws -> WEWallpaper {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ScreenSaverWebLoopTestPage", withExtension: "html"))
        try FileManager.default.copyItem(at: source, to: folder.appending(path: "index.html"))
        let project = #"{"type":"web","file":"\#(page)","title":"t","general":{"properties":{"barcolor":{"type":"color","value":"1 1 1"}}}}"#
        try Data(project.utf8).write(to: folder.appending(path: "project.json"))
        return WEWallpaper(using: WEProject(file: page, preview: "p.jpg", title: "t", type: "web"), where: folder)
    }

    private func recorder(_ wallpaper: WEWallpaper, output: URL) -> ScreenSaverWebLoopRecorder {
        let recorder = ScreenSaverWebLoopRecorder(wallpaper: wallpaper, pixelSize: SIMD2(64, 36), pointSize: SIMD2(64, 36),
                                                  output: output, properties: ["barcolor": "red"], fps: 30)
        recorder.minimumSeconds = 0.5
        recorder.maximumSeconds = 1.5
        recorder.settleSeconds = 0
        recorder.loadTimeout = 20
        return recorder
    }

    func testRecordsALoopInSteppedTime() throws {
        let output = folder.appending(path: "loop.mov")
        let recorder = recorder(try webWallpaper(page: "index.html"), output: output)
        XCTAssertEqual(recorder.run(), .recorded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
        XCTAssertFalse(recorder.frameDurations.isEmpty, "each frame's time is measured")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: ".pass-loop.mov").path(percentEncoded: false)),
                       "the intermediate video is removed")

        let asset = AVURLAsset(url: output)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let size = track.naturalSize
        XCTAssertEqual(size.width, 64)
        XCTAssertEqual(size.height, 36)
        // The bar crosses the page once a second of page time: 30 stepped frames, whatever the
        // snapshots cost in real time.
        let duration = asset.duration.seconds
        XCTAssertEqual(duration, 1.0, accuracy: 0.05)
    }

    func testAPageThatDoesNotLoadSaysWhy() throws {
        let output = folder.appending(path: "missing.mov")
        let recorder = recorder(try webWallpaper(page: "missing.html"), output: output)
        guard case .pageDidNotLoad = recorder.run() else { return XCTFail("a missing page is a load failure") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    func testRecordsWebPagesAndWebMVideosOnly() {
        func wallpaper(_ type: String, _ file: String) -> WEWallpaper {
            WEWallpaper(using: WEProject(file: file, preview: "p.jpg", title: "t", type: type),
                        where: URL(fileURLWithPath: "/tmp/owe-web-loop"))
        }
        XCTAssertTrue(ScreenSaverWebLoopRecorder.records(wallpaper("web", "index.html")))
        XCTAssertTrue(ScreenSaverWebLoopRecorder.records(wallpaper("video", "clip.WebM")))
        XCTAssertFalse(ScreenSaverWebLoopRecorder.records(wallpaper("video", "clip.mp4")))
        XCTAssertFalse(ScreenSaverWebLoopRecorder.records(wallpaper("scene", "scene.json")))
        XCTAssertFalse(ScreenSaverWebLoopRecorder.records(wallpaper("application", "app.exe")))
    }
}
