import Foundation
import OWEModelImport
import OWESceneEditing
import XCTest

/// Capture 549 (b): a static mesh, `centered_cube.fbx` (`FBXImport549`).
final class FBXImport549StaticTests: XCTestCase {
    /// WE's `.mdl` is the meshes alone: no `MDLS`, `MDLA` or `MDLE`.
    func testAStaticMeshCompilesWithoutSkeletonOrAnimations() throws {
        let (ours, theirs, output) = try FBXImport549.compiled("centered_cube", config: ModelImportConfig())
        XCTAssertEqual(theirs.sections, [])
        XCTAssertEqual(ours.sections, theirs.sections)
        XCTAssertEqual(ours.tag, theirs.tag)
        XCTAssertEqual(ours.legacyFormat, theirs.legacyFormat)
        XCTAssertEqual(ours.meshes.count, theirs.meshes.count)
        for (index, (a, b)) in zip(ours.meshes, theirs.meshes).enumerated() {
            XCTAssertEqual(a.materials.count, b.materials.count, "mesh \(index)")
            XCTAssertEqual(a.format, b.format, "mesh \(index)")
            XCTAssertEqual(a.indices, b.indices, "mesh \(index)")
            XCTAssertEqual(a.vertices.count, b.vertices.count, "mesh \(index)")
            guard a.vertices.count == b.vertices.count else { continue }
            let difference = WEDefaultProjectModelTests.largestDifference(a.vertices, b.vertices, stride: WEDefaultProjectModelTests.stride(a.format), format: a.format)
            XCTAssertLessThan(difference.value, 1e-4, "mesh \(index): \(difference.attribute)")
        }
        XCTAssertEqual(output.mdl.count, try Data(contentsOf: try FBXImport549.fixture("centered_cube.mdl")).count)
        XCTAssertEqual(output.bones, [])
        XCTAssertEqual(output.animations, [])
    }

    /// WE's `centered_cube.json`: `{"editor": {"animationmapping": null}, "normals": true,
    /// "tangentspace": true}`; no `skinning`.
    func testAStaticFBXsConfigurationIsWEs() throws {
        let url = try FBXImport549.fixture("centered_cube.fbx")
        let output = try ModelCompiler.compile(try ModelFileLoader.load(contentsOf: url), config: ModelImportConfig(), folder: "centered_cube")
        let saved = ModelImportConfig().completed(with: output, mapsAnimations: ModelFileLoader.mapsAnimations(url))
        let theirs = try Data(contentsOf: try FBXImport549.fixture("centered_cube.json"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: try saved.jsonData()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: theirs) as? NSDictionary)
        // WE's file is written again as it is.
        XCTAssertEqual(try JSONSerialization.jsonObject(with: try ModelImportConfig(json: theirs).jsonData()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: theirs) as? NSDictionary)
        // An OBJ gets no `editor` (capture 546's recompiled bars.json and flow.json).
        XCTAssertFalse(ModelFileLoader.mapsAnimations(URL(fileURLWithPath: "/a/bars.obj")))
        let obj = ModelImportConfig().completed(with: output, mapsAnimations: false)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: try obj.jsonData()) as? NSDictionary,
                       ["normals": true, "tangentspace": true] as NSDictionary)
    }
}
