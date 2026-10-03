// swift-tools-version:5.9
// Modules kept out of the app target:
// - OWEInspectorKit: controls the Scene Inspector and other panels share.
import PackageDescription

let package = Package(
    name: "OWEEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OWEInspectorKit", targets: ["OWEInspectorKit"]),
    ],
    targets: [
        .target(name: "OWEInspectorKit"),
        .testTarget(name: "OWEInspectorKitTests", dependencies: ["OWEInspectorKit"]),
    ]
)
