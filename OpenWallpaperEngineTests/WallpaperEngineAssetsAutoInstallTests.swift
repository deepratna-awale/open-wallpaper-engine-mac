import XCTest
import Combine
@testable import OpenWallpaperEngine

/// The Steam install that starts by itself after a login, and the storage move that carries the
/// assets cache along. The Steam helper is always a fake.
final class WallpaperEngineAssetsAutoInstallTests: XCTestCase {
    private var scratch: URL!
    private var suites: [String] = []

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appending(path: "owe-assets-auto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch) // scratch cleanup
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "owe-tests-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func write(_ text: String, to path: String, in directory: URL) throws {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @MainActor
    private func makeServices(helper: RecordingHelper, defaults: UserDefaults)
        -> (SteamCmdService, WallpaperEngineAssetsService) {
        let storage: URL = scratch
        let steamCmd = SteamCmdService(dependencyIndex: WorkshopDependencyIndex(libraryDirectory: { storage }),
                                       helperDownloads: helper, storageDirectory: { storage },
                                       previewCacheRoot: storage.appending(path: "previews"),
                                       downloadedIndex: DownloadedWallpaperIndex(defaults: makeDefaults(),
                                                                                 libraryDirectory: { storage }),
                                       presentPreview: { _ in })
        steamCmd.useSteamLogin(SteamLogin(accountName: "someone", steamID: "76561190000000001", refreshToken: "test-token"))
        let service = WallpaperEngineAssetsService(steamCmd: steamCmd, helperDownloads: helper, storageDirectory: { storage },
                                                   defaults: defaults, automaticInstallAllowed: true)
        return (steamCmd, service)
    }

    @MainActor
    private func waitUntilIdle(_ service: WallpaperEngineAssetsService) {
        let finished = expectation(description: "install finished")
        let cancellable = service.$phase.sink { phase in
            switch phase {
            case .idle, .failed: finished.fulfill()
            case .downloading, .copying: break
            }
        }
        wait(for: [finished], timeout: 10)
        cancellable.cancel()
    }

    // MARK: Trigger conditions

    @MainActor
    func testTheDecisionFollowsTheSettingTheFolderTheCacheAndOwnership() throws {
        let defaults = makeDefaults()
        let (_, service) = makeServices(helper: RecordingHelper(output: "", exitCode: 1), defaults: defaults)
        XCTAssertEqual(service.automaticInstallDecision(), .install(includingDefaultWallpapers: true))

        defaults.set(false, forKey: WallpaperEngineAssetsService.addsDefaultWallpapersKey)
        XCTAssertEqual(service.automaticInstallDecision(), .install(includingDefaultWallpapers: false))

        defaults.set(false, forKey: WallpaperEngineAssetsService.autoInstallKey)
        XCTAssertEqual(service.automaticInstallDecision(), .turnedOff)
        defaults.removeObject(forKey: WallpaperEngineAssetsService.autoInstallKey)

        defaults.set("someone", forKey: WallpaperEngineAssetsService.notOwnedAccountKey)
        XCTAssertEqual(service.automaticInstallDecision(), .notOwned)
        defaults.set("another", forKey: WallpaperEngineAssetsService.notOwnedAccountKey)
        XCTAssertEqual(service.automaticInstallDecision(), .install(includingDefaultWallpapers: false))

        defaults.set("/Some/Install", forKey: WallpaperEngineAssets.chosenFolderKey)
        XCTAssertEqual(service.automaticInstallDecision(), .folderChosen)
        defaults.removeObject(forKey: WallpaperEngineAssets.chosenFolderKey)

        let cache: URL = WallpaperEngineAssets.cacheDirectory(in: scratch)
        try write("x", to: "shaders/common.h", in: cache)
        try write("{}", to: "effects/tint/effect.json", in: cache)
        XCTAssertEqual(service.automaticInstallDecision(), .cached)
    }

    /// A login starts the install; the run then records that the account doesn't own the app, and
    /// the next login shows that instead of downloading again.
    @MainActor
    func testALoginStartsTheInstallOnceAndANotOwnedAccountIsNotRetried() throws {
        let defaults = makeDefaults()
        let runner = RecordingHelper(output: "Depot 431961 is not available from this account.", exitCode: 0)
        let (steamCmd, service) = makeServices(helper: runner, defaults: defaults)
        steamCmd.loginSucceeded.send()
        XCTAssertTrue(service.isBusy)
        steamCmd.loginSucceeded.send() // already running: ignored
        waitUntilIdle(service)
        XCTAssertEqual(runner.count, 1)
        XCTAssertEqual(defaults.string(forKey: WallpaperEngineAssetsService.notOwnedAccountKey), "someone")

        steamCmd.loginSucceeded.send()
        XCTAssertFalse(service.isBusy)
        XCTAssertEqual(service.phase, .failed(WallpaperEngineAssetsService.Failure.notOwned.errorDescription ?? ""))
        XCTAssertEqual(runner.count, 1)
    }

    /// Turned off, or under XCTest by default, a login downloads nothing.
    @MainActor
    func testNoInstallWhenTurnedOffOrUnderXCTest() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: WallpaperEngineAssetsService.autoInstallKey)
        let runner = RecordingHelper(output: "", exitCode: 1)
        let (steamCmd, service) = makeServices(helper: runner, defaults: defaults)
        steamCmd.loginSucceeded.send()
        XCTAssertFalse(service.isBusy)

