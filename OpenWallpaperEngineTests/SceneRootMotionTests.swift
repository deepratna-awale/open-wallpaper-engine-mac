import XCTest
import simd
@testable import OpenWallpaperEngine

/// Root motion against WE 2.8.0.42 (docs/test-risks.md MG4, docs/models-plan.md §2.8): the model
/// editor's own `.mdl` (`mg4-rootmotion-all-on.mdl`: a box skinned to the bone `root` under
/// `RootNode` and `Rig`, whose clip "Scene (Clip 5)", id 26, cut from "Scene", id 16, moves the root
/// by (1, 2, 3)·s(t) and turns it by (0.3, 0.6, 0.9)·s(t) in Blender's axes over 30 frames, its last
/// frame equal to its first). The editor's nine settings differ only in the clip flags byte (at
/// 0x17D4: 0x04 Match loop, 0x08/0x10/0x20 position x/y/z, 0x80 rotation y) and the root bone (the
/// u32 at 0x2534).
///
/// WE's captures (we-test-wp-images @ 2aad5f2, tools/peer/requests/owe-beta3) show WE strips the
/// flagged axes from the root's pose and never moves the object by them, with nothing carried
/// from loop to loop. The stack has no object motion to apply, so these tests check the pose.
final class SceneRootMotionTests: XCTestCase {
    struct Variant {
        var name: String
        var flags: UInt32
        var rootBone: Int32
        /// WE's box centroid on the 1920×1080 screen at frames 5, 10, 15, 20 and 25 of a loop, read
        /// from its capture `clips/mg4p_<name>.mp4` (6 s at 30 fps, from the frame the box jumps
        /// back to its start); nil for the settings whose file is the same as another's.
        var we: [SIMD2<Float>]? = nil
    }

    static let variants: [Variant] = [
        Variant(name: "bone_none", flags: 0x401, rootBone: -1,
                we: [SIMD2(946, 556), SIMD2(892, 539), SIMD2(849, 527), SIMD2(782, 510), SIMD2(737, 498)]),
        Variant(name: "root_all_off", flags: 0x401, rootBone: 2),
        Variant(name: "root_posX", flags: 0xc01, rootBone: 2,
                we: [SIMD2(931, 550), SIMD2(886, 535), SIMD2(831, 517), SIMD2(724, 484), SIMD2(671, 469)]),
        Variant(name: "root_posY", flags: 0x1401, rootBone: 2,
                we: [SIMD2(936, 559), SIMD2(862, 558), SIMD2(779, 559), SIMD2(611, 563), SIMD2(530, 566)]),
        Variant(name: "root_posZ", flags: 0x2401, rootBone: 2,
                we: [SIMD2(945, 574), SIMD2(894, 626), SIMD2(852, 675), SIMD2(793, 746), SIMD2(764, 783)]),
        Variant(name: "root_rotX", flags: 0x401, rootBone: 2),
        Variant(name: "root_rotY", flags: 0x8401, rootBone: 2,
                we: [SIMD2(931, 551), SIMD2(885, 537), SIMD2(851, 531), SIMD2(789, 530), SIMD2(769, 530)]),
        Variant(name: "root_rotZ", flags: 0x401, rootBone: 2),
        Variant(name: "root_all_on", flags: 0xbc01, rootBone: 2,
                we: [SIMD2(915, 582), SIMD2(834, 649), SIMD2(776, 742), SIMD2(740, 911), SIMD2(742, 998)]),
    ]

    static var allOff: Variant { variants[1] }
    static var yawOnly: Variant { variants[6] }
    static var allOn: Variant { variants[8] }

    static let flagsOffset = 0x17D4
    static let rootBoneOffset = 0x2534

