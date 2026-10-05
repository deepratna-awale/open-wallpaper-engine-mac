import XCTest
@testable import OpenWallpaperEngine

final class ScreenSaverLoopTests: XCTestCase {
    private typealias Period = ScreenSaverLoopLength.Period

    // MARK: Periods

    func testTimelinePeriodIsLengthOverFPSAndMirrorDoublesIt() throws {
        let loop = try XCTUnwrap(Period(timelineLength: 60, fps: 30, mirrored: false))
        XCTAssertEqual(loop.seconds, 2, accuracy: 1e-9)
        let mirror = try XCTUnwrap(Period(timelineLength: 60, fps: 30, mirrored: true))
        XCTAssertEqual(mirror.seconds, 4, accuracy: 1e-9)
        XCTAssertNil(Period(timelineLength: 60, fps: 0, mirrored: false))
        XCTAssertNil(Period(timelineLength: 0, fps: 30, mirrored: false))
    }

    func testSpriteSheetPeriodIsTheSumOfItsFrameTimes() throws {
        let period = try XCTUnwrap(Period(frameTimes: [0.1, 0.1, 0.1, 0.2]))
        XCTAssertEqual(period.seconds, 0.5, accuracy: 1e-9)
    }

    func testLeastCommonMultipleOfFractions() throws {
        // 2 s and 3 s loop together every 6 s; 1.5 s and 2 s every 6 s.
        let a = try XCTUnwrap(Period(numerator: 2, denominator: 1))
        let b = try XCTUnwrap(Period(numerator: 3, denominator: 1))
        let c = try XCTUnwrap(Period(numerator: 3, denominator: 2))
        XCTAssertEqual(ScreenSaverLoopLength.leastCommonMultiple([a, b])?.seconds, 6)
        XCTAssertEqual(ScreenSaverLoopLength.leastCommonMultiple([c, a])?.seconds, 6)
        XCTAssertNil(ScreenSaverLoopLength.leastCommonMultiple([]))
    }

    func testPeriodicLoopIsAWholeNumberOfFramesEndingBeforeFrameZero() throws {
        let periods = [try XCTUnwrap(Period(timelineLength: 60, fps: 30, mirrored: false)),
                       try XCTUnwrap(Period(frameTimes: [0.5, 0.5, 0.5]))]
        let loop = try XCTUnwrap(ScreenSaverLoopLength.periodicLoop(periods))
        // lcm(2 s, 1.5 s) = 6 s = 180 frames at 30 fps: frame 180 is frame 0 again.
        XCTAssertEqual(loop, ScreenSaverLoopLength.Loop(frames: 180, frameRate: 30))
    }

