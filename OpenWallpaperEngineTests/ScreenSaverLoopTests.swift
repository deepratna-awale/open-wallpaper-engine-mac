import XCTest
@testable import OpenWallpaperEngine

/// The loops' crossfade and frame signature the exports use, and the screen saver's folder's isolation.
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

    func testTurningOffKeepsTheStills() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenSaverVideoStore(directory: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: store.url(fileName: name).path(percentEncoded: false)) }
        let stills = [ScreenSaverStills.fileName, "still-A.heic", "still-pick.jpg", ".1F2E-still-B.heic"]
        for name in [ScreenSaverLiveManifest.fileName] + stills {
            try Data().write(to: store.url(fileName: name))
        }
        store.removeAll()
        XCTAssertFalse(exists(ScreenSaverLiveManifest.fileName))
        for still in stills { XCTAssertTrue(exists(still), "\(still): turning the plugin off keeps the stills") }
        for still in stills { try FileManager.default.removeItem(at: store.url(fileName: still)) }
        try Data().write(to: store.url(fileName: "again.json"))
        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "an emptied folder goes")
    }

    func testHelperRunArgumentsAreReadOnlyHelperRuns() {
        XCTAssertTrue(HelperRunCommand.isHelperRun(arguments: ["app", HelperRunCommand.prepareArgument]))
        XCTAssertFalse(HelperRunCommand.isHelperRun(arguments: ["app", "--render-screensaver-loop"]), "the loop render is gone")
        XCTAssertEqual(HelperRunCommand.size("3840x2160"), SIMD2(3840, 2160))
        XCTAssertNil(HelperRunCommand.size("3840"))
        XCTAssertNil(HelperRunCommand.size("0x10"))
    }
}
