import Foundation
import XCTest
import simd
@testable import OpenWallpaperEngine

/// The WE effect gallery (tools/peer/effect_gallery on the captures' branch): one scene per built-in
/// effect, drawn by WE 2.8.0.42 at 1920×1080. Each scene is orthographic 1920×1080 with clear colour
/// 0.15 and two 1024² image layers at scale 0.85, a checkerboard centred at (480, 540) and an HSV
/// gradient at (1440, 540), each carrying only `{"file": "effects/<name>/effect.json"}`: no passes,
/// values or combos, so what draws is the effect at its shader-annotation defaults. The effect's
/// files are copied into the project as WE's editor copies them (WE doesn't read an effect's
/// materials from its assets folder). The two pictures are generated and live in
/// `Tests/Fixtures/WEEffectGallery`; the effects come from the WE assets.
enum WEEffectGallery {
    static let fixtures = Fixtures.url("WEEffectGallery")
    /// Rows at the bottom of WE's captures covered by the taskbar (summarize.py keeps 1030).
    static let comparedHeight = 1030
    /// The still is taken about 5 s after the wallpaper opened; the clip runs 3 s from there.
    static let stillTime = 5.0
    /// summarize.py samples the clip at 5 fps.
    static let motionStep = 0.2
    static let motionFrames = 16
    /// Screen pixels from the top-left. The cursor wasn't over the captured display (cursor
    /// ripple and x-ray show nothing in WE's captures), so it's off the screen here.
    static let cursor = SIMD2<Double>(-1920, -1080)

    struct Expectation: Decodable {
        /// The capture's name: the effect, `none`, a `user_…` project or an extra (EXTRAS.md).
        var effect: String
        /// The effect folder the scene uses, when the name isn't one.
        var uses: String?
        /// The capture relative to the gallery folder; `captures/<effect>.png` when absent.
        var capture: String?
        /// WE's mean absolute difference from the no-effect scene, 0…255 (metrics.tsv).
        var diff: Double
        /// WE's mean frame-to-frame change over the clip at 5 fps, 480×270 luma (metrics.tsv).
        var motion: Double
        /// Allowed |ours − WE's|; the defaults below when absent.
        var diffTolerance: Double?
        var motionTolerance: Double?
        /// A known gap: its test-risks id and cause. The check is expected to fail until fixed.
        var knownGap: String?

        var allowedDiff: Double { diffTolerance ?? max(2, diff * 0.25) }
        var allowedMotion: Double { motionTolerance ?? max(0.35, motion * 0.4) }
        /// The layers' scene.json effect `passes` (they map to effect.json's passes by position).
        var passes: [Any]?

        var effectFolder: String? { effect == "none" ? nil : (uses ?? effect) }
        var capturePath: String { capture ?? "captures/\(effect).png" }

        private enum CodingKeys: String, CodingKey {
            case effect, uses, capture, diff, motion, diffTolerance, motionTolerance, knownGap
        }
    }

    static func expectations() throws -> [Expectation] {
        let data = try Data(contentsOf: fixtures.appending(path: "expected.json"))
        var result = try JSONDecoder().decode([Expectation].self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for index in result.indices { result[index].passes = raw[index]["passes"] as? [Any] }
        return result
    }

    /// Writes project `fxgal_<effect>` (the control `fxgal_none` for nil) into `parent`, as the
    /// gallery's build_gallery.py does, with the effect's files from `assets/effects/<effect>`.
    static func makeProject(effect: String?, passes: [Any]? = nil, name: String? = nil, assets: URL,
                            in parent: URL) throws -> URL {
        let fm = FileManager.default
        let directory = parent.appending(path: "fxgal_\(name ?? effect ?? "none")", directoryHint: .isDirectory)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.createDirectory(at: directory.appending(path: "materials"), withIntermediateDirectories: true)
        try fm.createDirectory(at: directory.appending(path: "models"), withIntermediateDirectories: true)
        var objects: [[String: Any]] = []
        for (index, key) in ["checkerboard", "gradient"].enumerated() {
            let png = fixtures.appending(path: "\(key)_1024.png")
            try texData(png: png).write(to: directory.appending(path: "materials/\(key).tex"))
            let material: [String: Any] = ["passes": [["blending": "translucent", "cullmode": "nocull", "depthtest": "disabled",
                                                       "depthwrite": "disabled", "shader": "genericimage2", "textures": [key]]]]
            try json(material).write(to: directory.appending(path: "materials/\(key).json"))
            try json(["autosize": true, "material": "materials/\(key).json"]).write(to: directory.appending(path: "models/\(key).json"))
            objects.append(["id": 10 + index, "name": key, "image": "models/\(key).json",
                            "origin": "\(480 + 960 * index) 540 0", "angles": "0 0 0", "scale": "0.85 0.85 1",
                            "size": "1024 1024", "visible": true,
                            "effects": effect.map { effect -> [[String: Any]] in
                                var entry: [String: Any] = ["file": "effects/\(effect)/effect.json"]
                                if let passes { entry["passes"] = passes }
                                return [entry]
                            } ?? []])
        }
        if let effect { try copyEffect(effect, assets: assets, into: directory) }
        let scene: [String: Any] = [
            "camera": ["center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"],
            "general": ["clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                        "orthogonalprojection": ["width": 1920, "height": 1080]],
            "objects": objects]
        try json(scene).write(to: directory.appending(path: "scene.json"))
        // Like the gallery's own, the project.json has no `preview`; WE loads it anyway.
        let project: [String: Any] = ["file": "scene.json", "title": directory.lastPathComponent, "type": "scene",
                                      "general": ["properties": [String: Any]()]]
        try json(project).write(to: directory.appending(path: "project.json"))
        return directory
    }

    /// Adds a `preview` to a gallery project.json that has none. Not needed since `WEProject.preview`
    /// became optional; kept only until the particle gallery drops its calls.
    static func addPreview(to directory: URL) throws {
        let url = directory.appending(path: "project.json")
        var project = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        guard project["preview"] == nil else { return }
        project["preview"] = "preview.jpg"
        try json(project).write(to: url)
    }

    /// Copies `assets/effects/<effect>` into the project as WE's editor does: `effect.json` into
    /// `effects/<effect>/`, its `materials/`, `shaders/`… merged into the project's own.
    static func copyEffect(_ effect: String, assets: URL, into directory: URL) throws {
        let fm = FileManager.default
        let source = assets.appending(path: "effects/\(effect)", directoryHint: .isDirectory)
        let target = directory.appending(path: "effects/\(effect)", directoryHint: .isDirectory)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try fm.copyItem(at: source.appending(path: "effect.json"), to: target.appending(path: "effect.json"))
        for sub in try fm.contentsOfDirectory(atPath: source.path) where sub != "preview" {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.appending(path: sub).path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            try merge(source.appending(path: sub, directoryHint: .isDirectory),
                      into: directory.appending(path: sub, directoryHint: .isDirectory))
        }
    }

    private static func merge(_ source: URL, into target: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in enumerator {
            let relative = String(url.standardizedFileURL.path.dropFirst(source.standardizedFileURL.path.count + 1))
            let destination = target.appending(path: relative)
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: destination.path) {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: destination)
            }
        }
    }

