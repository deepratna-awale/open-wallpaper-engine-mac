import MetalKit
import XCTest
@testable import OpenWallpaperEngine

/// Static-layer flattening and culling (docs/efficiency-plan-2d.md WP2-B): the decisions, and that
/// a frame drawn with them matches the frame drawn without.
final class SceneFlatteningCullingTests: XCTestCase {
    // MARK: - Culling decisions

    private static let scene = SIMD2<Float>(400, 200)

    private static func layer(_ index: Int, _ min: SIMD2<Float>, _ max: SIMD2<Float>, opaque: Bool = false,
                              confined: Bool = true, protected: Bool = false, reads: Bool = false,
                              opacity: Float? = nil, visible: Bool = true) -> SceneCulling.Layer {
        SceneCulling.Layer(index: index, coverage: SceneLayerCoverage(min: min, max: max, fullScene: false, opaque: opaque),
                           confinedToQuad: confined, opacity: opacity, protected: protected, readsFrameBeneath: reads,
                           visible: visible)
    }

    private static func cull(_ layers: [SceneCulling.Layer], occlusion: Bool = true) -> [Int: SceneCulling.Reason] {
        SceneCulling.cull(layers, sceneSize: scene, margin: 1, occlusionAllowed: occlusion)
    }

    func testOffTargetAndTransparentLayersAreCulled() {
        let culled = Self.cull([
            Self.layer(0, SIMD2(400, 0), SIMD2(400, 200)),
            Self.layer(1, SIMD2(10, 10), SIMD2(50, 50), opacity: 0),
            Self.layer(2, SIMD2(10, 10), SIMD2(50, 50)),
        ])
        XCTAssertEqual(culled[0], .offTarget)
        XCTAssertEqual(culled[1], .transparent)
        XCTAssertNil(culled[2])
        XCTAssertTrue(SceneCulling.isTransparent(opacity: 0, confinedToQuad: true, protected: false))
        XCTAssertFalse(SceneCulling.isTransparent(opacity: 0, confinedToQuad: false, protected: false))
        XCTAssertFalse(SceneCulling.isTransparent(opacity: 0, confinedToQuad: true, protected: true))
    }

    func testLayersUnderOneOpaqueLayerAreCulled() {
        let culled = Self.cull([
            Self.layer(0, SIMD2(20, 20), SIMD2(80, 80)),
            Self.layer(1, SIMD2(0, 0), SIMD2(90, 90), confined: false),
            Self.layer(2, SIMD2(10, 10), SIMD2(100, 100), opaque: true),
            Self.layer(3, SIMD2(95, 95), SIMD2(120, 120)),
        ])
        XCTAssertEqual(culled[0], .occluded(by: 2))
        // Not confined to its quad: it could draw anywhere, which the occluder doesn't cover.
        XCTAssertNil(culled[1])
        XCTAssertNil(culled[2])
        XCTAssertNil(culled[3])
    }

    func testAWholeSceneOccluderHidesEvenUnboundedLayers() {
        let culled = Self.cull([
            Self.layer(0, SIMD2(0, 0), SIMD2(10, 10), confined: false),
            Self.layer(1, SIMD2(0, 0), Self.scene, opaque: true),
        ])
        XCTAssertEqual(culled[0], .occluded(by: 1))
    }

    func testOcclusionNeedsAMarginAndNothingAboveReadingTheScene() {
        // Touching the occluder's edge: a pixel there may be half covered.
        XCTAssertNil(Self.cull([
            Self.layer(0, SIMD2(10, 10), SIMD2(100, 100)),
            Self.layer(1, SIMD2(10, 10), SIMD2(100, 100), opaque: true),
        ])[0])
        // Anything above sampling the frame beneath sees the layer.
        XCTAssertNil(Self.cull([
            Self.layer(0, SIMD2(20, 20), SIMD2(80, 80)),
            Self.layer(1, SIMD2(0, 0), Self.scene, opaque: true),
            Self.layer(2, SIMD2(0, 0), SIMD2(10, 10), reads: true),
        ])[0])
        XCTAssertNil(Self.cull([
            Self.layer(0, SIMD2(20, 20), SIMD2(80, 80)),
            Self.layer(1, SIMD2(0, 0), Self.scene, opaque: true),
        ], occlusion: false)[0])
        // A hidden or translucent occluder hides nothing.
        XCTAssertNil(Self.cull([
            Self.layer(0, SIMD2(20, 20), SIMD2(80, 80)),
            Self.layer(1, SIMD2(0, 0), Self.scene, opaque: true, visible: false),
        ])[0])
        XCTAssertNil(Self.cull([
            Self.layer(0, SIMD2(20, 20), SIMD2(80, 80)),
            Self.layer(1, SIMD2(0, 0), Self.scene, opaque: true, opacity: 0.5),
        ])[0])
    }

