import XCTest
@testable import OpenWallpaperEngine

/// The layers Set as Screen Saver switches off before it records: clock, day and date text layers
/// (`SceneClockLayers`) and audio-reactive layers (`SceneAudioReactiveLayers`), found from the
/// wallpaper's files.
final class ScreenSaverLiveLayersTests: XCTestCase {
    private let folder = Fixtures.url("Scenes/live-layers")

    /// The fixture's files by WE path, as the scene's load finds loose files.
    private func reader(_ root: URL) -> SceneAudioReactiveLayers.Read {
        { path in try? AssetPathResolver.data(path, in: root) } // A missing file is a miss here.
    }

    func testFindsTheAudioReactiveLayersFromTheirFiles() throws {
        let scene = try Fixtures.data("Scenes/live-layers/scene.json")
        // 2: its material's shader reads g_AudioSpectrum. 3: an effect whose audio-response combo
        // is on. 5: a child particle system's operator responds to audio. 7: a script registers
        // audio buffers. Not 4 (the combo at its default 0), 9 (the effect is off), 11
        // (audioprocessingmode 0), the clocks or the static layers.
        XCTAssertEqual(SceneAudioReactiveLayers.ids(inScene: scene, read: reader(folder)), [2, 3, 5, 7])
    }

    func testFindsAWorkshopEffectThatDrawsAudioBars() throws {
        let root = Fixtures.url("Scenes/audio-bars")
        let scene = try Fixtures.data("Scenes/audio-bars/scene.json")
        XCTAssertEqual(SceneAudioReactiveLayers.ids(inScene: scene, read: reader(root)), [2])
    }

    func testAShaderReadsAudioUnlessItsAudioResponseSwitchIsOff() {
        let custom = "uniform float g_AudioSpectrum64Average[64];"
        XCTAssertTrue(SceneAudioReactiveLayers.shaderReadsAudio(custom, combos: [:]))
        let switched = """
        // [COMBO] {"material":"ui_editor_properties_audio_response","combo":"AUDIOPROCESSING","type":"audioprocessingoptions","default":0}
        #if AUDIOPROCESSING
        uniform float g_AudioSpectrum16Left[16];
        #endif
        """
        XCTAssertFalse(SceneAudioReactiveLayers.shaderReadsAudio(switched, combos: [:]))
        XCTAssertFalse(SceneAudioReactiveLayers.shaderReadsAudio(switched, combos: ["AUDIOPROCESSING": 0]))
        XCTAssertTrue(SceneAudioReactiveLayers.shaderReadsAudio(switched, combos: ["AUDIOPROCESSING": 2]))
        XCTAssertFalse(SceneAudioReactiveLayers.shaderReadsAudio("uniform float g_Time;", combos: [:]))
    }

    func testScriptsUsingTheAudioAPIAreAudioReactive() {
        XCTAssertTrue(SceneAudioReactiveLayers.scriptReadsAudio("let a = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_32);"))
        XCTAssertFalse(SceneAudioReactiveLayers.scriptReadsAudio("export function update(v) { return v; }"))
    }

    func testTheWallpapersLiveLayersAreItsClocksAndItsAudioReactiveLayers() throws {
        let data = try Fixtures.data("Scenes/live-layers/project.json")
        let wallpaper = WEWallpaper(using: try JSONDecoder().decode(WEProject.self, from: data), where: folder)
        let found = expectation(description: "scanned")
        var ids: Set<Int> = []
        // The scan reads files: off the main thread, as the recording runs it.
        DispatchQueue.global(qos: .userInitiated).async {
            ids = ScreenSaverLiveLayers.objectIDs(of: wallpaper)
            found.fulfill()
        }
        wait(for: [found], timeout: 30)
        XCTAssertEqual(ids, [1, 2, 3, 5, 7, 10])
    }

    func testNothingButAScene() throws {
        let video = WEWallpaper(using: WEProject(file: "a.mp4", preview: "p.jpg", title: "v", type: "video"), where: folder)
        let found = expectation(description: "scanned")
        var ids: Set<Int> = [0]
        DispatchQueue.global(qos: .userInitiated).async {
            ids = ScreenSaverLiveLayers.objectIDs(of: video)
            found.fulfill()
        }
        wait(for: [found], timeout: 30)
        XCTAssertEqual(ids, [])
    }

    func testHidingSwitchesTheLayersOffAndKeepsTheOtherValues() {
        let values = ["speed": "2", sceneObjectVisibilityKey(objectID: 1): "true", sceneObjectVisibilityKey(objectID: 6): "false"]
        let hidden = ScreenSaverLiveLayers.hiding([1, 2], in: values)
        XCTAssertEqual(hidden, ["speed": "2",
                                sceneObjectVisibilityKey(objectID: 1): "false",
                                sceneObjectVisibilityKey(objectID: 2): "false",
                                sceneObjectVisibilityKey(objectID: 6): "false"])
        XCTAssertEqual(ScreenSaverLiveLayers.hiding([], in: values), values)
    }
}
