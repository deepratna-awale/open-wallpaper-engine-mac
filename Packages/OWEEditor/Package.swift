// swift-tools-version:5.9
// The Wallpaper Editor (docs/editor-plan.md), kept out of the app target:
// - OWESceneEditing: the edit model, Foundation only (the overlay over scene.json, the layer
//   outline, gizmo and canvas math, undo, Save as Local Wallpaper). The app's scene loader applies
//   the overlay through it, so the editor and the renderer can't disagree about an edit.
// - OWEInspectorKit: controls the Scene Inspector and the editor share.
import PackageDescription

let package = Package(
    name: "OWEEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OWESceneEditing", targets: ["OWESceneEditing"]),
        .library(name: "OWEInspectorKit", targets: ["OWEInspectorKit"]),
    ],
    targets: [
        .target(name: "OWESceneEditing"),
        .target(name: "OWEInspectorKit"),
        .testTarget(name: "OWESceneEditingTests", dependencies: ["OWESceneEditing"]),
        .testTarget(name: "OWEInspectorKitTests", dependencies: ["OWEInspectorKit"]),
    ]
)
