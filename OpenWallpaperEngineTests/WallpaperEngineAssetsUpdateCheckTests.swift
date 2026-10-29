import XCTest
@testable import OpenWallpaperEngine

/// "Update from Steam" looks up the current Wallpaper Engine build first and downloads only when
/// it differs from the installed one; "Re-download" always downloads; a failed lookup downloads
/// nothing. The Steam helper is always a fake.
final class WallpaperEngineAssetsUpdateCheckTests: XCTestCase {
    private typealias Check = WallpaperEngineAssetsUpdateCheck
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appending(path: "owe-assets-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch) // scratch cleanup
    }

    // MARK: Skip or update

    func testTheDecisionSkipsOnlyACompleteCopyOfTheCurrentBuild() {
        let steam = WallpaperEngineAssetsCache.Info(origin: .steam, installedAt: .now, steamBuildID: "100")
        let folder = WallpaperEngineAssetsCache.Info(origin: .folder, installedAt: .now)
        XCTAssertEqual(Check.decision(installed: steam, assetsComplete: true, currentBuild: "100"), .upToDate(build: "100"))
        XCTAssertEqual(Check.decision(installed: steam, assetsComplete: true, currentBuild: "101"), .download)
        XCTAssertEqual(Check.decision(installed: steam, assetsComplete: false, currentBuild: "100"), .download)
        XCTAssertEqual(Check.decision(installed: folder, assetsComplete: true, currentBuild: "100"), .download)
        XCTAssertEqual(Check.decision(installed: nil, assetsComplete: false, currentBuild: "100"), .download)

        XCTAssertTrue(Check.needsLookup(force: false, installed: steam, assetsComplete: true))
        XCTAssertFalse(Check.needsLookup(force: true, installed: steam, assetsComplete: true), "Re-download")
        XCTAssertFalse(Check.needsLookup(force: false, installed: steam, assetsComplete: false), "damaged copy")
        XCTAssertFalse(Check.needsLookup(force: false, installed: folder, assetsComplete: true))
        XCTAssertFalse(Check.needsLookup(force: false, installed: nil, assetsComplete: false))
    }

    // MARK: Service

    @MainActor
    func testTheCurrentBuildIsNotDownloadedAgain() async throws {
        try installCache(build: "100")
        let helper = RecordingDownloader()
        let service = await makeService(appInfo: .build("100"), helper: helper)
        service.installFromSteam()
        try await waitUntilSettled(service)
        XCTAssertEqual(service.phase, .idle)
        XCTAssertTrue(service.notice?.contains("100") == true, String(describing: service.notice))
        XCTAssertEqual(helper.count, 0)
    }

    @MainActor
    func testANewerBuildDownloadsAndIsRecorded() async throws {
        try installCache(build: "100")
        let helper = RecordingDownloader()
        let service = await makeService(appInfo: .build("101"), helper: helper)
        service.installFromSteam()
        try await waitUntilSettled(service)
        XCTAssertEqual(service.phase, .idle)
        XCTAssertNil(service.notice)
        XCTAssertEqual(helper.count, 1)
        XCTAssertEqual(WallpaperEngineAssetsCache.readInfo(cache: cache)?.steamBuildID, "101")
    }

    @MainActor
    func testReDownloadSkipsTheCheck() async throws {
        try installCache(build: "100")
        let helper = RecordingDownloader()
        let service = await makeService(appInfo: .build("100"), helper: helper)
        service.installFromSteam(force: true)
        try await waitUntilSettled(service)
        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(helper.count, 1)
    }

