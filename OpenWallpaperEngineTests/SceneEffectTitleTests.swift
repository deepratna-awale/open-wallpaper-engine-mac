import XCTest
@testable import OpenWallpaperEngine

/// WE's labels read as words when WE's own text table isn't available (`SceneEffectParameters.title`).
final class SceneEffectTitleTests: XCTestCase {
    /// An effect's name key reads as the effect's name, as Add Effect lists it.
    func testAnEffectNameKeyReadsAsTheName() {
        XCTAssertEqual(SceneEffectParameters.title("ui_editor_effect_blur_title"), "Blur")
        XCTAssertEqual(SceneEffectParameters.title("ui_editor_effect_water_ripple_title"), "Water Ripple")
        XCTAssertEqual(SceneEffectParameters.title("ui_editor_properties_speed"), "Speed")
    }
}
