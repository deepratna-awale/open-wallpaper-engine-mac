import XCTest
@testable import OpenWallpaperEngine

final class UserAdjustmentBlurResetTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "owe-blur-reset-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testResetsBlurInEveryStoreOnce() {
        let shared = "SceneUserProperties.workshop-1"
        let display = "SceneUserProperties.workshop-1.display.2"
        let untouched = "SceneUserProperties.workshop-2"
        defaults.set(["_owe_blur": "1.5", "_owe_blur_musicSync": "true", "_owe_blur_musicAmount": "0.4",
                      "_owe_hue": "20"], forKey: shared)
        defaults.set(["_owe_blur": "0.7"], forKey: display)
        defaults.set(["_owe_hue": "10"], forKey: untouched)
        defaults.set(true, forKey: "SceneUserPropertiesExplicit.workshop-1")

        UserAdjustmentBlurReset.runOnce(defaults: defaults)

        XCTAssertEqual(defaults.dictionary(forKey: shared) as? [String: String], ["_owe_hue": "20"])
        XCTAssertEqual(defaults.dictionary(forKey: display) as? [String: String], [:])
        XCTAssertEqual(defaults.dictionary(forKey: untouched) as? [String: String], ["_owe_hue": "10"])
        XCTAssertTrue(defaults.bool(forKey: "SceneUserPropertiesExplicit.workshop-1"))

        // Values set after the reset are the user's.
        defaults.set(["_owe_blur": "0.3"], forKey: shared)
        UserAdjustmentBlurReset.runOnce(defaults: defaults)
        XCTAssertEqual(defaults.dictionary(forKey: shared) as? [String: String], ["_owe_blur": "0.3"])
    }
}
