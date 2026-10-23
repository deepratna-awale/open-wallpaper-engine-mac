import Foundation
import OWEModelImport
import OWESceneEditing
import XCTest

/// WE 2.8.0.42's own FBX import (capture 549, `Fixtures/FBXImport549`), from its editor's Edit ›
/// Import Model:
/// - `siblings.fbx` (`make_siblings_fbx.py`, Blender: an armature "Rig" › root with two chains,
///   armL1 › armL2 and armR1 › armR2, a bar skinned to the four chain bones, one take exported as
///   "Scene"), then Add Clip on Scene and, in the Events tab with the animation Scene selected,
///   Add Event "flapmid" at frame 15. `siblings.json` and `siblings.mdl` are what WE wrote.
/// - `centered_cube.fbx`, a static mesh: `centered_cube.json` and `centered_cube.mdl`.
enum FBXImport549 {
    static func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/FBXImport549"))
    }

    static func config(_ name: String) throws -> ModelImportConfig {
        try ModelImportConfig(json: Data(contentsOf: try fixture(name)))
    }

    /// `model`.fbx compiled with `config`, read back, beside WE's `model`.mdl.
    static func compiled(_ model: String, config: ModelImportConfig) throws -> (ours: MDLTestModel, theirs: MDLTestModel, output: ModelCompiler.Output) {
        let source = try ModelFileLoader.load(contentsOf: try fixture("\(model).fbx"))
        let output = try ModelCompiler.compile(source, config: config, folder: model)
        return (try MDLTestReader.read(output.mdl), try MDLTestReader.read(try Data(contentsOf: try fixture("\(model).mdl"))), output)
    }
}
