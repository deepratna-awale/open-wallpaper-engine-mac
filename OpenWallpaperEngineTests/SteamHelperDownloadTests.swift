import Combine
import XCTest
@testable import OpenWallpaperEngine

/// Downloads through the Steam login: the helper's `download` arguments and output, and Workshop
/// downloads with a fake helper that "downloads" by writing files into `-dir`.
@MainActor
final class SteamHelperDownloadTests: XCTestCase {
    /// A stand-in for `owe-steam-helper download`: records each run and answers with `respond`,
    /// which gets the `-dir` folder to write into.
    private final class FakeHelper: SteamHelperDownloading, @unchecked Sendable {
        // `lock` owns `runs`.
        private let lock = NSLock()
        private var runs: [[String]] = []
        private let respond: @Sendable (URL) throws -> SteamCmdRun

        init(respond: @escaping @Sendable (URL) throws -> SteamCmdRun) {
            self.respond = respond
        }

        var arguments: [[String]] { lock.withLock { runs } }

        func run(arguments: [String], login: SteamLogin, cancellation: SteamCmdCancellation,
                 onOutput: @escaping @Sendable (String) -> Void) -> SteamCmdRun {
            lock.withLock { runs.append(arguments) }
            guard let index = arguments.firstIndex(of: "-dir"), index + 1 < arguments.count else {
                return SteamCmdRun(output: "no -dir", exitCode: 2)
            }
            do {
                let run = try respond(URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
                onOutput(run.output)
                return run
            } catch {
                return SteamCmdRun(output: "\(error)", exitCode: 1)
            }
        }
    }

    private static let login = SteamLogin(accountName: "owe_test", steamID: "76561190000000001", refreshToken: "test-refresh-token")

    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "owe-helper-download-\(UUID().uuidString)",
                                                                directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    /// `sleepUntil` for main-actor state.
    private func waitFor(_ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting for \(what)", file: file, line: line) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Arguments and output

    func testWorkshopAndAssetsArguments() {
        let folder = URL(fileURLWithPath: "/Volumes/Storage/item", isDirectory: true)
        XCTAssertEqual(SteamHelperDownload.workshopArguments(workshopId: "123", directory: folder, validate: true),
                       ["-app", "431960", "-pubfile", "123", "-dir", "/Volumes/Storage/item", "-validate"])
        XCTAssertEqual(SteamHelperDownload.workshopArguments(workshopId: "123", directory: folder, validate: false),
                       ["-app", "431960", "-pubfile", "123", "-dir", "/Volumes/Storage/item"])
        XCTAssertEqual(SteamHelperDownload.assetsArguments(directory: folder, fileList: URL(fileURLWithPath: "/tmp/list.txt")),
                       ["-app", "431960", "-depot", "431961", "-depot", "431966", "-dir", "/Volumes/Storage/item",
                        "-filelist", "/tmp/list.txt", "-validate"])
    }

    func testTheLoginLineHasOnlyTheAccountAndToken() throws {
        let line = try SteamHelperDownload.standardInput(for: Self.login)
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: String])
        XCTAssertEqual(object, ["accountName": "owe_test", "refreshToken": "test-refresh-token"])
    }

    /// The file list's regexes, read the way DepotDownloader reads them (case-insensitive).
    func testTheAssetsFileListTakesOnlyWhatTheCacheKeeps() throws {
        let patterns = try SteamHelperDownload.assetsFileList.split(separator: "\n").map { line in
            XCTAssertTrue(line.hasPrefix("regex:"), String(line))
            return try NSRegularExpression(pattern: String(line.dropFirst("regex:".count)), options: .caseInsensitive)
        }
        func included(_ path: String) -> Bool {
            patterns.contains { $0.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil }
        }
        for path in ["assets/materials/white.tex", "locale/ui_en-us.json", "projects/templates/scene/project.json",
                     "projects/defaultprojects/rain/project.json", "ui/dist/monaco/snippets/glsl.json"] {
            XCTAssertTrue(included(path), path)
        }
        for path in ["wallpaper64.exe", "bin/ui32.exe", "locale/steam_en-us.json", "ui/dist/index.js",
                     "projects/myprojects/x/project.json", "notassets/x"] {
            XCTAssertFalse(included(path), path)
        }
    }

    func testTheOutcomeTellsLoginRemovedItemsOwnershipAndErrorsApart() {
        typealias Download = SteamHelperDownload
        XCTAssertEqual(Download.outcome(output: "Access token was rejected (AccessDenied).\nUnable to get steam3 credentials.",
                                        exitCode: 1, downloaded: false), .loginRejected)
        XCTAssertEqual(Download.outcome(output: "Could not connect to Steam after 10 tries\nUnable to get steam3 credentials.",
                                        exitCode: 1, downloaded: false),
                       .failed("Unable to get steam3 credentials."), "a network failure isn't the login's")
        XCTAssertEqual(Download.outcome(output: "Unable to locate manifest ID for published file 123", exitCode: 0,
                                        downloaded: false), .unavailable)
        XCTAssertEqual(Download.outcome(output: "Depot 431961 is not available from this account.", exitCode: 0,
                                        downloaded: false), .notOwned)
        XCTAssertEqual(Download.outcome(output: "100.00% project.json\nTotal downloaded: 10 bytes", exitCode: 0,
                                        downloaded: true), .downloaded)
        XCTAssertEqual(Download.outcome(output: "Total downloaded: 0 bytes", exitCode: 0, downloaded: false),
                       .failed("Total downloaded: 0 bytes"))
    }

