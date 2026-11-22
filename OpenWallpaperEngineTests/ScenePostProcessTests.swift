import XCTest
import Metal
import MetalKit
@testable import OpenWallpaperEngine

/// `ScenePostProcess`, the stage after the scene pass: WE's bloom gate and strength, and the
/// composite that carries the app's own adjustments.
@MainActor
final class ScenePostProcessTests: XCTestCase {
    private let placement = LayerUniform(position: SIMD2(960, 540), size: SIMD2(1920, 1080), sceneSize: SIMD2(1920, 1080),
                                         opacity: 1, particleShape: 0, rotation: 0, color: SIMD4(repeating: 1),
                                         uvOrigin: .zero, uvAxisX: SIMD2(1, 0), uvAxisY: SIMD2(0, 1),
                                         effects: SIMD4(1, 1, 1, 0), blur: 0, colorEffects: SIMD4(0, 1, 0, 0.7),
                                         transform: SIMD4(0, 0, 0, 1), transformScaleY: 1)

    /// The composite adds only the user adjustment layer's saturation and hue; its blur and bloom
    /// are WE's Blur effect and bloom chain, not the composite's.
    func testCompositeUniformCarriesTheAppExtrasOnly() {
        let extras = ScenePostProcess.AppExtras(bloom: 1.5, saturation: 0.8, hue: 0.25, blur: 1.5)
        let uniform = ScenePostProcess.compositeUniform(placement, extras: extras)
        XCTAssertEqual(uniform.effects, SIMD4(1, 1, 0.8, 0), "no native bloom")
        XCTAssertEqual(uniform.colorEffects.z, 0.25)
        XCTAssertEqual(uniform.blur, 0, "no native blur")
        XCTAssertEqual(uniform.position, placement.position)
        let identity = ScenePostProcess.compositeUniform(placement, extras: .init())
        XCTAssertEqual(identity.effects, SIMD4(1, 1, 1, 0))
        XCTAssertEqual(identity.colorEffects.z, 0)
        XCTAssertEqual(identity.blur, 0)
    }

    /// WE blooms when post-processing isn't "disabled" and the scene's live `bloom` is on (0x140180a41).
    func testBloomRunsWhenTheSceneAndTheSettingAllowIt() {
        let on = ScenePostProcess.Bloom(enabled: true, strength: 2, threshold: 0.65, tint: SIMD3(repeating: 1))
        var off = on
        off.enabled = false
        var settings = SceneRenderSettings()
        for quality in [GSPostProcessingQuality.enabled, .ultra, .displayhdr] {
            settings.postProcessing = quality
            XCTAssertTrue(ScenePostProcess.runsBloom(on, settings: settings), "\(quality)")
            XCTAssertFalse(ScenePostProcess.runsBloom(off, settings: settings), "\(quality): the scene's bloom is off")
        }
        settings.postProcessing = .disabled
        XCTAssertFalse(ScenePostProcess.runsBloom(on, settings: settings), "post-processing disabled")
    }

