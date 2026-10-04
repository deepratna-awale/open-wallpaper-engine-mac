import XCTest
@testable import OWETheming

final class SchemeColorSourceTests: XCTestCase {
    private let project = "0.69 0.27 0.33"

    func testProjectValueWithoutUserChanges() {
        XCTAssertEqual(SchemeColorSource.resolve(running: [:], userSet: [:], projectValue: project),
                       ThemeColor(weString: project))
    }

    func testFollowsUserPropertyChanges() {
        // Saved in the Details panel.
        XCTAssertEqual(SchemeColorSource.resolve(running: [:], userSet: ["schemecolor": "0 0 1"], projectValue: project),
                       ThemeColor(red: 0, green: 0, blue: 1))
        // Changed live (a preset, or an edit not yet saved): the running value wins.
        XCTAssertEqual(SchemeColorSource.resolve(running: ["schemecolor": "1 0 0"], userSet: ["schemecolor": "0 0 1"],
                                                 projectValue: project),
                       ThemeColor(red: 1, green: 0, blue: 0))
        // Other properties don't matter.
        XCTAssertEqual(SchemeColorSource.resolve(running: ["speed": "2"], userSet: [:], projectValue: project),
                       ThemeColor(weString: project))
    }

    func testUnreadableValueFallsBack() {
        XCTAssertEqual(SchemeColorSource.resolve(running: ["schemecolor": "nope"], userSet: [:], projectValue: project),
                       ThemeColor(weString: project))
        XCTAssertNil(SchemeColorSource.resolve(running: [:], userSet: [:], projectValue: nil))
    }

    func testDominantColorPicksTheLargestCluster() throws {
        let blue = ThemeColor(red: 0.1, green: 0.2, blue: 0.8)
        let orange = ThemeColor(red: 0.9, green: 0.5, blue: 0.1)
        let colors = Array(repeating: blue, count: 700) + Array(repeating: orange, count: 300)
        let dominant = try XCTUnwrap(DominantColor.dominant(of: colors))
        XCTAssertEqual(dominant.red, blue.red, accuracy: 1e-6)
        XCTAssertEqual(dominant.blue, blue.blue, accuracy: 1e-6)
        XCTAssertNil(DominantColor.dominant(of: []))
    }

    func testDominantColorOfAnImage() throws {
        let image = try XCTUnwrap(MenuBarStripTests.solid(width: 64, height: 64, gray: 0.5))
        let color = try XCTUnwrap(DominantColor.of(image))
        XCTAssertEqual(color.red, 0.5, accuracy: 0.01)
    }

    func testSettingsDefaultsAreOffAndDecodeTolerantly() throws {
        let defaults = ThemingSettings()
        XCTAssertFalse(defaults.isEnabled || defaults.menuBar || defaults.accentColor || defaults.tintedIcons
                       || defaults.folderColor || defaults.usesDominantColor)
        XCTAssertTrue(defaults.restoresOnQuit)
        let decoded = try JSONDecoder().decode(ThemingSettings.self,
                                               from: Data(#"{"isEnabled":true,"menuBar":"bad"}"#.utf8))
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertFalse(decoded.menuBar)
    }
}
