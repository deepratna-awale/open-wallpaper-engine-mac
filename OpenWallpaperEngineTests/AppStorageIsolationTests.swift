import XCTest
@testable import OpenWallpaperEngine

/// A test run must never read or write the user's real state: the test host is the app itself and
/// shares its bundle identifier, so without isolation tests overwrote playlists and settings.
final class AppStorageIsolationTests: XCTestCase {
    func testTheTestHostUsesAnIsolatedStore() throws {
        let store = AppStorageLocation.current
        XCTAssertTrue(store.isIsolated)
        XCTAssertFalse(store.defaults === UserDefaults.standard, "tests must not use UserDefaults.standard")
        XCTAssertFalse(UserDefaults.app === UserDefaults.standard)
        let suite = try XCTUnwrap(store.suiteName)
        XCTAssertTrue(suite.contains("isolated"), suite)
        XCTAssertNotEqual(suite, AppStorageLocation.realBundleIdentifier)

        let real = AppStorageLocation(isolationTag: nil)
        XCTAssertTrue(real.defaults === UserDefaults.standard, "the user's launch keeps the real domain")
        XCTAssertNotEqual(store.supportDirectory.standardizedFileURL, real.supportDirectory.standardizedFileURL)
        XCTAssertNotEqual(store.cachesDirectory.standardizedFileURL, real.cachesDirectory.standardizedFileURL)
        XCTAssertNotEqual(store.keychainServicePrefix, real.keychainServicePrefix)
        XCTAssertTrue(store.keychainServicePrefix.contains("isolated"))
    }

    func testDefaultLocationsLiveInTheIsolatedStore() {
        let store = AppStorageLocation.current
        XCTAssertTrue(SafeRestartStore.defaultFileURL.path.hasPrefix(store.supportDirectory.path))
        XCTAssertTrue(SceneScriptStorage.defaultDirectory.path.hasPrefix(store.supportDirectory.path))
        XCTAssertTrue(ShaderVariantTranslator.defaultCacheDirectory?.path.hasPrefix(store.cachesDirectory.path) ?? true)
        XCTAssertTrue(KeychainSecret.service("steam-web-api-key").hasPrefix(store.keychainServicePrefix + "."))
    }

    func testIsolationTagSources() {
        typealias L = AppStorageLocation
        XCTAssertNil(L.isolationTag(environment: [:], arguments: ["app"], isRunningTests: false))
        XCTAssertEqual(L.isolationTag(environment: [:], arguments: [], isRunningTests: true), "tests")
        XCTAssertEqual(L.isolationTag(environment: ["XCTestConfigurationFilePath": "/x"], arguments: [], isRunningTests: false),
                       "tests")
        XCTAssertEqual(L.isolationTag(environment: ["XCTestBundlePath": "/x"], arguments: [], isRunningTests: false), "tests")
        XCTAssertEqual(L.isolationTag(environment: ["OWE_ISOLATED_STATE": "shots"], arguments: [], isRunningTests: false),
                       "shots")
        XCTAssertEqual(L.isolationTag(environment: [:], arguments: ["app", "-OWEIsolatedState", "agent 7/x"],
                                      isRunningTests: false), "agent-7-x")
        XCTAssertNil(L.isolationTag(environment: ["OWE_ISOLATED_STATE": ""], arguments: [], isRunningTests: false),
                     "an empty tag doesn't isolate")
    }

    func testIsolatedLocationNaming() {
        let store = AppStorageLocation(isolationTag: "shots", bundleIdentifier: "com.winddog.wallpaper-engine")
        XCTAssertEqual(store.suiteName, "com.winddog.wallpaper-engine.isolated.shots")
        XCTAssertEqual(store.supportDirectory.lastPathComponent, "Open Wallpaper Engine (isolated shots)")
        XCTAssertEqual(store.cachesDirectory.lastPathComponent, "Open Wallpaper Engine (isolated shots)")
        XCTAssertEqual(store.keychainServicePrefix, "com.winddog.wallpaper-engine.isolated.shots")
    }
}
