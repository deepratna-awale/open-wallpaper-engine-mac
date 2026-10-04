import ImageIO
import XCTest
@testable import OWESceneEditing

/// The small wallpapers previews are rendered from: an effect on the test card with generated
/// inputs where it needs them, and particle systems on a dark background.
final class EditorPreviewSceneTests: XCTestCase {
    func testInputsAreGeneratedOnlyWhereAnEffectNeedsThem() {
        typealias Scene = EditorPreviewScene
        XCTAssertEqual(Scene.input(mode: "depth", combo: nil, defaultTexture: "util/black", hidden: false), .depth)
        XCTAssertEqual(Scene.input(mode: "flowmask", combo: nil, defaultTexture: "util/noflow", hidden: false), .flow)
        XCTAssertEqual(Scene.input(mode: "opacitymask", combo: nil, defaultTexture: nil, hidden: false), .mask)
        XCTAssertNil(Scene.input(mode: "opacitymask", combo: "MASK", defaultTexture: nil, hidden: false),
                     "a mask the effect switches on: without one it applies everywhere")
        XCTAssertNil(Scene.input(mode: "rgbmask", combo: nil, defaultTexture: "util/white", hidden: false), "its own default")
        XCTAssertNil(Scene.input(mode: nil, combo: nil, defaultTexture: "util/noise", hidden: false))
        XCTAssertNil(Scene.input(mode: "depth", combo: nil, defaultTexture: nil, hidden: true))
    }

