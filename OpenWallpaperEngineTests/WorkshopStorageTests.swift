import Combine
import XCTest
@testable import OpenWallpaperEngine

/// Every way a Workshop item reaches the app ends in the Wallpaper Storage folder, as `<storage>/<id>`,
/// with nothing left in the download's staging folder. The Steam helper is a fake that "downloads"
/// by writing the item into its `-dir`.
@MainActor
final class WorkshopStorageTests: XCTestCase {
    /// The storage folder the service reads at each download, so a test can change it.
    /// Read by the service's `@Sendable` folder closures off the main thread, so it is lock-guarded.
    private final class StorageLocation: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URL
        var url: URL {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
        init(_ url: URL) { stored = url }
    }

    private var root: URL!
    private var storage: StorageLocation!
    private var previewCache: URL!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!
    private var workshopDownloads: FakeHelper!
    private var dependencyIndex: WorkshopDependencyIndex!
    private var downloadedIndex: DownloadedWallpaperIndex!
    private var presented: [WEWallpaper] = []
    private var service: WorkshopDownloadService!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appending(path: "owe-storage-\(UUID().uuidString)", directoryHint: .isDirectory)
        let firstStorage = root.appending(path: "Storage A", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstStorage, withIntermediateDirectories: true)
        storage = StorageLocation(firstStorage)
        previewCache = root.appending(path: "Caches/WorkshopPreviews", directoryHint: .isDirectory)
        defaultsSuite = "owe-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
        workshopDownloads = FakeHelper()
        let storage = storage!
        dependencyIndex = WorkshopDependencyIndex(libraryDirectory: { storage.url })
        downloadedIndex = DownloadedWallpaperIndex(defaults: defaults, libraryDirectory: { storage.url })
        service = WorkshopDownloadService(dependencyIndex: dependencyIndex, helperDownloads: workshopDownloads,
                                  storageDirectory: { try WallpaperStorage.availableDirectory(storage.url) },
                                  previewCacheRoot: previewCache, downloadedIndex: downloadedIndex,
                                  presentPreview: { [weak self] in self?.presented.append($0) })
        service.useSteamLogin(SteamLogin(accountName: "tester", steamID: "76561190000000001", refreshToken: "test-token"))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaultsSuite)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func download(_ id: String, asDependency: Bool = false) async -> URL? {
        await withCheckedContinuation { continuation in
            service.downloadWorkshopItem(workshopId: id, asDependency: asDependency) { continuation.resume(returning: $0) }
        }
    }

    private func children(of directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func listed(in directory: URL) -> Set<String> {
        Set(InstalledLibrary.wallpapers(in: directory, hiding: dependencyIndex.ids).map(\.wallpaperDirectory.lastPathComponent))
    }

    private func makeWallpaper(_ id: String, in directory: URL, referencing dependency: String) throws -> URL {
        let folder = directory.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"type": "scene", "title": "Uses \#(dependency)", "file": "scene.json"}"#.utf8)
            .write(to: folder.appending(path: "project.json"))
        try Data(#"{"objects": [{"effects": [{"file": "effects/workshop/\#(dependency)/glow/effect.json"}]}]}"#.utf8)
            .write(to: folder.appending(path: "scene.json"))
        return folder
    }

    /// A dependency service on the test storage whose Steam check answers `availability`
    /// (nothing by default, as when Steam leaves the ids out).
    private func makeDependencyService(
        availability: @escaping WorkshopDependencyService.AvailabilityCheck = { _ in [:] },
        now: @escaping () -> Date = Date.init
    ) -> WorkshopDependencyService {
        let storage = storage!
        return WorkshopDependencyService(
            workshopDownloads: service,
            makeResolver: { WorkshopAssetResolver(roots: [storage.url]) },
            store: UnavailableWorkshopItemStore(fileURL: root.appending(path: "UnavailableWorkshopItems.json"), now: now),
            checkAvailability: availability)
    }

    // MARK: - Downloads

    func testUserDownloadGoesIntoStorage() async throws {
        let destination = await download("1000000001")

        XCTAssertEqual(destination?.standardizedFileURL, storage.url.appending(path: "1000000001").standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url.appending(path: "1000000001/project.json").path))
        // The staging folder, DepotDownloader's bookkeeping included, is gone.
        XCTAssertEqual(try children(of: storage.url), ["1000000001"])
        XCTAssertEqual(workshopDownloads.installDirectories, [WorkshopItemInstaller.stagingDirectory(in: storage.url).path])
        XCTAssertEqual(service.downloadProgress["1000000001"], .completed)
        XCTAssertTrue(downloadedIndex.contains("1000000001"))
        XCTAssertEqual(listed(in: storage.url), ["1000000001"])
    }

    func testDependencyDownloadGoesIntoStorageHiddenAndResolvable() async throws {
        let wallpaper = try makeWallpaper("1000000001", in: storage.url, referencing: "2000000002")
        let dependencies = makeDependencyService()

        dependencies.ensureDependencies(ofItemAt: wallpaper)
        try await sleepUntil("the dependency is installed", timeout: 10) { @Sendable @MainActor in dependencies.states["2000000002"] == .installed }

        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url.appending(path: "2000000002/project.json").path))
        XCTAssertEqual(try children(of: storage.url), ["1000000001", "2000000002", WorkshopDependencyIndex.fileName])
        XCTAssertTrue(dependencyIndex.contains("2000000002"))
        XCTAssertEqual(listed(in: storage.url), ["1000000001"], "a dependency-only item stays out of Installed")
        XCTAssertEqual(WorkshopAssetResolver(roots: [storage.url]).itemDirectory(for: "2000000002")?.standardizedFileURL,
                       storage.url.appending(path: "2000000002").standardizedFileURL)
    }

    /// A dependency Steam reports removed is never downloaded, is remembered for the next
    /// load, and the wallpaper still loads: its assets resolve as missing and nothing waits on it.
    func testUnavailableDependencyIsSkippedAndTheWallpaperStillLoads() async throws {
        let wallpaper = try makeWallpaper("1000000001", in: storage.url, referencing: "9000000009")
        let reloads = LockedValue(0)
        let observer = NotificationCenter.default.addObserver(forName: .workshopDependenciesDidInstall, object: nil,
                                                              queue: .main) { _ in reloads.mutate { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        let dependencies = makeDependencyService(availability: { _ in ["9000000009": .unavailable(.removedOrPrivate)] })

        dependencies.ensureDependencies(ofItemAt: wallpaper)
        try await sleepUntil("the dependency is unavailable", timeout: 10) { @Sendable @MainActor in
            dependencies.states["9000000009"] == .itemUnavailable(.removedOrPrivate)
        }

        XCTAssertTrue(workshopDownloads.installDirectories.isEmpty, "a removed item isn't downloaded")
        XCTAssertTrue(dependencies.pending.isEmpty)
        XCTAssertEqual(dependencies.unavailableReason(for: "9000000009"), .removedOrPrivate)
        XCTAssertEqual(reloads.value, 0)
        // Loading: the reference resolves as missing and no link is made.
        let resolver = WorkshopAssetResolver(roots: [storage.url])
        WorkshopDependencyResolver.linkInstalledDependencies(inItemAt: wallpaper, resolver: resolver)
        XCTAssertNil(resolver.url(for: "effects/workshop/9000000009/glow/effect.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wallpaper.appending(path: "effects/workshop").path))

        // A later load skips it without asking Steam.
        let later = makeDependencyService(availability: { ids in
            XCTFail("asked Steam again for \(ids)")
            return [:]
        })
        later.ensureDependencies(ofItemAt: wallpaper)
        try await sleepUntil("the skipped dependency is reported", timeout: 10) { @Sendable @MainActor in
            later.states["9000000009"] == .itemUnavailable(.removedOrPrivate)
        }
        XCTAssertTrue(workshopDownloads.installDirectories.isEmpty)
    }

    /// A download that finds no manifest reads as a removed item, with the clear message, and is remembered.
    func testAMissingManifestMarksTheDependencyUnavailable() async throws {
        let wallpaper = try makeWallpaper("1000000001", in: storage.url, referencing: "9000000009")
        let dependencies = makeDependencyService()

        dependencies.ensureDependencies(ofItemAt: wallpaper)
        try await sleepUntil("the dependency is unavailable", timeout: 10) { @Sendable @MainActor in
            dependencies.states["9000000009"] == .itemUnavailable(.removedOrPrivate)
        }

        XCTAssertEqual(service.downloadProgress["9000000009"],
                       .failed(WorkshopItemAvailability.Reason.removedOrPrivate.message))
        XCTAssertTrue(dependencies.pending.isEmpty)
        XCTAssertEqual(makeDependencyService().unavailableReason(for: "9000000009"), .removedOrPrivate)
    }

    /// When Steam can't be reached the dependency is downloaded as before.
    func testOfflineCheckFallsBackToDownloading() async throws {
        let wallpaper = try makeWallpaper("1000000001", in: storage.url, referencing: "2000000002")
        let dependencies = makeDependencyService(availability: { _ in throw WorkshopAPIError.requestFailed })

        dependencies.ensureDependencies(ofItemAt: wallpaper)
        try await sleepUntil("the dependency is installed", timeout: 10) { @Sendable @MainActor in dependencies.states["2000000002"] == .installed }
    }

    /// Retry forgets the item and checks it again; an item back on Steam downloads.
    func testRetryChecksAnUnavailableDependencyAgain() async throws {
        let wallpaper = try makeWallpaper("1000000001", in: storage.url, referencing: "2000000002")
        var removed = true
        let dependencies = makeDependencyService(availability: { _ in
            removed ? ["2000000002": .unavailable(.otherApp)] : ["2000000002": .available]
        })
        dependencies.ensureDependencies(ofItemAt: wallpaper)
        try await sleepUntil("the dependency is unavailable", timeout: 10) { @Sendable @MainActor in
            dependencies.states["2000000002"] == .itemUnavailable(.otherApp)
        }

        removed = false
        dependencies.retry(["2000000002"], forItemAt: wallpaper)
        try await sleepUntil("the dependency is installed", timeout: 10) { @Sendable @MainActor in dependencies.states["2000000002"] == .installed }
        XCTAssertNil(dependencies.unavailableReason(for: "2000000002"))
    }

    func testRedownloadKeepsTheInstalledItemAndLeavesNoCopy() async throws {
        _ = await download("1000000001")
        let marker = storage.url.appending(path: "1000000001/settings-marker")
        try Data().write(to: marker)

        let destination = await download("1000000001")

        XCTAssertNotNil(destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try children(of: storage.url), ["1000000001"])
    }

    func testUpdateDownloadsOverACopyOfTheInstalledItem() async throws {
        _ = await download("1000000001")
        let item = storage.url.appending(path: "1000000001", directoryHint: .isDirectory)
        // A file Steam's manifest still has: in the copy, DepotDownloader only checks it.
        try Data("unchanged".utf8).write(to: item.appending(path: "textures.bin"))
        try Data(#"{"type": "scene", "title": "Old"}"#.utf8).write(to: item.appending(path: "project.json"))
        let updated = Updates(service)

        service.updateWorkshopItem(workshopId: "1000000001", title: "Item", previewURL: nil)
        try await sleepUntil("the update is in", timeout: 10) { @Sendable @MainActor in updated.ids == ["1000000001"] }

        XCTAssertEqual(try String(contentsOf: item.appending(path: "textures.bin"), encoding: .utf8), "unchanged")
        XCTAssertTrue(try String(contentsOf: item.appending(path: "project.json"), encoding: .utf8).contains("Item 1000000001"))
        XCTAssertEqual(try children(of: storage.url), ["1000000001"])
        XCTAssertEqual(service.downloadProgress["1000000001"], .completed)
    }

    func testUpdateKeepsTheUserFilesOfAConvertedBundle() async throws {
        _ = await download("1000000001")
        let item = storage.url.appending(path: "1000000001", directoryHint: .isDirectory)
        try Data("{}".utf8).write(to: item.appending(path: WallpaperPackageConverter.manifestName))
        try Data("converted".utf8).write(to: item.appending(path: "converted.tex"))
        let userFiles = item.appending(path: WebUserFiles.pathPrefix, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: userFiles, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: userFiles.appending(path: "photo.jpg"))
        let updated = Updates(service)

        service.updateWorkshopItem(workshopId: "1000000001", title: "Item", previewURL: nil)
        try await sleepUntil("the update is in", timeout: 10) { @Sendable @MainActor in updated.ids == ["1000000001"] }

        // A converted bundle's files aren't the Workshop's, so it downloads in full.
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.appending(path: "converted.tex").path))
        XCTAssertEqual(try String(contentsOf: userFiles.appending(path: "photo.jpg"), encoding: .utf8), "mine")
        XCTAssertEqual(try children(of: storage.url), ["1000000001"])
    }

    func testUpdateCheckUpdatesOnlyItemsChangedSinceTheirDownload() async throws {
        _ = await download("1000000001")
        _ = await download("1000000002")
        let downloadedAt = try XCTUnwrap(downloadedIndex.contentDate(for: "1000000001"))
        let unchangedAt = downloadedIndex.contentDate(for: "1000000002")
        let seconds = Int(downloadedAt.timeIntervalSince1970)
        let checker = WorkshopUpdateChecker(downloads: service, index: downloadedIndex) { ids in
            ids.map {
                WorkshopItem(id: $0, title: $0, previewURL: nil, tags: [], subscriptions: 0, fileSize: 0,
                             creatorAppId: nil, creatorId: nil, description: nil, votesUp: 0, votesDown: 0,
                             timeUpdated: $0 == "1000000001" ? seconds + 60 : seconds - 60)
            }
        }
        let updated = Updates(service)

        await checker.checkNow()
        try await sleepUntil("the update is in", timeout: 10) { @Sendable @MainActor in !updated.ids.isEmpty }

        XCTAssertEqual(updated.ids, ["1000000001"])
        XCTAssertEqual(workshopDownloads.installDirectories.count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(downloadedIndex.contentDate(for: "1000000001")), downloadedAt)
        XCTAssertEqual(downloadedIndex.contentDate(for: "1000000002"), unchangedAt)
    }

    func testItemsDownloadedBeforeContentDatesUseTheirDateAdded() {
        downloadedIndex.insert("1000000001")

        XCTAssertNotNil(downloadedIndex.contentDate(for: "1000000001"))
        XCTAssertNil(downloadedIndex.contentDate(for: "1000000002"))
    }

    func testOutdatedNeedsSteamsDateAndTheDownloadDate() {
        func item(_ id: String, _ updated: Int?) -> WorkshopItem {
            WorkshopItem(id: id, title: id, previewURL: nil, tags: [], subscriptions: 0, fileSize: 0, creatorAppId: nil,
                         creatorId: nil, description: nil, votesUp: 0, votesDown: 0, timeUpdated: updated)
        }
        let downloaded = Date(timeIntervalSince1970: 1_000)

        let outdated = WorkshopUpdateChecker.outdated(
            [item("1", 2_000), item("2", 500), item("3", nil), item("4", 2_000)],
            downloadedAt: { $0 == "4" ? nil : downloaded })

        XCTAssertEqual(outdated.map(\.id), ["1"])
    }

    func testFailedDownloadReportsTheReasonAndCleansUp() async throws {
        let destination = await download("9999999999")

        XCTAssertNil(destination)
        guard case .failed(let message) = service.downloadProgress["9999999999"] else {
            return XCTFail("expected a failure, got \(String(describing: service.downloadProgress["9999999999"]))")
        }
        // A missing manifest is shown as what it means.
        XCTAssertEqual(message, WorkshopItemAvailability.Reason.removedOrPrivate.message)
        XCTAssertEqual(try children(of: storage.url), [])
    }

    func testChangedStorageTakesNewDownloads() async throws {
        let firstStorage = storage.url
        _ = await download("1000000001")
        let secondStorage = root.appending(path: "Storage B", directoryHint: .isDirectory)
        storage.url = secondStorage

        let destination = await download("3000000003")

        XCTAssertEqual(destination?.standardizedFileURL, secondStorage.appending(path: "3000000003").standardizedFileURL)
        XCTAssertEqual(try children(of: secondStorage), ["3000000003"])
        XCTAssertEqual(try children(of: firstStorage), ["1000000001"])
    }

    func testStorageOnDisconnectedVolumeFailsWithoutFallback() async throws {
        let volume = URL(fileURLWithPath: "/Volumes/owe-missing-\(UUID().uuidString)", isDirectory: true)
        storage.url = volume.appending(path: "OpenWallpaperStorage", directoryHint: .isDirectory)

        let destination = await download("1000000001")

        XCTAssertNil(destination)
        guard case .failed(let message) = service.downloadProgress["1000000001"] else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(message.contains("isn't connected"), message)
        XCTAssertTrue(workshopDownloads.installDirectories.isEmpty, "nothing downloads without the storage folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: volume.path))
    }

    // MARK: - Previews

    func testKeptPreviewMovesIntoStorage() async throws {
        dependencyIndex.recordDependencyDownload("1000000001", copiedIntoLibrary: true)
        service.previewWorkshopItem(workshopId: "1000000001")
        try await sleepUntil("the preview is presented", timeout: 10) { @Sendable @MainActor in !presented.isEmpty }
        let preview = try XCTUnwrap(presented.first)
        XCTAssertTrue(WorkshopItemInstaller.isPreview(preview.wallpaperDirectory, cacheRoot: previewCache))
        XCTAssertEqual(try children(of: storage.url), [WorkshopDependencyIndex.fileName], "a preview isn't in the library")

        let kept = try XCTUnwrap(try service.keepPreview(preview))

        XCTAssertEqual(kept.wallpaperDirectory.standardizedFileURL, storage.url.appending(path: "1000000001").standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.wallpaperDirectory.appending(path: "project.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.wallpaperDirectory.path), "no copy stays in the cache")
        XCTAssertFalse(dependencyIndex.contains("1000000001"), "keeping it makes it the user's")
        XCTAssertTrue(downloadedIndex.contains("1000000001"))
        XCTAssertEqual(listed(in: storage.url), ["1000000001"])
    }

    func testKeepPreviewIgnoresLibraryWallpapers() async throws {
        let downloaded = await download("1000000001")
        let destination = try XCTUnwrap(downloaded)
        let wallpaper = WEWallpaper(using: WEProject(file: "scene.json", preview: "", title: "", type: "scene"), where: destination)
        XCTAssertNil(try service.keepPreview(wallpaper))
    }

    // MARK: - Storage folder

    func testUnmountedVolumeIsDetected() {
        XCTAssertNotNil(WallpaperStorage.unmountedVolume(of: URL(fileURLWithPath: "/Volumes/owe-missing-\(UUID().uuidString)/Storage")))
        XCTAssertNil(WallpaperStorage.unmountedVolume(of: root))
    }

    func testMovedLibraryCarriesItsDependencyList() throws {
        let source = root.appending(path: "Old", directoryHint: .isDirectory)
        let destination = root.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        WorkshopDependencyIndex(libraryDirectory: { source }).recordDependencyDownload("2000000002", copiedIntoLibrary: true)
        WorkshopDependencyIndex(libraryDirectory: { source }).recordDependencyDownload("5000000005", copiedIntoLibrary: true)
        WorkshopDependencyIndex(libraryDirectory: { destination }).recordDependencyDownload("6000000006", copiedIntoLibrary: true)

        // 5000000005 was already in the new folder, so it kept its standing there.
        try WorkshopDependencyIndex.carry(from: source, to: destination, movedItems: ["2000000002", "1000000001"])

        XCTAssertEqual(WorkshopDependencyIndex(libraryDirectory: { destination }).ids, ["2000000002", "6000000006"])
    }

    func testMovedLibraryMovesItsDependencyList() throws {
        let source = root.appending(path: "Old", directoryHint: .isDirectory)
        let destination = root.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        WorkshopDependencyIndex(libraryDirectory: { source }).recordDependencyDownload("2000000002", copiedIntoLibrary: true)

        try WorkshopDependencyIndex.carry(from: source, to: destination, movedItems: ["2000000002"])

        XCTAssertEqual(WorkshopDependencyIndex(libraryDirectory: { destination }).ids, ["2000000002"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appending(path: WorkshopDependencyIndex.fileName).path))
    }
}

/// The ids of the items `WorkshopDownloadService.itemUpdated` reported, in order.
@MainActor
private final class Updates {
    private(set) var ids: [String] = []
    private var cancellable: AnyCancellable?

    init(_ service: WorkshopDownloadService) {
        cancellable = service.itemUpdated.sink { [weak self] directory in
            MainActor.assumeIsolated { self?.ids.append(directory.lastPathComponent) }
        }
    }
}

/// Stands in for the Steam helper: a download of a known id writes the item (and DepotDownloader's
/// bookkeeping) into `-dir`; an unknown id is reported removed.
// `@unchecked Sendable`: its one mutable list is guarded by `lock`.
private final class FakeHelper: SteamHelperDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedInstallDirectories: [String] = []

    /// The install dir of each download: `-dir` without `steamapps/workshop/content/431960/<id>`.
    var installDirectories: [String] { lock.withLock { recordedInstallDirectories } }

    func run(arguments: [String], login: SteamLogin, cancellation: ProcessCancellation,
             onOutput: @escaping @Sendable (String) -> Void) -> ProcessRun {
        func value(_ option: String) -> String? {
            arguments.firstIndex(of: option).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        guard let directory = value("-dir").map({ URL(fileURLWithPath: $0, isDirectory: true) }),
              let workshopId = value("-pubfile") else {
            return ProcessRun(output: "no -dir or -pubfile\n", exitCode: 2)
        }
        var installDirectory = directory
        for _ in 0..<5 { installDirectory = installDirectory.deletingLastPathComponent() }
        lock.withLock { recordedInstallDirectories.append(installDirectory.path) }
        guard workshopId.hasPrefix("1") || workshopId.hasPrefix("2") || workshopId.hasPrefix("3") else {
            return ProcessRun(output: "Unable to locate manifest ID for published file \(workshopId)\n", exitCode: 0)
        }
        do {
            try FileManager.default.createDirectory(at: directory.appending(path: SteamHelperDownload.bookkeepingFolderName),
                                                    withIntermediateDirectories: true)
            try Data(#"{"type": "scene", "title": "Item \#(workshopId)", "file": "scene.json", "preview": "preview.jpg"}"#.utf8)
                .write(to: directory.appending(path: "project.json"))
        } catch {
            return ProcessRun(output: "Error: \(error)\n", exitCode: 1)
        }
        onOutput("100.00% project.json\n")
        return ProcessRun(output: "100.00% project.json\nTotal downloaded: 100 bytes\n", exitCode: 0)
    }
}
