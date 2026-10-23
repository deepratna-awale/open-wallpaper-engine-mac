import XCTest
import simd
@testable import OpenWallpaperEngine

/// WE 2.8.0.42's capture 551 (`Tests/Fixtures/Models/PuppetGroundTruth551`; we-test-wp-images,
/// tools/peer/requests/owe-beta8/models-open/551-mdle-reference-pose; docs/models-plan.md §1.5):
/// 509's bars with clip 23 (blue 0 → 180 → 0° over 2 s, red only rest keys), and the same rig with
/// Puppet Warp › Reference Pose (red, the root, turned 30° about z). WE draws the reference pose
/// only without an animation layer; with one, even held at frame 0 (rate 0), the frame is the one
/// the rig without a reference pose draws.
///
/// The editor bakes the reference pose into the rig: red's `MDLS` matrix is turned, the mesh is
/// skinned into it (`a_Position`), and `MDLE` keeps the locals from before (the clip's keys are
/// those). So the bind pose drawn as it is shows the reference pose, and a clip's keys pose the
/// rig as the one without it: `MDLE` itself changes no drawing.
final class PuppetGroundTruth551Tests: XCTestCase {
    private static func model(_ name: String) throws -> MDLModel {
        try MDLReader.read(try Fixtures.data("Models/PuppetGroundTruth551/\(name).mdl"))
    }

    private static func animator(_ model: MDLModel, layers json: String) throws -> ScenePuppetAnimator {
        let skeleton = try XCTUnwrap(model.skeleton)
        let clips = model.animations ?? []
        let layers = try JSONDecoder().decode([WEAnimationLayer].self, from: Data(json.utf8))
        return ScenePuppetAnimator(skeleton: skeleton, clips: clips, layers: layers,
                                   drawOrder: ScenePuppetDrawOrder(mesh: model.meshes[0], skeleton: skeleton, clips: clips))
    }

    /// The mesh's positions skinned by `pose` (`g_Bones` blended by the vertex weights), x and y.
    private static func skinned(_ mesh: MDLMesh, _ pose: ScenePuppetPose) throws -> [SIMD2<Float>] {
        let positions = try XCTUnwrap(mesh.floatValues(.position))
        let indices = try XCTUnwrap(mesh.unsignedValues(.blendIndices))
        let weights = try XCTUnwrap(mesh.floatValues(.blendWeights))
        return (0..<mesh.vertexCount).map { vertex in
            let point = SIMD4<Float>(positions[3 * vertex], positions[3 * vertex + 1], positions[3 * vertex + 2], 1)
            var out = SIMD4<Float>(repeating: 0)
            for slot in 0..<4 where weights[4 * vertex + slot] > 0 {
                out += weights[4 * vertex + slot] * (pose.bones[Int(indices[4 * vertex + slot])] * point)
            }
            return SIMD2(out.x, out.y)
        }
    }

    private static func farthest(_ a: [SIMD2<Float>], _ b: [SIMD2<Float>]) -> Float {
        zip(a, b).map { simd_distance($0, $1) }.max() ?? .infinity
    }

    /// The files: red's bind matrix is the 30° turn (z scale 0.998, as the JSON's
    /// `referencepose`), `MDLE` holds red's local from before, blue's is unchanged.
    func testTheReferencePoseIsBakedIntoTheBindPose() throws {
        let reference = try Self.model("ref_clip"), plain = try Self.model("noref_clip")
        XCTAssertEqual(reference.sections.map(\.tag), ["MDLS0004", "MDLA0006", "MDLE0002"])
        XCTAssertEqual(plain.sections.map(\.tag), ["MDLS0004", "MDLA0006"])
        let red = try XCTUnwrap(reference.skeleton?.bones.first?.matrix)
        XCTAssertEqual(red.columns.0.x, 0.8645602, accuracy: 1e-5)
        XCTAssertEqual(red.columns.0.y, 0.49915406, accuracy: 1e-5)
        XCTAssertEqual(red.columns.2.z, 0.9983081, accuracy: 1e-5)
        let before = try XCTUnwrap(reference.referencePose)
        let plainBones = try XCTUnwrap(plain.skeleton?.bones)
        for (index, matrix) in before.enumerated() {
            for column in 0..<4 {
                XCTAssertEqual(simd_distance(matrix[column], plainBones[index].matrix[column]), 0, accuracy: 1e-4,
                               "MDLE is the plain rig's bind local of \(plainBones[index].name)")
            }
        }
    }

    /// "none": no animation layer draws the reference pose, red turned 30° about its origin and
    /// blue carried with it (WE: red's slope −0.49 in the still, y down).
    func testWithoutALayerTheReferencePoseDraws() throws {
        let reference = try Self.model("ref_clip"), plain = try Self.model("noref_clip")
        let animator = try Self.animator(reference, layers: "[]")
        animator.advance(delta: 2, values: EmptySceneValues())
        let drawn = try Self.skinned(reference.meshes[0], animator.pose)
        let origin = SIMD2<Float>(-126.16821, 0)
        let turn = simd_float2x2(SIMD2(0.8645602, 0.49915406), SIMD2(-0.49915406, 0.8645602))
        let flat = try Self.skinned(plain.meshes[0], .bind(boneCount: 2)).map { origin + turn * ($0 - origin) }
        XCTAssertEqual(drawn.count, flat.count)
        XCTAssertLessThan(Self.farthest(drawn, flat), 0.5, "the plain rig turned 30° about red's origin")
        let plainAnimator = try Self.animator(plain, layers: "[]")
        plainAnimator.advance(delta: 2, values: EmptySceneValues())
        XCTAssertLessThan(Self.farthest(try Self.skinned(plain.meshes[0], plainAnimator.pose),
                                        try Self.skinned(plain.meshes[0], .bind(boneCount: 2))), 1e-3, "the plain rig lies flat")
    }

    /// "f0" (rate 0) and "play" (rate 1 at 0.05, 0.5 and 1 s): with a layer the frame is the plain
    /// rig's, pixel for pixel in WE's stills.
    func testWithALayerTheFrameIsThePlainRigs() throws {
        let reference = try Self.model("ref_clip"), plain = try Self.model("noref_clip")
        for (layers, times) in [(#"[{"animation": 23, "rate": 0}]"#, [Float(2)]),
                                (#"[{"animation": 23, "rate": 1}]"#, [Float(0.05), 0.5, 1])] {
            let turned = try Self.animator(reference, layers: layers), flat = try Self.animator(plain, layers: layers)
            var elapsed: Float = 0
            for time in times {
                turned.advance(delta: time - elapsed, values: EmptySceneValues())
                flat.advance(delta: time - elapsed, values: EmptySceneValues())
                elapsed = time
                let drawn = try Self.skinned(reference.meshes[0], turned.pose)
                let expected = try Self.skinned(plain.meshes[0], flat.pose)
                XCTAssertLessThan(Self.farthest(drawn, expected), 0.5, "\(layers) at \(time) s")
            }
        }
    }
}