    func testPeriodicLoopTakesAFrameRateThatCutsItExactly() throws {
        // 1/24 s × 25 frames isn't a whole number of frames at 30 fps.
        let period = try XCTUnwrap(Period(numerator: 25, denominator: 24))
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop([period]), ScreenSaverLoopLength.Loop(frames: 25, frameRate: 24))
    }

    func testPeriodicLoopIsCappedAtThirtySecondsAndThirtyFPS() throws {
        XCTAssertEqual(ScreenSaverLoopLength.maximumSeconds, 30)
        XCTAssertEqual(ScreenSaverSeamFinder.maximumSeconds, 30)
        XCTAssertTrue(ScreenSaverLoopLength.frameRates.allSatisfy { $0 <= 30 })
        let five = try XCTUnwrap(Period(numerator: 5, denominator: 1))
        let seven = try XCTUnwrap(Period(numerator: 7, denominator: 1))
        XCTAssertNil(ScreenSaverLoopLength.periodicLoop([five, seven]), "35 s is over the cap")
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop([five, seven], maximumSeconds: 40)?.seconds, 35)
        let thirty = try XCTUnwrap(Period(numerator: 30, denominator: 1))
        XCTAssertEqual(ScreenSaverLoopLength.periodicLoop([thirty]), ScreenSaverLoopLength.Loop(frames: 900, frameRate: 30))
        // 1/60 s × 61 frames needs 60 fps to cut exactly: no loop, so the seam is searched at 30.
        let sixtieths = try XCTUnwrap(Period(numerator: 61, denominator: 60))
        XCTAssertNil(ScreenSaverLoopLength.periodicLoop([sixtieths]))
    }

    // MARK: Seam

    func testBestFrameIsTheClosestMatchAfterTheMinimum() {
        // 1 fps for readability: frames 0…9, minimum 5 s.
        let differences = [0, 0.001, 0.2, 0.3, 0.2, 0.15, 0.05, 0.02, 0.03, 0.1]
        XCTAssertEqual(ScreenSaverSeamFinder.bestFrame(differences: differences, frameRate: 1), 7,
                       "frame 1 matches better but is before the minimum")
        XCTAssertNil(ScreenSaverSeamFinder.bestFrame(differences: Array(differences.prefix(5)), frameRate: 1))
    }

    func testBestFrameTakesTheEarliestOnATie() {
        let differences = [0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.01, 0.01, 0.4]
        XCTAssertEqual(ScreenSaverSeamFinder.bestFrame(differences: differences, frameRate: 1), 6)
    }

    func testAnInvisibleSeamCutsAndAVisibleOneCrossfades() {
        XCTAssertEqual(ScreenSaverSeamFinder.seam(difference: 0.005, frameRate: 30, loopFrames: 300), .cut)
        XCTAssertEqual(ScreenSaverSeamFinder.seam(difference: 0.08, frameRate: 30, loopFrames: 300), .crossfade(frames: 8))
        XCTAssertEqual(ScreenSaverSeamFinder.seam(difference: 0.08, frameRate: 30, loopFrames: 6), .crossfade(frames: 3),
                       "a crossfade never takes more than half the loop")
    }

    func testDecisionCombinesBestFrameAndSeam() {
        var differences = [Double](repeating: 0.3, count: 400)
        differences[0] = 0
        differences[200] = 0.002
        XCTAssertEqual(ScreenSaverSeamFinder.decide(differences: differences, frameRate: 30),
                       .init(frames: 200, seam: .cut))
        differences[200] = 0.05
        XCTAssertEqual(ScreenSaverSeamFinder.decide(differences: differences, frameRate: 30),
                       .init(frames: 200, seam: .crossfade(frames: 8)))
    }

    func testCrossfadeWeightRisesOverTheLastFramesOnly() {
        XCTAssertEqual(ScreenSaverSeamFinder.crossfadeWeight(index: 5, loopFrames: 10, fade: 4), 0)
        XCTAssertEqual(ScreenSaverSeamFinder.crossfadeWeight(index: 6, loopFrames: 10, fade: 4), 0.2, accuracy: 1e-9)
        XCTAssertEqual(ScreenSaverSeamFinder.crossfadeWeight(index: 9, loopFrames: 10, fade: 4), 0.8, accuracy: 1e-9)
        XCTAssertEqual(ScreenSaverSeamFinder.crossfadeWeight(index: 9, loopFrames: 10, fade: 0), 0)
    }

    func testFrameSignatureDifference() throws {
        let black = try XCTUnwrap(ScreenSaverFrameSignature(Self.image(gray: 0)))
        let white = try XCTUnwrap(ScreenSaverFrameSignature(Self.image(gray: 255)))
        XCTAssertEqual(black.difference(black), 0)
        XCTAssertGreaterThan(black.difference(white), 0.4)
        XCTAssertEqual(black.difference(ScreenSaverFrameSignature(values: [])), 1)
    }

    private static func image(gray: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: CGFloat(gray) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        return context.makeImage()!
    }
}