    /// In HDR the chain runs where bloom does, over WE's levels capped by `bloomhdriterations`;
    /// elsewhere the frame takes `combine_srgb` (nil).
    func testHDRLevelsFollowTheBloomGateAndIterations() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 48,
                                                                  mipmapped: false)
        let scene = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var hdr = SceneHDRBloomSettings()
        hdr.enabled = true
        var frame = ScenePostProcess.Frame(
            scene: scene, output: MTLRenderPassDescriptor(), commandBuffer: try XCTUnwrap(queue.makeCommandBuffer()),
            placement: placement,
            bloom: ScenePostProcess.Bloom(enabled: true, strength: 2, threshold: 0.65, tint: SIMD3(repeating: 1), hdr: hdr),
            extras: .init(), settings: SceneRenderSettings())
        frame.settings.postProcessing = .ultra
        XCTAssertEqual(ScenePostProcess.hdrLevels(frame), 5, "48 halves 5 times")
        frame.bloom.hdr.iterations = 3
        XCTAssertEqual(ScenePostProcess.hdrLevels(frame), 3)
        frame.bloom.enabled = false
        XCTAssertNil(ScenePostProcess.hdrLevels(frame), "a script turned bloom off: combine_srgb")
    }

    /// The user adjustment layer exists only once an adjustment leaves its default; WE's effects
    /// draw on it, hue, saturation, Color Pop and Dim are the composite's.
    func testTheUserAdjustmentLayerRunsOnlyForItsEffects() {
        XCTAssertTrue(ScenePostProcess.AppExtras().isIdentity)
        XCTAssertFalse(ScenePostProcess.AppExtras(hue: 0.5).isIdentity)
        XCTAssertTrue(ScenePostProcess.AppExtras(colorPopKey: SIMD3(0, 1, 0), tintColor: SIMD3(0, 0, 1)).isIdentity,
                      "a colour alone changes nothing")
        XCTAssertFalse(SceneUserAdjustmentLayer.runs(.init()))
        XCTAssertFalse(SceneUserAdjustmentLayer.runs(.init(saturation: 0.5, hue: 1, dim: 0.5, colorPop: 0.5)))
        XCTAssertTrue(SceneUserAdjustmentLayer.runs(.init(blur: 0.5)))
        XCTAssertTrue(SceneUserAdjustmentLayer.runs(.init(bloom: 0.5)))
        for extras in [ScenePostProcess.AppExtras(tint: 0.5), .init(localContrast: 0.5), .init(chromaticAberration: 0.5),
                       .init(vhs: 0.5), .init(filmGrain: 0.5)] {
            XCTAssertTrue(SceneUserAdjustmentLayer.runs(extras))
        }
        XCTAssertEqual(SceneUserAdjustmentLayer.blur.constants(.init(blur: 1.5)),
                       [SceneScriptConstantWrite(material: nil, name: "scale", value: [1.5, 1.5])])
        XCTAssertFalse(ScenePostProcess.AppExtras(tint: 1, localContrast: 1, chromaticAberration: 1).animates)
        XCTAssertTrue(ScenePostProcess.AppExtras(vhs: 0.1).animates)
        XCTAssertTrue(ScenePostProcess.AppExtras(filmGrain: 0.1).animates)
    }

    /// Dim darkens the composite's colour; Color Pop keys its colour with the slider's range.
    func testDimAndColorPopAreTheComposites() {
        let dimmed = ScenePostProcess.compositeUniform(placement, extras: .init(dim: 0.25))
        XCTAssertEqual(dimmed.color.x, placement.color.x * 0.75, accuracy: 1e-6)
        XCTAssertEqual(dimmed.color.w, placement.color.w)
        XCTAssertEqual(ScenePostProcess.compositeUniform(placement, extras: .init()).colorPop, .zero)
        let popped = ScenePostProcess.compositeUniform(placement, extras: .init(colorPop: 0.5, colorPopKey: SIMD3(0, 1, 0)))
        XCTAssertEqual(popped.colorPop, SIMD4(0, 1, 0, 0.25))
        let size = SIMD2(1920, 1080)
        XCTAssertFalse(ScenePostProcess.compositeCopies(dimmed, size: size))
        XCTAssertFalse(ScenePostProcess.compositeCopies(popped, size: size))
    }

    /// The colour rows' values: 0…1 or 0…255 components; the fallback for anything else.
    func testAdjustmentColorsParse() {
        XCTAssertEqual(SceneMetalRenderer.color("0 0.5 1", or: .zero), SIMD3(0, 0.5, 1))
        XCTAssertEqual(SceneMetalRenderer.color("255 0 51", or: .zero), SIMD3(1, 0, 0.2))
        XCTAssertEqual(SceneMetalRenderer.color(nil, or: SIMD3(1, 0, 0)), SIMD3(1, 0, 0))
        XCTAssertEqual(SceneMetalRenderer.color("1 0", or: SIMD3(1, 1, 1)), SIMD3(1, 1, 1))
    }

    /// The User Adjustments apply in place: none rebuilds the scene.
    func testEveryUserAdjustmentAppliesInPlace() {
        for property in SceneUserPropertiesModel.userAdjustments() {
            XCTAssertEqual(SceneChangeImpact.impact(of: property.id), .none, property.id)
        }
    }

    // MARK: - Composite skip (efficiency-plan-2d notes WP3-A, S2)

    /// The composite is a copy only for a quad exactly covering the output with every adjustment at identity.
    func testTheCompositeCopiesOnlyAnExactIdentityPlacement() {
        let size = SIMD2(1920, 1080)
        XCTAssertTrue(ScenePostProcess.compositeCopies(placement, size: size))
        var shifted = placement
        shifted.position.x += 0.5
        XCTAssertFalse(ScenePostProcess.compositeCopies(shifted, size: size))
        XCTAssertFalse(ScenePostProcess.compositeCopies(placement, size: SIMD2(1920, 1200)))
        XCTAssertFalse(ScenePostProcess.compositeCopies(
            ScenePostProcess.compositeUniform(placement, extras: .init(saturation: 0.9)), size: size))
        XCTAssertTrue(ScenePostProcess.compositeCopies(
            ScenePostProcess.compositeUniform(placement, extras: .init(blur: 1.5)), size: size),
                      "the blur is the adjustment layer's, which `passesThrough` checks")
    }

    /// Every CI scene drawn at its own size with the composite skipped equals, byte for byte (colour;
    /// the desktop ignores alpha), the frame drawn through the composite, wherever two composited
    /// renders agree with each other (random particles don't); through a view and a shared frame.
    /// About 10 min in Debug, so it runs nightly and locally (`OWE_SLOW_TESTS=1`), not on every PR.
    func testTheCompositeSkipEqualsTheCompositeOnCIScenes() throws {
        try SlowTests.require()
        let root = Fixtures.url("Scenes")
        var skipped = 0, compared = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() where !Fixtures.unrenderableScenes.contains(name) {
            let directory = root.appending(path: name)
            guard let data = FileManager.default.contents(atPath: directory.appending(path: "scene.json").path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let general = json["general"] as? [String: Any],
                  let projection = general["orthogonalprojection"] as? [String: Any],
                  let width = projection["width"] as? Int, let height = projection["height"] as? Int,
                  width * height <= 1920 * 1080 else { continue }
            let size = SIMD2(width, height)
            // Set before each load: a draw while a later harness loads would otherwise count.
            func harness(_ screen: String, skips: Bool) throws -> SceneFrameHarness {
                try SceneFrameHarness(directory: directory, size: size, screenID: screen) {
                    $0.skipsIdleFrames = false
                    $0.skipsIdentityComposite = skips
                }
            }
            let skip = try harness("skip", skips: true)
            let plain = try harness("plain", skips: false)
            let control = try harness("control", skips: false)
            defer { skip.close(); plain.close(); control.close() }
            for frame in 0..<24 {
                let shared = frame % 2 == 1
                for harness in [skip, plain, control] {
                    if shared {
                        harness.now += 1.0 / 30
                        let drawable = SIMD2<Float>(Float(size.x), Float(size.y))
                        harness.renderer.renderShared([SceneViewport(drawableSize: drawable, pointSize: drawable, cursor: nil,
                                                                     frameRateLimit: 60)])
                        harness.renderer.lastCommandBuffer?.waitUntilCompleted()
                        harness.renderer.scripts.wallpaper?.waitUntilIdle()
                    } else {
                        harness.draw(frames: 1, step: 1.0 / 30)
                    }
                }
                let reference = Self.rgb(plain, shared: shared)
                guard frame > 2, !reference.isEmpty, reference == Self.rgb(control, shared: shared) else { continue }
                XCTAssertTrue(reference == Self.rgb(skip, shared: shared), "\(name) frame \(frame) (shared \(shared)) differs")
                compared += 1
            }
            skipped += skip.renderer.compositesSkipped
            XCTAssertEqual(plain.renderer.compositesSkipped, 0)
        }
        print("Composite skip CI: \(compared) frames compared, \(skipped) composites skipped")
        XCTAssertGreaterThan(compared, 20)
        XCTAssertGreaterThan(skipped, 20)
    }

    /// The last frame's colour bytes: the view's drawable, or the shared frame.
    private static func rgb(_ harness: SceneFrameHarness, shared: Bool) -> [UInt8] {
        guard let texture = shared ? harness.renderer.sharedFrame : harness.view.currentDrawable?.texture,
              texture.width == harness.size.x, texture.height == harness.size.y,
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return [] }
        let bytesPerRow = texture.width * 4
        guard let buffer = device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else { return [] }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let bytes = UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: buffer.length)
        return bytes.enumerated().compactMap { $0.offset % 4 == 3 ? nil : $0.element }
    }
}
