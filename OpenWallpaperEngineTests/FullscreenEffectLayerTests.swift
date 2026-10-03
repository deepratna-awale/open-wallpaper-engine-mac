import XCTest
import Metal
import simd
@testable import OpenWallpaperEngine

/// The fullscreen-layer optimisations: effect buffers shaded only where a display can show them
/// (`SceneVisibleRegion`), copies handed over instead of copied (`EffectGraphRenderer.copyCanAlias`)
/// and motion blur's history at half size (`EffectResolutionPolicy.temporalDivisor`).
final class FullscreenEffectLayerTests: XCTestCase {
    private typealias Rect = SceneSnapshotTracker.Rect

    // MARK: - What a display shows

    /// A 2560×1600 scene filling a 3840×2160 display is drawn 1.5× and loses 80 scene rows at the
    /// top and the bottom; stretched, fitted or of the display's own shape it shows whole.
    func testFillShowsTheMiddleOfATallerScene() throws {
        let scene = SIMD2<Float>(2560, 1600)
        let display = SceneVisibleRegion.Display(drawableSize: SIMD2(3840, 2160), pixelsPerPoint: 2)
        let window = try XCTUnwrap(SceneVisibleRegion.window(sceneSize: scene, displays: [display], placement: .fill))
        XCTAssertEqual(window.min.x, 0, accuracy: 1e-3)
        XCTAssertEqual(window.max.x, 2560, accuracy: 1e-3)
        XCTAssertEqual(window.min.y, 80, accuracy: 1e-3)
        XCTAssertEqual(window.max.y, 1520, accuracy: 1e-3)
        XCTAssertNil(SceneVisibleRegion.window(sceneSize: scene, displays: [display], placement: .stretch))
        XCTAssertNil(SceneVisibleRegion.window(sceneSize: scene, displays: [display], placement: .fit))
        let sameShape = SceneVisibleRegion.Display(drawableSize: SIMD2(3840, 2400), pixelsPerPoint: 2)
        XCTAssertNil(SceneVisibleRegion.window(sceneSize: scene, displays: [sameShape], placement: .fill))
        XCTAssertNil(SceneVisibleRegion.window(sceneSize: scene, displays: [], placement: .fill))
    }

    /// Displays of different shapes showing one frame: what any of them shows.
    func testSharedFrameShowsWhatAnyDisplayShows() throws {
        let scene = SIMD2<Float>(1920, 1080)
        // Two ultrawides crop a 16:9 scene's rows: 3440×1440 keeps 138.1…941.9, 2560×1080 keeps 135…945.
        let wide = SceneVisibleRegion.Display(drawableSize: SIMD2(3440, 1440), pixelsPerPoint: 1)
        let other = SceneVisibleRegion.Display(drawableSize: SIMD2(2560, 1080), pixelsPerPoint: 1)
        let window = try XCTUnwrap(SceneVisibleRegion.window(sceneSize: scene, displays: [wide, other], placement: .fill))
        XCTAssertEqual(window.min.x, 0, accuracy: 1e-3)
        XCTAssertEqual(window.max.x, 1920, accuracy: 1e-3)
        XCTAssertEqual(window.min.y, 135, accuracy: 1e-2)
        XCTAssertEqual(window.max.y, 945, accuracy: 1e-2)
        // A square display shows every row (and loses columns): together they show it all.
        let square = SceneVisibleRegion.Display(drawableSize: SIMD2(1080, 1080), pixelsPerPoint: 1)
        XCTAssertNil(SceneVisibleRegion.window(sceneSize: scene, displays: [wide, square], placement: .fill))
    }

    // MARK: - The shaded part of the buffers

    private func fullscreenQuad(_ scene: SIMD2<Float>, offset: SIMD2<Float> = .zero) -> SceneQuadGeometry {
        SceneQuadGeometry(center: scene / 2 + offset, axisX: SIMD2(scene.x, 0), axisY: SIMD2(0, scene.y))
    }

