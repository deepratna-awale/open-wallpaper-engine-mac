import IOSurface
import Metal
import XCTest
@testable import OpenWallpaperEngine

/// The live screen saver's frames: rings of global surfaces, the manifest that lists them, the
/// stamps that announce each frame, and what a saver process reads back (`LiveFrameStore`).
final class ScreenSaverFramePublisherTests: XCTestCase {
    private final class RecordingNotifier: ScreenSaverFrameNotifier, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [(String, UInt64)] = []
        var posts: [(String, UInt64)] { lock.withLock { stored } }
        func post(_ name: String, state: UInt64) { lock.withLock { stored.append((name, state)) } }
    }

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func publisher(_ notifier: RecordingNotifier) throws -> ScreenSaverFramePublisher {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return ScreenSaverFramePublisher(manifestURL: folder.appending(path: ScreenSaverLiveManifest.fileName),
                                         notifier: notifier, device: device)
    }

    func testPublishListsARingOfGlobalSurfacesPerLoop() throws {
        let publisher = try publisher(RecordingNotifier())
        let previous = publisher.current.generation
        try publisher.publish(sizes: [SIMD2(64, 32), SIMD2(16, 16)],
                              displays: [.init(display: nil, ring: 0)], frameRate: 30)
        let manifest = try XCTUnwrap(ScreenSaverLiveManifest.read(folder.appending(path: ScreenSaverLiveManifest.fileName)))
        XCTAssertEqual(manifest, publisher.current)
        XCTAssertEqual(manifest.generation, ScreenSaverFramePublisher.nextGeneration(after: previous))
        XCTAssertEqual(manifest.pid, getpid())
        XCTAssertEqual(manifest.frameRate, 30)
        XCTAssertEqual(manifest.rings.map(\.surfaces.count), [ScreenSaverFramePublisher.ringSize, ScreenSaverFramePublisher.ringSize])
        XCTAssertEqual(manifest.rings.map(\.notifyName), [ScreenSaverLiveNames.frameNotification(ring: 0),
                                                          ScreenSaverLiveNames.frameNotification(ring: 1)])
        for id in manifest.rings[0].surfaces {
            // What the `.saver`'s sandboxed host does with the ids.
            let surface = try XCTUnwrap(IOSurfaceLookup(id), "surface \(id) is global")
            XCTAssertEqual(IOSurfaceGetWidth(surface), 64)
            XCTAssertEqual(IOSurfaceGetHeight(surface), 32)
        }
        XCTAssertTrue(publisher.framesMessage.isConsistent)
        XCTAssertEqual(publisher.framesMessage.surfaces(ofRing: 1).map(\.width), [16, 16, 16])
    }

    func testFramesGoRoundTheRingAndAreStampedOnceDrawn() throws {
        let notifier = RecordingNotifier()
        let publisher = try publisher(notifier)
        let stamps = LockedValue<[(Int, UInt64)]>([])
        publisher.onStamp = { ring, stamp in stamps.mutate { $0.append((ring, stamp)) } }
        try publisher.publish(sizes: [SIMD2(8, 8)], displays: [.init(display: nil, ring: 0)], frameRate: 60)
        let generation = publisher.current.generation

        let slots = (0..<4).compactMap { _ in publisher.target(ring: 0)?.slot }
        XCTAssertEqual(slots, [0, 1, 2, 0], "the slot after the newest, round the ring")
        XCTAssertNil(publisher.target(ring: 5))
        XCTAssertTrue(notifier.posts.isEmpty, "nothing is announced before the GPU is done")

        publisher.drawn(ring: 0, slot: 1, generation: generation)
        publisher.drawn(ring: 0, slot: 2, generation: generation)
        publisher.drawn(ring: 0, slot: 0, generation: generation - 1) // A frame of older rings.
        XCTAssertEqual(notifier.posts.map(\.0), [ScreenSaverLiveNames.frameNotification(ring: 0),
                                                ScreenSaverLiveNames.frameNotification(ring: 0)])
        let posted = notifier.posts.compactMap { ScreenSaverLiveStamp(state: $0.1) }
        XCTAssertEqual(posted, [ScreenSaverLiveStamp(generation: ScreenSaverLiveStamp.generation(generation), frame: 1, slot: 1),
                                ScreenSaverLiveStamp(generation: ScreenSaverLiveStamp.generation(generation), frame: 2, slot: 2)])
        XCTAssertEqual(stamps.value.map(\.1), notifier.posts.map(\.1), "the extension gets the same stamps")
    }

    func testClearListsNothingAndNewRingsReachTheExtension() throws {
        let publisher = try publisher(RecordingNotifier())
        let messages = LockedValue<[LiveSaverFramesMessage]>([])
        publisher.onRings = { message in messages.mutate { $0.append(message) } }
        try publisher.publish(sizes: [SIMD2(8, 8)], displays: [.init(display: "A", ring: 0)], frameRate: 60)
        let live = publisher.current.generation
        publisher.clear()
        let manifest = try XCTUnwrap(ScreenSaverLiveManifest.read(folder.appending(path: ScreenSaverLiveManifest.fileName)))
        XCTAssertFalse(manifest.isLive)
        XCTAssertNotEqual(manifest.generation, live, "a stamp of the old rings matches nothing")
        XCTAssertNil(publisher.target(ring: 0))
        XCTAssertEqual(messages.value.map(\.manifest.isLive), [true, false])
        XCTAssertEqual(messages.value.map(\.surfaces.count), [3, 0])
    }

    func testGenerationsWrapPastZero() {
        XCTAssertEqual(ScreenSaverFramePublisher.nextGeneration(after: 4), 5)
        XCTAssertEqual(ScreenSaverFramePublisher.nextGeneration(after: 0xFFFF), 1)
    }

    // MARK: What a saver reads

    func testTheStoreShowsTheNewestFrameOfTheCurrentRings() throws {
        let publisher = try publisher(RecordingNotifier())
        try publisher.publish(sizes: [SIMD2(8, 8)], displays: [.init(display: "A", ring: 0,
                                                                     crop: ScreenSaverManifest.Crop(x: 0, y: 0, width: 0.5, height: 1))],
                              frameRate: 60)
        let message = publisher.framesMessage
        let store = LiveFrameStore()
        store.use(message.manifest, surfaces: [0: message.surfaces(ofRing: 0)])
        let generation = ScreenSaverLiveStamp.generation(message.manifest.generation)
        XCTAssertNil(store.newestFrame(display: "A", pixels: (8, 8)), "nothing drawn yet")

        store.show(ring: 0, stamp: ScreenSaverLiveStamp(generation: generation, frame: 5, slot: 2))
        store.show(ring: 0, stamp: ScreenSaverLiveStamp(generation: generation, frame: 4, slot: 1)) // Late: ignored.
        store.show(ring: 0, stamp: ScreenSaverLiveStamp(generation: generation &+ 1, frame: 9, slot: 0)) // Other rings.
        let frame = try XCTUnwrap(store.newestFrame(display: "A", pixels: (8, 8)))
        XCTAssertEqual(frame.stamp.frame, 5)
        XCTAssertEqual(IOSurfaceGetID(frame.surface), message.manifest.rings[0].surfaces[2])
        XCTAssertEqual(frame.crop?.width, 0.5)
        XCTAssertEqual(frame.frameRate, 60)
        XCTAssertNil(store.newestFrame(display: "B", pixels: (8, 8)), "B plays its video")
    }
}

/// A value shared with XPC's and Metal's threads.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
