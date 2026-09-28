import XCTest
import CryptoKit
@testable import OpenWallpaperEngine

final class SceneCacheFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "owe-scene-cache-\(UUID().uuidString)",
                                                                 directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        SceneWallpaperViewModel.sceneCacheStore = nil
    }

    private func baseKey() -> SceneCacheKey {
        SceneCacheKey(sources: [.init(path: "/scene.pkg", size: 100, modified: 5)],
                      edits: ["_owe_scene_object_1_origin": "1 2 3"],
                      userProperties: ["speed": "1"],
                      displays: [.init(pixelWidth: 3840, pixelHeight: 2160, scale: 2)],
                      settings: "hdr", appBuild: "1(1)", shaderRevision: 10, gpu: "gpu|apple9")
    }

    // MARK: - Key

    func testKeyChangesWithEveryInput() {
        let base = baseKey()
        var variants: [(String, SceneCacheKey)] = []
        var key = base; key.sources[0].size = 101; variants.append(("size", key))
        key = base; key.sources[0].modified = 6; variants.append(("mtime", key))
        key = base; key.sources.append(.init(path: "/x", size: 1, modified: 1)); variants.append(("file", key))
        key = base; key.edits["_owe_scene_object_1_origin"] = "1 2 4"; variants.append(("edit", key))
        key = base; key.userProperties["speed"] = "2"; variants.append(("property", key))
        key = base; key.displays[0].scale = 1; variants.append(("scale", key))
        key = base; key.displays[0].pixelWidth = 2560; variants.append(("display", key))
        key = base; key.settings = "sdr"; variants.append(("settings", key))
        key = base; key.appBuild = "1(2)"; variants.append(("build", key))
        key = base; key.shaderRevision = 11; variants.append(("revision", key))
        key = base; key.gpu = "gpu|apple8"; variants.append(("gpu", key))
        let baseName: String = base.name
        for (label, variant) in variants {
            let name: String = variant.name
            XCTAssertNotEqual(name, baseName, label)
        }
        let again: String = baseKey().name
        XCTAssertEqual(again, baseName)
    }

    func testKeyIgnoresDictionaryAndDisplayOrder() {
        var a = baseKey()
        a.userProperties = ["a": "1", "b": "2", "c": "3"]
        a.displays = [.init(pixelWidth: 1, pixelHeight: 1, scale: 1), .init(pixelWidth: 2, pixelHeight: 2, scale: 2)]
        var b = a
        b.displays.reverse()
        let nameA: String = a.name
        let nameB: String = b.name
        XCTAssertEqual(nameA, nameB)
    }

    // MARK: - File

    private func sample() -> SceneCacheFile {
        SceneCacheFile(key: baseKey().digest, sections: [
            .scenePlan: Data("{\"objects\":[]}".utf8),
            .shaderVariants: Data([1, 2, 3]),
            .textures: Data(repeating: 7, count: 1000),
        ])
    }

    func testRoundTripAndAlignment() throws {
        let file = sample()
        let data = file.encoded()
        let alignedSize: Bool = data.count % 16 == 0
        XCTAssertTrue(alignedSize)
        let decoded = try SceneCacheFile(decoding: data, expectedKey: baseKey().digest)
        XCTAssertEqual(decoded, file)
        for (_, section) in decoded.sections {
            let offset: Int = section.startIndex - data.startIndex
            let aligned: Bool = offset % 16 == 0
            XCTAssertTrue(aligned)
        }
    }

    func testTruncatedFileIsRejected() {
        let data = sample().encoded()
        for length in [0, 20, 60, data.count - 16, data.count - 1] {
            XCTAssertThrowsError(try SceneCacheFile(decoding: data.prefix(length)), "length \(length)")
        }
    }

    func testCorruptForeignAndMismatchedFilesAreRejected() {
        let data = sample().encoded()
        var corrupt = data
        corrupt[corrupt.count / 2] ^= 0xFF
        XCTAssertThrowsError(try SceneCacheFile(decoding: corrupt))
        var foreign = data
        foreign[8] = 99
        XCTAssertThrowsError(try SceneCacheFile(decoding: foreign)) { error in
            XCTAssertEqual(error as? SceneCacheFile.ReadError, .foreignVersion(99))
        }
        var other = baseKey()
        other.settings = "other"
        XCTAssertThrowsError(try SceneCacheFile(decoding: data, expectedKey: other.digest)) { error in
            XCTAssertEqual(error as? SceneCacheFile.ReadError, .keyMismatch)
        }
    }

    // MARK: - Store

    func testStoreDeletesUnreadableFileAndWritesAtomically() throws {
        let store = SceneCacheStore(root: root)
        let key = baseKey()
        let url = try store.write(sample(), wallpaper: "123", key: key)
        XCTAssertEqual(store.read(wallpaper: "123", key: key), sample())
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, [url.lastPathComponent])
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        XCTAssertNil(store.read(wallpaper: "123", key: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testStoreEvictsLeastRecentlyUsed() throws {
        let fileSize = sample().encoded().count
        let store = SceneCacheStore(root: root, capacity: Int64(fileSize * 2))
        var keys: [SceneCacheKey] = []
        for index in 0..<3 {
            var key = baseKey()
            key.settings = "s\(index)"
            keys.append(key)
            let url = try store.write(SceneCacheFile(key: key.digest, sections: sample().sections), wallpaper: "w", key: key)
            let used = Date(timeIntervalSinceNow: TimeInterval(index * 10 - 100))
            try FileManager.default.setAttributes([.modificationDate: used], ofItemAtPath: url.path)
        }
        store.trim()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(wallpaper: "w", key: keys[0]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(wallpaper: "w", key: keys[1]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(wallpaper: "w", key: keys[2]).path))
    }

    // MARK: - Preparation and loading

    private func request(_ directory: URL) -> ScenePreparation.Request {
        ScenePreparation.Request(wallpaperID: "fixture", directory: directory, sceneFile: "scene.json",
                                 edits: [:], userProperties: [:], settings: "s", displays: [])
    }

    func testPreparationRunsOffTheMainThreadAndWritesTheResolvedPlan() async throws {
        let directory = Fixtures.url("Scenes/layers")
        let store = SceneCacheStore(root: root)
        let pool = PreparationPool(maxWorkers: 2)
        let request = request(directory)
        let file = try await ScenePreparation.prepare(request, priority: .settingWallpaper, store: store, pool: pool)
        let source = try ScenePreparation.resolvedScene(Data(contentsOf: directory.appending(path: "scene.json")), edits: [:])
        let plan = try JSONSerialization.jsonObject(with: XCTUnwrap(file.sections[.scenePlan])) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: source) as? NSDictionary
        XCTAssertEqual(plan, expected)
        let read = try XCTUnwrap(store.read(wallpaper: "fixture", key: request.key))
        XCTAssertEqual(read, file)
    }

    func testEditsAreAppliedToThePlan() throws {
        let data = Data("{\"objects\":[{\"id\":4,\"origin\":\"0 0 0\"}]}".utf8)
        let resolved = try ScenePreparation.resolvedScene(data, edits: ["_owe_scene_object_4_origin": "5 6 0"])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: resolved) as? [String: Any])
        let objects = try XCTUnwrap(root["objects"] as? [[String: Any]])
        XCTAssertEqual(objects.first?["origin"] as? String, "5 6 0")
    }

    /// A load prefers the cache: a prepared plan that differs from the source is what loads.
    func testLoadPrefersTheCache() throws {
        let directory = try Fixtures.temporaryCopy(of: "Scenes/solid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SceneCacheStore(root: root)
        SceneWallpaperViewModel.sceneCacheStore = store
        let wallpaper = try loadWallpaper(directory)
        defer { Fixtures.removeStoredSettings(for: directory) }

        let first = SceneWallpaperViewModel(wallpaper: wallpaper)
        let sourceLayers: Int = try XCTUnwrap(first.metalContent()).layers.count
        let written = try waitForCacheFile(in: root)

        let cached = try SceneCacheFile(decoding: Data(contentsOf: written))
        var plan = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(cached.sections[.scenePlan])) as? [String: Any])
        plan["objects"] = Array((plan["objects"] as? [Any] ?? []).prefix(1))
        let edited = SceneCacheFile(key: cached.key, sections: [.scenePlan: try JSONSerialization.data(withJSONObject: plan)])
        try edited.encoded().write(to: written)

        SceneWallpaperViewModel.dropSharedParses()
        let second = SceneWallpaperViewModel(wallpaper: wallpaper)
        let cachedLayers: Int = try XCTUnwrap(second.metalContent()).layers.count
        XCTAssertGreaterThan(sourceLayers, 1)
        XCTAssertEqual(cachedLayers, 1)
    }

    /// Loading from the cache draws what loading from source draws.
    func testCacheLoadRendersLikeSourceLoad() throws {
        let directory = try Fixtures.temporaryCopy(of: "Scenes/layers")
        defer { try? FileManager.default.removeItem(at: directory) }
        SceneWallpaperViewModel.sceneCacheStore = nil
        let source = try FixtureSceneRenderer(directory: directory).render()

        SceneWallpaperViewModel.sceneCacheStore = SceneCacheStore(root: root)
        SceneWallpaperViewModel.dropSharedParses()
        _ = SceneWallpaperViewModel(wallpaper: try loadWallpaper(directory))
        _ = try waitForCacheFile(in: root)
        Fixtures.removeStoredSettings(for: directory)
        SceneWallpaperViewModel.dropSharedParses()
        let cached = try FixtureSceneRenderer(directory: directory).render()

        let ssim: Double = PerceptualCompare.ssim(
            PerceptualImage(width: source.width, height: source.height, rgba: source.pixels),
            PerceptualImage(width: cached.width, height: cached.height, rgba: cached.pixels))
        XCTAssertGreaterThanOrEqual(ssim, 0.999)
        XCTAssertEqual(source.pixels, cached.pixels)
    }

    private func loadWallpaper(_ directory: URL) throws -> WEWallpaper {
        let project = try JSONDecoder().decode(WEProject.self, from: Data(contentsOf: directory.appending(path: "project.json")))
        return WEWallpaper(using: project, where: directory)
    }

    private func waitForCacheFile(in root: URL) throws -> URL {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in walker where url.pathExtension == SceneCacheStore.fileExtension { return url }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTFail("no cache file was written")
        throw CocoaError(.fileNoSuchFile)
    }
}