    func testProgressReadsTheLastPercentage() throws {
        XCTAssertEqual(try XCTUnwrap(SteamHelperDownload.progress(in: " 12.50% scene.json\n 45.00% scene.pkg\n")), 0.45,
                       accuracy: 0.0001)
        XCTAssertEqual(SteamHelperDownload.progress(in: "100.00% a b.json"), 1)
        XCTAssertNil(SteamHelperDownload.progress(in: "Got depot key for 431961 result: OK"))
    }

    // MARK: Workshop downloads

    private func makeService(_ helper: FakeHelper) throws -> SteamCmdService {
        let storage = root.appending(path: "Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let library = root!
        let suite = "owe-tests-\(UUID().uuidString)"
        let service = SteamCmdService(dependencyIndex: WorkshopDependencyIndex(libraryDirectory: { library }),
                                      runner: UnusedSteamCmd(), helperDownloads: helper,
                                      storageDirectory: { try WallpaperStorage.availableDirectory(storage) },
                                      previewCacheRoot: root.appending(path: "Previews"),
                                      downloadedIndex: DownloadedWallpaperIndex(defaults: UserDefaults(suiteName: suite)!,
                                                                                libraryDirectory: { library }),
                                      presentPreview: { _ in }, account: .inMemory(), restoresSession: false)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return service
    }

    private func download(_ id: String, with service: SteamCmdService) async -> URL? {
        await withCheckedContinuation { continuation in
            service.downloadWorkshopItem(workshopId: id) { continuation.resume(returning: $0) }
        }
    }

    func testTheSteamLoginLogsInAndDownloadsWithoutSteamCmd() async throws {
        let helper = FakeHelper { directory in
            try FileManager.default.createDirectory(at: directory.appending(path: ".DepotDownloader"), withIntermediateDirectories: true)
            try Data(#"{"type": "scene", "title": "T", "file": "scene.json"}"#.utf8).write(to: directory.appending(path: "project.json"))
            return SteamCmdRun(output: "100.00% project.json\n", exitCode: 0)
        }
        let service = try makeService(helper)
        XCTAssertFalse(service.isInstalled)
        var logins = 0
        let cancellable = service.loginSucceeded.sink { logins += 1 }
        defer { cancellable.cancel() }

        service.useSteamLogin(Self.login)
        XCTAssertTrue(service.isInstalled, "no SteamCMD needed")
        XCTAssertTrue(service.isLoggedIn)
        XCTAssertEqual(service.steamUsername, "owe_test")
        XCTAssertEqual(logins, 1)

        let downloaded = await download("1000000001", with: service)
        let destination = try XCTUnwrap(downloaded)
        let files = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertTrue(files.contains("project.json"))
        XCTAssertFalse(files.contains(SteamHelperDownload.bookkeepingFolderName), "DepotDownloader's bookkeeping is gone")
        XCTAssertEqual(service.downloadProgress["1000000001"], .completed)
        XCTAssertEqual(helper.arguments.first?.prefix(4), ["-app", "431960", "-pubfile", "1000000001"])

        service.useSteamLogin(nil)
        XCTAssertFalse(service.isLoggedIn)
        XCTAssertFalse(service.isInstalled)
    }

    func testARemovedItemIsReportedUnavailable() async throws {
        let service = try makeService(FakeHelper { _ in
            SteamCmdRun(output: "Unable to locate manifest ID for published file 1000000002", exitCode: 0)
        })
        service.useSteamLogin(Self.login)
        var unavailable: [String] = []
        let cancellable = service.itemUnavailable.sink { unavailable.append($0) }
        defer { cancellable.cancel() }

        let destination = await download("1000000002", with: service)
        XCTAssertNil(destination)
        XCTAssertEqual(unavailable, ["1000000002"])
        guard case .failed = service.downloadProgress["1000000002"] else {
            return XCTFail("\(String(describing: service.downloadProgress["1000000002"]))")
        }
    }

    func testARejectedLoginIsReported() async throws {
        let service = try makeService(FakeHelper { _ in
            SteamCmdRun(output: "Access token was rejected (Revoked).", exitCode: 1)
        })
        service.useSteamLogin(Self.login)
        var rejected = 0
        let cancellable = service.steamLoginRejected.sink { rejected += 1 }
        defer { cancellable.cancel() }

        let destination = await download("1000000003", with: service)
        XCTAssertNil(destination)
        try await waitFor("the rejection") { rejected == 1 }
        XCTAssertEqual(service.downloadProgress["1000000003"],
                       .failed(SteamHelperError(code: .tokenRejected, message: "").errorDescription ?? ""))
    }
}

/// steamcmd, which these tests never run.
private struct UnusedSteamCmd: SteamCmdRunning {
    func run(executable: URL, script: SteamCmdScript, timeout: TimeInterval?,
             onOutput: @escaping @Sendable (String) -> Void) -> SteamCmdRun {
        XCTFail("steamcmd ran")
        return SteamCmdRun(output: "", exitCode: 1)
    }
}