    /// The editor's file with another setting written in.
    static func data(_ variant: Variant) throws -> Data {
        var data = try Data(contentsOf: Fixtures.url("Models/mg4-rootmotion-all-on.mdl"))
        data[flagsOffset] = UInt8((variant.flags >> 8) & 0xff)
        withUnsafeBytes(of: variant.rootBone.littleEndian) { bytes in
            for (index, byte) in bytes.enumerated() { data[rootBoneOffset + index] = byte }
        }
        return data
    }

    func testTheEditorsClipRecord() throws {
        let model = try MDLModel(contentsOf: Fixtures.url("Models/mg4-rootmotion-all-on.mdl"))
        let clips = try XCTUnwrap(model.animations)
        XCTAssertEqual(clips.map(\.id), [16, 26])
        XCTAssertEqual(clips.map(\.name), ["Scene", "Scene (Clip 5)"])
        XCTAssertNil(clips[0].reference)
        XCTAssertEqual(clips[1].flags, 0xbc01, "reference, Match loop, position x y z, rotation y")
        XCTAssertEqual(clips[1].reference,
                       MDLAnimation.Reference(animation: 0, startFrame: 0, endFrame: 30, frameOffset: 0, rootBone: 2))
        XCTAssertEqual(model.skeleton?.bones.map(\.name), ["RootNode", "Rig", "root"])
    }

