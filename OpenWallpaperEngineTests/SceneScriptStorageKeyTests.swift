import XCTest
@testable import OpenWallpaperEngine

/// SceneScript `localStorage` is keyed on the install folder, not project.json's `workshopid`
/// (`SceneScriptStorageKey`).
final class SceneScriptStorageKeyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appending(path: "owe-storage-key-\(UUID().uuidString)",
                                                                  directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    private func folder(_ name: String, create: Bool = true) throws -> URL {
        let url = root.appending(path: "library/\(name)", directoryHint: .isDirectory)
        if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return url
    }

    // MARK: - Key

    func testNumericFolderIsTheKey() throws {
        XCTAssertEqual(SceneScriptStorageKey.key(forWallpaperDirectory: try folder("123456")), "123456")
    }

    func testOtherFoldersAreKeyedOnTheirPath() throws {
        let named = try folder("My Wallpaper")
        let key = SceneScriptStorageKey.key(forWallpaperDirectory: named)
        XCTAssertTrue(key.hasPrefix("local-"))
        XCTAssertEqual(key, SceneScriptStorageKey.key(forWallpaperDirectory: named.appending(path: "x/..")),
                       "the path is standardized")
        XCTAssertNotEqual(key, SceneScriptStorageKey.key(forWallpaperDirectory: try folder("Other")))
        // Non-ASCII digits are not a Steam id.
        XCTAssertTrue(SceneScriptStorageKey.key(forWallpaperDirectory: try folder("١٢٣")).hasPrefix("local-"))
        XCTAssertEqual(SceneContentLoader.localWallpaperID(named), key)
    }
}
