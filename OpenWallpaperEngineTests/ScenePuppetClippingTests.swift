import XCTest
import Metal
import ImageIO
import simd
@testable import OpenWallpaperEngine

/// Puppet Warp clipping masks (docs/models-plan.md §2.13a): the `MDLV` 23 records WE 2.8.0.42's
/// editor writes (capture 532 and 532c, `Tests/Fixtures/Models/PuppetGroundTruth532`; we-test-wp-images,
/// tools/peer/requests/owe-beta7/models-open), WE's plan of the draws, and hand-built rigs drawn
/// through the bundled `genericimage4`, which reads the coverage, and `genericimage2`, which doesn't.
/// Capture 548 (`PuppetGroundTruth548`; owe-beta8/models-open/548-clipping-genericimage4): the
/// coverage at half the frame's size, sampled linearly, and the editor's nested masks.
///
/// The coverage is half the drawing's size, so a clipped part fades over the two texels either
/// side of a masking part's edge on a texel boundary (0.75 inside, 0.25 outside); the rows below
/// leave those texels out (nil) and `testTheCoverageIsHalfTheDrawingAndSampledLinearly` checks them.
final class ScenePuppetClippingTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var builder: ImageMaterialPlanBuilder!
    private var renderer: ScenePuppetRenderer!
    private var cache: URL!
    /// The mask textures the rigs' masks name, by name.
    private var maskTextures: [String: MTLTexture] = [:]

    private static func model(_ name: String) throws -> MDLModel {
        try MDLReader.read(try Fixtures.data("Models/PuppetGroundTruth532/\(name).mdl"))
    }

    // MARK: - The editor's files

    /// "Assign Clipping Mask" on the blue limb with the mask painted over the red one (532
    /// g_mask): the size of the range block goes 0x20 → 0x30, the blue island's part of bone 0's
    /// range splits off (540 + 54 + 486 indices), and one group is the mask: id 30 (the JSON's),
    /// the texture, flags 0, the blue ranges clipped and the red one masking.
    func testTheEditorsMaskIsAGroupOverTheSplitRanges() throws {
        let locked = try Self.model("g_locked"), masked = try Self.model("g_mask")
        XCTAssertEqual(locked.meshes[0].groups ?? [], [])
        XCTAssertEqual(MDLClippingMask.masks(of: locked.meshes[0]), [])
        XCTAssertNil(ScenePuppetClipping(mesh: locked.meshes[0], boneCount: 2))
        XCTAssertEqual(locked.meshes[0].boneRanges(boneCount: 2)?.map(\.indexCount), [594, 486])

        let mesh = masked.meshes[0]
        XCTAssertEqual(mesh.boneRanges(boneCount: 2), [.init(bone: 0, firstIndex: 0, indexCount: 540),
                                                       .init(bone: 0, firstIndex: 540, indexCount: 54),
                                                       .init(bone: 1, firstIndex: 594, indexCount: 486)])
        XCTAssertEqual(MDLClippingMask.masks(of: mesh), [MDLClippingMask(
            id: 30, texture: "masks/clipping_mask_608392ae", flags: [], clippedRanges: [1, 2], maskRanges: [0], parent: nil)])
        XCTAssertEqual(MDLClippingMask.masks(of: try Self.model("c_mask_noclip").meshes[0]), [MDLClippingMask(
            id: 40, texture: "masks/clipping_mask_6efbf20d", flags: [], clippedRanges: [1], maskRanges: [0], parent: nil)])
    }

    /// The panel's checkboxes are the group's flags: "Hide mask geometry" 0x4, "Invert mask" 0xa.
    func testTheMaskSettingsAreTheGroupsFlags() throws {
        XCTAssertEqual(MDLClippingMask.masks(of: try Self.model("g_mask_hide").meshes[0]).first?.flags, [.hidesMaskGeometry])
        XCTAssertEqual(MDLClippingMask.masks(of: try Self.model("g_mask_invert").meshes[0]).first?.flags, [.invert, .drawsInPlace])
    }

    /// WE's frame of g_mask drew three `DrawIndexed(540)` (rd_draws_report): the red part, its
    /// coverage, and the blue parts through it. With "Hide mask geometry" (g_mask_hide) the red
    /// part draws only into the coverage: WE's stills lost the red limb.
    func testThePlanDrawsTheMaskingPartThenTheClippedOnes() throws {
        let clipping = try XCTUnwrap(ScenePuppetClipping(mesh: try Self.model("g_mask").meshes[0], boneCount: 2))
        let steps = clipping.steps(order: clipping.order(nil))
        XCTAssertEqual(steps, [.draw([0]), .clip(layers: [.init(mask: 0, ranges: [0])], clipped: [1, 2], additive: false)])
        let draws = steps.flatMap { step -> [ScenePuppetDrawOrder.Range] in
            switch step {
            case .draw(let ranges): clipping.drawRanges(ranges)
            case let .clip(layers, clipped, _): layers.flatMap { clipping.drawRanges($0.ranges) } + clipping.drawRanges(clipped)
            }
        }
        XCTAssertEqual(draws.map(\.indexCount), [540, 540, 540])

        let hidden = try XCTUnwrap(ScenePuppetClipping(mesh: try Self.model("g_mask_hide").meshes[0], boneCount: 2))
        XCTAssertEqual(hidden.steps(order: hidden.order(nil)),
                       [.clip(layers: [.init(mask: 0, ranges: [0])], clipped: [1, 2], additive: false)])
        XCTAssertEqual(hidden.visibleRanges(order: hidden.order(nil)), [.init(firstIndex: 540, indexCount: 540)])

        let inverted = try XCTUnwrap(ScenePuppetClipping(mesh: try Self.model("g_mask_invert").meshes[0], boneCount: 2))
        XCTAssertEqual(inverted.steps(order: inverted.order(nil)),
                       [.draw([0]), .clip(layers: [.init(mask: 0, ranges: [0])], clipped: [1, 2], additive: false)])
    }

    /// A pose's reordered ranges are taken apart into the parts they merged.
    func testTheOrderFollowsThePosesDrawRanges() throws {
        let clipping = try XCTUnwrap(ScenePuppetClipping(mesh: try Self.model("g_mask").meshes[0], boneCount: 2))
        XCTAssertEqual(clipping.order(nil), [0, 1, 2])
        XCTAssertEqual(clipping.order([.init(firstIndex: 540, indexCount: 540), .init(firstIndex: 0, indexCount: 540)]), [1, 2, 0])
        // Blue first: the mask's last masking part comes after them, and so does their draw.
        XCTAssertEqual(clipping.steps(order: [1, 2, 0]),
                       [.draw([0]), .clip(layers: [.init(mask: 0, ranges: [0])], clipped: [1, 2], additive: false)])
    }

    /// Nesting (0x140262032): a mask whose masking ranges are all clipped by another nests in it;
    /// one that would close a loop doesn't.
    func testMasksNestInTheMaskThatClipsTheirMaskingParts() {
        func group(_ id: UInt64, clipped: [UInt32], masking: [UInt32]) -> MDLMesh.Group {
            MDLMesh.Group(id: id, name: "masks/m\(id)", flags: 0, listA: clipped, listB: masking)
        }
        var mesh = ScenePuppetTests.mesh(format: 0x1800009, flags: 0)
        mesh.groups = [group(1, clipped: [1], masking: [0]), group(2, clipped: [2], masking: [1])]
        XCTAssertEqual(MDLClippingMask.masks(of: mesh).map(\.parent), [nil, 0])
        mesh.groups = [group(1, clipped: [1], masking: [0]), group(2, clipped: [0], masking: [1])]
        XCTAssertEqual(MDLClippingMask.masks(of: mesh).map(\.parent), [1, nil], "A → B → A: the second is left out")
    }

    // MARK: - Drawing

    /// The docs' setup: a limb (blue) clipped by a mask painted over another (red). Moved half over
    /// the red one, blue shows only there; where it leaves the red, it's invisible.
    func testAClippedLimbShowsOnlyOverThePaintedLimb() throws {
        let pixels = try drawTwoLimbs(flags: [])
        assertRow(pixels, width: 16, [red, red, red, red, blue, blue, blue, nil, nil, clear, clear, clear, clear, clear, clear, clear])
    }

    /// "Invert mask": blue shows everywhere but over the painted limb.
    func testAnInvertedMaskShowsTheLimbOnlyAwayFromThePaintedLimb() throws {
        for flags: MDLClippingMask.Flags in [[.invert], [.invert, .drawsInPlace]] {
            let pixels = try drawTwoLimbs(flags: flags)
            assertRow(pixels, width: 16, [red, red, red, red, red, red, red, nil, nil, blue, blue, blue, clear, clear, clear, clear],
                      "flags \(flags.rawValue)")
        }
    }

    /// "Hide mask geometry": the red limb isn't drawn, only through the mask (WE 2.8's g_mask_hide).
    func testHiddenMaskGeometryDrawsOnlyIntoTheMask() throws {
        let pixels = try drawTwoLimbs(flags: [.hidesMaskGeometry])
        assertRow(pixels, width: 16, [clear, clear, clear, clear, blue, blue, blue, nil, nil, clear, clear, clear, clear, clear, clear, clear])
    }

    /// "Additive blending": the clipped limb adds to what's under it.
    func testAnAdditiveClippedLimbAddsToThePaintedLimb() throws {
        let pixels = try drawTwoLimbs(flags: [.additive])
        let magenta: [UInt8] = [255, 0, 255, 255]
        assertRow(pixels, width: 16, [red, red, red, red, magenta, magenta, magenta, nil, nil, clear, clear, clear, clear, clear, clear, clear])
    }

    /// `genericimage2` has no `CLIPPINGTARGET`: the limb draws unclipped, as in WE 2.8's captures of
    /// the editor's default puppet material. "Hide mask geometry" still hides the red limb.
    func testAShaderWithoutClippingDrawsTheLimbWhole() throws {
        let shown = try drawTwoLimbs(flags: [], material: "image2version")
        assertRow(shown, width: 16, [red, red, red, red, blue, blue, blue, blue, blue, blue, blue, blue, clear, clear, clear, clear])
        let hidden = try drawTwoLimbs(flags: [.hidesMaskGeometry], material: "image2version")
        assertRow(hidden, width: 16, [clear, clear, clear, clear, blue, blue, blue, blue, blue, blue, blue, blue, clear, clear, clear, clear])
    }

    /// A mask nested in another by WE's reader (0x140262032: green's mask is drawn only through
    /// green, which red's mask clips) is intersected with it: blue shows only where green and red
    /// both are. The editor doesn't write this shape for nested limbs (capture 548's rig lists
    /// every limb up to the masking one, `testTheEditorsNestedMasksEachDrawFromTheirOwnerUncut`).
    func testANestedMaskShowsItsLimbOnlyOverBothLimbs() throws {
        // Texture: red, green, blue thirds of 24 × 8.
        var bytes = [UInt8](repeating: 0, count: 24 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<24 { bytes.replaceSubrange((y * 24 + x) * 4..<(y * 24 + x) * 4 + 4, with: [red, green, blue][x / 8]) }
        }
        // Typed quads: Xcode 26.3 infers the untyped thirds as [Any].
        let quads: [(position: SIMD4<Float>, uv: SIMD4<Float>)] = [
            (SIMD4<Float>(-12, 4, -4, -4), SIMD4<Float>(0, 0, 1 / 3, 1)),
            (SIMD4<Float>(-4, 4, 4, -4), SIMD4<Float>(1 / 3, 0, 2 / 3, 1)),
            (SIMD4<Float>(4, 4, 12, -4), SIMD4<Float>(2 / 3, 0, 1, 1)),
        ]
        var mesh = ScenePuppetTests.mesh(quads: quads, bones: [0, 1, 2])
        mesh.vector4Block = Self.ranges([(0, 0, 6), (1, 6, 6), (2, 12, 6)])
        mesh.groups = [MDLMesh.Group(id: 1, name: "masks/red", flags: 0, listA: [1], listB: [0]),
                       MDLMesh.Group(id: 2, name: "masks/green", flags: 0, listA: [2], listB: [1])]
        maskTextures["masks/red"] = try maskTexture(width: 24, height: 8) { $0 < 8 }
        maskTextures["masks/green"] = try maskTexture(width: 24, height: 8) { $0 >= 8 && $0 < 16 }
        let plan = try plan(mesh, bones: 3, size: SIMD2(24, 8))
        var pose = ScenePuppetPose.bind(boneCount: 3)
        pose.bones[1] = ScenePuppetTests.translation(SIMD3(-4, 0, 0))
        pose.bones[2] = ScenePuppetTests.translation(SIMD3(-12, 0, 0))
        let pixels = try draw(plan, source: ScenePuppetTests.Picture(width: 24, height: 8, pixels: bytes), pose: pose)
        assertRow(pixels, width: 24, [red, red, red, red, nil, blue, blue, nil, nil, clear, clear, clear]
                  + Array(repeating: clear, count: 12))
        XCTAssertEqual(renderer.clippingMaskPasses("puppet"), 2)
    }

    // MARK: - Capture 548

    private static func model548(_ name: String) throws -> MDLModel {
        try MDLReader.read(try Fixtures.data("Models/PuppetGroundTruth548/\(name).mdl"))
    }

    /// WE makes the coverage half the frame's size (capture 548: a 960 × 540 R8 target for the
    /// 1920 × 1080 frame); here the frame is the layer's drawing.
    func testTheCoverageIsHalfTheDrawingsSize() {
        XCTAssertEqual(ScenePuppetRenderer.coverageSize(SIMD2(1920, 1080)), SIMD2(960, 540))
        XCTAssertEqual(ScenePuppetRenderer.coverageSize(SIMD2(512, 256)), SIMD2(256, 128))
        XCTAssertEqual(ScenePuppetRenderer.coverageSize(SIMD2(1, 1)), SIMD2(1, 1))
    }

    /// Read at the clipped part's screen position from a half-size target with linear filtering,
    /// a mask edge on a texel boundary fades over two pixels: 0.75 inside, 0.25 outside. WE's
    /// still (`mo2_548_c_mask_on_t1.0`, column 1090) has the circle at 0.26 on row 481 above the
    /// rectangle and at 0.73 over it on row 482, where the full-size coverage would cut sharply.
    func testTheCoverageIsHalfTheDrawingAndSampledLinearly() throws {
        let shown = try drawTwoLimbs(flags: [])
        assertRow(shown, width: 16, [nil, nil, nil, nil, nil, nil, blue, [64, 0, 191, 255], [0, 0, 255, 64], clear])
        let inverted = try drawTwoLimbs(flags: [.invert, .drawsInPlace])
        assertRow(inverted, width: 16, [nil, nil, nil, nil, nil, nil, red, [191, 0, 64, 255], [0, 0, 255, 191], blue])
    }

    /// The masked rig of 548 (c_mask_on): WE's frame drew `DrawIndexed` 516 (the rectangle), 516
    /// (its coverage) and 414 (the circle through it).
    func testTheMaskedRigDrawsAsWEsFrame() throws {
        let clipping = try XCTUnwrap(ScenePuppetClipping(mesh: try Self.model548("c_mask_on").meshes[0], boneCount: 2))
        XCTAssertEqual(drawCounts(clipping), [516, 516, 414])
    }

    /// The nested rig of 548 (`abc_puppet`): A, B clipped by maskA (id 34), C by maskB (id 50).
    /// The editor lists every limb from the first up to the painted one as masking (both masks:
    /// A and B), so neither nests in the other by WE's rule, and the limbs are the ranges the
    /// groups name, whatever their order in the image or the editor's limb numbers (Limb 20 = C,
    /// 21 = A, 22 = B; the JSON's island ids [50, 0, 34]). WE's frame: `DrawIndexed` 636 (A),
    /// 636 (maskA through A), 396 (B), 1032 (maskB through A and B, into the same target) and
    /// 150 (C).
    func testTheEditorsNestedMasksArePlannedAsWEsFrame() throws {
        let mesh = try Self.model548("abc_puppet").meshes[0]
        let masks = MDLClippingMask.masks(of: mesh)
        XCTAssertEqual(masks.map(\.id), [50, 34])
        XCTAssertEqual(masks.map(\.clippedRanges), [[2], [1]], "maskB clips C, maskA clips B")
        XCTAssertEqual(masks.map(\.maskRanges), [[0, 1], [0, 1]])
        XCTAssertEqual(masks.map(\.parent), [nil, nil])
        let clipping = try XCTUnwrap(ScenePuppetClipping(mesh: mesh, boneCount: 3))
        XCTAssertEqual(clipping.ranges.map(\.indexCount), [636, 396, 150])
        XCTAssertEqual(clipping.steps(order: clipping.order(nil)), [
            .draw([0]),
            .clip(layers: [.init(mask: 1, ranges: [0])], clipped: [1], additive: false),
            .clip(layers: [.init(mask: 0, ranges: [0, 1])], clipped: [2], additive: false),
        ])
        XCTAssertEqual(drawCounts(clipping), [636, 636, 396, 1032, 150])
    }

    /// 548's nested rig drawn at clip 65's frame 0 (B 90 px left, half over A; C 100 px left of B,
    /// over B's right side), as WE's frame poses it (`g_Bones` x −90 and −190). A draws whole; B
    /// only over A; C wherever maskB covers B's place, including the part of B that A's mask cut
    /// away: masks aren't cumulative (`mo2_548_nest_f0_t2.0`: B green from 824 to 883, C blue from
    /// 884 to 923 on row 540, the image's 120…179 and 180…219 on row 128).
    func testTheEditorsNestedMasksEachDrawFromTheirOwnerUncut() throws {
        let model = try Self.model548("abc_puppet")
        maskTextures["masks/clipping_mask_9fdadc16"] = try pngMask("clipping_mask_9fdadc16")
        maskTextures["masks/clipping_mask_a5b35b31"] = try pngMask("clipping_mask_a5b35b31")
        let source = SceneMetalTextureSource.dxt(TEXCompressedTexture(format: 0, width: 512, height: 256, data: [],
                                                                      contentWidth: 512, contentHeight: 256))
        let plan = try ScenePuppetPlan.make(model: model, rigPath: "abc_puppet.mdl", materialPath: "materials/image4.json",
                                            source: source, imageSize: SIMD2(512, 256), builder: builder)
        XCTAssertNotNil(plan.clipping?.mask)
        var pose = ScenePuppetPose.bind(boneCount: 3)
        pose.bones[1] = ScenePuppetTests.translation(SIMD3(-90, 0, 0))
        pose.bones[2] = ScenePuppetTests.translation(SIMD3(-190, 0, 0))
        let pixels = try draw(plan, source: try png("abc"), pose: pose)
        XCTAssertEqual(renderer.clippingMaskPasses("puppet"), 2)
        let a: [UInt8] = [230, 30, 30, 255], b: [UInt8] = [40, 200, 60, 255], c: [UInt8] = [40, 90, 240, 255]
        func texel(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[(y * 512 + x) * 4..<(y * 512 + x) * 4 + 4]) }
        func assertTexel(_ x: Int, _ y: Int, _ expected: [UInt8], _ message: String, line: UInt = #line) {
            let actual = texel(x, y)
            let close = abs(Int(actual[3]) - Int(expected[3])) <= 2
                && (expected[3] == 0 || zip(actual.prefix(3), expected.prefix(3)).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
            XCTAssertTrue(close, "(\(x), \(y)): \(actual), expected \(expected): \(message)", line: line)
        }
        assertTexel(50, 128, a, "A whole")
        assertTexel(100, 128, a, "A under B's place, left of B")
        assertTexel(150, 128, b, "B over A")
        assertTexel(190, 90, clear, "B off A: maskA cuts it")
        assertTexel(150, 90, b, "B over A, above C")
        assertTexel(200, 128, c, "C where A cut B away: maskB is B's whole place")
        assertTexel(210, 110, c, "C inside B's place")
        assertTexel(226, 128, clear, "C past B's place")
        assertTexel(260, 128, clear, "B's rest place: nothing there")
    }

    /// The index counts `steps` draws, coverage passes included, in order.
    private func drawCounts(_ clipping: ScenePuppetClipping) -> [Int] {
        clipping.steps(order: clipping.order(nil)).flatMap { step -> [Int] in
            switch step {
            case .draw(let ranges): clipping.drawRanges(ranges).map(\.indexCount)
            case let .clip(layers, clipped, _):
                layers.map { clipping.drawRanges($0.ranges).reduce(0) { $0 + $1.indexCount } }
                    + [clipping.drawRanges(clipped).reduce(0) { $0 + $1.indexCount }]
            }
        }
    }

    /// A capture PNG as straight-alpha RGBA8.
    private func png(_ name: String) throws -> ScenePuppetTests.Picture {
        let url = Fixtures.url("Models/PuppetGroundTruth548/\(name).png")
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let width = image.width, height = image.height
        var premultiplied = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &premultiplied, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The test images are opaque where drawn and empty elsewhere: unpremultiplying is exact.
        for index in stride(from: 0, to: premultiplied.count, by: 4) where premultiplied[index + 3] > 0 {
            let alpha = Float(premultiplied[index + 3]) / 255
            for channel in 0..<3 {
                premultiplied[index + channel] = UInt8(min(255, (Float(premultiplied[index + channel]) / alpha).rounded()))
            }
        }
        return ScenePuppetTests.Picture(width: width, height: height, pixels: premultiplied)
    }

    /// A capture's mask PNG (the `.tex`'s R8 as grey) as an R8 texture.
    private func pngMask(_ name: String) throws -> MTLTexture {
        let picture = try png(name)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: picture.width,
                                                                  height: picture.height, mipmapped: false)
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let red = stride(from: 0, to: picture.pixels.count, by: 4).map { picture.pixels[$0] }
        texture.replace(region: MTLRegionMake2D(0, 0, picture.width, picture.height), mipmapLevel: 0, withBytes: red,
                        bytesPerRow: picture.width)
        return texture
    }

    // MARK: - Helpers

    private let red: [UInt8] = [255, 0, 0, 255], green: [UInt8] = [0, 255, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
    private let clear: [UInt8] = [0, 0, 0, 0]

    override func setUpWithError() throws {
        let assets = ShaderVariantTests.weAssets
        try XCTSkipUnless(FileManager.default.fileExists(atPath: assets.appending(path: "shaders/clippingmaskimage4.frag").path),
                          "bundled WE shaders missing")
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        cache = FileManager.default.temporaryDirectory.appending(path: "owe-puppet-clip-\(UUID().uuidString)")
        let translator = ShaderVariantTranslator(compiler: InProcessShaderCompiler(), cacheDirectory: cache)
        let roots = [Fixtures.url("ImageMaterials"), assets]
        builder = ImageMaterialPlanBuilder(
            translator: translator,
            readFile: { path in
                for root in roots {
                    if let data = FileManager.default.contents(atPath: root.appending(path: path).path) { return data }
                }
                return nil
            },
            loadTexture: { name, _ in
                // The masks' textures; the test hands the drawn ones over by key.
                name.hasPrefix("masks/") ? .dxt(TEXCompressedTexture(format: 0, width: 1, height: 1, data: [], contentWidth: 1,
                                                                    contentHeight: 1)) : nil
            })
        renderer = try XCTUnwrap(ScenePuppetRenderer(device: device, archive: nil))
    }

    override func tearDownWithError() throws {
        if let cache { try? FileManager.default.removeItem(at: cache) } // scratch cleanup
    }

    /// `(bone, firstIndex, indexCount)` records as the file keeps them.
    private static func ranges(_ records: [(UInt32, UInt32, UInt32)]) -> [SIMD4<Float>] {
        records.map { SIMD4(Float(bitPattern: $0.0), Float(bitPattern: 0), Float(bitPattern: $0.1), Float(bitPattern: $0.2)) }
    }

    /// Red left, blue right of a 16 × 8 image; blue (bone 1) clipped by a mask painted over red and
    /// moved 4 px left, so its left half lies over red.
    private func drawTwoLimbs(flags: MDLClippingMask.Flags, material: String = "image4") throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<16 { bytes.replaceSubrange((y * 16 + x) * 4..<(y * 16 + x) * 4 + 4, with: x < 8 ? red : blue) }
        }
        var mesh = ScenePuppetTests.mesh(quads: [(SIMD4(-8, 4, 0, -4), SIMD4(0, 0, 0.5, 1)),
                                                 (SIMD4(0, 4, 8, -4), SIMD4(0.5, 0, 1, 1))], bones: [0, 1])
        mesh.vector4Block = Self.ranges([(0, 0, 6), (1, 6, 6)])
        mesh.groups = [MDLMesh.Group(id: 30, name: "masks/red", flags: flags.rawValue, listA: [1], listB: [0])]
        maskTextures["masks/red"] = try maskTexture(width: 16, height: 8) { $0 < 8 }
        let plan = try plan(mesh, bones: 2, size: SIMD2(16, 8), material: material)
        XCTAssertNotNil(plan.clipping)
        XCTAssertEqual(plan.clipping?.mask != nil, material == "image4", "only genericimage4 reads the coverage")
        var pose = ScenePuppetPose.bind(boneCount: 2)
        pose.bones[1] = ScenePuppetTests.translation(SIMD3(-4, 0, 0))
        return try draw(plan, source: ScenePuppetTests.Picture(width: 16, height: 8, pixels: bytes), pose: pose)
    }

    /// A single-channel mask, 255 in the columns `painted` picks.
    private func maskTexture(width: Int, height: Int, painted: (Int) -> Bool) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let bytes = (0..<height).flatMap { _ in (0..<width).map { painted($0) ? UInt8(255) : 0 } }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width)
        return texture
    }

    private func plan(_ mesh: MDLMesh, bones: Int, size: SIMD2<Float>, material: String = "image4") throws -> ScenePuppetPlan {
        let source = SceneMetalTextureSource.dxt(TEXCompressedTexture(format: 0, width: Int(size.x), height: Int(size.y),
                                                                      data: [], contentWidth: Int(size.x), contentHeight: Int(size.y)))
        return try ScenePuppetPlan.make(model: ScenePuppetTests.model(mesh, bones: bones), rigPath: "rig.mdl",
                                        materialPath: "materials/\(material).json", source: source, imageSize: size,
                                        builder: builder)
    }

    private func draw(_ plan: ScenePuppetPlan, source: ScenePuppetTests.Picture, pose: ScenePuppetPose) throws -> [UInt8] {
        XCTAssertTrue(renderer.waitUntilReady(plan), "the pipelines compile")
        let texture = try ScenePuppetTests.texture(source, device: device)
        let masks = maskTextures
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let target = try XCTUnwrap(renderer.albedo(plan, ScenePuppetRenderer.Draw(
            layerID: "puppet", source: texture, pose: pose, frame: BuiltinFrameContext(), values: EmptySceneValues(),
            assetTexture: { key, _ in masks.first { key.hasSuffix("|\($0.key)") }?.value }), commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertTrue(renderer.hasDrawn("puppet"))
        return try ScenePuppetTestSupport.rgba8(target, device: device)
    }

    /// The middle row's texels are `expected`, within 2 per channel (colour only where opaque);
    /// nil texels aren't checked.
    private func assertRow(_ pixels: [UInt8], width: Int, _ expected: [[UInt8]?], _ message: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
        let row = pixels.count / (4 * width) / 2
        for (x, texel) in expected.enumerated() {
            guard let texel else { continue }
            let at = (row * width + x) * 4
            let actual = Array(pixels[at..<at + 4])
            let alphaOK = abs(Int(actual[3]) - Int(texel[3])) <= 2
            let colourOK = texel[3] == 0 || zip(actual.prefix(3), texel.prefix(3)).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
            XCTAssertTrue(alphaOK && colourOK, "texel \(x): \(actual), expected \(texel) \(message)", file: file, line: line)
        }
    }
}