final class ScreenSaverStorageTests: XCTestCase {
    func testPropertyHashIgnoresOrderAndFollowsValues() {
        let a = ScreenSaverVideoStore.propertyHash(["speed": "1", "color": "0 0 1"])
        let b = ScreenSaverVideoStore.propertyHash(["color": "0 0 1", "speed": "1"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, ScreenSaverVideoStore.propertyHash(["speed": "2", "color": "0 0 1"]))
    }

    func testFileNameKeysWallpaperPropertiesSizeAndRevision() {
        let name = ScreenSaverVideoStore.fileName(wallpaperKey: "123-abc", contentKey: "c0ffee", propertyHash: "beef",
                                                  pixelSize: SIMD2(3840, 2160))
        XCTAssertEqual(name, "123-abc_c0ffee-beef-3840x2160-r\(ScreenSaverVideoStore.revision).mov")
        XCTAssertNotEqual(name, ScreenSaverVideoStore.fileName(wallpaperKey: "123-abc", contentKey: "c0ffee",
                                                               propertyHash: "beef", pixelSize: SIMD2(2560, 1440)))
        XCTAssertNotEqual(name, ScreenSaverVideoStore.fileName(wallpaperKey: "123-abc", contentKey: "d00d",
                                                               propertyHash: "beef", pixelSize: SIMD2(3840, 2160)))
    }

    func testIsolatedCopiesWriteWhereNoSaverReads() throws {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let isolated = ScreenSaverVideoStore(location: AppStorageLocation(isolationTag: "screensaver-test"), home: home)
        XCTAssertFalse(isolated.directory.path.hasPrefix(ScreenSaverManifest.sharedFolder(home: home).path))
        XCTAssertTrue(isolated.directory.path.contains("isolated screensaver-test"))
        let user = ScreenSaverVideoStore(location: AppStorageLocation(isolationTag: nil), home: home)
        XCTAssertEqual(user.directory, ScreenSaverManifest.sharedFolder(home: home))
        XCTAssertTrue(user.directory.path.hasPrefix(
            "/Users/someone/Library/Application Support/Open Wallpaper Engine/ScreenSaver"))
        // The test host itself is isolated.
        XCTAssertNotEqual(ScreenSaverVideoStore.current.directory, ScreenSaverManifest.sharedFolder(home: ScreenSaverManifest.userHome))
    }

    func testSaverReadsTheRealHomeNotItsContainer() {
        XCTAssertFalse(ScreenSaverManifest.userHome.path.contains("/Library/Containers/"))
        XCTAssertEqual(ScreenSaverManifest.userHome.standardizedFileURL,
                       URL(filePath: NSHomeDirectoryForUser(NSUserName()) ?? "", directoryHint: .isDirectory).standardizedFileURL)
    }

    func testInstallerNeverTouchesTheUsersSaversWhenIsolated() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundled = folder.appending(path: "bundled.saver", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let savers = folder.appending(path: "Screen Savers", directoryHint: .isDirectory)
        let isolated = ScreenSaverInstaller(bundledSaver: bundled, saversDirectory: savers, mayInstall: false)
        XCTAssertFalse(isolated.install())
        XCTAssertFalse(isolated.isInstalled)
        XCTAssertFalse(ScreenSaverInstaller.current.mayInstall, "the test host is isolated")
        let user = ScreenSaverInstaller(bundledSaver: bundled, saversDirectory: savers, mayInstall: true)
        XCTAssertTrue(user.install())
        XCTAssertTrue(user.isInstalled)
        user.uninstall()
        XCTAssertFalse(user.isInstalled)
    }

    func testRetainKeepsTheManifestAndListedVideosOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenSaverVideoStore(directory: folder)
        try store.writeManifest(ScreenSaverManifest(videos: [.init(file: "new.mov", width: 1, height: 1)]))
        for name in ["new.mov", "old.mov", ".partial-new.mov"] { try Data().write(to: store.url(fileName: name)) }
        store.retain(["new.mov"])
        XCTAssertTrue(store.exists(fileName: "new.mov"))
        XCTAssertTrue(store.exists(fileName: ScreenSaverManifest.fileName))
        XCTAssertFalse(store.exists(fileName: "old.mov"))
        XCTAssertFalse(store.exists(fileName: ".partial-new.mov"))
        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testManifestPicksTheVideoForTheViewSize() {
        let manifest = ScreenSaverManifest(videos: [.init(file: "4k.mov", width: 3840, height: 2160),
                                                    .init(file: "air.mov", width: 2560, height: 1664),
                                                    .init(file: "qhd.mov", width: 2560, height: 1440)])
        XCTAssertEqual(manifest.video(forPixels: (2560, 1440))?.file, "qhd.mov")
        XCTAssertEqual(manifest.video(forPixels: (5120, 2880))?.file, "4k.mov", "same aspect first")
        XCTAssertEqual(manifest.video(forPixels: (2940, 1912))?.file, "air.mov")
        XCTAssertNil(ScreenSaverManifest().video(forPixels: (100, 100)))
    }

    func testHelperRunArgumentsAreReadOnlyHelperRuns() {
        XCTAssertTrue(ShaderPrewarmCommand.isHelperRun(arguments: ["app", ShaderPrewarmCommand.screenSaverArgument]))
        XCTAssertEqual(ShaderPrewarmCommand.size("3840x2160"), SIMD2(3840, 2160))
        XCTAssertNil(ShaderPrewarmCommand.size("3840"))
        XCTAssertNil(ShaderPrewarmCommand.size("0x10"))
    }

    func testOneLoopAtTheLargestDisplaysPointSize() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "scene.json"))
        let wallpaper = WEWallpaper(using: WEProject(file: "scene.json", title: "Loop", type: "scene"), where: folder)
        let targets = ScreenSaverPlugin.targets(
            for: wallpaper,
            screens: [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080)),
                      (pixels: SIMD2(2560, 1600), points: SIMD2(2560, 1600)),
                      (pixels: SIMD2(1920, 1080), points: SIMD2(1920, 1080))],
            properties: [:])
        XCTAssertEqual(targets.map(\.pixelSize), [SIMD2(2560, 1600)], "one video, at the largest display's points")
        XCTAssertEqual(targets.first?.pointSize, SIMD2(2560, 1600))
    }

    func testTheLoopFollowsRenderResolution() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "scene.json"))
        let wallpaper = WEWallpaper(using: WEProject(file: "scene.json", title: "Loop", type: "scene"), where: folder)
        let screens = [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080)),
                       (pixels: SIMD2(1920, 1080), points: SIMD2(1920, 1080))]
        for (resolution, size) in [(GSRenderResolution.display, SIMD2(1920, 1080)),
                                   (.retina, SIMD2(3840, 2160)), (.full, SIMD2(3840, 2160))] {
            let targets = ScreenSaverPlugin.targets(for: wallpaper, screens: screens, properties: [:], resolution: resolution)
            XCTAssertEqual(targets.map(\.pixelSize), [size], "\(resolution)")
            XCTAssertEqual(targets.first?.pointSize, SIMD2(1920, 1080), "\(resolution)")
        }
    }
}