    /// Every setting the editor wrote reads back as written; with the capture's files present
    /// (`OWE_MG4_VARIANTS`, or the peer's ground-truth folder) those are read too.
    func testEveryEditorVariantParses() throws {
        let folder = ProcessInfo.processInfo.environment["OWE_MG4_VARIANTS"]
            ?? "/Volumes/980Pro/dd-agentREF/peer/tools/peer/models_gt/mg4/mdl_variants"
        var files = 0
        for variant in Self.variants {
            var sources = [try Self.data(variant)]
            let file = URL(fileURLWithPath: folder).appending(path: "rootmotion_\(variant.name).mdl")
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                XCTAssertEqual(data, sources[0], "\(variant.name): the editor's file is the fixture with its two fields")
                sources.append(data)
                files += 1
            }
            for data in sources {
                let model = try MDLReader.read(data)
                let clip = try XCTUnwrap(model.animations?.last, variant.name)
                XCTAssertEqual(clip.id, 26, variant.name)
                XCTAssertEqual(clip.flags, variant.flags, variant.name)
                XCTAssertEqual(clip.reference?.rootBone, variant.rootBone, variant.name)
                XCTAssertEqual(clip.reference?.endFrame, 30, variant.name)
            }
        }
        if files > 0 { XCTAssertEqual(files, Self.variants.count) }
    }

    /// WE's fast-fail: without Match loop, root-motion Start and End frames must lie in the clip.
    func testRootMotionFramesPastTheClipAreRefused() throws {
        var data = try Self.data(Self.variants[2])
        data[Self.flagsOffset] = 0x08  // position x without Match loop
        data[Self.rootBoneOffset - 8] = 31  // End frame 31 of a 30-frame clip
        XCTAssertThrowsError(try MDLReader.read(data))
        data[Self.rootBoneOffset - 8] = 30
        XCTAssertNoThrow(try MDLReader.read(data))
    }

    /// The flags byte at 0x17D4 is bits 8…15 of the clip flags: 0xBC is position x, y, z, rotation
    /// y and Match loop, after the clip record's own bit (0x01).
    func testTheFlagsByte() throws {
        var data = try Self.data(Self.allOn)
        let flags: [(UInt8, UInt32)] = [
            (0x04, MDLAnimation.Flag.matchLoop), (0x08, MDLAnimation.Flag.rootPositionX),
            (0x10, MDLAnimation.Flag.rootPositionY), (0x20, MDLAnimation.Flag.rootPositionZ),
            (0x80, MDLAnimation.Flag.rootRotationY),
        ]
        for (byte, flag) in flags {
            data[Self.flagsOffset] = byte
            let clip = try XCTUnwrap(try MDLReader.read(data).animations?.last)
            XCTAssertEqual(clip.flags, MDLAnimation.Flag.reference | flag, String(format: "0x%02x", byte))
        }
        data[Self.flagsOffset] = 0xBC
        XCTAssertEqual(try XCTUnwrap(try MDLReader.read(data).animations?.last).flags, 0xbc01)
    }

    /// All off: the root plays its full motion, the pose a model without root motion has.
    func testAllOffPlaysTheFullMotion() throws {
        let rooted = try Self.rootPath(Self.allOff, rootMotion: true)
        let plain = try Self.rootPath(Self.allOff, rootMotion: false)
        for (a, b) in zip(rooted, plain) {
            XCTAssertLessThan(simd_distance(a.translation, b.translation), 1e-5)
            XCTAssertEqual(a.yaw, b.yaw, accuracy: 1e-5)
        }
        XCTAssertGreaterThan(Self.spread(rooted.map(\.translation)), 0.1, "the root travels")
        XCTAssertGreaterThan(rooted.map { abs($0.yaw) }.max() ?? 0, 0.1, "the root turns")
    }

    /// Yaw only: the root's yaw comes out of the pose, its translation plays as with all off.
    func testYawOnlyKeepsTheRootsYaw() throws {
        let yaw = try Self.rootPath(Self.yawOnly, rootMotion: true)
        let full = try Self.rootPath(Self.allOff, rootMotion: true)
        let fullTurn = full.map { abs($0.yaw) }.max() ?? 0
        XCTAssertLessThan(yaw.map { abs($0.yaw) }.max() ?? 0, fullTurn * 0.25, "the yaw is stripped")
        for (a, b) in zip(yaw, full) {
            XCTAssertLessThan(simd_distance(a.translation, b.translation), 1e-4, "the translation still plays")
        }
    }

    /// All on: translation and yaw come out of the pose, so the root stays near its start.
    func testAllOnKeepsTheModelNearTheOrigin() throws {
        let on = try Self.rootPath(Self.allOn, rootMotion: true)
        let off = try Self.rootPath(Self.allOff, rootMotion: true)
        XCTAssertLessThan(Self.spread(on.map(\.translation)), Self.spread(off.map(\.translation)) * 0.25)
        XCTAssertLessThan(on.map { abs($0.yaw) }.max() ?? 0, (off.map { abs($0.yaw) }.max() ?? 0) * 0.25)
    }

    /// The box's path through a loop, played as the capture's project plays it (layer on clip 26,
    /// model scale 0.01, camera 8 6 8 → 0 1 0, fov 50, 1920×1080), against WE's MG4 captures, with
    /// the object never moved by root motion. All off is the root bone with no axis, the same
    /// file as `bone_none`, whose capture stands for it.
    func testTheLoopFollowsWEsCaptures() throws {
        let captured: [(Variant, [SIMD2<Float>])] = [
            (Self.allOff, try XCTUnwrap(Self.variants[0].we)),
            (Self.yawOnly, try XCTUnwrap(Self.yawOnly.we)),
            (Self.allOn, try XCTUnwrap(Self.allOn.we)),
        ] + Self.variants[2...4].compactMap { variant in variant.we.map { (variant, $0) } }
        for (variant, we) in captured {
            let path = try Self.screenPath(variant)
            let errors: [Float] = zip(path, we).map { simd_distance($0, $1) }
            let mean: Float = errors.reduce(0, +) / Float(errors.count)
            XCTAssertLessThan(mean, 20, "\(variant.name): ours \(path), WE's \(we)")
        }
    }

    /// WE 2.8.0.42's newer captures (we-test-wp-images @ 2aad5f2, tools/peer/requests/owe-beta3:
    /// `rootmotion_strips.png` and `models_gt/mg4/clips`), read from `OWE_BETA3_CAPTURES` when set.
    func testTheBeta3Captures() throws {
        guard let folder = ProcessInfo.processInfo.environment["OWE_BETA3_CAPTURES"],
              FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appending(path: "rootmotion_strips.png").path) else {
            throw XCTSkip("the owe-beta3 captures weren't reachable when this was written; their frames aren't transcribed yet")
        }
        throw XCTSkip("transcribe the box centroids from rootmotion_strips.png and models_gt/mg4/clips into `we` paths here")
    }

    /// Nothing accumulates: each loop poses the root as the last did, for every setting.
    func testNoAccumulationAcrossLoops() throws {
        let frames = [5, 10, 15, 20, 25]
        for variant in [Self.allOff, Self.yawOnly, Self.allOn] {
            let loops = (0..<5).map { loop in frames.map { $0 + 30 * loop } }
            let path = try Self.rootPath(variant, rootMotion: true, steps: loops.flatMap { $0 })
            for loop in 1..<5 {
                for index in frames.indices {
                    let a = path[index], b = path[loop * frames.count + index]
                    XCTAssertLessThan(simd_distance(a.translation, b.translation), 1e-3, "\(variant.name) loop \(loop)")
                    XCTAssertEqual(a.yaw, b.yaw, accuracy: 1e-3, "\(variant.name) loop \(loop)")
                }
            }
        }
    }

    /// A clip the editor cut without Match loop reads its source clip from its Start frame in a
    /// model (0x14021c6b3), whatever tracks it carries; with Match loop, or on a puppet, it reads
    /// its own.
    func testACutClipWithoutMatchLoopReadsItsSource() throws {
        let skeleton = SceneAnimationLayersTests.skeleton()
        let source = SceneAnimationLayersTests.clip(id: 16, name: "Scene", fps: 10, frames: 20) { frame in
            MDLBonePose(position: SIMD3(Float(frame), 0, 0), euler: .zero, scale: SIMD3(repeating: 1))
        }
        var cut = SceneAnimationLayersTests.clip(id: 26, name: "cut", fps: 10, frames: 5) { _ in
            MDLBonePose(position: SIMD3(0, -7, 0), euler: .zero, scale: SIMD3(repeating: 1))
        }
        cut.flags = MDLAnimation.Flag.reference
        cut.reference = MDLAnimation.Reference(animation: 0, startFrame: 8, endFrame: 13, frameOffset: 0, rootBone: -1)
        func translation(_ clip: MDLAnimation, model: Bool) -> SIMD3<Float> {
            var stack = SceneAnimationLayerStack(skeleton: skeleton, clips: [source, clip], model: model)
            stack.insert(SceneAnimationLayer(key: 1, name: "cut", clip: 1, animation: clip))
            var update = SceneAnimationLayerUpdate()
            return stack.evaluate(delta: 0.2, update: &update)[0].translation  // frame 2 of the cut
        }
        XCTAssertEqual(translation(cut, model: true), SIMD3(10, 0, 0), "the source's frame 8 + 2")
        XCTAssertEqual(translation(cut, model: false), SIMD3(0, -7, 0), "a puppet reads the clip's own")
        cut.flags |= MDLAnimation.Flag.matchLoop
        XCTAssertEqual(translation(cut, model: true), SIMD3(0, -7, 0), "with Match loop the clip's own")
    }

    // MARK: - The path

    static func stack(_ model: MDLModel, rootMotion: Bool) throws -> SceneAnimationLayerStack {
        let skeleton = SceneSkeleton(try XCTUnwrap(model.skeleton))
        let clips = try XCTUnwrap(model.animations)
        var stack = SceneAnimationLayerStack(skeleton: skeleton, clips: clips, model: true, rootMotion: rootMotion)
        let index = try XCTUnwrap(stack.clipIndex(id: 26), "the layer names the clip, 26, not the source 16")
        stack.insert(SceneAnimationLayer(key: 900, name: "clip", clip: index, animation: clips[index]))
        return stack
    }

    struct RootSample {
        /// The root's model-space position.
        var translation: SIMD3<Float>
        /// The root's yaw since frame 0 (radians).
        var yaw: Float
    }

    /// The root bone's model-space position and yaw after each of `steps` frames of 1/30 s (by
    /// default frames 5, 10, 15, 20 and 25 of the second loop).
    static func rootPath(_ variant: Variant, rootMotion: Bool, steps: [Int] = [35, 40, 45, 50, 55]) throws -> [RootSample] {
        let model = try MDLReader.read(try data(variant))
        var stack = try stack(model, rootMotion: rootMotion)
        let skeleton = stack.skeleton
        func root(_ pose: [SceneBoneTransform]) -> simd_float4x4 { skeleton.worlds(locals: pose.map(\.matrix))[2] }
        func rotation(_ matrix: simd_float4x4) -> simd_float3x3 {
            let r = SceneRootMotion.rotation(matrix)
            return simd_float3x3(simd_normalize(r.columns.0), simd_normalize(r.columns.1), simd_normalize(r.columns.2))
        }
        var update = SceneAnimationLayerUpdate()
        let first = rotation(root(stack.evaluate(delta: 0, update: &update)))
        var samples: [RootSample] = []
        for step in 1...(steps.max() ?? 0) {
            let pose = stack.evaluate(delta: 1.0 / 30, update: &update)
            guard steps.contains(step) else { continue }
            let world = root(pose)
            let yaw = SceneRootMotion.yaw(rotation(world) * first.inverse)
            // The yaw matrix's columns are (c, 0, −s), (0, 1, 0), (s, 0, c).
            samples.append(RootSample(translation: SceneRootMotion.translation(world),
                                      yaw: atan2(yaw.columns.2.x, yaw.columns.2.z)))
        }
        return samples
    }

    /// The box centre on screen after each of `steps` frames of 1/30 s (by default frames 5, 10,
    /// 15, 20 and 25 of the second loop). The object stays at the origin, scale 0.01: root motion
    /// never moves it.
    static func screenPath(_ variant: Variant, steps: [Int] = [35, 40, 45, 50, 55]) throws -> [SIMD2<Float>] {
        let model = try MDLReader.read(try data(variant))
        var stack = try stack(model, rootMotion: true)
        let bounds = model.bounds
        let centre = (bounds.min + bounds.max) * 0.5
        let object = SceneWorldMatrix.local(SceneLocalTransform3D(origin: .zero, scale: SIMD3(repeating: 0.01), angles: .zero))
        var update = SceneAnimationLayerUpdate()
        var path: [SIMD2<Float>] = []
        for step in 1...(steps.max() ?? 0) {
            let pose = stack.evaluate(delta: 1.0 / 30, update: &update)
            guard steps.contains(step) else { continue }
            let palette = stack.skeleton.palette(worlds: stack.skeleton.worlds(locals: pose.map(\.matrix)))
            let placed: SIMD4<Float> = object * (palette[2] * SIMD4<Float>(centre, 1))
            path.append(screen(SIMD3(placed.x, placed.y, placed.z)))
        }
        return path
    }

    /// Through the capture's camera: eye 8 6 8, centre 0 1 0, a 50° vertical fov, 16:9.
    static func screen(_ point: SIMD3<Float>) -> SIMD2<Float> {
        let eye = SIMD3<Float>(8, 6, 8)
        let forward = simd_normalize(SIMD3<Float>(0, 1, 0) - eye)
        let side = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(side, forward)
        let relative = point - eye
        let depth: Float = simd_dot(relative, forward)
        let tangent: Float = tan(25 * Float.pi / 180)
        let x: Float = simd_dot(relative, side) / depth / tangent / (16.0 / 9.0)
        let y: Float = simd_dot(relative, up) / depth / tangent
        return SIMD2(960 + x * 960, 540 - y * 540)
    }

    /// The largest distance of a point from the first.
    static func spread(_ points: [SIMD3<Float>]) -> Float {
        points.map { simd_distance($0, points[0]) }.max() ?? 0
    }
}
