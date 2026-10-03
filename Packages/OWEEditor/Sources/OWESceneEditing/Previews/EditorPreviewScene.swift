import CoreGraphics
import Foundation

/// The small wallpapers editor previews are rendered from (`EditorPreviewCache`), written into a
/// scratch folder the real loader and renderer read like any wallpaper:
/// - an effect: one image layer showing the editor's test card, with the effect added at its
///   default values, in a 2D scene of the card's size; texture slots an effect needs filled
///   (a depth map, a flow map, a mask with no switch) get a generated picture (`Input`);
/// - a particle system: the system (or a preset's systems) on a dark background, in a 2D scene of
///   a wallpaper's proportions centred on it, or for a 3D one, WE's particle editor camera.
public enum EditorPreviewScene {
    /// A scene's size in its own units, and the preview's size in pixels.
    public struct Frame: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var pixelHeight: Int
    }

    /// The test card's size (`EditorPreviewTestCard.png`), and the effect preview's.
    public static let effectFrame = Frame(width: 512, height: 320, pixelWidth: 384, pixelHeight: 240)
    /// A 2D particle preview: a 1280×720 piece of a wallpaper around the system.
    public static let particleFrame = Frame(width: 1280, height: 720, pixelWidth: 480, pixelHeight: 270)
    /// The particle preview's background.
    public static let particleBackground = "0.05 0.05 0.07"
    /// WE's particle editor camera for 3D systems (`assets/scenes/particleeditor3dscale`).
    public static let camera3D = (eye: "1.7 1 2.9", center: "0 0 0", up: "0 1 0")

    /// The test card's texture, model and material in the preview's folder.
    public static let testCardFile = "materials/editorpreview/testcard.png"
    static let testCardTexture = "editorpreview/testcard"
    static let testCardModel = "models/editorpreview/testcard.json"
    static let testCardMaterial = "materials/editorpreview/testcard.json"

    // MARK: Generated inputs

    /// A picture an effect's texture slot needs to show anything, generated for the preview.
    public enum Input: String, Codable, CaseIterable, Sendable {
        /// A mask, white in the middle fading to black at the edges.
        case mask
        /// A depth map: near (white) in the middle, far at the edges.
        case depth
        /// A flow map turning around the middle (direction in red and green, 0.5 for none).
        case flow

        /// The texture an effect's pass names.
        public var texture: String { "masks/editorpreview_\(rawValue)" }
        /// The file in the preview's folder.
        public var file: String { "materials/\(texture).png" }
    }

    /// The input a texture slot needs, from its shader annotation: a depth or flow map, or a mask
    /// whose slot has no switch (`combo`) and no picture of its own. Nil for any other slot (it
    /// uses its default, or the effect turns the feature off without it).
    public static func input(mode: String?, combo: String?, defaultTexture: String?, hidden: Bool) -> Input? {
        guard !hidden, combo?.isEmpty ?? true else { return nil }
        let mode = mode?.lowercased() ?? ""
        let fallback = defaultTexture?.lowercased() ?? ""
        switch mode {
        case "depth": return .depth
        case "flowmask": return .flow
        case "opacitymask", "rgbmask": return fallback.isEmpty || fallback == "util/black" ? .mask : nil
        default: return nil
        }
    }

    /// The input's picture as a PNG, `size` pixels square.
    public static func png(_ input: Input, size: Int = 256) -> Data? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let centre = Double(size - 1) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) - centre) / centre, dy = (Double(y) - centre) / centre
                let distance = min((dx * dx + dy * dy).squareRoot(), 1)
                let index = (y * size + x) * 4
                switch input {
                case .mask, .depth:
                    // Smooth falloff: 1 at the middle, 0 at the edge.
                    let value = 1 - distance * distance * (3 - 2 * distance)
                    let byte = UInt8((value * 255).rounded())
                    pixels[index] = byte
                    pixels[index + 1] = byte
                    pixels[index + 2] = byte
                case .flow:
                    // Counter-clockwise around the middle, strongest half-way out.
                    let length = max((dx * dx + dy * dy).squareRoot(), 1e-6)
                    let strength = sin(min(distance, 1) * .pi)
                    let fx = -dy / length * strength, fy = dx / length * strength
                    pixels[index] = UInt8(((0.5 + 0.5 * fx) * 255).rounded())
                    pixels[index + 1] = UInt8(((0.5 + 0.5 * fy) * 255).rounded())
                    pixels[index + 2] = 0
                }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // The context draws from the buffer only while it is borrowed: the image is made inside.
        let image: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        return image.flatMap(EditorAssetStore.pngData)
    }

    // MARK: Effects

    /// The files of an effect's preview besides the test card's picture (`testCardFile`) and the
    /// effect's own files: project.json, scene.json, and the card's model and material.
    /// `passInputs` holds, per pass of the effect, the generated inputs by texture slot.
    public static func effectFiles(effectFile: String, passInputs: [[Int: Input]]) throws -> [String: Data] {
        let frame = effectFrame
        let passes: [Any] = passInputs.map { inputs -> [String: Any] in
            guard let last = inputs.keys.max() else { return [:] }
            let textures: [Any] = (0...last).map { slot in inputs[slot].map { $0.texture as Any } ?? NSNull() }
            return ["textures": textures]
        }
        let object: [String: Any] = [
            "id": 1, "name": "Test card", "image": testCardModel, "visible": true,
            "origin": "\(frame.width / 2) \(frame.height / 2) 0", "scale": "1 1 1", "angles": "0 0 0",
            "size": "\(frame.width) \(frame.height)",
            "effects": [["id": 2, "file": effectFile, "name": "", "visible": true, "passes": passes]],
        ]
        var files = try sceneFiles(scene(frame: frame, clearColor: "0 0 0", camera: nil, objects: [object]))
        files[testCardMaterial] = try json([
            "passes": [[
                "blending": "translucent", "cullmode": "nocull", "depthtest": "disabled", "depthwrite": "disabled",
                "shader": "genericimage2", "textures": [testCardTexture],
            ]],
        ])
        files[testCardModel] = try json(["autosize": true, "material": testCardMaterial])
        return files
    }

    /// A built-in effect's files (`effect.json`'s `dependencies`): its materials, shaders and
    /// textures, which WE's editor copies from `assets/effects/<name>/` into the project, where WE
    /// reads them (`EditorWallpaperResources.prepareEffect`).
    public static func builtInDependencies(effectJSON: Data) -> [String] {
        // Optional: an effect file that can't be read has no dependencies (the load logs it).
        guard let root = try? WETolerantJSON.object(from: effectJSON) as? [String: Any] else { return [] }
        return (root["dependencies"] as? [Any] ?? []).compactMap { $0 as? String }
    }

    /// The files of a Workshop effect a wallpaper ships, by their path in the wallpaper: the
    /// effect file, its `dependencies`, its passes' materials, their shaders (with the headers
    /// they include) and textures. Only the files `read` finds are listed.
    public static func workshopFiles(effectFile: String, read: (String) -> Data?) -> [String] {
        var files: [String] = []
        var seen = Set<String>()
        func add(_ path: String) -> Data? {
            guard !seen.contains(path) else { return nil }
            seen.insert(path)
            guard let data = read(path) else { return nil }
            files.append(path)
            return data
        }
        guard let effectData = add(effectFile),
              let effect = try? WETolerantJSON.object(from: effectData) as? [String: Any] else { return files }
        for dependency in effect["dependencies"] as? [Any] ?? [] {
            if let path = dependency as? String { _ = add(path) }
        }
        let materials = (effect["passes"] as? [[String: Any]] ?? []).compactMap { $0["material"] as? String }
        for materialPath in materials {
            // Optional: a material the wallpaper doesn't ship is WE's (found in its assets).
            guard let data = add(materialPath),
                  let material = try? WETolerantJSON.object(from: data) as? [String: Any] else { continue }
            for pass in material["passes"] as? [[String: Any]] ?? [] {
                if let shader = pass["shader"] as? String {
                    for stage in ["vert", "frag", "geom"] {
                        if let source = add("shaders/\(shader).\(stage)") { addIncludes(of: source, add: add) }
                    }
                }
                for texture in pass["textures"] as? [Any] ?? [] {
                    guard let name = texture as? String, !name.isEmpty, !name.hasPrefix("_rt_") else { continue }
                    for candidate in ["materials/\(name).tex", "materials/\(name).tex-json", "materials/\(name).png",
                                      "materials/\(name).jpg"] {
                        _ = add(candidate)
                    }
                }
            }
        }
        return files
    }

    /// Adds the headers a shader includes (`#include "common.h"` → `shaders/common.h`), and theirs.
    private static func addIncludes(of source: Data, add: (String) -> Data?) {
        let text = String(decoding: source, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #"#include\s+"([^"]+)""#) else { return }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            if let header = add("shaders/\(text[range])") { addIncludes(of: header, add: add) }
        }
    }

    // MARK: Particles

    /// A default system's scene object: the system at the middle of the scene.
    public static func systemObjects(path: String, is3D: Bool) -> [SceneJSONValue] {
        [.object([
            "id": .number(1), "name": .string("Particle System"), "particle": .string(path), "visible": .bool(true),
            "origin": .string(is3D ? "0 0 0" : "\(particleFrame.width / 2) \(particleFrame.height / 2) 0"),
            "scale": .string("1 1 1"), "angles": .string("0 0 0"),
        ])]
    }

    /// A preset variant's objects, numbered and placed as WE's editor adds them: their origins
    /// are offsets from the middle of a 2D scene.
    public static func presetObjects(_ objects: [SceneJSONValue], is3D: Bool) -> [SceneJSONValue] {
        let centre: [Double] = is3D ? [0, 0, 0] : [Double(particleFrame.width / 2), Double(particleFrame.height / 2), 0]
        return objects.enumerated().compactMap { index, authored in
            guard case .object(var fields) = authored else { return nil }
            fields["id"] = .number(Double(index + 1))
            let origin = SceneVector.components(fields["origin"], fallback: [0, 0, 0])
            fields["origin"] = SceneVector.value([origin[0] + centre[0], origin[1] + centre[1], origin[2] + centre[2]])
            return .object(fields)
        }
    }

    /// project.json and scene.json of a particle preview showing `objects`.
    public static func particleFiles(objects: [SceneJSONValue], is3D: Bool) throws -> [String: Data] {
        try sceneFiles(scene(frame: is3D ? nil : particleFrame, clearColor: particleBackground,
                             camera: is3D ? camera3D : nil, objects: objects.map(\.any)))
    }

    // MARK: Writing

    static func scene(frame: Frame?, clearColor: String, camera: (eye: String, center: String, up: String)?,
                      objects: [Any]) -> [String: Any] {
        var general: [String: Any] = [
            "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3", "bloom": false,
            "clearcolor": clearColor, "clearenabled": true, "camerapreview": true,
        ]
        if let frame {
            general["orthogonalprojection"] = ["width": frame.width, "height": frame.height]
        } else {
            general["fov"] = 50
            general["nearz"] = 0.01
            general["farz"] = 10000
        }
        let view = camera ?? (eye: "0 0 0", center: "0 0 -1", up: "0 1 0")
        return [
            "camera": ["eye": view.eye, "center": view.center, "up": view.up],
            "general": general,
            "objects": objects,
        ]
    }

    static func sceneFiles(_ scene: [String: Any]) throws -> [String: Data] {
        [
            "project.json": try json(["file": "scene.json", "title": "Editor preview", "type": "scene"]),
            "scene.json": try json(scene),
        ]
    }

    static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