    /// The rain case: a 3840×2400 target of which rows 120…2280 show. With the 64-pixel sampling
    /// margin the buffers shade rows 56…2344 (snapped outward to 8), and the layer draws 2 pixels
    /// inside that: 95 % of the rows, the full width.
    func testBuffersShadeWhatShowsPlusTheMargin() throws {
        let scene = SIMD2<Float>(2560, 1600)
        let pixelsPerUnit: Float = 1.5
        let window = SceneVisibleRegion.Rect(min: SIMD2(0, 80), max: SIMD2(2560, 1520))
        let margin = SIMD2<Float>(repeating: SceneVisibleRegion.samplingMargin / pixelsPerUnit)
        let chainSize = SIMD2(3840, 2400)
        let chain = try XCTUnwrap(SceneVisibleRegion.chainRect(quad: fullscreenQuad(scene), offset: .zero, window: window,
                                                               margin: margin, chainSize: chainSize))
        XCTAssertEqual(chain.x, 0)
        XCTAssertEqual(chain.width, 3840)
        XCTAssertEqual(chain.y % SceneVisibleRegion.grid, 0)
        XCTAssertEqual(chain.maxY % SceneVisibleRegion.grid, 0)
        XCTAssertTrue((48...56).contains(chain.y), "\(chain)")
        XCTAssertTrue((2344...2352).contains(chain.maxY), "\(chain)")
        let target = try XCTUnwrap(SceneVisibleRegion.targetRect(chain, chainSize: chainSize, quad: fullscreenQuad(scene),
                                                                 sceneSize: scene, targetSize: chainSize))
        // Full width (the buffers' own edges), rows inset by 2 where the shaded part ends inside.
        XCTAssertEqual(target.x, 0)
        XCTAssertEqual(target.width, 3840)
        XCTAssertTrue((chain.y + 2...chain.y + 3).contains(target.y), "\(target)")
        XCTAssertTrue((chain.maxY - 3...chain.maxY - 2).contains(target.maxY), "\(target)")
        XCTAssertLessThanOrEqual(target.y, 120 - 60, "what shows and the margin, less the inset, is drawn")
        XCTAssertGreaterThanOrEqual(target.maxY, 2280 + 60)
    }

    /// Nearly everything showing isn't worth a scissor: no rect.
    func testAlmostEverythingShowingShadesEverything() {
        let scene = SIMD2<Float>(1920, 1080)
        let window = SceneVisibleRegion.Rect(min: SIMD2(0, 2), max: SIMD2(1920, 1078))
        XCTAssertNil(SceneVisibleRegion.chainRect(quad: fullscreenQuad(scene), offset: .zero, window: window,
                                                  margin: .zero, chainSize: SIMD2(1920, 1080)))
        let rotated = SceneQuadGeometry(center: scene / 2, axisX: SIMD2(1000, 10), axisY: SIMD2(-10, 1000))
        XCTAssertNil(SceneVisibleRegion.chainRect(quad: rotated, offset: .zero, window: window, margin: .zero,
                                                  chainSize: SIMD2(1920, 1080)), "only upright, axis-aligned quads")
    }

    /// Parallax and shake move the layer, so the shaded part reaches as far as they can move it,
    /// and stays where it is in the buffers wherever the layer is this frame (a carried buffer
    /// keeps its pixels); the draw follows the layer.
    func testParallaxMarginsWidenTheRectAndKeepItStill() throws {
        let scene = SIMD2<Float>(2560, 1600)
        let window = SceneVisibleRegion.Rect(min: SIMD2(0, 80), max: SIMD2(2560, 1520))
        let chainSize = SIMD2(3840, 2400)
        // WE's defaults: amount 0.5, mouse influence 0.1, depth 1, a fullscreen layer at the centre.
        let parallax = SceneVisibleRegion.parallaxBound(amount: 0.5, rootOrigin: scene / 2, rootDepth: SIMD2(1, 1),
                                                        sceneSize: scene, influence: 0.1, shake: 0)
        XCTAssertEqual(parallax.x, 64, accuracy: 1e-3, "0.5 × (2560 × 0.1 / 2)")
        XCTAssertEqual(parallax.y, 40, accuracy: 1e-3, "0.5 × (1600 × 0.1 / 2)")
        let still = try XCTUnwrap(SceneVisibleRegion.chainRect(quad: fullscreenQuad(scene), offset: .zero, window: window,
                                                               margin: .zero, chainSize: chainSize))
        let margin = parallax
        let wide = try XCTUnwrap(SceneVisibleRegion.chainRect(quad: fullscreenQuad(scene), offset: .zero, window: window,
                                                              margin: margin, chainSize: chainSize))
        XCTAssertLessThan(wide.y, still.y)
        XCTAssertGreaterThan(wide.maxY, still.maxY)
        XCTAssertEqual(wide.y, 56, "row 120 less 40 units at 1.5 px each, snapped down to 8")
        for offset in [SIMD2<Float>(-64, -40), SIMD2(30, 12), SIMD2(64, 40)] {
            let moved = fullscreenQuad(scene, offset: offset)
            let rect = try XCTUnwrap(SceneVisibleRegion.chainRect(quad: moved, offset: offset, window: window,
                                                                  margin: margin, chainSize: chainSize))
            XCTAssertEqual(rect, wide, "the shaded part stays put at offset \(offset)")
            // Wherever the layer is, what shows of it lies inside the part drawn this frame.
            let target = try XCTUnwrap(SceneVisibleRegion.targetRect(rect, chainSize: chainSize, quad: moved,
                                                                     sceneSize: scene, targetSize: chainSize))
            let shownTop = Int((scene.y - window.max.y) * 1.5), shownBottom = Int((scene.y - window.min.y) * 1.5)
            XCTAssertLessThanOrEqual(target.y, shownTop, "offset \(offset)")
            XCTAssertGreaterThanOrEqual(target.maxY, shownBottom, "offset \(offset)")
        }
    }

