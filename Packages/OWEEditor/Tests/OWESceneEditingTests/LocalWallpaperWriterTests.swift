import XCTest
@testable import OWESceneEditing

/// Save as Local Wallpaper: a new folder with the edits baked in; the source untouched.
final class LocalWallpaperWriterTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var library: URL!

    override func setUpWithError() throws {
        root = try Fixtures.temporaryDirectory()
        source = root.appending(path: "123456", directoryHint: .isDirectory)
        library = root.appending(path: "Library", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: source.appending(path: "materials"), withIntermediateDirectories: true)
        try Data(#"{"title": "Rainy City", "type": "scene", "file": "scene.json", "workshopid": "123456", "workshopurl": "steam://x", "preview": "preview.jpg"}"#.utf8)
            .write(to: source.appending(path: "project.json"))
        try Fixtures.sceneData.write(to: source.appending(path: "scene.json"))
        try Data("jpg".utf8).write(to: source.appending(path: "preview.jpg"))
        try Data("tex".utf8).write(to: source.appending(path: "materials/rain.tex"))
        try fm.createDirectory(at: source.appending(path: ".owe-source"), withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: source.appending(path: ".owe-source/scene.pkg"))
        try fm.createSymbolicLink(at: source.appending(path: "dependency"), withDestinationURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func snapshot(_ folder: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        // The temporary folder is behind a link (/var → /private/var); paths are compared resolved.
        let base = folder.resolvingSymlinksInPath().path
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            files[String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))] = try Data(contentsOf: url)
        }
        return files
    }

    func testWritesANewLocalWallpaperWithTheEdits() throws {
        let before = try snapshot(source)
        var overlay = SceneEditOverlay()
        overlay.setField("alpha", to: .number(0.25), of: 10)
        let scene = try overlay.applied(to: Fixtures.sceneData)
        let folder = try LocalWallpaperWriter().save(.init(directory: source, sceneFile: "scene.json"), scene: scene,
                                                     title: "Rainy City (Edited)", into: library)

        XCTAssertEqual(folder.lastPathComponent, "Rainy City (Edited)")
        XCTAssertEqual(try snapshot(source), before, "the installed wallpaper is never modified")
        let written = try snapshot(folder)
        XCTAssertEqual(Set(written.keys), ["project.json", "scene.json", "preview.jpg", "materials/rain.tex"],
                       "hidden folders and symbolic links stay behind")
        XCTAssertEqual((try Fixtures.object(10, in: written["scene.json"]!)["alpha"] as? NSNumber)?.doubleValue, 0.25)
        let project = try JSONSerialization.jsonObject(with: written["project.json"]!) as! [String: Any]
        XCTAssertEqual(project["title"] as? String, "Rainy City (Edited)")
        XCTAssertNil(project["workshopid"], "the copy is a local wallpaper with its own identity")
        XCTAssertNil(project["workshopurl"])
        XCTAssertEqual(project["file"] as? String, "scene.json")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: library.path).contains { $0.hasPrefix(".owe-editor-") },
                       "no staging folder is left")
    }

    func testAPackedSceneIsWrittenLoose() throws {
        try Data("pkg".utf8).write(to: source.appending(path: "scene.pkg"))
        let files = ["scene.json": Fixtures.sceneData, "materials/rain.tex": Data("packed".utf8),
                     "models/bg.json": Data("{}".utf8)]
        let folder = try LocalWallpaperWriter().save(.init(directory: source, sceneFile: "scene.json", packageFiles: files,
                                                           packageName: "scene.pkg"),
                                                     scene: Data("{\"objects\":[]}".utf8), title: "Packed", into: library)
        let written = try snapshot(folder)
        XCTAssertNil(written["scene.pkg"], "the package is left out: the loader would prefer it to the edited scene")
        XCTAssertEqual(written["materials/rain.tex"], Data("packed".utf8), "the package's files win, as the loader reads them")
        XCTAssertEqual(written["models/bg.json"], Data("{}".utf8))
        XCTAssertEqual(written["scene.json"], Data("{\"objects\":[]}".utf8))
    }

    func testFolderNamesAreUniqueAndSafe() throws {
        let writer = LocalWallpaperWriter()
        let first = try writer.save(.init(directory: source, sceneFile: "scene.json"), scene: Fixtures.sceneData,
                                    title: "A/B: C", into: library)
        let second = try writer.save(.init(directory: source, sceneFile: "scene.json"), scene: Fixtures.sceneData,
                                     title: "A/B: C", into: library)
        XCTAssertEqual(first.lastPathComponent, "A-B- C")
        XCTAssertEqual(second.lastPathComponent, "A-B- C 2")
        XCTAssertEqual(LocalWallpaperWriter.folderName("..."), "Wallpaper")
    }

    func testAPackagePathOutsideTheFolderIsRefused() {
        XCTAssertThrowsError(try LocalWallpaperWriter().save(
            .init(directory: source, sceneFile: "scene.json", packageFiles: ["../escape.txt": Data()], packageName: nil),
            scene: Fixtures.sceneData, title: "Bad", into: library)) { error in
            XCTAssertEqual(error as? LocalWallpaperWriter.WriteError, .unsafePath("../escape.txt"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [], "nothing is left behind")
    }
}
