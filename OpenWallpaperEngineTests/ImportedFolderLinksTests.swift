import XCTest
@testable import OpenWallpaperEngine

/// Imports and package extraction keep a wallpaper's files inside its own folder.
final class ImportedFolderLinksTests: XCTestCase {
    private var root: URL!
    private var outside: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "owe-links-\(UUID().uuidString)")
        outside = root.appending(path: "outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: outside.appending(path: "keep.txt"))
    }

    override func tearDownWithError() throws {
        try fm.removeItem(at: root)
    }

    private func symlinks(under folder: URL) -> [String] {
        let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        }.map(\.lastPathComponent)
    }

    private func makeWallpaper(_ name: String, in parent: URL) throws -> URL {
        let folder = parent.appending(path: name)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"file":"scene.json","title":"T","type":"scene"}"#.utf8).write(to: folder.appending(path: "project.json"))
        return folder
    }

    func testRemovesEveryLinkInAnImportedFolder() throws {
        let wallpaper = try makeWallpaper("200", in: root)
        try fm.createDirectory(at: wallpaper.appending(path: "sub"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: wallpaper.appending(path: "sub/file"), withDestinationURL: outside.appending(path: "keep.txt"))
        try fm.createSymbolicLink(at: wallpaper.appending(path: "dir"), withDestinationURL: outside)
        XCTAssertEqual(try ImportedFolderLinks.removeLinks(in: wallpaper), 2)
        XCTAssertEqual(symlinks(under: wallpaper), [])
        XCTAssertTrue(fm.fileExists(atPath: wallpaper.appending(path: "project.json").path))
        XCTAssertTrue(fm.fileExists(atPath: outside.appending(path: "keep.txt").path), "the target stays")
    }

    func testCopyLeavesNoLinksAndRefusesALinkedFolder() throws {
        let wallpaper = try makeWallpaper("300", in: root)
        try fm.createSymbolicLink(at: wallpaper.appending(path: "dir"), withDestinationURL: outside)
        let library = root.appending(path: "library")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        try ImportedFolderLinks.copyWithoutLinks(from: wallpaper, to: library.appending(path: "300"))
        XCTAssertEqual(symlinks(under: library), [])

        let linked = root.appending(path: "linked")
        try fm.createSymbolicLink(at: linked, withDestinationURL: wallpaper)
        XCTAssertThrowsError(try ImportedFolderLinks.copyWithoutLinks(from: linked, to: library.appending(path: "linked")))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: library.path), ["300"])
    }

    func testZipImportLeavesNoLinks() throws {
        let source = root.appending(path: "source")
        let wallpaper = try makeWallpaper("400", in: source)
        try fm.createSymbolicLink(at: wallpaper.appending(path: "escape"), withDestinationURL: outside)
        let zip = root.appending(path: "w.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-ck", "--keepParent", wallpaper.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let library = root.appending(path: "library")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        XCTAssertEqual(ZipImporter.importZip(at: zip, into: library), 1)
        XCTAssertTrue(fm.fileExists(atPath: library.appending(path: "400/project.json").path))
        XCTAssertEqual(symlinks(under: library), [])
    }

    func testLinkedWallpaperFoldersAreNotFound() throws {
        let scan = root.appending(path: "scan")
        let real = try makeWallpaper("500", in: scan)
        let elsewhere = try makeWallpaper("600", in: root)
        try fm.createSymbolicLink(at: scan.appending(path: "600"), withDestinationURL: elsewhere)
        XCTAssertEqual(ZipImporter.findWallpaperFolders(in: scan).map(\.lastPathComponent), [real.lastPathComponent])
    }
}