    /// Camera shake's farthest reach: √2 (the longest its vector gets) × amplitude × 0.1 × 0.1 ×
    /// the orthographic height, raised by a roughness exponent above 1.
    func testShakeBoundCoversEveryFrame() {
        let bound = SceneVisibleRegion.shakeBound(amplitude: 0.5, roughness: 1, orthographicHeight: 1600)
        XCTAssertEqual(bound, Float(2).squareRoot() * 0.5 * 0.1 * 160, accuracy: 1e-3)
        for roughness: Float in [0, 0.5, 1, 1.5] {
            let reach = SceneVisibleRegion.shakeBound(amplitude: 0.5, roughness: roughness, orthographicHeight: 1600)
            for step in 0..<2000 {
                let shake = SceneCameraShake.cameraOffset(time: Float(step) * 0.0137, speed: 3, amplitude: 0.5,
                                                          roughness: roughness, orthographicHeight: 1600)
                XCTAssertLessThanOrEqual(abs(shake.x), reach + 1e-3, "roughness \(roughness)")
                XCTAssertLessThanOrEqual(abs(shake.y), reach + 1e-3, "roughness \(roughness)")
            }
        }
        XCTAssertEqual(SceneVisibleRegion.shakeBound(amplitude: 0, roughness: 1, orthographicHeight: 1600), 0)
    }

    /// The parallax bound holds for every cursor position and delay WE's parallax can reach.
    func testParallaxBoundCoversEveryCursor() {
        let scene = SIMD2<Float>(1920, 1080)
        let origin = SIMD2<Float>(1000, 500)
        let depth = SIMD2<Float>(1.2, 0.8)
        let bound = SceneVisibleRegion.parallaxBound(amount: 0.7, rootOrigin: origin, rootDepth: depth, sceneSize: scene,
                                                     influence: -0.3, shake: 0)
        var parallax = SceneCameraParallax(sceneSize: scene)
        for step in 0..<400 {
            let cursor = SIMD2<Float>(Float(step % 20) / 19, Float(step / 20) / 19)
            parallax.update(cursor: cursor, eye: .zero, sceneSize: scene, influence: -0.3, delay: step % 2 == 0 ? 0 : 1.5,
                            deltaTime: 1.0 / 60)
            let offset = parallax.offset(rootOrigin: origin, rootDepth: depth, amount: 0.7)
            XCTAssertLessThanOrEqual(abs(offset.x), bound.x + 1e-3)
            XCTAssertLessThanOrEqual(abs(offset.y), bound.y + 1e-3)
        }
    }

    /// A rect on a smaller buffer (half-size history, a ¼ blur buffer) is rounded outward.
    func testRectsScaleOutwardOntoSmallerBuffers() {
        let rect = Rect(x: 0, y: 57, width: 3840, height: 2287)
        XCTAssertEqual(SceneVisibleRegion.scaled(rect, from: SIMD2(3840, 2400), to: SIMD2(1920, 1200)),
                       Rect(x: 0, y: 28, width: 1920, height: 1144))
        XCTAssertEqual(SceneVisibleRegion.scaled(rect, from: SIMD2(3840, 2400), to: SIMD2(3840, 2400)), rect)
    }

