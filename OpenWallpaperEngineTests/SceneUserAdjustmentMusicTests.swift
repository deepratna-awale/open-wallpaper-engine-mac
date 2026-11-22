import XCTest
@testable import OpenWallpaperEngine

/// Sync to Music on the User Adjustments: a synced adjustment holds system audio capture and keeps
/// an idle scene sampling, and the Animation Speed follows the level.
final class SceneUserAdjustmentMusicTests: XCTestCase {
    func testASyncedAdjustmentHoldsAudioCaptureUntilItsSyncIsOff() throws {
        let harness = try SceneFrameHarness(directory: Fixtures.url("Scenes/layers"), scope: .display("adjustment-music"),
                                            screenID: "A")
        defer { harness.close() }
        let store = harness.model.propertyStoreKey
        harness.draw(frames: 2)
        XCTAssertFalse(harness.renderer.adjustmentsFollowMusic)

        try harness.changeProperties(["_owe_saturation_musicSync": "true", "_owe_saturation_musicAmount": "0.5"])
        XCTAssertTrue(SceneMetalRenderer.adjustmentsFollowMusic(store: store))
        XCTAssertTrue(harness.renderer.adjustmentsFollowMusic)
        XCTAssertTrue(harness.renderer.framePacing.changesOnItsOwn, "an idle scene keeps sampling the level")

        try harness.changeProperties(["_owe_saturation_musicAmount": "0"])
        XCTAssertFalse(harness.renderer.adjustmentsFollowMusic, "synced without an amount follows nothing")
        try harness.changeProperties(["_owe_saturation_musicAmount": "0.5", "_owe_saturation_musicSync": "false"])
        XCTAssertFalse(harness.renderer.adjustmentsFollowMusic)
        XCTAssertEqual(harness.renderer.framePacing.changesOnItsOwn, harness.renderer.contentChangesOnItsOwn)
    }

    /// Every slider of User Adjustments can be synced, the speed and parallax amount included.
    func testEveryAdjustmentSliderCanBeSynced() {
        for key in ["_owe_hue", "_owe_saturation", "_owe_bloom", "_owe_blur", "_owe_speed", "_owe_effect_parallax_amount"] {
            let store = "adjustment-music-\(key)"
            WallpaperServices.shared.setUserProperties(["\(key)_musicSync": "true", "\(key)_musicAmount": "1"],
                                                       wallpaper: store, replacing: true)
            XCTAssertTrue(SceneMetalRenderer.adjustmentsFollowMusic(store: store), key)
            WallpaperServices.shared.setUserProperties([:], wallpaper: store, replacing: true)
        }
    }

    /// Unsynced, the speed has no music offset; synced, its amount times the level.
    func testTheSpeedsMusicOffset() {
        let store = "adjustment-music-speed"
        WallpaperServices.shared.setUserProperties([ScenePlaybackSpeed.propertyKey: "1.5"], wallpaper: store, replacing: true)
        defer { WallpaperServices.shared.setUserProperties([:], wallpaper: store, replacing: true) }
        XCTAssertEqual(ScenePlaybackSpeed.musicOffset(ofStore: store, services: .shared), 0)
        XCTAssertEqual(ScenePlaybackSpeed.speed(ofStore: store), 1.5)
        WallpaperServices.shared.setUserProperties(["_owe_speed_musicSync": "true", "_owe_speed_musicAmount": "1"],
                                                   wallpaper: store, replacing: false)
        let level = WallpaperServices.shared.audioLevel
        XCTAssertEqual(ScenePlaybackSpeed.musicOffset(ofStore: store, services: .shared), level, accuracy: 1e-9)
    }
}
