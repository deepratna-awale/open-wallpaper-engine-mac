import Combine
import XCTest
@testable import OpenWallpaperEngine

/// When unpacked wallpapers are downloaded again: after launch, with a later login, and not at all
/// while the user keeps the loose copies; and when a login is asked for.
@MainActor
final class UnpackedBundleRestoreServiceTests: XCTestCase {
    private typealias Fake = FakeSteamHelperTransport

    private var storage: URL!
    private var defaults: UserDefaults!
    private var suite = ""
    private let fm = FileManager.default
    private let logins = PassthroughSubject<Void, Never>()

    override func setUp() async throws {
        storage = fm.temporaryDirectory.appending(path: "owe-unpacked-service-\(UUID().uuidString)")
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        suite = "owe-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: storage) // scratch cleanup
        defaults.removePersistentDomain(forName: suite)
    }

    /// An unpacked wallpaper whose loose files come to `bytes`.
    private func makeBundle(_ name: String, bytes: Int = 2, archived: Bool = false) throws {
        let folder = storage.appending(path: name)
        try fm.createDirectory(at: folder.appending(path: UnpackedBundle.sourceFolderName), withIntermediateDirectories: true)
        try Data(#"{"file": "scene.json", "type": "scene", "title": "T"}"#.utf8).write(to: folder.appending(path: "project.json"))
        try Data(repeating: 0x20, count: bytes).write(to: folder.appending(path: "scene.json"))
        try Data(#"{"sourcePackage": "scene.pkg", "extractedFiles": ["scene.json"]}"#.utf8)
            .write(to: folder.appending(path: UnpackedBundle.manifestName))
        if archived {
            try UnpackedBundleRestoreTests.scenePackage
                .write(to: folder.appending(path: UnpackedBundle.sourceFolderName).appending(path: "scene.pkg"))
        }
    }

    private func makeService(_ downloader: FakePackageDownloader, launchDelay: TimeInterval = 0) -> UnpackedBundleRestoreService {
        let storage = storage!
        return UnpackedBundleRestoreService(
            downloader: downloader, loginSucceeded: logins.eraseToAnyPublisher(), defaults: defaults,
            launchDelay: launchDelay, isShown: { _ in false },
            finish: { bundle, package in _ = bundle.finish(with: package) },
            scan: {
                UnpackedBundle.scan(storage: storage, hasEdits: { _ in false }).map { (bundle: $0, packageOnDisk: $0.packageOnDisk()) }
            })
    }

    private func makeDownloader(isLoggedIn: Bool) -> FakePackageDownloader {
        FakePackageDownloader(result: .package(UnpackedBundleRestoreTests.scenePackage), isLoggedIn: isLoggedIn)
    }

    private func isAsDownloaded(_ name: String) -> Bool {
        let folder = storage.appending(path: name)
        return fm.fileExists(atPath: folder.appending(path: "scene.pkg").path)
            && !fm.fileExists(atPath: folder.appending(path: UnpackedBundle.manifestName).path)
    }

    private func waitFor(_ what: String, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), what)
    }

    func testALoginAfterTheLaunchRunDownloadsWhatWaited() async throws {
        try makeBundle("1000000001")
        try makeBundle("1000000002", archived: true)
        let downloader = makeDownloader(isLoggedIn: false)
        let service = makeService(downloader)
        service.start()
        // The launch run takes the package on disk, and leaves the download.
        try await waitFor("the launch run") { self.isAsDownloaded("1000000002") }
        XCTAssertEqual(downloader.requests, [])

        downloader.isLoggedIn = true
        logins.send()
        try await waitFor("the download") { self.isAsDownloaded("1000000001") }
        XCTAssertEqual(downloader.requests, ["1000000001"])
    }

    func testLoggingInFromThePromptDoesNotWaitForTheLaunchDelay() async throws {
        try makeBundle("1000000001")
        let downloader = makeDownloader(isLoggedIn: true)
        let service = makeService(downloader, launchDelay: 600)
        service.start()
        try await waitFor("the download") {
            service.startDownloads()
            return self.isAsDownloaded("1000000001")
        }
        XCTAssertEqual(downloader.requests, ["1000000001"], "once")
    }

