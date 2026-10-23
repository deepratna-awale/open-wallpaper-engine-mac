import Foundation
import OWEModelImport
import OWESceneEditing
import XCTest

/// Capture 549 (a): sibling bone chains (`FBXImport549`).
final class FBXImport549BoneOrderTests: XCTestCase {
    /// WE orders the bones breadth-first, each node's children last to first in the file's order:
    /// both children of root before their children, armR1 before armL1 (the file connects armL1
    /// first).
    func testSiblingChainsKeepWEsBoneOrder() throws {
        let (ours, theirs, _) = try FBXImport549.compiled("siblings", config: try FBXImport549.config("siblings.json"))
        XCTAssertEqual(theirs.bones.map(\.name), ["RootNode", "Rig", "root", "armR1", "armL1", "armR2", "armL2"])
        XCTAssertEqual(ours.bones.map(\.name), theirs.bones.map(\.name))
        XCTAssertEqual(ours.bones.map(\.parent), theirs.bones.map(\.parent))
        XCTAssertEqual(ours.bones.map(\.flags), theirs.bones.map(\.flags))
        for (a, b) in zip(ours.bones, theirs.bones) {
            for (x, y) in zip(a.matrix, b.matrix) { XCTAssertEqual(x, y, accuracy: 1e-4, a.name) }
        }
        XCTAssertEqual(ours.boneBoxes.count, theirs.boneBoxes.count)
        for (a, b) in zip(ours.boneBoxes, theirs.boneBoxes) {
            for (x, y) in zip(a.half + a.matrix, b.half + b.matrix) { XCTAssertEqual(x, y, accuracy: 1e-4) }
        }
        XCTAssertEqual(ours.sections, theirs.sections)
        // The skinned bar: its influences name the bones by their new indices.
        XCTAssertEqual(ours.meshes.count, theirs.meshes.count)
        for (index, (a, b)) in zip(ours.meshes, theirs.meshes).enumerated() {
            XCTAssertEqual(a.format, b.format, "mesh \(index)")
            XCTAssertEqual(a.indices, b.indices, "mesh \(index)")
            let difference = WEDefaultProjectModelTests.largestDifference(a.vertices, b.vertices, stride: 80, format: a.format)
            XCTAssertLessThan(difference.value, 1e-4, "mesh \(index): \(difference.attribute)")
        }
        // Every track in the bones' order. Each frame's nine values are the translation, the Euler
        // angles and the scale; WE's angles for armR1 and armL1 past frame 0 are the same turn
        // written 2π lower (−4.712 for our 1.571), so angles compare modulo 2π.
        XCTAssertEqual(ours.animations.map(\.name), theirs.animations.map(\.name))
        for (a, b) in zip(ours.animations, theirs.animations) {
            XCTAssertEqual(a.tracks.count, b.tracks.count, a.name)
            for (bone, (x, y)) in zip(a.tracks, b.tracks).enumerated() {
                for (index, (p, q)) in zip(x, y).enumerated() {
                    let isAngle = (3..<6).contains(index % 9)
                    let difference = isAngle ? abs(remainder(p - q, 2 * Float.pi)) : abs(p - q)
                    XCTAssertLessThan(difference, 1e-3, "\(a.name) bone \(bone) frame \(index / 9) value \(index % 9): \(p) vs \(q)")
                }
            }
        }
    }
}
