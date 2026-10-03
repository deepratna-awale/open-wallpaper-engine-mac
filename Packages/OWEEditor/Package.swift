// swift-tools-version:5.9
// The Wallpaper Editor (docs/editor-plan.md), kept out of the app target:
// - OWESceneEditing: the edit model, Foundation only (the overlay over scene.json, the layer
//   outline, gizmo and canvas math, undo, Save as Local Wallpaper). The app's scene loader applies
//   the overlay through it, so the editor and the renderer can't disagree about an edit.
// - OWEInspectorKit: controls the Scene Inspector and the editor share.
// - OWEEditor: the editor window's views; the app hands it the live canvas and its services.
import PackageDescription

let package = Package(
    name: "OWEEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OWESceneEditing", targets: ["OWESceneEditing"]),
        .library(name: "OWEInspectorKit", targets: ["OWEInspectorKit"]),
        .library(name: "OWEEditor", targets: ["OWEEditor"]),
    ],
    targets: [
        .target(name: "OWESceneEditing"),
        .target(name: "OWEInspectorKit"),
        .target(name: "OWEEditor",
                dependencies: ["OWESceneEditing", "OWEInspectorKit"],
                // The particle editor's catalog and its copy of WE's editor schema
                // (docs/we-particle-editor-schema.json).
                resources: [.process("Resources"), .process("Particles/Resources")]),
        .testTarget(name: "OWESceneEditingTests", dependencies: ["OWESceneEditing"]),
        .testTarget(name: "OWEInspectorKitTests", dependencies: ["OWEInspectorKit"]),
        .testTarget(name: "OWEEditorTests", dependencies: ["OWEEditor"]),
    ]
)
