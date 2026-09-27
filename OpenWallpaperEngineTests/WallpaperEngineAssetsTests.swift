import XCTest
@testable import OpenWallpaperEngine

/// Risk #19: the WE assets without a WE install. The app always uses its bundled copy.
final class WallpaperEngineAssetsTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appending(path: "owe-assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch) // scratch cleanup
    }

    private func write(_ text: String, to path: String, in directory: URL) throws {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// The app ships its own copy, so effects work with no WE install at all. A value left in the
    /// removed `WallpaperEngineAssetsDirectory` setting is ignored.
    func testBundledAssetsAreShippedAndUsed() throws {
        try XCTSkipIf(WallpaperEngineAssets.testInstall != nil, "OWE_WE_ASSETS names a WE install for this run")
        let bundled = try XCTUnwrap(WallpaperEngineAssets.bundled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundled.appending(path: "shaders/genericimage2.frag").path))
        let key = "WallpaperEngineAssetsDirectory", before = UserDefaults.app.object(forKey: key)
        defer { UserDefaults.app.set(before, forKey: key) }
        UserDefaults.app.set(scratch.path, forKey: key)
        XCTAssertEqual(WallpaperEngineAssets.directory, bundled)
        XCTAssertEqual(WallpaperEngineAssets.searchDirectories, [bundled])
    }

    /// A file the first directory lacks still resolves from the next.
    func testLookupFallsBackToTheNextDirectory() throws {
        let install = scratch.appending(path: "install"), bundled = scratch.appending(path: "bundled")
        try write("install", to: "shaders/both.frag", in: install)
        try write("bundled", to: "shaders/both.frag", in: bundled)
        try write("bundled", to: "materials/only-bundled.json", in: bundled)
        let both = try XCTUnwrap(WallpaperEngineAssets.locate(["shaders/both.frag"], in: [install, bundled]))
        XCTAssertEqual(try String(contentsOf: both, encoding: .utf8), "install")
        let fallback = try XCTUnwrap(WallpaperEngineAssets.locate(["only-bundled.json", "materials/only-bundled.json"],
                                                                  in: [install, bundled]))
        XCTAssertEqual(fallback.path, bundled.appending(path: "materials/only-bundled.json").standardizedFileURL.path)
        XCTAssertNil(WallpaperEngineAssets.locate(["missing"], in: [install, bundled]))
    }
}