    func testProtectedLayersAreNeverCulled() {
        let culled = Self.cull([
            Self.layer(0, SIMD2(400, 0), SIMD2(400, 200), protected: true),
            Self.layer(1, SIMD2(10, 10), SIMD2(50, 50), protected: true, opacity: 0),
            Self.layer(2, SIMD2(20, 20), SIMD2(80, 80), protected: true),
            Self.layer(3, SIMD2(0, 0), Self.scene, opaque: true),
        ])
        XCTAssertTrue(culled.isEmpty)
    }

    // MARK: - Flattening decisions

    private static func key(_ layers: [Int], revision: Int = 0) -> SceneFlattening.Key {
        SceneFlattening.Key(layers: layers, visible: layers.map { _ in true }, clearColor: .zero, width: 8, height: 8,
                            pixelFormat: .bgra8Unorm, pixelsPerUnit: 1, detailScale: 1, settings: SceneRenderSettings(),
                            generation: revision)
    }

    func testARunIsCapturedOnceStableAndRestoredWhileClean() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        let scene = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let flattening = SceneFlattening()
        flattening.isEnabled = true
        let run = Self.key([0, 1])
        // First sight: draw. Second clean frame in a row: capture.
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 0, now: 10), .draw)
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 0, now: 10.1), .capture(run))
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        flattening.capture(run, from: scene, device: device, commandBuffer: buffer)
        buffer.commit()
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 0, now: 10.2), .restore(run))
        XCTAssertEqual(flattening.flattenedThisFrame, 2)
        // A layer of the run went dirty: the run is shorter, the copy is dropped at once.
        let shorter = Self.key([0])
        XCTAssertEqual(flattening.plan(candidate: shorter, propertiesRevision: 0, now: 10.3), .draw)
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 0, now: 10.4), .draw)
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 0, now: 10.5), .capture(run))
    }

    func testEditsDropTheCopyAndWaitUntilQuiet() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        let scene = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let flattening = SceneFlattening()
        flattening.isEnabled = true
        let run = Self.key([0])
        _ = flattening.plan(candidate: run, propertiesRevision: 0, now: 10)
        _ = flattening.plan(candidate: run, propertiesRevision: 0, now: 10.1)
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        flattening.capture(run, from: scene, device: device, commandBuffer: buffer)
        buffer.commit()
        // An Inspector edit (a user-property change) shows at once: the copy is gone.
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 1, now: 10.2), .draw)
        // Still inside the quiet period.
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 1, now: 10.4), .draw)
        XCTAssertEqual(flattening.plan(candidate: run, propertiesRevision: 1, now: 10.8), .capture(run))
        // New content never reuses a copy.
        XCTAssertEqual(flattening.plan(candidate: Self.key([0], revision: 1), propertiesRevision: 1, now: 11), .draw)
    }

    func testTheRunStopsAtTheFirstLayerThatCantBeFlattened() {
        let run = SceneFlattening.run(count: 5, eligible: { $0 != 3 }, clean: { $0 != 2 })
        XCTAssertEqual(run, [0, 1])
        XCTAssertEqual(SceneFlattening.run(count: 3, eligible: { _ in true }, clean: { _ in true }), [0, 1, 2])
    }

    func testPipelineCompletionsCount() {
        let before = ScenePipelineCompletions.count
        ScenePipelineCompletions.landed()
        let after = ScenePipelineCompletions.count
        XCTAssertGreaterThan(after, before)
    }

    // MARK: - Lossless on real scenes

    /// Every fixture scene that is a wallpaper folder, bar the one whose script hangs on purpose.
    private static var ciScenes: [URL] {
        let root = Fixtures.url("Scenes")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().filter { name in
            name != "scripted-hang" && FileManager.default.fileExists(atPath: root.appending(path: "\(name)/project.json").path)
        }.map { root.appending(path: $0) }
    }

    /// Flattening and culling on vs off over the CI scenes: every frame matches (SSIM ≥ 0.999)
    /// wherever two plain renders match each other (scripts or particles that draw randomly don't).
    func testFlattenedAndCulledFramesMatchPlainFramesOnCIScenes() throws {
        let result = try Self.compare(Self.ciScenes, size: SIMD2(256, 128), frames: 120)
        print("SceneFlattening CI: \(result.compared) frames compared, min SSIM \(result.minSSIM)")
        XCTAssertGreaterThan(result.compared, 100)
    }

    /// The same on library wallpapers: `OWE_FLATTEN_LIBRARY` lists folders under `OWE_LIBRARY`
    /// (comma separated, or `all`).
    /// Prints how many layers each flattens and culls per frame.
    func testFlattenedAndCulledFramesMatchPlainFramesOnLibraryWallpapers() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ids = environment["OWE_FLATTEN_LIBRARY"], !ids.isEmpty else {
            throw XCTSkip("set OWE_FLATTEN_LIBRARY to compare library wallpapers")
        }
        let library = LibrarySweepTests.libraryRoot
        let names = ids == "all"
            ? ((try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []).sorted()
            : ids.split(separator: ",").map(String.init)
        let directories = names.map { library.appending(path: $0) }
            .filter { directory in
                guard let data = FileManager.default.contents(atPath: directory.appending(path: "project.json").path),
                      let project = try? JSONDecoder().decode(WEProject.self, from: data) else { return false }
                return project.type.lowercased() == "scene"
            }
        let result = try Self.compare(directories, size: SIMD2(960, 540), frames: 90)
        print("SceneFlattening library: \(result.compared) frames compared, min SSIM \(result.minSSIM)")
    }

    private static func compare(_ directories: [URL], size: SIMD2<Int>, frames: Int) throws
        -> (compared: Int, minSSIM: Double) {
        var compared = 0
        var minSSIM = 1.0
        for directory in directories {
            let name = directory.lastPathComponent
            let on = try SceneFrameHarness(directory: directory, size: size, screenID: "on")
            let plain = try SceneFrameHarness(directory: directory, size: size, screenID: "plain")
            let control = try SceneFrameHarness(directory: directory, size: size, screenID: "control")
            defer { on.close(); plain.close(); control.close() }
            on.renderer.flattening.isEnabled = true
            on.renderer.cullingEnabled = true
            for harness in [plain, control] {
                harness.renderer.flattening.isEnabled = false
                harness.renderer.cullingEnabled = false
            }
            var culled = 0, flattened = 0, layers = 0, sceneCompared = 0
            for frame in 0..<frames {
                // Stretches of held clock (where flattening pays) between moving ones.
                let step = (frame / 10) % 2 == 0 ? 0 : 1.0 / 30
                for harness in [on, plain, control] { harness.draw(frames: 1, step: step) }
                culled += on.renderer.lastFrameSkips.culled
                flattened += on.renderer.lastFrameSkips.flattened
                layers += on.renderer.layerAnalysis?.layers.count ?? 0
                let reference = read(plain)
                guard frame > 10, PerceptualCompare.ssim(reference, read(control)) >= 0.9999 else { continue }
                let ssim: Double = PerceptualCompare.ssim(read(on), reference)
                minSSIM = min(minSSIM, ssim)
                XCTAssertGreaterThanOrEqual(ssim, 0.999, "\(name) frame \(frame): flattened/culled frame differs")
                compared += 1
                sceneCompared += 1
            }
            if ProcessInfo.processInfo.environment["OWE_FLATTEN_EXPLAIN"] != nil, let analysis = on.renderer.layerAnalysis {
                // Why the run stops where it does: the bottom layers' inputs and state.
                let bottom = analysis.layers.sorted { $0.order < $1.order }.prefix(4)
                let lines = bottom.map { "\($0.id) deps \($0.dependencies) dirty \(analysis.isDirty($0.id))" }
                print("SceneFlattening explain \(name): stages \(analysis.sceneStagesAnimate), changed \(analysis.changed); "
                      + lines.joined(separator: "; "))
            }
            let perFrame = { (value: Int) in Double(value) / Double(frames) }
            print(String(format: "SceneFlattening %@: layers %.1f, culled/f %.2f, flattened/f %.2f, copies %d, compared %d",
                         name, perFrame(layers), perFrame(culled), perFrame(flattened), on.renderer.flattening.captures,
                         sceneCompared))
        }
        return (compared, minSSIM)
    }

    private static func read(_ scene: SceneFrameHarness) -> PerceptualImage {
        let size = scene.size
        var bytes = [UInt8](repeating: 0, count: size.x * size.y * 4)
        scene.view.currentDrawable?.texture.getBytes(&bytes, bytesPerRow: size.x * 4,
                                                     from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes.swapAt(pixel, pixel + 2)
            bytes[pixel + 3] = 255
        }
        return PerceptualImage(width: size.x, height: size.y, rgba: bytes)
    }
}
