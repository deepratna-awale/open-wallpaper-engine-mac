import XCTest
@testable import OpenWallpaperEngine

/// Installing the assets from the user's Steam copy through the Steam login: the subset kept in the
/// cache, the default wallpapers, and the service's states. The Steam helper is always a fake.
final class WallpaperEngineAssetsInstallTests: XCTestCase {
    private var scratch: URL!
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "owe-tests-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appending(path: "owe-assets-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch) // scratch cleanup
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    private func write(_ text: String, to path: String, in directory: URL) throws {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    // MARK: Cache layout

    /// The same subset `Scripts/fill-assets-cache.sh` takes: no preview projects (of effects and
    /// presets), no HLSL or editor shaders, the presets the editor offers, the locale's `ui_*.json`
    /// from beside `assets`, and nothing else of the install.
    func testTheCacheKeepsOnlyTheAssetsSubset() throws {
        let install = scratch.appending(path: "download")
        let assets = install.appending(path: "assets")
        for path in ["effects/tint/effect.json", "effects/tint/preview/preview.jpg", "shaders/common.h",
                     "shaders/HLSL/common.hlsl", "shaders/editor/grid.frag", "materials/util/white.json",
                     "models/util/sphere.mdl", "particles/fire.json", "scripts/jsclasses/baseclasses.js",
                     "zcompat/web/1.json", "fonts/Roboto.ttf", "fonts/SIL Open Font License.txt",
                     "presets/rain/preset.json", "presets/rain/particles/presets/rain.json",
                     "presets/rain/previewdownpour/scene.json", "scenes/particleeditor/scene.json",
                     "effects/tint/.DS_Store"] {
            try write(path, to: path, in: assets)
        }
        try write("{}", to: "locale/ui_en-us.json", in: install)
        try write("{}", to: "locale/other.json", in: install)
        try write("exe", to: "wallpaper64.exe", in: install)

        let cache = WallpaperEngineAssets.cacheDirectory(in: scratch.appending(path: "storage"))
        let info = WallpaperEngineAssetsCache.Info(origin: .steam, installedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                                   steamBuildID: "7")
        let copied = try WallpaperEngineAssetsCache.fill(cache, from: install, info: info)

        let files = try Set(FileManager.default.subpathsOfDirectory(atPath: cache.path).filter {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: cache.appending(path: $0).path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        })
        XCTAssertEqual(files, ["effects/tint/effect.json", "shaders/common.h", "materials/util/white.json",
                               "models/util/sphere.mdl", "particles/fire.json", "scripts/jsclasses/baseclasses.js",
                               "zcompat/web/1.json", "fonts/Roboto.ttf", "fonts/SIL Open Font License.txt",
                               "presets/rain/preset.json", "presets/rain/particles/presets/rain.json",
                               "locale/ui_en-us.json", ".owe-assets-info.json"])
        XCTAssertEqual(copied, 12)
        XCTAssertEqual(WallpaperEngineAssetsCache.readInfo(cache: cache), info)
        XCTAssertTrue(WallpaperEngineAssets.isAssetTree(cache))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path + ".partial"))
    }

    /// A folder that isn't an install is refused, and a cancelled copy keeps the previous cache.
    func testAFailedOrCancelledFillKeepsThePreviousCache() throws {
        let cache = WallpaperEngineAssets.cacheDirectory(in: scratch)
        try write("old", to: "shaders/common.h", in: cache)
        try write("{}", to: "effects/old/effect.json", in: cache)
        let info = WallpaperEngineAssetsCache.Info(origin: .folder, installedAt: .now, steamBuildID: nil)
        XCTAssertThrowsError(try WallpaperEngineAssetsCache.fill(cache, from: scratch.appending(path: "nothing"), info: info))

        let install = scratch.appending(path: "install")
        try write("new", to: "assets/shaders/common.h", in: install)
        try write("{}", to: "assets/effects/new/effect.json", in: install)
        XCTAssertThrowsError(try WallpaperEngineAssetsCache.fill(cache, from: install, info: info, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try String(contentsOf: cache.appending(path: "shaders/common.h"), encoding: .utf8), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path + ".partial"))
    }

    // MARK: Default wallpapers

    /// Only `projects/defaultprojects` comes in, scene, video and web only (application skipped,
    /// declared or implied by an `.exe`), names kept, and an existing folder never replaced.
    func testDefaultWallpapersComeInWithoutApplicationsOrOverwrites() throws {
        let install = scratch.appending(path: "download"), storage = scratch.appending(path: "storage")
        let projects: [(String, String)] = [
            ("aurora", #"{"title":"A","file":"scene.json","type":"scene"}"#),
            ("untyped", #"{"title":"U","file":"untyped.json"}"#),
            ("clip", #"{"title":"C","file":"clip.mp4","type":"Video"}"#),
            ("page", #"{"title":"P","file":"index.html","type":"web"}"#),
            ("game", #"{"title":"G","file":"game.exe","type":"application"}"#),
            ("sheep", #"{"title":"S","file":"sheep.exe"}"#),
            ("taken", #"{"title":"T","file":"scene.json","type":"scene"}"#),
        ]
        for (name, json) in projects {
            try write(json, to: "projects/defaultprojects/\(name)/project.json", in: install)
            try write("x", to: "projects/defaultprojects/\(name)/content.bin", in: install)
        }
        try write("x", to: "projects/defaultprojects/no-project/readme.txt", in: install)
        try write(#"{"title":"M","file":"scene.json","type":"scene"}"#, to: "projects/myprojects/mine/project.json", in: install)
        try write("mine", to: "taken/project.json", in: storage)

        let result = try WallpaperEngineDefaultProjects.importProjects(from: install, into: storage, move: true)
        XCTAssertEqual(result.imported, ["aurora", "clip", "page", "untyped"])
        XCTAssertEqual(result.existing, ["taken"])
        XCTAssertEqual(result.unsupported, ["game", "sheep"])
        XCTAssertEqual(try String(contentsOf: storage.appending(path: "taken/project.json"), encoding: .utf8), "mine")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.appending(path: "aurora/content.bin").path))
        for absent in ["game", "sheep", "mine", "no-project"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: storage.appending(path: absent).path), absent)
        }
        let none = try WallpaperEngineDefaultProjects.importProjects(from: scratch.appending(path: "empty"), into: storage, move: false)
        XCTAssertEqual(none, .init())
    }

    /// WE's default projects may leave out `type`; the library then reads the one `file` implies.
    func testAProjectWithoutATypeTakesTheOneItsFileImplies() throws {
        let scene = try JSONDecoder().decode(WEProject.self, from: Data(#"{"title":"A","file":"audiophile.json"}"#.utf8))
        XCTAssertEqual(scene.type, "scene")
        let typed = try JSONDecoder().decode(WEProject.self, from: Data(#"{"title":"A","file":"a.json","type":"video"}"#.utf8))
        XCTAssertEqual(typed.type, "video")
        XCTAssertEqual(WEProject.impliedType(file: "sheep.exe"), "application")
        XCTAssertEqual(WEProject.impliedType(file: "index.html"), "web")
        XCTAssertEqual(WEProject.impliedType(file: "assets.json", category: "Asset"), "")
    }

    /// WE marks its own default projects `"official": true`; the Details panel names their
    /// author Wallpaper Engine. Workshop items leave it out.
    func testAnOfficialProjectIsMarked() throws {
        let official = try JSONDecoder().decode(WEProject.self, from: Data(#"{"title":"Dino Run","file":"scene.json","official":true}"#.utf8))
        XCTAssertEqual(official.official, true)
        let workshop = try JSONDecoder().decode(WEProject.self, from: Data(#"{"title":"A","file":"scene.json"}"#.utf8))
        XCTAssertNil(workshop.official)
    }

    // MARK: Service

    /// A download service logged in with `login`, or logged out.
    @MainActor
    private func makeSteamCmd(storage: URL, login: SteamLogin? = FakeSteamHelperTransport.login) -> SteamCmdService {
        let steamCmd = SteamCmdService(dependencyIndex: WorkshopDependencyIndex(libraryDirectory: { storage }),
                                       helperDownloads: AssetsHelper(), storageDirectory: { storage },
                                       previewCacheRoot: storage.appending(path: "previews"),
                                       downloadedIndex: DownloadedWallpaperIndex(defaults: makeDefaults(),
                                                                                 libraryDirectory: { storage }),
                                       presentPreview: { _ in })
        steamCmd.useSteamLogin(login)
        return steamCmd
    }

    /// A Steam helper connection whose app info has build `build`.
    private func makeClient(build: String = "20112233") async -> SteamHelperClient {
        let client = SteamHelperClient {
            FakeSteamHelperTransport { request in
                switch request.method {
                case "appInfo":
                    [FakeSteamHelperTransport.result(request, #"{"appID":431960,"publicBuildID":"\#(build)","depots":[]}"#)]
                default:
                    [FakeSteamHelperTransport.result(request)]
                }
            }
        }
        await client.use(FakeSteamHelperTransport.login)
        return client
    }

    @MainActor
    private func waitUntilFinished(_ service: WallpaperEngineAssetsService) async {
        let finished = expectation(description: "install finished")
        let cancellable = service.$phase.dropFirst().sink { phase in
            switch phase {
            case .idle, .failed: finished.fulfill()
            case .downloading, .copying: break
            }
        }
        await fulfillment(of: [finished], timeout: 10)
        cancellable.cancel()
    }

    @MainActor
    func testTheServiceReportsMissingAssetsAndThatInstallingNeedsTheLogin() throws {
        try XCTSkipIf(WallpaperEngineAssets.directory != nil, "OWE_ASSETS is set for this run")
        let scratch: URL = self.scratch
        let service = WallpaperEngineAssetsService(steamCmd: makeSteamCmd(storage: scratch, login: nil),
                                                   helperDownloads: AssetsHelper(), storageDirectory: { scratch },
                                                   defaults: makeDefaults())
        XCTAssertTrue(service.isMissing)
        service.installFromSteam()
        XCTAssertEqual(service.phase, .failed(WallpaperEngineAssetsService.Failure.notLoggedIn.errorDescription ?? ""))
        XCTAssertFalse(service.isBusy)
    }

    /// The account doesn't own the app: the user is told so, and the download folder is gone afterwards.
    @MainActor
    func testANotOwnedAppIsReportedAndTheDownloadRemoved() async throws {
        let scratch: URL = self.scratch
        let helper = AssetsHelper(output: "Depot 431961 is not available from this account.")
        let service = WallpaperEngineAssetsService(steamCmd: makeSteamCmd(storage: scratch), steamHelper: await makeClient(),
                                                   helperDownloads: helper, storageDirectory: { scratch },
                                                   defaults: makeDefaults())
        service.installFromSteam()
        XCTAssertTrue(service.isBusy)
        await waitUntilFinished(service)
        XCTAssertEqual(service.phase, .failed(WallpaperEngineAssetsService.Failure.notOwned.errorDescription ?? ""))
        XCTAssertEqual(helper.arguments.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: WallpaperEngineAssetsDownload.downloadDirectory(in: scratch).path))
    }

    /// The install with and without the default wallpapers: the assets land in the cache either
    /// way; the default wallpapers only when asked, and never an application one.
    @MainActor
    func testDefaultWallpapersComeInOnlyWhenAsked() async throws {
        for includes in [true, false] {
            let storage = scratch.appending(path: "storage-\(includes)")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let service = WallpaperEngineAssetsService(steamCmd: makeSteamCmd(storage: storage), steamHelper: await makeClient(),
                                                       helperDownloads: AssetsHelper(), storageDirectory: { storage },
                                                       defaults: makeDefaults())
            service.installFromSteam(includingDefaultWallpapers: includes)
            await waitUntilFinished(service)
            XCTAssertEqual(service.phase, .idle)
            XCTAssertTrue(WallpaperEngineAssets.isAssetTree(WallpaperEngineAssets.cacheDirectory(in: storage)))
            XCTAssertEqual(FileManager.default.fileExists(atPath: storage.appending(path: "aurora/project.json").path), includes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: storage.appending(path: "game").path))
            XCTAssertEqual(WallpaperEngineAssetsCache.readInfo(cache: WallpaperEngineAssets.cacheDirectory(in: storage))?.defaultProjects ?? [],
                           includes ? ["aurora"] : [])
        }
    }

    /// The build comes from the helper's app info, and DepotDownloader fetches only the listed
    /// parts of the two depots.
    @MainActor
    func testTheSteamLoginInstallsTheAssetsWithTheHelper() async throws {
        let storage = scratch.appending(path: "storage-helper")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let helper = AssetsHelper()
        let service = WallpaperEngineAssetsService(steamCmd: makeSteamCmd(storage: storage), steamHelper: await makeClient(),
                                                   helperDownloads: helper, storageDirectory: { storage },
                                                   defaults: makeDefaults())
        service.installFromSteam()
        await waitUntilFinished(service)
        XCTAssertEqual(service.phase, .idle)
        let cache = WallpaperEngineAssets.cacheDirectory(in: storage)
        XCTAssertTrue(WallpaperEngineAssets.isAssetTree(cache))
        XCTAssertEqual(WallpaperEngineAssetsCache.readInfo(cache: cache)?.steamBuildID, "20112233")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.appending(path: "aurora/project.json").path))
        let arguments = try XCTUnwrap(helper.arguments.first)
        XCTAssertEqual(Array(arguments.prefix(6)), ["-app", "431960", "-depot", "431961", "-depot", "431966"])
        XCTAssertTrue(arguments.contains("-filelist"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: WallpaperEngineAssetsDownload.downloadDirectory(in: storage).path))
    }

    /// Steam no longer accepts the login: the install fails asking for a new one, and the account
    /// hears about it.
    @MainActor
    func testARejectedLoginAsksForANewOne() async throws {
        let scratch: URL = self.scratch
        let steamCmd = makeSteamCmd(storage: scratch)
        var rejected = 0
        let cancellable = steamCmd.steamLoginRejected.sink { rejected += 1 }
        defer { cancellable.cancel() }
        let service = WallpaperEngineAssetsService(steamCmd: steamCmd, steamHelper: await makeClient(),
                                                   helperDownloads: AssetsHelper(output: "Access token was rejected (Revoked).",
                                                                                 exitCode: 1),
                                                   storageDirectory: { scratch }, defaults: makeDefaults())
        service.installFromSteam()
        await waitUntilFinished(service)
        XCTAssertEqual(service.phase, .failed(WallpaperEngineAssetsService.Failure.notLoggedIn.errorDescription ?? ""))
        XCTAssertEqual(rejected, 1)
    }
}

/// A fake Steam helper that "downloads" the listed parts of Wallpaper Engine into `-dir`: an asset
/// tree and two default projects, one of them an application. With `output`, it only prints that.
private final class AssetsHelper: SteamHelperDownloading, @unchecked Sendable {
    // `lock` owns `runs`.
    private let lock = NSLock()
    private var runs: [[String]] = []
    private let answer: SteamCmdRun?

    init(output: String? = nil, exitCode: Int32 = 0) {
        answer = output.map { SteamCmdRun(output: $0, exitCode: exitCode) }
    }

    var arguments: [[String]] { lock.withLock { runs } }

    func run(arguments: [String], login: SteamLogin, cancellation: SteamCmdCancellation,
             onOutput: @escaping @Sendable (String) -> Void) -> SteamCmdRun {
        lock.withLock { runs.append(arguments) }
        if let answer { return answer }
        guard let index = arguments.firstIndex(of: "-dir"), index + 1 < arguments.count else {
            return SteamCmdRun(output: "no -dir", exitCode: 2)
        }
        let install = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let files: [(String, String)] = [
            ("assets/shaders/common.h", "x"), ("assets/effects/tint/effect.json", "{}"),
            ("projects/defaultprojects/aurora/project.json", #"{"title":"A","file":"scene.json","type":"scene"}"#),
            ("projects/defaultprojects/game/project.json", #"{"title":"G","file":"game.exe","type":"application"}"#),
        ]
        do {
            for (relative, text) in files {
                let url = install.appending(path: relative)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
        } catch {
            return SteamCmdRun(output: "write failed: \(error)", exitCode: 1)
        }
        onOutput("100.00% assets/shaders/common.h\n")
        return SteamCmdRun(output: "100.00% assets/shaders/common.h\nTotal downloaded: 1 bytes", exitCode: 0)
    }
}
