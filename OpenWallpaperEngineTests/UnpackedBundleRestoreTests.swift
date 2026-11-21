import XCTest
@testable import OpenWallpaperEngine
import OWESceneEditing

/// Wallpapers an earlier version unpacked get their package back (downloaded again, or the one on
/// disk) and lose the loose copy, only once the package holds the scene and the wallpaper isn't
/// shown; anything else keeps the loose copy for a later launch. The downloader is a fake.
final class UnpackedBundleRestoreTests: XCTestCase {
    private var storage: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        storage = fm.temporaryDirectory.appending(path: "owe-unpacked-\(UUID().uuidString)")
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: storage) // scratch cleanup
    }

    /// A PKGV archive holding `files`.
    static func package(_ files: [(String, Data)]) -> Data {
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let magic = Data("PKGV0001".utf8)
        var header = u32(magic.count) + magic + u32(files.count)
        var body = Data()
        for (path, contents) in files {
            let name = Data(path.utf8)
            header += u32(name.count) + name + u32(body.count) + u32(contents.count)
            body += contents
        }
        return header + body
    }

    static let scenePackage = package([("scene.json", Data("{}".utf8)), ("materials/a.json", Data("{}".utf8))])

    private func write(_ data: Data, to path: String, in folder: URL) throws {
        let url = folder.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// An unpacked wallpaper in folder `name`: the loose files the manifest lists, a file of its
    /// own, and, `archived`, the original package in `.owe-source`.
    private func makeBundle(_ name: String, workshopid: String? = nil, archived: Bool = false) throws -> URL {
        let folder = storage.appending(path: name)
        let id = workshopid.map { #", "workshopid": "\#($0)""# } ?? ""
        try write(Data(#"{"file": "scene.json", "type": "scene", "title": "T \#(name)"\#(id)}"#.utf8), to: "project.json", in: folder)
        try write(Data("{}".utf8), to: "scene.json", in: folder)
        try write(Data("{}".utf8), to: "materials/a.json", in: folder)
        try write(Data("gif".utf8), to: "preview.gif", in: folder)
        try write(Data(#"{"sourcePackage": "scene.pkg", "extractedFiles": ["scene.json", "materials/a.json"]}"#.utf8),
                  to: UnpackedBundle.manifestName, in: folder)
        if archived { try write(Self.scenePackage, to: ".owe-source/scene.pkg", in: folder) }
        return folder
    }

    private func isAsDownloaded(_ folder: URL) -> Bool {
        fm.fileExists(atPath: folder.appending(path: "scene.pkg").path)
            && !fm.fileExists(atPath: folder.appending(path: "scene.json").path)
            && !fm.fileExists(atPath: folder.appending(path: "materials").path)
            && !fm.fileExists(atPath: folder.appending(path: UnpackedBundle.manifestName).path)
            && !fm.fileExists(atPath: folder.appending(path: UnpackedBundle.sourceFolderName).path)
            && fm.fileExists(atPath: folder.appending(path: "preview.gif").path)
            && fm.fileExists(atPath: folder.appending(path: "project.json").path)
    }

    private func isUnpacked(_ folder: URL) -> Bool {
        fm.fileExists(atPath: folder.appending(path: "scene.json").path)
            && fm.fileExists(atPath: folder.appending(path: "materials/a.json").path)
            && fm.fileExists(atPath: folder.appending(path: UnpackedBundle.manifestName).path)
            && !fm.fileExists(atPath: folder.appending(path: "scene.pkg").path)
    }

    /// Runs `restorer` over what the scan finds and waits until it's through.
    @MainActor
    private func restore(_ restorer: UnpackedBundleRestorer) async {
        let bundles = UnpackedBundle.scan(storage: storage, hasEdits: { _ in false }).map { (bundle: $0, packageOnDisk: $0.packageOnDisk()) }
        let finished = expectation(description: "restore finished")
        restorer.run(bundles) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 5)
    }

    @MainActor
    private func makeRestorer(_ downloader: FakePackageDownloader,
                              isShown: @escaping (URL) -> Bool = { _ in false }) -> UnpackedBundleRestorer {
        UnpackedBundleRestorer(downloader: downloader, isShown: isShown, finish: { bundle, package in
            _ = bundle.finish(with: package)
        })
    }

    func testTheScanFindsUnpackedWallpapersAndTheirWorkshopIds() throws {
        _ = try makeBundle("1000000001")
        _ = try makeBundle("mine")
        _ = try makeBundle("copied", workshopid: "1000000003")
        try write(Data(#"{"file": "scene.json", "type": "scene", "title": "P"}"#.utf8), to: "1000000004/project.json", in: storage)
        let bundles = UnpackedBundle.scan(storage: storage, hasEdits: { _ in false })
        XCTAssertEqual(bundles.map(\.directory.lastPathComponent), ["1000000001", "copied", "mine"])
        XCTAssertEqual(bundles.map(\.workshopId), ["1000000001", "1000000003", nil])
        XCTAssertEqual(bundles.map(\.packageName), ["scene.pkg", "scene.pkg", "scene.pkg"])
    }

    @MainActor
    func testADownloadedPackageReplacesTheLooseCopy() async throws {
        let folder = try makeBundle("1000000001")
        let downloader = FakePackageDownloader(result: .package(Self.scenePackage))
        await restore(makeRestorer(downloader))
        XCTAssertEqual(downloader.requests, ["1000000001"])
        XCTAssertTrue(isAsDownloaded(folder))
        XCTAssertFalse(fm.fileExists(atPath: folder.appending(path: UnpackedBundle.restoredPrefix + "scene.pkg").path))
        XCTAssertTrue(UnpackedBundle.scan(storage: storage, hasEdits: { _ in false }).isEmpty, "nothing left to do on the next launch")
    }

    @MainActor
    func testAFailedDownloadKeepsTheLooseCopy() async throws {
        let folder = try makeBundle("1000000001")
        let downloader = FakePackageDownloader(result: .failure)
        let restorer = makeRestorer(downloader)
        await restore(restorer)
        XCTAssertEqual(downloader.requests, ["1000000001"])
        XCTAssertTrue(isUnpacked(folder))
        XCTAssertEqual(restorer.skipped.map(\.directory.lastPathComponent), ["1000000001"])
        XCTAssertEqual(UnpackedBundle.scan(storage: storage, hasEdits: { _ in false }).count, 1, "tried again on a later launch")
    }

    /// An item gone from the Workshop is a download that fails: the loose copy stays.
    @MainActor
    func testAnItemNoLongerOnTheWorkshopKeepsTheLooseCopy() async throws {
        let folder = try makeBundle("1000000001")
        let restorer = makeRestorer(FakePackageDownloader(result: .unavailable))
        await restore(restorer)
        XCTAssertTrue(isUnpacked(folder))
        XCTAssertEqual(restorer.skipped.count, 1)
    }

    @MainActor
    func testWithoutASteamLoginNothingIsDownloaded() async throws {
        let folder = try makeBundle("1000000001")
        let downloader = FakePackageDownloader(result: .package(Self.scenePackage), isLoggedIn: false)
        let restorer = makeRestorer(downloader)
        await restore(restorer)
        XCTAssertEqual(downloader.requests, [])
        XCTAssertTrue(isUnpacked(folder))
        XCTAssertEqual(restorer.skipped.count, 1)
    }

    @MainActor
    func testALocalImportWithoutItsPackageIsLeftAlone() async throws {
        let folder = try makeBundle("mine")
        let downloader = FakePackageDownloader(result: .package(Self.scenePackage))
        let restorer = makeRestorer(downloader)
        await restore(restorer)
        XCTAssertEqual(downloader.requests, [])
        XCTAssertTrue(isUnpacked(folder))
        XCTAssertEqual(restorer.skipped.map(\.workshopId), [nil])
    }

    /// The package an earlier version kept is used without a download, a local import's too.
    @MainActor
    func testAKeptOriginalIsUsedWithoutADownload() async throws {
        let workshop = try makeBundle("1000000001", archived: true)
        let local = try makeBundle("mine", archived: true)
        let downloader = FakePackageDownloader(result: .failure)
        await restore(makeRestorer(downloader))
        XCTAssertEqual(downloader.requests, [])
        XCTAssertTrue(isAsDownloaded(workshop))
        XCTAssertTrue(isAsDownloaded(local))
    }

    @MainActor
    func testAShownWallpaperWaitsUntilItIsNotShown() async throws {
        let folder = try makeBundle("1000000001")
        var shown = true
        let restorer = makeRestorer(FakePackageDownloader(result: .package(Self.scenePackage)),
                                    isShown: { $0.standardizedFileURL == folder.standardizedFileURL && shown })
        await restore(restorer)
        XCTAssertEqual(restorer.pending.count, 1)
        XCTAssertTrue(isUnpacked(folder), "the shown wallpaper's files aren't touched")
        restorer.shownWallpapersChanged()
        XCTAssertTrue(isUnpacked(folder), "still shown")
        shown = false
        restorer.shownWallpapersChanged()
        XCTAssertTrue(restorer.pending.isEmpty)
        XCTAssertTrue(isAsDownloaded(folder))
    }

    /// A download that doesn't hold the scene isn't put in place, and the loose copy stays.
    @MainActor
    func testAPackageWithoutTheSceneIsRefused() async throws {
        let folder = try makeBundle("1000000001")
        let restorer = UnpackedBundleRestorer(downloader: FakePackageDownloader(result: .package(Self.package([("other.json", Data("{}".utf8))]))),
                                              isShown: { _ in false }, finish: { bundle, package in
            XCTAssertFalse(bundle.finish(with: package))
        })
        await restore(restorer)
        XCTAssertTrue(isUnpacked(folder))
    }

    /// A wallpaper with Wallpaper Editor or Scene Edit edits keeps its loose copy as it is.
    func testAWallpaperWithEditsIsLeftAsItIs() throws {
        let edited = try makeBundle("1000000001")
        let drafted = try makeBundle("1000000002")
        let sceneEdited = try makeBundle("1000000003")
        _ = try makeBundle("1000000004")
        let overlays = SceneEditOverlayStore(directory: storage.appending(path: "editor"))
        try write(Data("{}".utf8), to: "workshop-1000000001.json", in: overlays.directory)
        XCTAssertEqual(overlays.fileURL(for: "workshop-1000000001").lastPathComponent, "workshop-1000000001.json")
        try write(Data("{}".utf8), to: "Drafts/workshop-1000000002.json", in: overlays.directory)
        let suite = "owe-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["_owe_scene_object_7": "{}"], forKey: "SceneUserProperties.workshop-1000000003.display.2")
        defaults.set(["speed": "2"], forKey: "SceneUserProperties.workshop-1000000004")
        let hasEdits = { (folder: URL) in UnpackedBundle.hasEditorEdits(folder, defaults: defaults, overlays: overlays) }
        XCTAssertTrue(hasEdits(edited))
        XCTAssertTrue(hasEdits(drafted))
        XCTAssertTrue(hasEdits(sceneEdited))
        XCTAssertEqual(UnpackedBundle.scan(storage: storage, hasEdits: hasEdits).map(\.directory.lastPathComponent), ["1000000004"],
                       "a user property alone isn't an edit")
    }

    /// Only what the unpacking wrote goes: files it didn't list, and files behind a link, stay.
    func testOnlyTheListedFilesGo() throws {
        let folder = try makeBundle("1000000001")
        let outside = storage.appending(path: "outside")
        try write(Data("keep".utf8), to: "a.json", in: outside)
        try write(Data("mine".utf8), to: "materials/mine.json", in: folder)
        try fm.createSymbolicLink(at: folder.appending(path: "effects"), withDestinationURL: outside)
        try write(Data(#"{"sourcePackage": "scene.pkg", "extractedFiles": ["scene.json", "materials/a.json", "effects/a.json", "../outside/a.json", "project.json"]}"#.utf8),
                  to: UnpackedBundle.manifestName, in: folder)
        try write(Self.scenePackage, to: UnpackedBundle.restoredPrefix + "scene.pkg", in: folder)
        let bundle = try XCTUnwrap(UnpackedBundle.bundle(at: folder))
        XCTAssertEqual(bundle.packageOnDisk()?.lastPathComponent, UnpackedBundle.restoredPrefix + "scene.pkg")
        XCTAssertTrue(bundle.finish(with: try XCTUnwrap(bundle.packageOnDisk())))
        XCTAssertTrue(fm.fileExists(atPath: folder.appending(path: "scene.pkg").path))
        XCTAssertFalse(fm.fileExists(atPath: folder.appending(path: "materials/a.json").path))
        XCTAssertTrue(fm.fileExists(atPath: folder.appending(path: "materials/mine.json").path))
        XCTAssertTrue(fm.fileExists(atPath: outside.appending(path: "a.json").path))
        XCTAssertTrue(fm.fileExists(atPath: folder.appending(path: "project.json").path))
    }
}

/// A Workshop download path that "downloads" a package, or fails.
@MainActor
private final class FakePackageDownloader: UnpackedBundleDownloading {
    enum Result {
        case package(Data)
        case failure
        /// The item was removed or made private.
        case unavailable
    }

    let result: Result
    let isLoggedIn: Bool
    private(set) var requests: [String] = []

    init(result: Result, isLoggedIn: Bool = true) {
        self.result = result
        self.isLoggedIn = isLoggedIn
    }

    func fetchPackage(workshopId: String, packageName: String, to destination: URL,
                      completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        requests.append(workshopId)
        var landed = false
        if case .package(let data) = result {
            do {
                try data.write(to: destination)
                landed = true
            } catch {
                XCTFail("can't write \(destination.path): \(error)")
            }
        }
        DispatchQueue.main.async { completion(landed) }
    }
}
