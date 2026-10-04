import XCTest
@testable import OpenWallpaperEngine

/// The screen saver's layout (WE's `wallpaperconfigscreensaver`): its default, the loops each
/// layout plans on the displays (`ScreenSaverLayoutPlan`), the manifest's per-display videos and
/// crops, and the saver's choice among them.
final class ScreenSaverLayoutTests: XCTestCase {
    private typealias Plan = ScreenSaverLayoutPlan
    private typealias Plugin = ScreenSaverPlugin

    private let a = Plan.Display(screenId: "1", identity: "A", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 2)
    private let b = Plan.Display(screenId: "2", identity: "B", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), scale: 1)
    private let x = Plan.Content(id: "/x", properties: ["p": "1"])
    private let y = Plan.Content(id: "/y")

    private func plan(_ layout: ScreenSaverDisplayLayout, wallpaperLayout: DisplayLayoutMode = .perDisplay,
                      resolution: DisplayLayoutResolution = .empty, displays: [Plan.Display],
                      shown: [String: Plan.Content]) -> Plan {
        Plan(layout, wallpaperLayout: wallpaperLayout, resolution: resolution, displays: displays, shown: shown)
    }

    private func resolution(_ configuration: DisplayLayoutConfiguration, _ displays: [Plan.Display]) -> DisplayLayoutResolution {
        DisplayLayoutResolution(configuration, displays: displays.map {
            DisplayIdentity(screenId: $0.screenId, identity: $0.identity, frame: $0.frame)
        })
    }

    private func assertEqual(_ rect: CGRect?, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        guard let rect else { return XCTFail("no rect", file: file, line: line) }
        for (value, wanted) in [(rect.minX, expected.minX), (rect.minY, expected.minY),
                                (rect.width, expected.width), (rect.height, expected.height)] {
            XCTAssertEqual(value, wanted, accuracy: 1e-9, "\(rect) ≠ \(expected)", file: file, line: line)
        }
    }

    // MARK: Default

    func testTheDefaultIsSameAsWallpaper() throws {
        XCTAssertTrue(ScreenSaverDisplayLayout().sameAsWallpaper)
        let decoded = try JSONDecoder().decode(ScreenSaverDisplayLayout.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, ScreenSaverDisplayLayout())
        let name = "owe-screensaver-layout-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ScreenSaverDisplayLayout.load(from: defaults), ScreenSaverDisplayLayout())
        for layout in DisplayLayoutMode.allCases {
            XCTAssertEqual(decoded.effectiveLayout(wallpaperLayout: layout), layout, "follows the wallpapers' layout")
        }
        XCTAssertEqual(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .clone).effectiveLayout(wallpaperLayout: .stretch), .clone)
    }

    // MARK: Per display

    func testPerDisplayRecordsALoopPerShownWallpaper() {
        let plan = plan(ScreenSaverDisplayLayout(), displays: [a, b], shown: ["1": x, "2": y])
        XCTAssertEqual(plan.loops.map(\.content), [x, y])
        XCTAssertEqual(plan.loops.map(\.displays), [["A"], ["B"]])
        XCTAssertEqual(plan.loops[0].sizes, [Plan.Size(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080))])
        XCTAssertTrue(plan.loops.allSatisfy { $0.canvas == nil && $0.crops.isEmpty })
    }

    func testDisplaysShowingTheSameWallpaperShareOneLoop() {
        let plan = plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .perDisplay), displays: [a, b],
                        shown: ["1": x, "2": x])
        XCTAssertEqual(plan.loops.count, 1)
        XCTAssertEqual(plan.loops[0].displays, ["A", "B"])
        XCTAssertEqual(plan.loops[0].sizes.count, 2, "recorded at the largest of both")
        XCTAssertEqual(plan.displays, ["A", "B"])
    }

    func testOtherPropertiesAreAnotherLoop() {
        let plan = plan(ScreenSaverDisplayLayout(), displays: [a, b], shown: ["1": x, "2": Plan.Content(id: "/x")])
        XCTAssertEqual(plan.loops.count, 2)
    }

    func testASplitDisplayPlaysItsFirstRegionsWallpaper() {
        var configuration = DisplayLayoutConfiguration()
        configuration.setSplit(DisplaySplit(), at: "A")
        let resolution = resolution(configuration, [a, b])
        let regions = resolution.regions["1"] ?? []
        XCTAssertGreaterThanOrEqual(regions.count, 2)
        let displayed = [regions[0].id: x, regions[1].id: y, "2": y]
        XCTAssertEqual(Plan.shown(displayed, screenIds: ["1", "2"], resolution: resolution), ["1": x, "2": y])
    }

    // MARK: Clone

    func testCloneLayoutPlaysTheMainDisplaysLoopEverywhere() {
        let plan = plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .clone), displays: [a, b],
                        shown: ["1": x, "2": y])
        XCTAssertEqual(plan.loops.map(\.content), [x])
        XCTAssertEqual(plan.loops[0].displays, ["A", "B"])
        XCTAssertNil(plan.loops[0].canvas)
    }

    func testSameAsWallpaperClonesTheWallpapersCloneSource() {
        var configuration = DisplayLayoutConfiguration(layout: .clone)
        configuration.setCloneSource("B", isSource: true, connected: ["A", "B"])
        let resolution = resolution(configuration, [a, b])
        let source = resolution.clones.first?.source
        XCTAssertNotNil(source)
        let shown = resolution.shown(["1": x, "2": y])
        let plan = plan(ScreenSaverDisplayLayout(), wallpaperLayout: .clone, resolution: resolution, displays: [a, b], shown: shown)
        XCTAssertEqual(plan.loops.count, 1)
        XCTAssertEqual(plan.loops[0].content, source == "2" ? y : x)
        XCTAssertEqual(plan.loops[0].displays, ["A", "B"])
    }

    // MARK: Stretch

    func testStretchRecordsOneLoopAtTheCanvasWithEachDisplaysCrop() throws {
        // Mixed resolutions, one display left of and above the main one, a gap on the right.
        let main = Plan.Display(screenId: "1", identity: "A", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1)
        let left = Plan.Display(screenId: "2", identity: "B", frame: CGRect(x: -1280, y: 200, width: 1280, height: 1024), scale: 1)
        let right = Plan.Display(screenId: "3", identity: "C", frame: CGRect(x: 2000, y: 0, width: 1920, height: 1080), scale: 1)
        let plan = plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .stretch), displays: [main, left, right],
                        shown: ["1": x, "2": y, "3": y])
        XCTAssertEqual(plan.loops.count, 1)
        let loop = try XCTUnwrap(plan.loops.first)
        XCTAssertEqual(loop.content, x, "the main display's wallpaper")
        XCTAssertEqual(loop.canvas, CGRect(x: -1280, y: 0, width: 5200, height: 1224))
        XCTAssertEqual(loop.sizes, [Plan.Size(pixels: SIMD2(5200, 1224), points: SIMD2(5200, 1224))])
        XCTAssertEqual(loop.displays, ["A", "B", "C"])
        assertEqual(loop.crops["A"], CGRect(x: 1280.0 / 5200, y: 144.0 / 1224, width: 1920.0 / 5200, height: 1080.0 / 1224))
        assertEqual(loop.crops["B"], CGRect(x: 0, y: 0, width: 1280.0 / 5200, height: 1024.0 / 1224))
        assertEqual(loop.crops["C"], CGRect(x: 3280.0 / 5200, y: 144.0 / 1224, width: 1920.0 / 5200, height: 1080.0 / 1224))

        // The manifest lists the one file once per display, each with its crop.
        let videos = Plugin.manifestVideos(for: loop, file: "s.mov", size: SIMD2(5200, 1224), rate: nil, everyDisplay: true)
        XCTAssertEqual(videos.map(\.file), ["s.mov", "s.mov", "s.mov"])
        XCTAssertEqual(videos.map(\.displays), [["A"], ["B"], ["C"]])
        let crop = try XCTUnwrap(videos.first?.crop)
        XCTAssertEqual(crop.x, 1280.0 / 5200, accuracy: 1e-9)
        XCTAssertEqual(crop.height, 1080.0 / 1224, accuracy: 1e-9)
    }

    func testAStretchOnRetinaDisplaysIsFittedAndEven() throws {
        let wide = (0..<3).map {
            Plan.Display(screenId: "\($0)", identity: "D\($0)", frame: CGRect(x: CGFloat($0) * 2560, y: 0, width: 2560, height: 1441), scale: 2)
        }
        let plan = plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .stretch), displays: wide, shown: ["0": x])
        let size = try XCTUnwrap(plan.loops.first?.sizes.first)
        XCTAssertLessThanOrEqual(max(size.pixels.x, size.pixels.y), Int(Plan.maximumDimension))
        XCTAssertEqual(size.pixels.x % 2, 0)
        XCTAssertEqual(size.pixels.y % 2, 0)
        XCTAssertEqual(size.points.y % 2, 0)
    }

    func testSameAsWallpaperKeepsTheWallpapersStretchGroup() {
        let c = Plan.Display(screenId: "3", identity: "C", frame: CGRect(x: 4480, y: 0, width: 1920, height: 1080), scale: 2)
        var configuration = DisplayLayoutConfiguration()
        configuration.addGroup(["A", "B"], layout: .stretch)
        let resolution = resolution(configuration, [a, b, c])
        let shown = resolution.shown(["1": x, "3": y])
        let plan = plan(ScreenSaverDisplayLayout(), resolution: resolution, displays: [a, b, c], shown: shown)
        XCTAssertEqual(plan.loops.map(\.content), [y, x])
        XCTAssertEqual(plan.loops.map(\.displays), [["C"], ["A", "B"]])
        XCTAssertNil(plan.loops[0].canvas)
        XCTAssertEqual(plan.loops[1].canvas, CGRect(x: 0, y: 0, width: 4480, height: 1440))

        let own = self.plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .perDisplay), resolution: resolution,
                            displays: [a, b, c], shown: shown)
        XCTAssertTrue(own.loops.allSatisfy { $0.canvas == nil }, "its own per-display layout has no groups")
    }

    func testAStretchOnOneDisplayShowsTheWholeLoop() {
        let plan = plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .stretch), displays: [a], shown: ["1": x])
        XCTAssertEqual(plan.loops.count, 1)
        XCTAssertNil(plan.loops[0].canvas)
    }

    // MARK: Video wallpapers

    func testAVideoWallpapersStretchPlaysItsOwnFileCropped() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "owe-ss-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a real movie".utf8).write(to: directory.appending(path: "clip.mp4"))
        let video = WEWallpaper(using: WEProject(file: "clip.mp4", preview: "p.jpg", title: "t", type: "video"), where: directory)
        let content = Plan.Content(id: directory.standardizedFileURL.path)
        let plan = plan(ScreenSaverDisplayLayout(sameAsWallpaper: false, layout: .stretch), displays: [a, b],
                        shown: ["1": content])
        let store = ScreenSaverVideoStore(directory: directory.appending(path: "Store"))
        let work = Plugin.work(for: plan, wallpapers: [content.id: video], resolution: .display, store: store)
        XCTAssertTrue(work.renders.isEmpty, "a video plays its own file: nothing is rendered")
        XCTAssertEqual(work.videos.count, 1)
        let entry = try XCTUnwrap(work.entries.first)
        XCTAssertTrue(entry.isVideo)
        XCTAssertEqual(entry.file, work.videos.first?.file)

        // A 16:9 file filling the 4480×1440 canvas: its middle band, split between the displays.
        let videos = Plugin.manifestVideos(for: entry.loop, file: entry.file, size: SIMD2(1920, 1080), rate: 1, everyDisplay: true)
        XCTAssertEqual(videos.map(\.file), [entry.file, entry.file])
        XCTAssertEqual(videos.map(\.displays), [["A"], ["B"]])
        let band = (1920.0 / 1080) / (4480.0 / 1440)
        let crops = videos.compactMap(\.crop)
        XCTAssertEqual(crops.count, 2)
        XCTAssertEqual(crops[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(crops[0].width, 1920.0 / 4480, accuracy: 1e-9)
        XCTAssertEqual(crops[1].x + crops[1].width, 1, accuracy: 1e-9)
        XCTAssertEqual(crops[1].height, band, accuracy: 1e-9, "B is the canvas's full height")
        XCTAssertEqual(crops[1].y, (1 - band) / 2, accuracy: 1e-9)
        // Each crop has its display's aspect, so the saver scales it without distortion.
        XCTAssertEqual(crops[0].width * 1920 / (crops[0].height * 1080), 1920.0 / 1080, accuracy: 1e-9)
        XCTAssertEqual(crops[1].width * 1920 / (crops[1].height * 1080), 2560.0 / 1440, accuracy: 1e-9)
    }

    func testASceneRendersOnceForDisplaysSharingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "owe-ss-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appending(path: "scene.json"))
        let scene = WEWallpaper(using: WEProject(file: "scene.json", preview: "p.jpg", title: "t", type: "scene"), where: directory)
        let content = Plan.Content(id: directory.standardizedFileURL.path)
        let plan = plan(ScreenSaverDisplayLayout(), displays: [a, b], shown: ["1": content, "2": content])
        let store = ScreenSaverVideoStore(directory: directory.appending(path: "Store"))
        let work = Plugin.work(for: plan, wallpapers: [content.id: scene], resolution: .retina, store: store)
        XCTAssertEqual(work.renders.count, 1)
        XCTAssertEqual(work.renders.first?.target.pixelSize, SIMD2(3840, 2160), "the largest of both displays")
        XCTAssertEqual(work.entries.first?.size, SIMD2(3840, 2160))
        let videos = Plugin.manifestVideos(for: try XCTUnwrap(work.entries.first).loop, file: "f.mov", size: SIMD2(3840, 2160),
                                           rate: nil, everyDisplay: true)
        XCTAssertEqual(videos, [ScreenSaverManifest.Video(file: "f.mov", width: 3840, height: 2160)], "plays on any display")
    }

    // MARK: Saver

    func testTheSaverPicksItsDisplaysVideo() {
        let manifest = ScreenSaverManifest(videos: [
            .init(file: "a.mov", width: 3840, height: 2160, displays: ["A"]),
            .init(file: "b.mov", width: 3840, height: 2160, displays: ["B"]),
            .init(file: "any.mov", width: 1920, height: 1080),
        ])
        XCTAssertEqual(manifest.video(forDisplay: "A", pixels: (3840, 2160))?.file, "a.mov")
        XCTAssertEqual(manifest.video(forDisplay: "B", pixels: (1920, 1080))?.file, "b.mov")
        XCTAssertEqual(manifest.video(forDisplay: "C", pixels: (3840, 2160))?.file, "any.mov", "a new display")
        XCTAssertEqual(manifest.video(forDisplay: nil, pixels: (3840, 2160))?.file, "any.mov")

        let stretched = ScreenSaverManifest(videos: [
            .init(file: "s.mov", width: 3840, height: 1080, displays: ["A"], crop: .init(x: 0, y: 0, width: 0.5, height: 1)),
            .init(file: "s.mov", width: 3840, height: 1080, displays: ["B"], crop: .init(x: 0.5, y: 0, width: 0.5, height: 1)),
        ])
        XCTAssertEqual(stretched.video(forDisplay: "B", pixels: (1920, 1080))?.crop?.x, 0.5)
        XCTAssertNotNil(stretched.video(forDisplay: "C", pixels: (1920, 1080)), "an unknown display still plays something")
    }

    func testACropFillsTheView() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let right = ScreenSaverManifest.Crop(x: 0.5, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(right.playerFrame(in: bounds), CGRect(x: -100, y: 0, width: 200, height: 50))
        // The top half (crops run from the top-left; the view's origin is bottom-left).
        let top = ScreenSaverManifest.Crop(x: 0, y: 0, width: 1, height: 0.5)
        XCTAssertEqual(top.playerFrame(in: bounds), CGRect(x: 0, y: -50, width: 100, height: 100))
    }

    func testAnOlderManifestStillDecodesAndPlaysEverywhere() throws {
        let json = #"{"revision":1,"videos":[{"file":"a.mov","width":1920,"height":1080}]}"#
        let manifest = try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(json.utf8))
        XCTAssertNil(manifest.videos.first?.displays)
        XCTAssertNil(manifest.videos.first?.crop)
        XCTAssertEqual(manifest.video(forDisplay: "A", pixels: (3840, 2160))?.file, "a.mov")
        XCTAssertEqual(ScreenSaverManifest.revision, 1)
        // Entries without displays or a crop are written as before.
        let written = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        XCTAssertFalse(written.contains("displays"))
        XCTAssertFalse(written.contains("crop"))
    }
}