    func testOptionsComeFromTheEnvironment() {
        XCTAssertEqual(SceneFullscreenEffectOptions.environment([:]), SceneFullscreenEffectOptions())
        let off = SceneFullscreenEffectOptions.environment(["OWE_FX_CLAMP": "0", "OWE_FX_COPY_ALIAS": "0", "OWE_FX_HALF_ACCUM": "0"])
        XCTAssertEqual(off, .none)
        let half = SceneFullscreenEffectOptions.environment(["OWE_FX_HALF_ACCUM": "1"])
        XCTAssertEqual(half.halfResolutionAccumulation, true)
        XCTAssertTrue(half.clampToVisible)
    }

    // MARK: - Copies handed over

    private func fbo(_ name: String, scale: Int = 1) throws -> EffectFBO {
        try JSONDecoder().decode(EffectFBO.self, from: Data(#"{"name":"\#(name)","scale":\#(scale),"format":"rgba_backbuffer"}"#.utf8))
    }

    private func pass(_ command: SceneEffectPassCommand, target: String? = nil,
                      textures: [Int: SceneEffectTextureInput] = [:]) -> SceneEffectPassPlan {
        SceneEffectPassPlan(command: command, variantKey: "", variant: nil, blending: "normal", target: target,
                            textures: textures, constants: .init(staticValues: [:], dynamic: []))
    }

    /// Motion blur: accumulate into B (reading A, last frame's), copy B into A, show B.
    private func motionBlur(file: String = "effects/motionblur/effect.json") throws -> SceneEffectPlan {
        SceneEffectPlan(file: file, fbos: [try fbo("A"), try fbo("B")], passes: [
            pass(.render, target: "B", textures: [0: .previous, 1: .fbo("A")]),
            pass(.copy(source: "B", target: "A")),
            pass(.render, textures: [0: .fbo("B")]),
        ])
    }

    func testMotionBlursHistoryCopyIsHandedOver() throws {
        XCTAssertTrue(EffectGraphRenderer.copyCanAlias(try motionBlur(), at: 1))
    }

    func testCopiesThatSomethingCouldTellApartStayCopies() throws {
        let fbos = [try fbo("A"), try fbo("B")]
        // The source is read before it's written: its next frame needs what it held.
        let readsFirst = SceneEffectPlan(file: "x", fbos: fbos, passes: [
            pass(.render, target: "A", textures: [0: .fbo("B")]),
            pass(.render, target: "B", textures: [0: .previous]),
            pass(.copy(source: "B", target: "A")),
        ])
        XCTAssertFalse(EffectGraphRenderer.copyCanAlias(readsFirst, at: 2))
        // Written again after the copy: the two would change together.
        let writtenAfter = SceneEffectPlan(file: "x", fbos: fbos, passes: [
            pass(.render, target: "B", textures: [0: .previous]),
            pass(.copy(source: "B", target: "A")),
            pass(.render, target: "B", textures: [0: .fbo("A")]),
        ])
        XCTAssertFalse(EffectGraphRenderer.copyCanAlias(writtenAfter, at: 1))
        // From the effect's input, or never written before the copy.
        let fromInput = SceneEffectPlan(file: "x", fbos: fbos, passes: [pass(.copy(source: "previous", target: "A"))])
        XCTAssertFalse(EffectGraphRenderer.copyCanAlias(fromInput, at: 0))
        let unwritten = SceneEffectPlan(file: "x", fbos: fbos, passes: [pass(.copy(source: "B", target: "A"))])
        XCTAssertFalse(EffectGraphRenderer.copyCanAlias(unwritten, at: 0))
        XCTAssertFalse(EffectGraphRenderer.copyCanAlias(try motionBlur(), at: 0), "not a copy")
    }

    // MARK: - Half-size history

    func testOnlyTemporalAccumulationsShrinkByTheTemporalDivisor() throws {
        let blur = try motionBlur()
        XCTAssertTrue(EffectResolutionPolicy.isTemporalAccumulation(blur))
        let policy = EffectResolutionPolicy(temporalDivisor: 2)
        XCTAssertEqual(policy.divisor(for: blur.fbos[0], in: blur), 2)
        XCTAssertEqual(policy.divisor(for: blur.fbos[1], in: blur), 2, "every buffer alike: the copy stays between equal sizes")
        XCTAssertEqual(EffectResolutionPolicy(divisor: 4).divisor(for: blur.fbos[0], in: blur), 1,
                       "the blur divisor alone leaves a frame-carrying effect")
        XCTAssertEqual(EffectResolutionPolicy(sharpContent: true, temporalDivisor: 2).divisor(for: blur.fbos[0], in: blur), 1)
        // A simulation swaps its buffers; an effect not named or shaped like a blur isn't a trail.
        let simulation = SceneEffectPlan(file: "effects/motionblur/effect.json", fbos: blur.fbos, passes: [
            pass(.render, target: "B", textures: [0: .fbo("A")]),
            pass(.swap("A", "B")),
        ])
        XCTAssertFalse(EffectResolutionPolicy.isTemporalAccumulation(simulation))
        XCTAssertFalse(EffectResolutionPolicy.isTemporalAccumulation(try motionBlur(file: "effects/feedback/effect.json")))
        XCTAssertEqual(policy.divisor(for: blur.fbos[0], in: try motionBlur(file: "effects/feedback/effect.json")), 1)
        // Buffers of different scales can't all shrink alike.
        let mixed = SceneEffectPlan(file: "effects/motionblur/effect.json", fbos: [try fbo("A"), try fbo("B", scale: 2)],
                                    passes: blur.passes)
        XCTAssertEqual(policy.divisor(for: mixed.fbos[0], in: mixed), 1)
    }

    func testTemporalDivisorFollowsTheSlider() {
        XCTAssertEqual(QualityEfficiency(stop: 4).temporalAccumulationDivisor, 1)
        XCTAssertEqual(QualityEfficiency(stop: 5).temporalAccumulationDivisor, 2)
    }
}

/// The same changes on WE's own motion blur, drawn on the GPU (needs `OWE_ASSETS`).
final class FullscreenEffectChainTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var builder: SceneEffectPlanBuilder!
    private var cache: URL!
    private var renderers: [EffectGraphRenderer] = []

    struct NoValues: SceneValueContext {
        func userProperty(_ name: String) -> String? { nil }
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: ShaderVariantTests.weAssets.path), "WE assets not present")
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        cache = FileManager.default.temporaryDirectory.appending(path: "owe-fullscreen-\(UUID().uuidString)")
        let root = ShaderVariantTests.weAssets
        builder = SceneEffectPlanBuilder(
            translator: ShaderVariantTranslator(compiler: InProcessShaderCompiler(), cacheDirectory: cache),
            readFile: { FileManager.default.contents(atPath: root.appending(path: $0).path) },
            loadTexture: { _, _ in nil })
    }

    override func tearDownWithError() throws {
        for renderer in renderers { renderer.pipelineArchive?.flush() }
        if let cache { try? FileManager.default.removeItem(at: cache) }
    }

    private func makeRenderer() throws -> EffectGraphRenderer {
        let renderer = try XCTUnwrap(EffectGraphRenderer(device: device, pipelineArchiveDirectory: cache.appending(path: "archives")))
        renderers.append(renderer)
        return renderer
    }

    /// WE's motion blur at an accumulation rate of 0.5, so history and the new frame both show.
    private func motionBlur() throws -> SceneEffectPlan {
        let json = #"{"file":"effects/motionblur/effect.json","passes":[{"constantshadervalues":{"rate":0.5}}]}"#
        return try builder.build(try JSONDecoder().decode(WEObjectEffect.self, from: Data(json.utf8)))
    }

    /// Frame `frame` of a moving image: a soft diagonal wave (`smooth`) or a hard-edged bar.
    private func image(frame: Int, size: SIMD2<Int>, smooth: Bool) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: size.x * size.y * 4)
        for y in 0..<size.y {
            for x in 0..<size.x {
                let i = (y * size.x + x) * 4
                let phase = Float(x + y + frame * 6) / 48 * 2 * .pi
                let value: Float = smooth ? 0.5 + 0.4 * sin(phase) : ((x + frame * 6) % 48 < 12 ? 0.9 : 0.1)
                pixels[i] = UInt8((value * 255).rounded())
                pixels[i + 1] = UInt8(((1 - value) * 255).rounded())
                pixels[i + 2] = UInt8((Float(y) / Float(size.y) * 255).rounded())
            }
        }
        return pixels
    }

    private func read(_ texture: MTLTexture) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                                  height: texture.height, mipmapped: false)
        descriptor.storageMode = .shared
        let copy = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(buffer.makeBlitCommandEncoder())
        blit.copy(from: texture, to: copy)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        copy.getBytes(&bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                      mipmapLevel: 0)
        return bytes
    }

    /// `frames` frames of the moving image through `plan`, each frame's output read back.
    private func run(_ plan: SceneEffectPlan, renderer: EffectGraphRenderer, frames: Int = 6, size: SIMD2<Int> = SIMD2(96, 64),
                     smooth: Bool = false, configure: (inout EffectGraphRenderer.Context) -> Void) throws -> [[UInt8]] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.x, height: size.y,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead]
        let input = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var context = EffectGraphRenderer.Context(frame: BuiltinFrameContext(time: 0), values: NoValues(),
                                                  assetTexture: { _, _ in nil }, sceneSnapshot: nil,
                                                  layerColor: SIMD3(1, 1, 1), layerAlpha: 1)
        configure(&context)
        XCTAssertTrue(renderer.waitUntilReady([plan], width: size.x, height: size.y), "pipelines still compiling")
        var outputs: [[UInt8]] = []
        for frame in 0..<frames {
            input.replace(region: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0,
                          withBytes: image(frame: frame, size: size, smooth: smooth), bytesPerRow: size.x * 4)
            // The image changes in place each frame, as the scene under a fullscreen layer does.
            context.inputVersion = UInt64(frame)
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            let output = try XCTUnwrap(renderer.apply([plan], to: input, layerID: "fullscreen", context: context,
                                                      commandBuffer: buffer))
            buffer.commit()
            buffer.waitUntilCompleted()
            outputs.append(try read(output))
        }
        return outputs
    }

    /// Handing the history copy over draws exactly what copying it draws, frame after frame.
    func testHandedOverCopyDrawsWhatTheCopyDraws() throws {
        let plan = try motionBlur()
        XCTAssertTrue(EffectGraphRenderer.copyCanAlias(plan, at: 1))
        let copied = try run(plan, renderer: try makeRenderer()) { $0.aliasCopies = false }
        let aliasing = try makeRenderer()
        let handed = try run(plan, renderer: aliasing) { $0.aliasCopies = true }
        XCTAssertEqual(aliasing.copiesAliased, copied.count)
        for (frame, (a, b)) in zip(copied, handed).enumerated() {
            XCTAssertEqual(a, b, "frame \(frame)")
        }
        XCTAssertNotEqual(copied[0], copied[3], "the history moves with the image")
    }

    /// Shading only a part of the buffers draws, inside that part, exactly what shading all of
    /// them draws: motion blur works pixel by pixel, and its history stays where it was.
    func testShadedPartMatchesTheWholeChainInside() throws {
        let plan = try motionBlur()
        let size = SIMD2(96, 64)
        let rect = SceneSnapshotTracker.Rect(x: 0, y: 8, width: 96, height: 40)
        let whole = try run(plan, renderer: try makeRenderer(), size: size) { _ in }
        let part = try run(plan, renderer: try makeRenderer(), size: size) {
            $0.renderRect = rect
            $0.aliasCopies = true
        }
        for frame in whole.indices {
            for y in rect.y..<rect.maxY {
                let row = (y * size.x) * 4..<((y + 1) * size.x) * 4
                XCTAssertEqual(Array(whole[frame][row]), Array(part[frame][row]), "frame \(frame), row \(y)")
            }
        }
    }

    /// The history at half size: the upsampled trail of a soft moving image stays within the
    /// optimisation gate (SSIM ≥ 0.98) of the full-size one.
    func testHalfSizeHistoryBlendsWithinTolerance() throws {
        let plan = try motionBlur()
        let size = SIMD2(128, 96)
        let full = try run(plan, renderer: try makeRenderer(), frames: 10, size: size, smooth: true) { _ in }
        let half = try run(plan, renderer: try makeRenderer(), frames: 10, size: size, smooth: true) {
            $0.resolution = EffectResolutionPolicy(temporalDivisor: 2)
        }
        for frame in [3, 9] {
            let reference = PerceptualImage(width: size.x, height: size.y, rgba: full[frame])
            let candidate = PerceptualImage(width: size.x, height: size.y, rgba: half[frame])
            let ssim = PerceptualCompare.ssim(reference, candidate)
            XCTAssertGreaterThanOrEqual(ssim, 0.98, "frame \(frame)")
            let mean = zip(full[frame], half[frame]).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(full[frame].count)
            XCTAssertLessThan(mean, 3, "frame \(frame): mean difference /255")
        }
    }
}