    private static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    /// An uncompressed RGBA8888 `.tex` (TEXV0005 / TEXI0001 / TEXB0001, one image, one mip), as
    /// build_gallery.py writes it: format 0, flags 2 (clamp UVs).
    static func texData(png: URL) throws -> Data {
        let image = try WEReferenceImage.load(png)
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func int32(_ value: Int) { withUnsafeBytes(of: Int32(value).littleEndian) { data.append(contentsOf: $0) } }
        for value in [0, 2, image.width, image.height, image.width, image.height, 0] { int32(value) }
        data.append(Data("TEXB0001\0".utf8))
        for value in [1, 1, image.width, image.height, image.width * image.height * 4] { int32(value) }
        var pixels = image.pixels
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        data.append(contentsOf: pixels)
        return data
    }

    /// summarize.py's difference: the mean absolute RGB difference over the rows above the taskbar.
    static func meanAbsoluteDifference(_ a: WEReferenceImage, _ b: WEReferenceImage) -> Double {
        let count = a.width * min(comparedHeight, a.height, b.height)
        var sum = 0
        a.pixels.withUnsafeBufferPointer { p in
            b.pixels.withUnsafeBufferPointer { q in
                for i in 0..<count {
                    let o = i * 4
                    sum += abs(Int(p[o]) - Int(q[o])) + abs(Int(p[o + 1]) - Int(q[o + 1])) + abs(Int(p[o + 2]) - Int(q[o + 2]))
                }
            }
        }
        return Double(sum) / Double(count * 3)
    }

    /// summarize.py's motion: frames at 5 fps, scaled to 480×270 luma (ffmpeg's `format=gray` of the
    /// clip: full-range BT.601 luma), the top 257 rows, mean absolute change between consecutive frames.
    static func motion(_ frames: [WEReferenceImage]) -> Double {
        let lumas = frames.map(smallLuma)
        guard lumas.count > 1 else { return 0 }
        var total = 0.0
        for (a, b) in zip(lumas, lumas.dropFirst()) {
            var sum: Float = 0
            for i in 0..<a.count { sum += abs(a[i] - b[i]) }
            total += Double(sum) / Double(a.count)
        }
        return total / Double(lumas.count - 1)
    }

    private static func smallLuma(_ image: WEReferenceImage) -> [Float] {
        let factor = 4, width = image.width / factor, rows = 257
        var values = [Float](repeating: 0, count: width * rows)
        image.pixels.withUnsafeBufferPointer { p in
            for y in 0..<rows {
                for x in 0..<width {
                    var sum: Float = 0
                    for dy in 0..<factor {
                        for dx in 0..<factor {
                            let o = ((y * factor + dy) * image.width + x * factor + dx) * 4
                            sum += 0.299 * Float(p[o]) + 0.587 * Float(p[o + 1]) + 0.114 * Float(p[o + 2])
                        }
                    }
                    values[y * width + x] = sum / Float(factor * factor)
                }
            }
        }
        return values
    }
}
