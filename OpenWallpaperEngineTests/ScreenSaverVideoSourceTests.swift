import XCTest
@testable import OpenWallpaperEngine

/// Video wallpapers' screen saver: eligibility per container and codec, the store entry (a link
/// to the library file), the manifest entry and the Details status.
final class ScreenSaverVideoSourceTests: XCTestCase {
    private typealias Plugin = ScreenSaverPlugin
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ScreenSaverVideoSourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func wallpaper(file: String, type: String = "video", directory: URL? = nil) -> WEWallpaper {
        WEWallpaper(using: WEProject(file: file, preview: "p.jpg", title: "t", type: type), where: directory ?? root)
    }

    // MARK: - Synthetic MP4

    private static func box(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        data.appendMP4(UInt32(payload.count + 8))
        data.appendMP4FourCC(type)
        data.append(payload)
        return data
    }

    private static func fullBox(_ type: String, _ payload: Data) -> Data {
        box(type, Data([0, 0, 0, 0]) + payload)
    }

    /// An MP4 whose one track has a sample entry of `entryType` (no samples).
    private func mp4(entryType: String, name: String) throws -> URL {
        var count = Data()
        count.appendMP4(UInt32(1))
        let stsd = Self.fullBox("stsd", count + Self.box(entryType, Data(count: 78)))
        let trak = Self.box("trak", Self.box("mdia", Self.box("minf", Self.box("stbl", stsd))))
        var brand = Data("isom".utf8)
        brand.appendMP4(UInt32(512))
        let data = Self.box("ftyp", brand + Data("isomiso2mp41".utf8))
            + Self.box("moov", Self.fullBox("mvhd", Data(count: 96)) + trak)
            + Self.box("mdat", Data())
        let url = root.appending(path: name)
        try data.write(to: url)
        return url
    }

    // MARK: - Eligibility

    func testEligibilityPerContainer() {
        for file in ["video.mp4", "video.MOV", "video.m4v"] {
            XCTAssertTrue(Plugin.isEligible(wallpaper(file: file)), file)
        }
        for file in ["video.webm", "video.mkv", "https://example.com/video.mp4"] {
            XCTAssertFalse(Plugin.isEligible(wallpaper(file: file)), file)
        }
        XCTAssertFalse(Plugin.isEligible(wallpaper(file: "index.html", type: "web")))
        XCTAssertTrue(Plugin.isEligible(wallpaper(file: "scene.json", type: "scene")))
    }

    func testEligibilityPerCodec() {
        for codec in ["avc1", "avc3", "hvc1", "hev1"] {
            XCTAssertTrue(ScreenSaverVideoSource.isPlayable(sampleEntryTypes: [codec, "mp4a"]), codec)
        }
        for codec in ["vp09", "vp08", "av01", "mp4v"] {
            XCTAssertFalse(ScreenSaverVideoSource.isPlayable(sampleEntryTypes: [codec, "mp4a"]), codec)
        }
        XCTAssertTrue(ScreenSaverVideoSource.needsRepair(sampleEntryTypes: ["hev1"]))
        XCTAssertTrue(ScreenSaverVideoSource.needsRepair(sampleEntryTypes: ["avc3"]))
        XCTAssertFalse(ScreenSaverVideoSource.needsRepair(sampleEntryTypes: ["hvc1", "avc1", "mp4a"]))
    }

