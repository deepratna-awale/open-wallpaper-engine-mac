import Foundation
import OWEModelImport
import OWESceneEditing
import XCTest

/// Capture 549: the clip WE's Add Clip made on "Scene" (`FBXImport549`), and how its record's
/// flags compile.
final class FBXImport549ClipTests: XCTestCase {
    /// Add Clip's `motionflags` 43008 (position x and z, yaw) with no root-motion bone compiles to
    /// the clip record and Match loop alone, 0x401; capture 546's on "root" keeps them, 0xAC01.
    func testRootMotionFlagsNeedARootMotionBone() throws {
        let config = try FBXImport549.config("siblings.json")
        XCTAssertEqual(config.clips.first?.motionFlags, ModelImportConfig.Clip.defaultMotionFlags)
        XCTAssertEqual(config.clips.first?.rootMotion, "")
        let (ours, theirs, _) = try FBXImport549.compiled("siblings", config: config)
        XCTAssertEqual(theirs.animations.map(\.flags), [0, 0x401])
        XCTAssertEqual(ours.animations.map(\.flags), theirs.animations.map(\.flags))
        XCTAssertEqual(ours.animations.map(\.id), theirs.animations.map(\.id))
        XCTAssertEqual(ours.animations.map(\.frames), theirs.animations.map(\.frames))
        XCTAssertEqual(ours.animations.map(\.mode), theirs.animations.map(\.mode))
        XCTAssertEqual(ours.animations.map { $0.reference.map { [Int($0.source), Int($0.start), Int($0.end), Int($0.offset), Int($0.rootBone)] } },
                       theirs.animations.map { $0.reference.map { [Int($0.source), Int($0.start), Int($0.end), Int($0.offset), Int($0.rootBone)] } })

        // A root-motion bone the skeleton lacks keeps none either.
        var missing = config
        missing.clips[0].rootMotion = "nobone"
        XCTAssertEqual(try MDLTestReader.read(try FBXImport549.compiled("siblings", config: missing).output.mdl).animations.last?.flags, 0x401)
        // With "root", the flags stay; a one-frame clip has no Match loop.
        var rooted = config
        rooted.clips[0].rootMotion = "root"
        XCTAssertEqual(try MDLTestReader.read(try FBXImport549.compiled("siblings", config: rooted).output.mdl).animations.last?.flags, 0xAC01)
        rooted.clips[0].end = 0
        XCTAssertEqual(try MDLTestReader.read(try FBXImport549.compiled("siblings", config: rooted).output.mdl).animations.last?.flags, 0xA801)
    }
}