    @MainActor
    func testAFailedCheckDownloadsNothing() async throws {
        try installCache(build: "100")
        let helper = RecordingDownloader()
        let service = await makeService(appInfo: .error("network"), helper: helper)
        service.installFromSteam()
        try await waitUntilSettled(service)
        guard case .updateCheckFailed = service.lastFailure else { return XCTFail("\(String(describing: service.lastFailure))") }
        XCTAssertEqual(helper.count, 0)
        XCTAssertEqual(WallpaperEngineAssetsCache.readInfo(cache: cache)?.steamBuildID, "100")

        let loggedOut = await makeService(appInfo: .error("tokenRejected"), helper: helper)
        loggedOut.installFromSteam()
        try await waitUntilSettled(loggedOut)
        XCTAssertEqual(loggedOut.lastFailure, .notLoggedIn)
        XCTAssertEqual(helper.count, 0)
    }

    // MARK: Helpers

    private enum AppInfo {
        case build(String)
        /// A helper error with this code.
        case error(String)
    }

    private var cache: URL { WallpaperEngineAssets.cacheDirectory(in: scratch) }

    private func installCache(build: String) throws {
        for folder in ["shaders", "effects"] {
            try FileManager.default.createDirectory(at: cache.appending(path: folder), withIntermediateDirectories: true)
        }
        try WallpaperEngineAssetsCache.writeInfo(.init(origin: .steam, installedAt: .now, steamBuildID: build), cache: cache)
    }

    @MainActor
    private func makeService(appInfo: AppInfo, helper: RecordingDownloader) async -> WallpaperEngineAssetsService {
        let storage: URL = scratch
        let defaults = UserDefaults(suiteName: "owe-tests-\(UUID().uuidString)")!
        let steamCmd = SteamCmdService(dependencyIndex: WorkshopDependencyIndex(libraryDirectory: { storage }),
                                       helperDownloads: helper, storageDirectory: { storage },
                                       previewCacheRoot: storage.appending(path: "previews"),
                                       downloadedIndex: DownloadedWallpaperIndex(defaults: defaults, libraryDirectory: { storage }),
                                       presentPreview: { _ in })
        steamCmd.useSteamLogin(FakeSteamHelperTransport.login)
        let client = SteamHelperClient {
            FakeSteamHelperTransport { request in
                guard request.method == "appInfo" else { return [FakeSteamHelperTransport.result(request)] }
                switch appInfo {
                case .build(let build):
                    return [FakeSteamHelperTransport.result(request, #"{"appID":431960,"publicBuildID":"\#(build)","depots":[]}"#)]
                case .error(let code):
                    return [FakeSteamHelperTransport.error(request, code: code)]
                }
            }
        }
        await client.use(FakeSteamHelperTransport.login)
        return WallpaperEngineAssetsService(steamCmd: steamCmd, steamHelper: client, helperDownloads: helper,
                                            storageDirectory: { storage }, defaults: defaults)
    }

    @MainActor
    private func waitUntilSettled(_ service: WallpaperEngineAssetsService) async throws {
        let deadline = Date().addingTimeInterval(10)
        // The phase is `.downloading` from the start; the lookup and download run after.
        while service.isBusy {
            guard Date() < deadline else { return XCTFail("the install didn't finish") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A fake Steam helper download that counts its runs and writes a tiny asset tree into `-dir`.
private final class RecordingDownloader: SteamHelperDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0 // Owned by `lock`.
    var count: Int { lock.withLock { runs } }

    func run(arguments: [String], login: SteamLogin, cancellation: SteamCmdCancellation,
             onOutput: @escaping @Sendable (String) -> Void) -> SteamCmdRun {
        lock.withLock { runs += 1 }
        guard let index = arguments.firstIndex(of: "-dir"), index + 1 < arguments.count else {
            return SteamCmdRun(output: "no -dir", exitCode: 2)
        }
        let install = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        do {
            for (relative, text) in [("assets/shaders/common.h", "x"), ("assets/effects/tint/effect.json", "{}")] {
                let url = install.appending(path: relative)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
        } catch {
            return SteamCmdRun(output: "write failed: \(error)", exitCode: 1)
        }
        return SteamCmdRun(output: "100.00% assets/shaders/common.h\nTotal downloaded: 1 bytes", exitCode: 0)
    }
}
