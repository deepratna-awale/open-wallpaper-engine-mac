import XCTest
@testable import OpenWallpaperEngine

/// A helper run (shader prewarm) reads the user's defaults and never writes them.
final class ReadOnlyDefaultsTests: XCTestCase {
    func testReadOnlyViewReadsButNeverWritesTheDomain() throws {
        let domain = "com.winddog.wallpaper-engine.isolated.tests.readonly-base-\(UUID().uuidString)"
        let scratch = domain + ".scratch"
        let base = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            base.removePersistentDomain(forName: domain)
            UserDefaults(suiteName: scratch)?.removePersistentDomain(forName: scratch)
        }
        base.set("user value", forKey: "Setting")
        let view = AppStorageLocation.readOnlyView(of: base, domain: domain, scratchSuite: scratch)
        XCTAssertEqual(view.string(forKey: "Setting"), "user value")
        view.set("changed", forKey: "Setting")
        view.set(1, forKey: "New")
        view.removeObject(forKey: "Setting")
        XCTAssertEqual(base.persistentDomain(forName: domain) as NSDictionary?, ["Setting": "user value"] as NSDictionary)
        view.removePersistentDomain(forName: scratch)
        XCTAssertNil(view.persistentDomain(forName: scratch)?["New"])
    }

    func testHelperRunsUseReadOnlyDefaults() {
        XCTAssertTrue(ShaderPrewarmCommand.isHelperRun(arguments: ["app", "--prewarm-shaders"]))
        XCTAssertTrue(ShaderPrewarmCommand.isHelperRun(arguments: ["app", "--print-shader-cache-key"]))
        XCTAssertFalse(ShaderPrewarmCommand.isHelperRun(arguments: ["app", "-OWEIsolatedState", "x"]))
        let location = AppStorageLocation(isolationTag: "tests", readOnlyDefaults: true)
        defer { location.discardReadOnlyScratch() }
        XCTAssertNotNil(location.readOnlyScratchSuite)
        XCTAssertNotEqual(location.defaults, AppStorageLocation.current.defaults)
    }
}
