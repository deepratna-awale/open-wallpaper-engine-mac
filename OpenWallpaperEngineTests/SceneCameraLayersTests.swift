import XCTest
import simd
@testable import OpenWallpaperEngine

/// WE's camera layers (docs/models-plan.md §2.3; the layer update 0x1401f2ad0, the camera update
/// 0x140189220…0x140189402): the active layer, its view from its world matrix and parents, path
/// playback with both queue modes, the write-back, and where the fov comes from.
final class SceneCameraLayersTests: XCTestCase {
    private static func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 1e-4, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_length(a - b), accuracy, "\(a) vs \(b) \(message)", file: file, line: line)
    }

    /// A constant channel: one keyframe per component.
    private static func vector(_ value: SIMD3<Float>) -> String {
        #"{"c0": [{"frame": 0, "value": \#(value.x)}], "c1": [{"frame": 0, "value": \#(value.y)}], "c2": [{"frame": 0, "value": \#(value.z)}]}"#
    }

    /// A path of `frames` frames at 10 fps, played once.
    private static func path(eye: SIMD3<Float>? = nil, center: SIMD3<Float>? = nil, fov: Float? = nil, frames: Int = 5,
                             visible: Bool = true) -> String {
        var fields = [#""options": {"fps": 10, "length": \#(frames), "mode": "single", "wraploop": false}"#,
                      #""visible": \#(visible)"#]
        if let eye { fields.append(#""eye": \#(vector(eye))"#) }
        if let center { fields.append(#""center": \#(vector(center))"#) }
        if let fov { fields.append(#""fov": [{"frame": 0, "value": \#(fov)}]"#) }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    private static func layer(_ id: String, order: Int, paths: [String] = [], queue: WESceneCameraLayer.QueueMode = .sequential,
                              fov: Double = 40) throws -> SceneCameraLayerObject {
        let file = try WECameraLayerPathFile(data: Data(#"{"paths": [\#(paths.joined(separator: ", "))]}"#.utf8))
        XCTAssertEqual(file.paths.count, paths.count)
        return SceneCameraLayerObject(id: id, name: id, order: order,
                                      authored: WESceneCameraLayer(camera: "default", path: "p.json", queueMode: queue,
                                                                   values: [.fov: .number(fov)]),
                                      pathFile: file)
    }

    /// The objects' authored transforms and parents (M3's hierarchy).
    private static func transforms(_ nodes: [String: (local: SceneLocalTransform3D, parent: String?)] = [:]) -> SceneTransformHierarchy3D {
        SceneTransformHierarchy3D(nodes: nodes.mapValues { SceneTransformHierarchy3D.Node(parentID: $0.parent, local: $0.local) })
    }

    private static func local(origin: SIMD3<Float> = .zero, angles: SIMD3<Float> = .zero) -> SceneLocalTransform3D {
        SceneLocalTransform3D(origin: origin, scale: SIMD3(repeating: 1), angles: angles)
    }

    private static func input(visible: Set<String>? = nil, live: [String: SceneLocalTransform3D] = [:],
                              fov: [String: Float] = [:]) -> SceneCameraLayers.FrameInput {
        SceneCameraLayers.FrameInput(deltaTime: 0.1, isVisible: { visible?.contains($0) ?? true },
                                     live: { live[$0] }, fov: { fov[$0] })
    }

    // MARK: - The active layer and its view

    /// The last visible layer in scene order is the camera; it looks down its local −z with +y up,
    /// from its origin, with its own fov while no path plays.
    func testTheLastVisibleLayerIsTheCamera() throws {
        let tilted = Self.local(origin: SIMD3(0, 4, 5), angles: SIMD3(-0.38397, 0, 0))
        let layers = SceneCameraLayers([try Self.layer("a", order: 0, fov: 30), try Self.layer("b", order: 1, fov: 58.09)],
                                       transforms: Self.transforms(["b": (tilted, nil)]), values: SpatialProperties())
        let both = try XCTUnwrap(layers.update(Self.input()))
        XCTAssertEqual(both.id, "b")
        XCTAssertEqual(both.fov, 58.09, accuracy: 1e-5)
        Self.assertClose(both.pose.eye, SIMD3(0, 4, 5))
        // Rx(−0.384): row 2 = (0, sin x·…, cos x) — forward is −row 2, tipped down.
        let x: Float = -0.38397
        Self.assertClose(simd_normalize(both.pose.center - both.pose.eye), SIMD3(0, sin(x), -cos(x)))
        XCTAssertLessThan(both.pose.center.y, both.pose.eye.y, "the camera looks down")
        XCTAssertEqual(try XCTUnwrap(layers.update(Self.input(visible: ["a"]))).id, "a")
        XCTAssertNil(layers.update(Self.input(visible: [])))
        // A script's `fov` on the layer.
        XCTAssertEqual(try XCTUnwrap(layers.update(Self.input(fov: ["b": 70]))).fov, 70)
        // A script's transform on the layer wins.
        let moved = try XCTUnwrap(layers.update(Self.input(live: ["b": Self.local(origin: SIMD3(1, 1, 1))])))
        Self.assertClose(moved.pose.eye, SIMD3(1, 1, 1))
    }

    /// A parented layer's view is its world matrix: the parent's transform applies.
    func testAParentMovesTheCamera() throws {
        let parent = Self.local(origin: SIMD3(10, 0, 0), angles: SIMD3(0, .pi / 2, 0))
        let hierarchy = Self.transforms(["p": (parent, nil), "cam": (Self.local(origin: SIMD3(0, 0, 2)), "p")])
        let layers = SceneCameraLayers([try Self.layer("cam", order: 0)], transforms: hierarchy, values: SpatialProperties())
        let camera = try XCTUnwrap(layers.update(Self.input()))
        let world = parent.matrix * Self.local(origin: SIMD3(0, 0, 2)).matrix
        Self.assertClose(camera.pose.eye, SIMD3(world[3].x, world[3].y, world[3].z))
        // Ry(π/2): row 2 = (cos x·sin y, …, cos x·cos y) = (1, 0, 0), so the camera looks down −x.
        Self.assertClose(simd_normalize(camera.pose.center - camera.pose.eye), SIMD3(-1, 0, 0))
        Self.assertClose(camera.pose.eye, SIMD3(12, 0, 0))
    }

    // MARK: - Paths

    /// "sequential": each finished path hands over to the next visible one, wrapping. A path's
    /// channels drive the camera and are written back into the layer; a component without keys
    /// follows the layer's transform as it stands, which is the last write-back.
    func testSequentialPathsPlayInTurnAndWriteBack() throws {
        let layers = SceneCameraLayers([try Self.layer("cam", order: 0, paths: [
            Self.path(eye: SIMD3(1, 2, 3), center: SIMD3(1, 2, 0), fov: 30),
            Self.path(visible: false),
            Self.path(eye: SIMD3(4, 5, 6)),
        ])], transforms: Self.transforms(), values: SpatialProperties())
        var played: [Int] = []
        var cameras: [SceneCameraLayers.Camera] = []
        for _ in 0..<13 {
            cameras.append(try XCTUnwrap(layers.update(Self.input())))
            played.append(try XCTUnwrap(layers.playingPath("cam")))
        }
        // Five frames of 0.1 s fill each 0.5 s path; the hidden one never plays.
        XCTAssertEqual(played, [0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 0, 0, 0])
        let first = cameras[0]
        Self.assertClose(first.pose.eye, SIMD3(1, 2, 3))
        Self.assertClose(simd_normalize(first.pose.center - first.pose.eye), SIMD3(0, 0, -1))
        XCTAssertEqual(first.fov, 30, "the path's fov")
        let written = try XCTUnwrap(layers.writtenBack("cam"))
        Self.assertClose(written.origin, SIMD3(1, 2, 3))
        // Path 2 has an eye and no centre: the centre is 5 ahead of the layer as path 0 left it.
        let second = cameras[5]
        Self.assertClose(second.pose.eye, SIMD3(4, 5, 6))
        Self.assertClose(simd_normalize(second.pose.center - second.pose.eye), simd_normalize(SIMD3(1, 2, -2) - SIMD3(4, 5, 6)))
        XCTAssertEqual(second.fov, 50, "a path without a fov channel keeps WE's 50, not the layer's")
    }

    /// "random": a shuffle bag of the visible paths, refilled when empty, never drawing the path it
    /// drew last.
    func testRandomPathsDrawFromAShuffleBag() throws {
        let paths = (0..<3).map { Self.path(eye: SIMD3(Float($0), 0, 1), frames: 1) }
        let layers = SceneCameraLayers([try Self.layer("cam", order: 0, paths: paths, queue: .random)],
                                       transforms: Self.transforms(), values: SpatialProperties())
        var played: [Int] = []
        for _ in 0..<30 {
            let camera = try XCTUnwrap(layers.update(Self.input()))
            played.append(try XCTUnwrap(layers.playingPath("cam")))
            XCTAssertEqual(camera.pose.eye.x, Float(played.last!))
        }
        for start in stride(from: 0, to: 30, by: 3) {
            XCTAssertEqual(Set(played[start..<start + 3]), [0, 1, 2], "each bag holds every path once: \(played)")
        }
        for index in 1..<played.count { XCTAssertNotEqual(played[index], played[index - 1], "\(played)") }
    }

    /// A hidden layer doesn't play: its path's time stands until it shows again.
    func testAHiddenLayerDoesntPlay() throws {
        let layers = SceneCameraLayers([try Self.layer("cam", order: 0, paths: [Self.path(eye: SIMD3(0, 0, 1)),
                                                                                  Self.path(eye: SIMD3(9, 0, 1))])],
                                       transforms: Self.transforms(), values: SpatialProperties())
        for _ in 0..<3 { _ = layers.update(Self.input()) }
        for _ in 0..<10 { XCTAssertNil(layers.update(Self.input(visible: []))) }
        XCTAssertEqual(layers.playingPath("cam"), 0)
        for _ in 0..<2 { _ = layers.update(Self.input()) }
        XCTAssertEqual(layers.playingPath("cam"), 0, "five frames in, still the first path")
        _ = layers.update(Self.input())
        XCTAssertEqual(layers.playingPath("cam"), 1)
    }
}
