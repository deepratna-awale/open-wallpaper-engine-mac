// swift-tools-version:5.9
// The Wallpaper Editor (editor-plan notes), kept out of the app target:
// - OWESceneEditing: the edit model, no UI: Foundation, and JavaScriptCore for property conditions (the overlay over scene.json, the layer
//   outline, gizmo and canvas math, undo, Save as New Wallpaper). The app's scene loader applies
//   the overlay through it, so the editor and the renderer can't disagree about an edit.
// - OWEInspectorKit: controls Scene Edit / Export and the editor share.
// - OWEEditor: the editor window's views; the app hands it the live canvas and its services.
// - OWEModelImport: FBX and OBJ files read with ufbx (Vendor/ufbx) into OWESceneEditing's
//   `ModelSource`, which `ModelCompiler` writes as WE's `.mdl`.
import PackageDescription

let package = Package(
    name: "OWEEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OWESceneEditing", targets: ["OWESceneEditing"]),
        .library(name: "OWEInspectorKit", targets: ["OWEInspectorKit"]),
        .library(name: "OWEEditor", targets: ["OWEEditor"]),
        .library(name: "OWEModelImport", targets: ["OWEModelImport"]),
    ],
    dependencies: [
        .package(path: "../../Vendor/ufbx"),
    ],
    targets: [
        .target(name: "OWESceneEditing"),
        .target(name: "OWEInspectorKit"),
        .target(name: "OWEModelImport", dependencies: ["OWESceneEditing", .product(name: "CUfbx", package: "ufbx")]),
        .target(name: "OWEEditor",
                dependencies: ["OWESceneEditing", "OWEInspectorKit", "OWEModelImport"],
                // The particle editor's catalog and its copy of WE's editor schema
                // (docs/we-particle-editor-schema.json); the effect previews' test card.
                resources: [.process("Resources"), .process("Particles/Resources"), .process("Previews/Resources")]),
        .testTarget(name: "OWESceneEditingTests", dependencies: ["OWESceneEditing"]),
        .testTarget(name: "OWEInspectorKitTests", dependencies: ["OWEInspectorKit"]),
        .testTarget(name: "OWEEditorTests", dependencies: ["OWEEditor"]),
        .testTarget(name: "OWEModelImportTests", dependencies: ["OWEModelImport", "OWESceneEditing"],
                    resources: [.copy("Fixtures")]),
    ]
)
