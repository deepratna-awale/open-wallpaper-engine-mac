import AVFoundation
import Metal
import os
import XCTest
@testable import OpenWallpaperEngine

/// Video wallpapers keep playing the way WE's do: they loop, and never hold the display awake.
@MainActor
final class VideoWallpaperPlaybackTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: "owe-video-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.trashItem(at: directory, resultingItemURL: nil) } // Optional: best-effort cleanup.
        try await super.tearDown()
    }

    private func wallpaper(_ clip: URL) -> WEWallpaper {
        WEWallpaper(using: WEProject(file: clip.lastPathComponent, preview: "p.jpg", title: "clip", type: "video"),
                    where: clip.deletingLastPathComponent())
    }

    /// V1: a playing AVPlayer takes a `PreventUserIdleDisplaySleep` assertion unless told not to.
    func testWallpaperPlayersLetTheDisplaySleep() throws {
        let clip = try VideoClipFixture.make(frames: 10, in: directory)
        let factoryPlayer: AVPlayer = WallpaperAVPlayer.make()
        XCTAssertFalse(factoryPlayer.preventsDisplaySleepDuringVideoPlayback)

        let wallpapers = WallpaperViewModel(persistsWallpapers: false)
        wallpapers.audioOutputEnabled = false
        let model = VideoWallpaperViewModel(wallpaper: wallpaper(clip), wallpaperViewModel: wallpapers)
        XCTAssertFalse(model.player.preventsDisplaySleepDuringVideoPlayback, "AVKit path")
        model.stop()

        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let stream = try XCTUnwrap(VideoTextureStream(url: clip, device: device))
        XCTAssertFalse(stream.player.preventsDisplaySleepDuringVideoPlayback, "Metal path")
        stream.stop()
    }

    /// V9: a short clip played past its end runs on into its next pass, queued behind it, instead
    /// of seeking back (which paused picture and sound at every loop, #657).
    func testAVKitVideoLoopsPastItsEnd() throws {
        let clip = try VideoClipFixture.make(frames: 10, in: directory) // 1/3 s
        let wallpapers = WallpaperViewModel(persistsWallpapers: false)
        wallpapers.audioOutputEnabled = false
        let model = VideoWallpaperViewModel(wallpaper: wallpaper(clip), wallpaperViewModel: wallpapers)
        defer { model.stop() }
        let queue = try XCTUnwrap(model.player as? AVQueuePlayer)
        XCTAssertEqual(queue.actionAtItemEnd, .advance)
        waitUntil { queue.items().count == 2 }
        XCTAssertEqual(queue.items().count, 2, "the next pass is queued behind the one playing")
        let first = try XCTUnwrap(queue.currentItem)
        let ended = OSAllocatedUnfairLock(initialState: 0)
        func endedCount() -> Int { ended.withLock { $0 } }
        let observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                              object: nil, queue: .main) { _ in
            ended.withLock { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let deadline = Date().addingTimeInterval(5)
        while endedCount() < 2, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertGreaterThanOrEqual(endedCount(), 2, "the clip reached its end a second time")
        XCTAssertFalse(queue.currentItem === first, "a later pass plays")
        XCTAssertEqual(queue.items().count, 2, "another pass was queued")
        let rate: Float = model.player.rate
        XCTAssertGreaterThan(rate, 0)
    }

    /// The Metal path loops the same way; a video that stops looping keeps only the pass playing.
    func testVideoTextureStreamQueuesItsNextPass() throws {
        let clip = try VideoClipFixture.make(frames: 10, in: directory)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let stream = try XCTUnwrap(VideoTextureStream(url: clip, device: device))
        defer { stream.stop() }
        let queue = try XCTUnwrap(stream.player as? AVQueuePlayer)
        XCTAssertEqual(queue.actionAtItemEnd, .advance)
        waitUntil { queue.items().count == 2 }
        XCTAssertEqual(queue.items().count, 2)
        stream.perform(.loop(false))
        XCTAssertEqual(queue.actionAtItemEnd, .none, "the last frame holds")
        XCTAssertEqual(queue.items().count, 1)
        stream.perform(.loop(true))
        XCTAssertEqual(queue.actionAtItemEnd, .advance)
        XCTAssertEqual(queue.items().count, 2)
    }

    /// A loop plays the picture and the sound as items of one track each, as long as the picture:
    /// a queue player only runs from one pass into the next without a break for those.
    func testLoopAssetsAreSingleTrackAndAsLongAsThePicture() async throws {
        let clip = try VideoClipFixture.make(frames: 10, in: directory) // video only
        let assets = await VideoFileSource(url: clip, mode: .fromDisk).makeLoopAssets()
        XCTAssertNil(assets.soundtrack, "a silent clip has no soundtrack")
        let tracks = try await assets.picture.load(.tracks)
        XCTAssertEqual(tracks.map(\.mediaType), [.video])
        let source = try await AVURLAsset(url: clip).loadTracks(withMediaType: .video)[0].load(.timeRange)
        let duration = try await assets.picture.load(.duration)
        XCTAssertEqual(duration.seconds, source.end.seconds, accuracy: 1e-3)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// The soundtrack's drift from the picture is measured the short way round the loop.
    func testLoopDriftWrapsAroundTheLoop() throws {
        let drift = { (audio: Double, video: Double) in
            try XCTUnwrap(VideoWallpaperViewModel.loopDrift(audio: audio, video: video, duration: 60))
        }
        XCTAssertEqual(try drift(10.05, 10), 0.05, accuracy: 1e-9)
        XCTAssertEqual(try drift(59.9, 0.1), -0.2, accuracy: 1e-9, "the soundtrack hasn't looped yet")
        XCTAssertEqual(try drift(0.1, 59.95), 0.15, accuracy: 1e-9, "the soundtrack looped first")
        XCTAssertNil(VideoWallpaperViewModel.loopDrift(audio: .nan, video: 0, duration: 60))
        XCTAssertNil(VideoWallpaperViewModel.loopDrift(audio: 0, video: 0, duration: 0))
    }
}
