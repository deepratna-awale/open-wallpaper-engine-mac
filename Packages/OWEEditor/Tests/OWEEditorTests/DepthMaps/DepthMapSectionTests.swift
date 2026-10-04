import CoreGraphics
import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// The depth map section as both editors run it, with a fake model and pictures: Generate keeps
/// the depth map with the editor's files, Apply adds WE's effect bound to it through the overlay,
/// a new generation rebinds it, Strength and Remove change the overlay, each one undo step; and
/// the picture each kind of layer is generated from.
@MainActor
final class DepthMapSectionTests: XCTestCase {
    private static let scene = Data("""
    {
      "general": {"orthogonalprojection": {"width": 1920, "height": 1080}},
      "objects": [
        {"id": 1, "name": "Background", "image": "models/bg.json", "origin": "960 540 0", "size": "1920 1080"},
        {"id": 2, "name": "Title", "text": {"value": "Hello"}, "pointsize": 40, "origin": "300 200 0", "parent": 1},
        {"id": 3, "name": "Snow", "particle": "particles/snow.json", "origin": "960 540 0"},
        {"id": 4, "name": "Logo", "image": "models/logo.json", "origin": "1700 900 0", "size": "200 100"},
        {"id": 5, "name": "Speaker", "sound": ["sounds/a.mp3"]}
      ]
    }
    """.utf8)