    func testGeneratedInputsArePictures() throws {
        for input in EditorPreviewScene.Input.allCases {
            let png = try XCTUnwrap(EditorPreviewScene.png(input, size: 32), "\(input)")
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 32)
            XCTAssertEqual(image.height, 32)
            XCTAssertTrue(input.file.hasPrefix("materials/masks/editorpreview_"))
            XCTAssertEqual(input.file, "materials/\(input.texture).png")
        }
    }

    func testAnEffectIsAddedToTheTestCardAtItsDefaults() throws {
        let files = try EditorPreviewScene.effectFiles(effectFile: "effects/depthparallax/effect.json",
                                                       passInputs: [[1: .depth, 3: .mask], [:]])
        XCTAssertEqual(Set(files.keys), ["project.json", "scene.json", "models/editorpreview/testcard.json",
                                         "materials/editorpreview/testcard.json"])
        let project = try json(files["project.json"])
        XCTAssertEqual(project["type"] as? String, "scene")
        XCTAssertEqual(project["file"] as? String, "scene.json")
        let scene = try json(files["scene.json"])
        let general = try XCTUnwrap(scene["general"] as? [String: Any])
        let projection = try XCTUnwrap(general["orthogonalprojection"] as? [String: Any])
        XCTAssertEqual(projection["width"] as? Int, EditorPreviewScene.effectFrame.width)
        XCTAssertEqual(projection["height"] as? Int, EditorPreviewScene.effectFrame.height)
        let object = try XCTUnwrap((scene["objects"] as? [[String: Any]])?.first)
        XCTAssertEqual(object["image"] as? String, "models/editorpreview/testcard.json")
        XCTAssertEqual(object["origin"] as? String, "256 160 0")
        let effect = try XCTUnwrap((object["effects"] as? [[String: Any]])?.first)
        XCTAssertEqual(effect["file"] as? String, "effects/depthparallax/effect.json")
        let passes = try XCTUnwrap(effect["passes"] as? [[String: Any]])
        XCTAssertEqual(passes.count, 2, "one entry per pass of the effect")
        XCTAssertNil(passes[0]["constantshadervalues"], "the effect's own defaults")
        let textures = try XCTUnwrap(passes[0]["textures"] as? [Any])
        XCTAssertEqual(textures.count, 4)
        XCTAssertTrue(textures[0] is NSNull, "the layer's own image")
        XCTAssertEqual(textures[1] as? String, "masks/editorpreview_depth")
        XCTAssertTrue(textures[2] is NSNull)
        XCTAssertEqual(textures[3] as? String, "masks/editorpreview_mask")
        XCTAssertNil(passes[1]["textures"])
        let material = try json(files["materials/editorpreview/testcard.json"])
        let pass = try XCTUnwrap((material["passes"] as? [[String: Any]])?.first)
        XCTAssertEqual(pass["textures"] as? [String], ["editorpreview/testcard"])
        XCTAssertEqual(EditorPreviewScene.testCardFile, "materials/editorpreview/testcard.png")
    }

    func testAPresetVariantIsCentredOnADarkBackground() throws {
        let objects = EditorPreviewScene.presetObjects([
            .object(["name": .string("Rain"), "particle": .string("particles/presets/rain.json"), "origin": .string("0 100 0"),
                     "instanceoverride": .object(["count": .number(2)])]),
            .object(["particle": .string("particles/presets/splash.json")]),
        ], is3D: false)
        XCTAssertEqual(objects.map { $0["id"] }, [.number(1), .number(2)])
        XCTAssertEqual(objects[0]["origin"], .string("640 460 0"), "its offset from the middle of the frame")
        XCTAssertEqual(objects[1]["origin"], .string("640 360 0"))
        XCTAssertEqual(objects[0]["instanceoverride"], .object(["count": .number(2)]), "kept as authored")

        let scene = try json(try EditorPreviewScene.particleFiles(objects: objects, is3D: false)["scene.json"])
        let general = try XCTUnwrap(scene["general"] as? [String: Any])
        XCTAssertEqual(general["clearcolor"] as? String, EditorPreviewScene.particleBackground)
        XCTAssertNotNil(general["orthogonalprojection"])
        XCTAssertEqual((scene["objects"] as? [Any])?.count, 2)
    }

    func testA3DSystemIsSeenThroughWEsParticleEditorCamera() throws {
        let objects = EditorPreviewScene.systemObjects(path: "particles/example3d.json", is3D: true)
        XCTAssertEqual(objects.first?["origin"], .string("0 0 0"))
        XCTAssertEqual(objects.first?["particle"], .string("particles/example3d.json"))
        let scene = try json(try EditorPreviewScene.particleFiles(objects: objects, is3D: true)["scene.json"])
        let general = try XCTUnwrap(scene["general"] as? [String: Any])
        XCTAssertNil(general["orthogonalprojection"], "a perspective scene")
        let camera = try XCTUnwrap(scene["camera"] as? [String: Any])
        XCTAssertEqual(camera["eye"] as? String, "1.7 1 2.9")
        XCTAssertEqual(camera["center"] as? String, "0 0 0")
        XCTAssertEqual(EditorPreviewScene.systemObjects(path: "particles/example.json", is3D: false).first?["origin"],
                       .string("640 360 0"))
    }

    func testAWorkshopEffectsFilesAreFoundInItsWallpaper() {
        let files: [String: String] = [
            "effects/workshop/1/glow/effect.json": #"{"dependencies": ["materials/extra.json"], "passes": [{"material": "materials/workshop/glow.json"}, {"command": "copy"}]}"#,
            "materials/extra.json": "{}",
            "materials/workshop/glow.json": #"{"passes": [{"shader": "workshop/glow", "textures": [null, "workshop/noise", "_rt_FullFrameBuffer"]}]}"#,
            "shaders/workshop/glow.frag": "#include \"common.h\"\n#include \"workshop/glow.h\"\nvoid main() {}",
            "shaders/workshop/glow.vert": "void main() {}",
            "shaders/workshop/glow.h": "#include \"workshop/glow.h\"\n",
            "materials/workshop/noise.tex": "tex",
            "materials/workshop/noise.tex-json": "{}",
            "materials/unrelated.tex": "tex",
        ]
        let found = EditorPreviewScene.workshopFiles(effectFile: "effects/workshop/1/glow/effect.json",
                                                     read: { files[$0].map { Data($0.utf8) } })
        XCTAssertEqual(Set(found), ["effects/workshop/1/glow/effect.json", "materials/extra.json", "materials/workshop/glow.json",
                                    "shaders/workshop/glow.frag", "shaders/workshop/glow.vert", "shaders/workshop/glow.h",
                                    "materials/workshop/noise.tex", "materials/workshop/noise.tex-json"],
                       "WE's own headers (common.h) come from its assets; a header including itself is read once")
        XCTAssertEqual(found.count, Set(found).count)
        XCTAssertEqual(EditorPreviewScene.builtInDependencies(effectJSON: Data(#"{"dependencies": ["a", 1, "b"],}"#.utf8)), ["a", "b"])
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }
}
