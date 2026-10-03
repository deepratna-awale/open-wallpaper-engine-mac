import XCTest
@testable import OpenWallpaperEngine

/// Web wallpapers go to Chromium exactly when the engine is installed and switched on.
final class WebEngineRoutingTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "WebEngineRoutingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "WebEngineRoutingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A complete install of `version`: its framework binary and manifest, recorded as active.
    private func install(_ version: String) throws {
        let folder = root.appending(path: version)
        let framework = folder.appending(path: ChromiumEnginePackage.frameworkName)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data().write(to: framework.appending(path: ChromiumEnginePackage.frameworkBinary))
        let manifest = ChromiumEnginePackage.Manifest(version: version, platform: "macosarm64", sha256: "00")
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: ChromiumEnginePackage.manifestName))
        try ChromiumEngineInstallState(active: version, previous: nil).write(in: root)
    }

    func testTheRule() {
        XCTAssertEqual(WebEngineRouting.engine(installed: true, enabled: true), .chromium)
        XCTAssertEqual(WebEngineRouting.engine(installed: true, enabled: false), .webKit)
        XCTAssertEqual(WebEngineRouting.engine(installed: false, enabled: true), .webKit)
        XCTAssertEqual(WebEngineRouting.engine(installed: false, enabled: false), .webKit)
    }

    func testNotInstalledRoutesToWebKit() {
        XCTAssertNil(ChromiumEngineInstallation.activeInstall(in: root))
        XCTAssertEqual(WebEngineRouting.current(root: root, defaults: defaults), .webKit)
    }

    func testInstalledRoutesToChromiumUnlessSwitchedOff() throws {
        try install("1.2.3")
        XCTAssertEqual(ChromiumEngineInstallation.activeInstall(in: root)?.lastPathComponent, "1.2.3")
        // On by default.
        XCTAssertEqual(WebEngineRouting.current(root: root, defaults: defaults), .chromium)
        defaults.set(false, forKey: WebEngineRouting.enabledKey)
        XCTAssertEqual(WebEngineRouting.current(root: root, defaults: defaults), .webKit)
        defaults.set(true, forKey: WebEngineRouting.enabledKey)
        XCTAssertEqual(WebEngineRouting.current(root: root, defaults: defaults), .chromium)
    }

    /// The rule: installed means Chromium, with nothing for the user to switch on.
    func testTheSwitchDefaultsToOn() throws {
        XCTAssertNil(defaults.object(forKey: WebEngineRouting.enabledKey))
        XCTAssertTrue(WebEngineRouting.isEnabled(in: defaults))
        try install("3.0.0")
        XCTAssertEqual(WebEngineRouting.current(root: root, defaults: defaults), .chromium)
    }

    func testAnIncompleteInstallRoutesToWebKit() throws {
        try install("1.2.3")
        try FileManager.default.removeItem(at: root.appending(path: "1.2.3/\(ChromiumEnginePackage.manifestName)"))
        XCTAssertEqual(WebEngineRouting.current(root: root, defaults: defaults), .webKit)
    }

    @MainActor
    func testTheRouterFollowsInstallAndRemove() throws {
        let root = self.root!, defaults = self.defaults!
        let router = WebEngineRouter(resolve: { WebEngineRouting.current(root: root, defaults: defaults) })
        XCTAssertEqual(router.engine, .webKit)
        try install("2.0.0")
        NotificationCenter.default.post(name: .chromiumEngineChanged, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(router.engine, .chromium)
        try FileManager.default.removeItem(at: root.appending(path: "2.0.0"))
        router.refresh()
        XCTAssertEqual(router.engine, .webKit)
    }
}