    private var directory: URL!
    private var session: SceneEditSession!
    private var scheduler: ManualIdleScheduler!
    private var requests: [DepthMapSourceRequest] = []
    private var prepared = 0
    private var prepareFails = false

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "owe-depthmap-section-\(UUID().uuidString)",
                                                                    directoryHint: .isDirectory)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session = SceneEditSession(outline: try SceneOutline(sceneData: Self.scene), undoManager: undoManager)
        scheduler = ManualIdleScheduler()
        requests = []
        prepared = 0
        prepareFails = false
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory) // Scratch: a leftover is harmless.
    }

    private struct PrepareFailure: LocalizedError {
        var errorDescription: String? { "WE's assets are missing" }
    }

    private func services(installed: Bool = true) -> DepthMapEditorServices {
        let generator = DepthMapGenerator(locateModel: { installed ? DepthMapTestSupport.model() : nil },
                                          loadModel: { try FakeModelLoader().load($0) }, cache: nil,
                                          scheduler: scheduler, log: { _ in })
        return DepthMapEditorServices(
            generator: generator, assetStore: EditorAssetStore(directory: directory),
            source: { [unowned self] request in
                self.requests.append(request)
                let isScene: Bool
                if case .scene = request.target { isScene = true } else { isScene = false }
                // Each request draws a little wider, as an edited layer would: a new depth map each time.
                return DepthMapSource(image: DepthMapTestSupport.edge(width: 62 + 2 * self.requests.count, height: 32),
                                      isOneFrame: isScene)
            },
            prepareEffect: { [unowned self] in
                if self.prepareFails { throw PrepareFailure() }
                self.prepared += 1
            },
            texture: { _ in nil },
            openPlugins: {})
    }

    // MARK: A layer

    func testGenerateApplyStrengthAndRemoveOnAnImageLayer() async throws {
        let model = DepthMapSectionModel(session: session, layerID: 4, services: services())
        XCTAssertFalse(model.isApplied)
        await model.generate()
        XCTAssertNil(model.problem)
        let texture = try XCTUnwrap(model.generatedTexture)
        XCTAssertTrue(texture.hasPrefix("depth/editor_logo-"))
        XCTAssertNotNil(EditorAssetStore(directory: directory).depthMapURL(texture), "kept with the editor's files")
        XCTAssertNotNil(model.depthPreview)
        XCTAssertFalse(model.isOneFrame, "a still image's own texture")
        XCTAssertFalse(session.overlay.hasSceneEdits, "generating alone changes nothing")

        model.pendingStrength = 0.7
        model.apply()
        XCTAssertEqual(prepared, 1, "WE's effect files are copied in, as adding any built-in effect does")
        XCTAssertTrue(model.isApplied)
        XCTAssertEqual(session.depthParallaxTexture(of: 4), texture)
        XCTAssertEqual(model.strength, 0.7, accuracy: 1e-9)

        model.strength = 1.4
        XCTAssertEqual(try XCTUnwrap(session.depthParallaxStrength(of: 4)), 1.4, accuracy: 1e-9)

        // A new generation (the layer changed, so another depth map) rebinds the applied effect.
        await model.generate()
        let second = try XCTUnwrap(model.generatedTexture)
        XCTAssertNotEqual(second, texture)
        XCTAssertEqual(session.depthParallaxTexture(of: 4), second)
        XCTAssertEqual(session.outline.layer(4)?.effects.count, 1)

        model.remove()
        XCTAssertFalse(model.isApplied)
        XCTAssertNil(session.depthParallaxEffect(of: 4))
        session.undo()
        XCTAssertEqual(session.depthParallaxTexture(of: 4), second, "Remove is one undo step")
    }

    func testAMissingEffectIsAProblemAndChangesNothing() async throws {
        prepareFails = true
        let model = DepthMapSectionModel(session: session, layerID: 4, services: services())
        await model.generate()
        model.apply()
        XCTAssertEqual(model.problem, "WE's assets are missing")
        XCTAssertFalse(session.overlay.hasSceneEdits)
    }

    func testAParticleSystemGetsTheLayerAboveIt() async throws {
        let model = DepthMapSectionModel(session: session, layerID: 3, services: services())
        XCTAssertTrue(model.comesFromOneFrame)
        await model.generate()
        XCTAssertTrue(model.isOneFrame)
        model.apply()
        let above = try XCTUnwrap(session.depthParallaxLayer(above: 3))
        XCTAssertEqual(model.effectLayer, above)
        model.remove()
        XCTAssertNil(session.depthParallaxLayer(above: 3))
        XCTAssertNil(session.outline.layer(above), "its fullscreen layer goes with it")
    }

    func testTheWholeScene() async throws {
        let model = DepthMapSectionModel(session: session, layerID: nil, services: services())
        await model.generate()
        model.apply()
        let top = try XCTUnwrap(session.depthParallaxLayer(above: nil))
        XCTAssertEqual(session.outline.layers.last?.id, top)
        XCTAssertEqual(session.outline.layer(top)?.name, DL("Scene Depth Parallax"))
        guard case .scene(upTo: nil)? = requests.last?.target else { return XCTFail("the scene as drawn") }
        XCTAssertNil(requests.last?.drawnLayers)
        session.undo()
        XCTAssertNil(session.depthParallaxLayer(above: nil))
    }

    func testASoundLayerCantHaveIt() {
        let model = DepthMapSectionModel(session: session, layerID: 5, services: services())
        XCTAssertFalse(model.isSupported)
    }

    func testWithoutThePluginNothingRuns() async {
        let model = DepthMapSectionModel(session: session, layerID: 4, services: services(installed: false))
        XCTAssertFalse(model.services.generator.isInstalled)
        await model.generate()
        XCTAssertNotNil(model.problem)
        XCTAssertNil(model.generatedTexture)
    }

    // MARK: What each layer is generated from

    func testRequestsByKindOfLayer() throws {
        let picture = session.depthMapRequest(for: 4)
        XCTAssertEqual(picture.target, .layer(4))
        XCTAssertEqual(picture.pictureModel, "models/logo.json", "a still picture may serve as it is")
        let rect = try XCTUnwrap(picture.sceneRect)
        XCTAssertEqual(rect.minX, 1600, accuracy: 1e-6)
        XCTAssertEqual(rect.minY, 850, accuracy: 1e-6)
        XCTAssertEqual(rect.width, 200, accuracy: 1e-6)
        XCTAssertEqual(rect.height, 100, accuracy: 1e-6)
        XCTAssertEqual(picture.drawnLayers, [4])
        XCTAssertEqual(picture.sceneSize, SIMD2(1920, 1080))

        let text = session.depthMapRequest(for: 2)
        XCTAssertEqual(text.target, .layer(2))
        XCTAssertNil(text.pictureModel)
        XCTAssertEqual(text.drawnLayers, [2, 1], "drawn with its parent")
        XCTAssertNotNil(text.sceneRect)

        let particles = session.depthMapRequest(for: 3)
        XCTAssertEqual(particles.target, .scene(upTo: 3))
        XCTAssertEqual(particles.drawnLayers, [1, 2, 3], "the scene drawn so far")
        XCTAssertNil(particles.sceneRect)

        let composition = session.addLayer(SceneLayerFactory.composition(name: "Comp", size: SIMD2(400, 400), origin: SIMD2(960, 540)),
                                           actionName: "Add")
        let order = session.outline.layers.map(\.id)
        let below = Set(order.prefix(through: try XCTUnwrap(order.firstIndex(of: composition))))
        XCTAssertEqual(session.depthMapRequest(for: composition).drawnLayers, below, "what it shows: the scene under it")

        let scene = session.depthMapRequest(for: nil)
        XCTAssertEqual(scene.target, .scene(upTo: nil))
        XCTAssertNil(scene.drawnLayers)
        XCTAssertEqual(Set(scene.allLayers), Set(session.outline.layers.map(\.id)))
    }
}

/// Every `DL("…")` text is in the depth map catalog, translated into every language the app ships.
final class DepthMapLocalizationTests: XCTestCase {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    private func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/DepthMaps.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    func testEveryKeyUsedIsTranslated() throws {
        let catalog = try catalog()
        let regex = try NSRegularExpression(pattern: #"\bDL\("((?:[^"\\]|\\.)*)"\)"#)
        var used = Set<String>()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        XCTAssertGreaterThan(used.count, 20)
        XCTAssertEqual(used.filter { catalog[$0] == nil }, [], "not in DepthMaps.xcstrings")
        var missing: [String] = []
        for (key, entry) in catalog {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in EditorLocalizationTests.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                if (unit?["value"] as? String)?.isEmpty != false || unit?["state"] as? String != "translated" {
                    missing.append("\(language): \(key)")
                }
            }
        }
        XCTAssertEqual(missing, [])
        XCTAssertEqual(DL("Depth Map"), "Depth Map")
    }
}
