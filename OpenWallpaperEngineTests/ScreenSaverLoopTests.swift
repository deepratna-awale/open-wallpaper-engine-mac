import XCTest
@testable import OpenWallpaperEngine

/// The loops' crossfade and frame signature the exports use, and the screen saver's folder:
/// names, isolation, pruning and the manifest.
final class ScreenSaverLoopTests: XCTestCase {
    // MARK: Seam

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

    func testRetainKeepsTheManifestsAndListedVideosOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenSaverVideoStore(directory: folder)
        try store.writeManifest(ScreenSaverManifest(videos: [.init(file: "new.mov", width: 1, height: 1)]))
        let stills = [ScreenSaverStills.fileName, "still-A.heic", "still-pick.jpg", ".1F2E-still-B.heic"]
        for name in ["new.mov", "old.mov", ".partial-new.mov", ScreenSaverLiveManifest.fileName] + stills {
            try Data().write(to: store.url(fileName: name))
        }
        store.retain(["new.mov"])
        XCTAssertTrue(store.exists(fileName: "new.mov"))
        XCTAssertTrue(store.exists(fileName: ScreenSaverManifest.fileName))
        XCTAssertTrue(store.exists(fileName: ScreenSaverLiveManifest.fileName), "the live frames' manifest stays")
        for still in stills { XCTAssertTrue(store.exists(fileName: still), "\(still): the saver's stills stay") }
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
        XCTAssertTrue(ShaderPrewarmCommand.isHelperRun(arguments: ["app", ShaderPrewarmCommand.prepareArgument]))
        XCTAssertFalse(ShaderPrewarmCommand.isHelperRun(arguments: ["app", "--render-screensaver-loop"]), "the loop render is gone")
        XCTAssertEqual(ShaderPrewarmCommand.size("3840x2160"), SIMD2(3840, 2160))
        XCTAssertNil(ShaderPrewarmCommand.size("3840"))
        XCTAssertNil(ShaderPrewarmCommand.size("0x10"))
    }

    // MARK: Earlier versions' recordings

    func testOnlyOWEsOwnRecordingNamesAreOldRecordings() {
        XCTAssertTrue(ScreenSaverVideoStore.isOldRecording("ab12_cd34-0a1b2c3d4e5f-3840x2160-r3.mov"))
        XCTAssertTrue(ScreenSaverVideoStore.isOldRecording("ab12_cd34-0a1b2c3d4e5f-1920x1080-r2-rec1790000000.mov"))
        XCTAssertFalse(ScreenSaverVideoStore.isOldRecording("ab12_cd34-video-r3.mp4"), "a video wallpaper's own file")
        XCTAssertFalse(ScreenSaverVideoStore.isOldRecording("ab12_cd34-video-r3-rec1790000000.mov"), "a video set as the screen saver")
        XCTAssertFalse(ScreenSaverVideoStore.isOldRecording("holiday.mov"))
        XCTAssertFalse(ScreenSaverVideoStore.isOldRecording("still-A.heic"))
        XCTAssertFalse(ScreenSaverVideoStore.isOldRecording(ScreenSaverManifest.fileName))
    }

    func testOldRecordingsAreDeletedAndNothingElse() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shared = folder.appending(path: "ScreenSaver", directoryHint: .isDirectory)
        let caches = folder.appending(path: "Caches", directoryHint: .isDirectory)
        let staging = caches.appending(path: "ScreenSaverRecordings", directoryHint: .isDirectory)
        let elsewhere = folder.appending(path: "Library", directoryHint: .isDirectory)
        for dir in [shared, staging, elsewhere, shared.appending(path: "sub-0a1b2c3d4e5f-1x1-r1.mov")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let loop = "w_c-0a1b2c3d4e5f-3840x2160-r3.mov", recording = "w_c-0a1b2c3d4e5f-3840x2160-r3-rec42.mov"
        let video = "v_c-video-r3.mp4", kept = "k_c-0a1b2c3d4e5f-1920x1080-r3.mov"
        for name in [loop, recording, video, kept, "still-A.heic", ScreenSaverStills.fileName, ScreenSaverManifest.fileName] {
            try Data("x".utf8).write(to: shared.appending(path: name))
        }
        try Data("x".utf8).write(to: staging.appending(path: recording))
        // A library file linked in under a recording's name is never followed or deleted.
        let libraryFile = elsewhere.appending(path: "clip.mov")
        try Data("library".utf8).write(to: libraryFile)
        let link = "l_c-0a1b2c3d4e5f-640x480-r3.mov"
        try FileManager.default.createSymbolicLink(at: shared.appending(path: link), withDestinationURL: libraryFile)

        ScreenSaverVideoStore(directory: shared).removeOldRecordings(cachesDirectory: caches, keeping: [kept])

        let left = try Set(FileManager.default.contentsOfDirectory(atPath: shared.path(percentEncoded: false)))
        XCTAssertEqual(left, [video, kept, link, "still-A.heic", ScreenSaverStills.fileName, ScreenSaverManifest.fileName,
                              "sub-0a1b2c3d4e5f-1x1-r1.mov"])
        XCTAssertEqual(try String(contentsOf: libraryFile, encoding: .utf8), "library")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)), "the emptied staging folder goes")
    }

    func testRetiredSettingsAreRemovedAndOldSelectionsStillDecode() throws {
        let suite = "owe-screensaver-retired-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"isEnabled":true,"hour":6,"minute":30}"#.utf8), forKey: "ScreenSaverSchedule")
        // A selection as earlier versions saved it, recording fields and all.
        defaults.set(Data(#"{"wallpaperDirectory":"/w/1","fileName":"a-rec1.mov","width":1920,"height":1080,"recorded":0}"#.utf8),
                     forKey: ScreenSaverSettingsStore.selectionKey)
        let store = ScreenSaverSettingsStore(defaults: defaults)
        store.removeRetiredKeys()
        XCTAssertNil(defaults.object(forKey: "ScreenSaverSchedule"))
        XCTAssertEqual(store.selection?.wallpaperDirectory, "/w/1")
        XCTAssertNil(store.livePick)
        store.removeRetiredKeys()
    }
}