        let plain = WallpaperEngineAssetsService(steamCmd: steamCmd, helperDownloads: runner, storageDirectory: { self.scratch },
                                                 defaults: makeDefaults())
        steamCmd.loginSucceeded.send()
        XCTAssertFalse(plain.isBusy)
        XCTAssertEqual(runner.count, 0)
    }

    // MARK: Storage move

    /// The assets cache (with its info file) and the app's other hidden data move with the
    /// storage folder; Finder junk, the dependency index (merged separately) and unfinished work
    /// stay behind, and nothing at the destination is replaced.
    func testMovingTheStorageCarriesTheAssetsCacheButNotJunk() throws {
        let source: URL = scratch.appending(path: "A"), destination: URL = scratch.appending(path: "B")
        let cache: URL = WallpaperEngineAssets.cacheDirectory(in: source)
        try write("x", to: "shaders/common.h", in: cache)
        try WallpaperEngineAssetsCache.writeInfo(.init(origin: .steam, installedAt: .now, steamBuildID: "7"), cache: cache)
        for path in ["123/project.json", ".owe-download/x", ".DS_Store", "._123", ".owe-assets-download/x",
                     ".owe-assets.partial/x", ".owe-incoming-1/x", "taken/mine"] {
            try write("s", to: path, in: source)
        }
        try write("[]", to: WorkshopDependencyIndex.fileName, in: source)
        try write("d", to: "taken/mine", in: destination)

        let moved: Set<String> = try WallpaperStorage.moveContents(from: source, to: destination)
        XCTAssertEqual(moved, ["123", ".owe-assets", ".owe-download"])
        let movedCache: URL = WallpaperEngineAssets.cacheDirectory(in: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedCache.appending(path: "shaders/common.h").path))
        XCTAssertEqual(WallpaperEngineAssetsCache.readInfo(cache: movedCache)?.steamBuildID, "7")
        for kept in [".DS_Store", "._123", ".owe-assets-download", ".owe-assets.partial", ".owe-incoming-1",
                     WorkshopDependencyIndex.fileName, "taken"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.appending(path: kept).path), kept)
        }
        XCTAssertEqual(try String(contentsOf: destination.appending(path: "taken/mine"), encoding: .utf8), "d")
    }
}

private final class RecordingHelper: SteamHelperDownloading, @unchecked Sendable {
    let output: String
    let exitCode: Int32
    private let lock = NSLock()
    private var runs = 0
    var count: Int { lock.withLock { runs } }

    init(output: String, exitCode: Int32) {
        self.output = output
        self.exitCode = exitCode
    }

    func run(arguments: [String], login: SteamLogin, cancellation: SteamCmdCancellation,
             onOutput: @escaping @Sendable (String) -> Void) -> SteamCmdRun {
        lock.withLock { runs += 1 }
        return SteamCmdRun(output: output, exitCode: exitCode)
    }
}