    func testVideosHaveNoRenderTargets() {
        let screens = [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080))]
        XCTAssertTrue(Plugin.targets(for: wallpaper(file: "video.mp4"), screens: screens, properties: [:]).isEmpty)
    }

    // MARK: - Store entry

    func testPlayableFileIsLinkedNotCopied() throws {
        let source = try mp4(entryType: "hvc1", name: "video.mp4")
        let destination = root.appending(path: "store/entry.mp4")
        XCTAssertEqual(ScreenSaverVideoSource.prepare(source, at: destination), .ready(repaired: false))
        let path = destination.path(percentEncoded: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))
        let isSymlink = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
        // Same volume: a hard link (same inode); otherwise a symbolic link.
        XCTAssertTrue(isSymlink || (attributes[.systemFileNumber] as? NSNumber) == (sourceAttributes[.systemFileNumber] as? NSNumber))
        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: source))
    }

    func testPreparingAgainReplacesTheEntry() throws {
        let source = try mp4(entryType: "avc1", name: "video.mov")
        let destination = root.appending(path: "store/entry.mov")
        XCTAssertEqual(ScreenSaverVideoSource.prepare(source, at: destination), .ready(repaired: false))
        XCTAssertEqual(ScreenSaverVideoSource.prepare(source, at: destination), .ready(repaired: false))
    }

    func testUnsupportedCodecIsNotLinked() throws {
        let source = try mp4(entryType: "vp09", name: "video.mp4")
        let destination = root.appending(path: "store/entry.mp4")
        XCTAssertEqual(ScreenSaverVideoSource.prepare(source, at: destination), .unsupported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    func testCodecCheckUpFront() throws {
        XCTAssertTrue(ScreenSaverVideoSource.hasPlayableTrack(try mp4(entryType: "hev1", name: "a.mp4")))
        let vp9 = try mp4(entryType: "vp09", name: "b.mp4")
        XCTAssertFalse(ScreenSaverVideoSource.hasPlayableTrack(vp9))
        XCTAssertFalse(ScreenSaverVideoSource.hasPlayableTrack(vp9), "cached")
        // A new version of the same file is read again.
        _ = try mp4(entryType: "avc1", name: "b.mp4")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)],
                                              ofItemAtPath: vp9.path(percentEncoded: false))
        XCTAssertTrue(ScreenSaverVideoSource.hasPlayableTrack(vp9))
        XCTAssertFalse(ScreenSaverVideoSource.hasPlayableTrack(root.appending(path: "missing.mp4")))
    }

    func testUnreadableFileIsUnsupported() throws {
        let source = root.appending(path: "broken.mp4")
        try Data("not a movie".utf8).write(to: source)
        XCTAssertEqual(ScreenSaverVideoSource.prepare(source, at: root.appending(path: "store/x.mp4")), .unsupported)
    }

    func testFileNameKeepsTheExtensionAndKey() {
        let key = Plugin.StatusKey(wallpaperKey: "w", contentKey: "c", propertyHash: "h")
        XCTAssertEqual(ScreenSaverVideoSource.fileName(key: key, source: URL(filePath: "/x/Video.MOV")),
                       "w_c-video-r\(ScreenSaverVideoStore.revision).mov")
    }

    // MARK: - Manifest

    func testManifestEntryUsesTheTrackSizeAndSpeed() throws {
        let manifest = Plugin.videoManifest(fileName: "a.mp4", size: SIMD2(1080, 1920), rate: 1)
        XCTAssertEqual(manifest.videos, [ScreenSaverManifest.Video(file: "a.mp4", width: 1080, height: 1920)])
        XCTAssertNil(manifest.videos.first?.rate)
        XCTAssertEqual(Plugin.videoManifest(fileName: "a.mp4", size: SIMD2(1, 1), rate: 1.5).videos.first?.rate, 1.5)
        XCTAssertNil(Plugin.videoManifest(fileName: "a.mp4", size: SIMD2(1, 1), rate: 0).videos.first?.rate)
    }

    func testManifestWithoutRateStillDecodes() throws {
        let json = #"{"revision":1,"videos":[{"file":"a.mov","width":1920,"height":1080}]}"#
        let manifest = try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(json.utf8))
        XCTAssertNil(manifest.videos.first?.rate)
    }

    // MARK: - Status

    func testVideoStatus() throws {
        _ = try mp4(entryType: "avc1", name: "video.mp4")
        let video = wallpaper(file: "video.mp4")
        let key = try XCTUnwrap(Plugin.statusKey(for: video, properties: ["ignored": "1"]))
        XCTAssertEqual(key.propertyHash, ScreenSaverVideoStore.propertyHash([:]), "a video's properties don't change its file")
        XCTAssertNil(Plugin.status(for: video, enabled: true, statuses: [:]))
        XCTAssertEqual(Plugin.status(for: video, enabled: true, statuses: [key: .rendering]), .rendering)
        XCTAssertEqual(Plugin.status(for: video, enabled: true, statuses: [key: .available]), .available)
        XCTAssertEqual(Plugin.status(for: video, enabled: true, statuses: [key: .notEligible]), .notEligible,
                       "a codec AVFoundation can't play")
        XCTAssertNil(Plugin.status(for: video, enabled: false, statuses: [key: .available]))
        XCTAssertEqual(Plugin.status(for: wallpaper(file: "video.webm"), enabled: true, statuses: [:]), .notEligible)
    }
}
