import XCTest
import simd
@testable import OpenWallpaperEngine

/// docs/models-plan.md §5.10, 5.11 and 5.31 against WE 2.8.42's captures of running wallpapers
/// (we-test-wp-images, tools/peer/requests/owe-beta3/models-open: 510, 511 and 531b, a README,
/// the stills and the projects each). The projects are in `Tests/Fixtures/Models/OpenPoints`
/// without their binaries, which come from the repository's fixtures: the box from WE's import of
/// `rootmotion_box` (models_gt/mg4), the rope from bone-physics A (`Models/BonePhysics/rope-A.mdl`)
/// with the texture-channels capture's `rope.tex`. Each is drawn headlessly at 1920×1080 by the
/// real loader and renderer (`ModelSceneHarness`); WE's shaders come from `OWE_ASSETS`, so the
/// tests skip without them. With `OWE_WE_REFERENCE` the stills are measured the same way.
final class ModelsOpenPointsRenderCaptureTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        _ = try Fixtures.assets()
        scratch = FileManager.default.temporaryDirectory.appending(path: "owe-models-open-\(UUID().uuidString)",
                                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch, FileManager.default.fileExists(atPath: scratch.path) {
            try FileManager.default.removeItem(at: scratch)
        }
    }

    // MARK: - 5.10 Text objects' `depthtest`

    /// A perspective scene: the box, and "DEPTH TEST" behind it, turned 45°. With the text's
    /// `depthtest` "enabled" the box hides the text behind it; "disabled" draws the text over it.
    /// Text over the box shows as bright pixels with the box's dark faces on both sides in the row.
    func testATextObjectsDepthTestLetTheBoxHideIt() throws {
        let enabled = try frame("510-text-depth-enabled", binaries: Self.box)
        let disabled = try frame("510-text-depth-disabled", binaries: Self.box)
        XCTAssertGreaterThan(Self.drawnPixels(enabled), 1000, "the box and the text draw")
        let hidden = Self.textOverBox(enabled), shown = Self.textOverBox(disabled)
        XCTAssertLessThan(hidden, 20, "enabled: the box occludes the text")
        XCTAssertGreaterThan(shown, 200, "disabled: the text is drawn over the box")

        guard let folder = ModelsOpenPointsCaptureTests.capture("510-text-depthtest") else { return }
        let weEnabled = try WEReferenceImage.load(folder.appending(path: "mo2_510_text_depth_enabled.png"))
        let weDisabled = try WEReferenceImage.load(folder.appending(path: "mo2_510_text_depth_disabled.png"))
        XCTAssertLessThan(Self.textOverBox(Image(weEnabled)), 20, "WE: occluded")
        XCTAssertGreaterThan(Self.textOverBox(Image(weDisabled)), 200, "WE: drawn over")
    }

    // MARK: - 5.11 Missing vertex attributes

    /// The box through a custom shader reading `a_Color` and `a_TexCoordC1`, which the mesh lacks:
    /// WE draws nothing of it (only the clear colour) and logs nothing. The app skips the draw too.
    /// The control (not captured in WE) reads only `a_Position` and draws: it declares `a_Color`
    /// without reading it, and only the inputs the compiled stage reads count, as in D3D11's
    /// `CreateInputLayout` against the compiled shader's input signature.
    func testAMeshLackingAShaderInputIsNotDrawn() throws {
        let missing = try frame("511-missing-attribute", binaries: Self.box)
        XCTAssertEqual(Self.drawnPixels(missing), 0, "only the clear colour")

        let control = try project("511-missing-attribute", binaries: Self.box, as: "511-control")
        try """
        attribute vec3 a_Position;
        attribute vec4 a_Color;
        uniform mat4 g_ModelViewProjectionMatrix;
        void main() {
        	gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        }
        """.write(to: control.appending(path: "shaders/probe_missing.vert"), atomically: true, encoding: .utf8)
        try """
        void main() {
        	gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
        }
        """.write(to: control.appending(path: "shaders/probe_missing.frag"), atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(Self.drawnPixels(try render(control)), 1000, "the control draws the box")

        guard let folder = ModelsOpenPointsCaptureTests.capture("511-missing-attribute") else { return }
        let still = try WEReferenceImage.load(folder.appending(path: "mo2_511_missing_attr.png"))
        XCTAssertEqual(Self.drawnPixels(Image(still)), 0, "WE: only the clear colour")
    }

    // MARK: - 5.31 A script's `origin` on a puppet image

    /// The rope puppet whose `origin` script sets `x = 760 + min(t, 4) · 100` moves in a running
    /// wallpaper: its unswung top (row 300) is centred on the script's x, 860 at 1 s, 1060 at 3 s,
    /// 1160 at 5.5 s (the app's 856.5, 1056.5 and 1160, the bar a few px left of the origin). WE's stills are centred on 855.5, 1055.5 and 1159.5 (the bar's x 824–887,
    /// 1024–1087 and 1128–1191), the script's x within the capture's timing (a few px, under 0.05 s,
    /// before the 4 s hold; exact after it).
    func testAScriptsOriginMovesAPuppetImage() throws {
        let directory = try project("531b-puppet-origin-script", binaries: [
            "Models/BonePhysics/rope-A.mdl": "models/rope_puppet.mdl",
            "Models/TextureChannels/materials/rope.tex": "materials/rope.tex",
        ])
        let harness = try ModelSceneHarness(directory: directory, settings: SceneRenderSettings(), size: SIMD2(1920, 1080),
                                            storage: scratch.appending(path: "storage", directoryHint: .isDirectory))
        defer { harness.close() }
        var time = 0.0
        for shot in [1.0, 3, 5.5] {
            while time + 1.0 / 60 < shot {
                harness.frame()
                time += 1.0 / 30
            }
            let bytes = try TextureUploadTests.read(try XCTUnwrap(harness.renderer.sharedFrame), device: harness.device)
            let centre = try XCTUnwrap(Self.rowCentre(Image(width: 1920, height: 1080, pixels: bytes), row: 300), "t \(shot)")
            XCTAssertEqual(centre, 760 + min(shot, 4) * 100, accuracy: 5, "t \(shot)")
        }
        XCTAssertEqual(harness.gpuErrors, [])

        guard let folder = ModelsOpenPointsCaptureTests.capture("531b-puppet-origin-script") else { return }
        for (shot, low, high) in [(1.0, 850.0, 862.0), (3, 1050, 1062), (5.5, 1157, 1163)] {
            let still = try WEReferenceImage.load(folder.appending(path: "mo2_531b_puppet_origin_script_t\(shot == 5.5 ? "5.5" : "\(Int(shot))").png"))
            let centre = try XCTUnwrap(Self.rowCentre(Image(still), row: 300), "WE t \(shot)")
            XCTAssertTrue((low...high).contains(centre), "WE t \(shot): \(centre)")
        }
    }

    // MARK: - Helpers

    private static let box = ["Models/OpenPoints/rootmotion_box.mdl": "models/rootmotion_box/rootmotion_box.mdl"]

    /// A frame's pixels, any channel order (the measures only compare channels' extremes).
    struct Image {
        let width: Int, height: Int, pixels: [UInt8]

        init(width: Int, height: Int, pixels: [UInt8]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }

        init(_ still: WEReferenceImage) {
            self.init(width: still.width, height: still.height, pixels: still.pixels)
        }

        /// The darkest and brightest channel at (x, y).
        func range(_ x: Int, _ y: Int) -> (low: Int, high: Int) {
            let index = (y * width + x) * 4
            let channels = pixels[index..<index + 3].map(Int.init)
            return (channels.min()!, channels.max()!)
        }
    }

    /// The Windows taskbar covers the stills' bottom 48 rows.
    private static let rows = 1080 - 48

    /// Pixels that differ from the top-left one (the clear colour) above the taskbar's rows.
    static func drawnPixels(_ image: Image) -> Int {
        let background = image.range(0, 0)
        var count = 0
        for y in 0..<min(rows, image.height) {
            for x in 0..<image.width {
                let pixel = image.range(x, y)
                if abs(pixel.low - background.low) + abs(pixel.high - background.high) > 24 { count += 1 }
            }
        }
        return count
    }

    /// Bright text pixels (every channel above 200) with a dark box pixel (every channel below
    /// 110) within 40 px both left and right in their row: the text drawn over the box.
    static func textOverBox(_ image: Image) -> Int {
        var count = 0
        for y in 0..<min(rows, image.height) {
            for x in 40..<(image.width - 40) where image.range(x, y).low > 200 {
                let dark = { (dx: Int) in image.range(x + dx, y).high < 110 }
                if (1...40).contains(where: { dark(-$0) }) && (1...40).contains(where: { dark($0) }) { count += 1 }
            }
        }
        return count
    }

    /// The centre of what differs from the background in one row; nil when nothing does.
    static func rowCentre(_ image: Image, row: Int) -> Double? {
        let background = image.range(0, row)
        let xs = (0..<image.width).filter {
            let pixel = image.range($0, row)
            return abs(pixel.low - background.low) + abs(pixel.high - background.high) > 120
        }
        guard let first = xs.first, let last = xs.last else { return nil }
        return Double(first + last) / 2
    }

    /// A writable copy of `name`'s fixture project with `binaries` (fixture path → project path).
    private func project(_ name: String, binaries: [String: String], as copy: String? = nil) throws -> URL {
        let directory = scratch.appending(path: copy ?? name, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: Fixtures.url("Models/OpenPoints/\(name)"), to: directory)
        for (source, destination) in binaries {
            let target = directory.appending(path: destination)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Fixtures.url(source), to: target)
        }
        return directory
    }

    private func frame(_ name: String, binaries: [String: String]) throws -> Image {
        try render(try project(name, binaries: binaries))
    }

    /// The settled frame of the wallpaper in `directory`.
    private func render(_ directory: URL) throws -> Image {
        let harness = try ModelSceneHarness(directory: directory, settings: SceneRenderSettings(), size: SIMD2(1920, 1080),
                                            storage: scratch.appending(path: "storage", directoryHint: .isDirectory))
        defer { harness.close() }
        try harness.settle(seconds: 10)
        let bytes = try TextureUploadTests.read(try XCTUnwrap(harness.renderer.sharedFrame), device: harness.device)
        XCTAssertEqual(harness.gpuErrors, [], directory.lastPathComponent)
        return Image(width: 1920, height: 1080, pixels: bytes)
    }
}