    func testKeepingTheLooseCopiesDownloadsNothingUntilTurnedOff() async throws {
        defaults.set(true, forKey: UnpackedBundleRestoreService.keepsLooseCopiesKey)
        try makeBundle("1000000001")
        try makeBundle("1000000002", archived: true)
        let downloader = makeDownloader(isLoggedIn: true)
        let service = makeService(downloader)
        service.start()
        try await waitFor("the launch run") { self.isAsDownloaded("1000000002") }
        logins.send()
        service.startDownloads()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(downloader.requests, [])
        XCTAssertFalse(isAsDownloaded("1000000001"))

        defaults.set(false, forKey: UnpackedBundleRestoreService.keepsLooseCopiesKey)
        service.startDownloads()
        try await waitFor("the download") { self.isAsDownloaded("1000000001") }
    }

    /// Turning the downloads off partway leaves the rest as it is.
    func testKeepingTheRestPartway() async throws {
        try makeBundle("1000000001")
        try makeBundle("1000000002")
        let downloader = makeDownloader(isLoggedIn: true)
        let defaults = defaults!
        downloader.onRequest = { defaults.set(true, forKey: UnpackedBundleRestoreService.keepsLooseCopiesKey) }
        let service = makeService(downloader)
        service.start()
        try await waitFor("the first download") { self.isAsDownloaded("1000000001") }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(downloader.requests, ["1000000001"])
        XCTAssertFalse(isAsDownloaded("1000000002"))
    }

    // MARK: Asking for the login

    private func makeAccount(saved: Bool, respond: @escaping @Sendable (FakeSteamHelperRequest) -> [String] = { [Fake.result($0)] }) throws -> SteamAccount {
        let store = SteamLoginStore(secret: KeychainSecret(
            keychain: KeychainStore(service: "app.openwallpaperengine.tests.keychain.\(UUID().uuidString)"), account: "SteamLogin"))
        if saved { try store.save(Fake.login) }
        addTeardownBlock { try? store.remove() }
        return SteamAccount(client: SteamHelperClient { Fake(respond: respond) }, store: store, deviceName: "Test Mac")
    }

    func testALoginIsAskedForWithoutOne() async throws {
        try makeBundle("1000000001", bytes: 1000)
        try makeBundle("1000000002", bytes: 500)
        try makeBundle("1000000003", archived: true) // has its package
        try makeBundle("mine") // nowhere to download from
        let service = makeService(makeDownloader(isLoggedIn: false))
        let account = try makeAccount(saved: false)
        await account.restore()
        let waiting = await service.waitingForLogin(account: account)
        XCTAssertEqual(waiting, .init(count: 2, bytes: 1500))
    }

    func testALoginIsAskedForWhenSteamRefusesTheSavedOne() async throws {
        try makeBundle("1000000001")
        let service = makeService(makeDownloader(isLoggedIn: false))
        let account = try makeAccount(saved: true) { [Fake.error($0, code: "tokenRejected", eresult: 5)] }
        // Asked before the saved login was tried: waits for that.
        async let waiting = service.waitingForLogin(account: account)
        await account.restore()
        let result = await waiting
        XCTAssertEqual(result?.count, 1)
    }

    func testNoLoginIsAskedForWithAWorkingOneOrNoNetwork() async throws {
        try makeBundle("1000000001")
        let service = makeService(makeDownloader(isLoggedIn: true))
        for respond: @Sendable (FakeSteamHelperRequest) -> [String] in [{ [Fake.result($0)] }, { [Fake.error($0, code: "network")] }] {
            let account = try makeAccount(saved: true, respond: respond)
            await account.restore()
            let waiting = await service.waitingForLogin(account: account)
            XCTAssertNil(waiting)
        }
    }

    func testNoLoginIsAskedForWithNothingToDownloadOrTheLooseCopiesKept() async throws {
        let service = makeService(makeDownloader(isLoggedIn: false))
        let account = try makeAccount(saved: false)
        await account.restore()
        var waiting = await service.waitingForLogin(account: account)
        XCTAssertNil(waiting)
        try makeBundle("1000000001")
        defaults.set(true, forKey: UnpackedBundleRestoreService.keepsLooseCopiesKey)
        waiting = await service.waitingForLogin(account: account)
        XCTAssertNil(waiting)
    }
}
