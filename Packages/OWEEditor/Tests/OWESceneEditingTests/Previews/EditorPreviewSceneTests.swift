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

    func testAnEffectMovesWhenAnyProbedFrameDiffers() throws {
        let first = try XCTUnwrap(card(squareAt: 20))
        let same = try XCTUnwrap(card(squareAt: 20))
        let shifted = try XCTUnwrap(card(squareAt: 21))
        XCTAssertEqual(EditorPreviewScene.changedFraction(same, from: first), 0)
        XCTAssertFalse(EditorPreviewScene.moved(same, from: first))
        XCTAssertTrue(EditorPreviewScene.moved(shifted, from: first), "a one-pixel shift is motion")
        let probe: [CGImage] = [first, same, same, shifted, same]
        XCTAssertTrue(probe.dropFirst().contains { EditorPreviewScene.moved($0, from: first) },
                      "motion back where it started by the end of the probe still counts")
    }

    func testAParticleCycleIncludesItsChildrensBursts() {
        let systems: [String: ParticleDefinition] = [
            "particles/launch.json": ParticleDefinition(root: [
                "emitter": .array([.object(["name": .string("sphererandom"), "rate": .number(0.5)])]),
                "initializer": .array([.object(["name": .string("lifetimerandom"), "min": .number(0.8), "max": .number(1.2)])]),
                "children": .array([
                    .object(["name": .string("particles/burst.json"), "type": .string("eventdeath")]),
                    .object(["name": .string("particles/launch.json"), "type": .string("eventfollow")]),
                ]),
            ]),
            "particles/burst.json": ParticleDefinition(root: [
                "emitter": .array([.object(["name": .string("sphererandom"), "instantaneous": .number(150), "delay": .number(0.25)])]),
                "initializer": .array([.object(["name": .string("lifetimerandom"), "max": .number(1.5)])]),
                "children": .null,
            ]),
        ]
        let read: (String) -> ParticleDefinition? = { systems[$0] }
        XCTAssertEqual(EditorPreviewScene.cycleSeconds(ofSystem: "particles/burst.json", read: read), 1.75, accuracy: 1e-9)
        XCTAssertEqual(EditorPreviewScene.cycleSeconds(ofSystem: "particles/launch.json", read: read), 2.95, accuracy: 1e-9,
                       "a launch's life, then its burst's delay and life; longer than its 2 s emission period")
        XCTAssertEqual(EditorPreviewScene.cycleSeconds(ofSystem: "particles/missing.json", read: read), 0)

        let timing = EditorPreviewScene.particleTiming(cycle: 2.95)
        XCTAssertEqual(timing.leadIn, 2.95, accuracy: 1e-9)
        XCTAssertEqual(timing.loop, 2.95, accuracy: 1e-9)
        XCTAssertEqual(EditorPreviewScene.particleTiming(cycle: 0.5), .init(leadIn: 1.5, loop: 2))
        let long = EditorPreviewScene.particleTiming(cycle: 30)
        XCTAssertEqual(long.loop, 5)
        XCTAssertEqual(long.leadIn + long.loop, EditorPreviewScene.particleSecondsCap)
    }

    func testAnOffsetSystemIsFramedOnWhatItDraws() throws {
        let probe = EditorPreviewScene.probeFraming
        let objects = EditorPreviewScene.presetObjects([.object(["particle": .string("particles/a.json"),
                                                                 "origin": .string("-1000 600 0")])], is3D: false)
        // Drawn into the probe, the system sits up and to the left of the middle.
        let probed = probe.place(objects[0])
        XCTAssertEqual(probed["origin"], .string("1560 2040 0"))
        let pixelsPerUnit: Double = Double(probe.frame.pixelWidth) / Double(probe.frame.width)
        let x: Double = (1560 * pixelsPerUnit).rounded()
        let y: Double = (Double(probe.frame.pixelHeight) - 2040 * pixelsPerUnit).rounded()
        let image = try XCTUnwrap(canvas(width: probe.frame.pixelWidth, height: probe.frame.pixelHeight,
                                         square: CGRect(x: x - 15, y: y - 10, width: 30, height: 20)))
        var bounds = EditorPreviewScene.ContentBounds(pixelWidth: probe.frame.pixelWidth, pixelHeight: probe.frame.pixelHeight)
        bounds.add(image)
        let content = try XCTUnwrap(bounds.rect())
        XCTAssertEqual(content.midX, x, accuracy: 1)
        XCTAssertEqual(content.midY, y, accuracy: 1)

        let fitted = EditorPreviewScene.fittedFraming(content: content, probe: probe)
        let frame = fitted.frame
        XCTAssertEqual(Double(frame.width) / Double(frame.height), 16.0 / 9.0, accuracy: 0.01, "the preview's proportions")
        let widthShare: Double = Double(content.width) / pixelsPerUnit / Double(frame.width)
        let heightShare: Double = Double(content.height) / pixelsPerUnit / Double(frame.height)
        XCTAssertEqual(max(widthShare, heightShare), EditorPreviewScene.particleFill, accuracy: 0.02, "fills 80% of it")
        // Within a probe pixel of the middle.
        let unitsPerPixel: Double = 1 / pixelsPerUnit
        let placed = SceneVector.components(fitted.place(objects[0])["origin"])
        XCTAssertEqual(placed[0], Double(frame.width) / 2, accuracy: unitsPerPixel, "centred")
        XCTAssertEqual(placed[1], Double(frame.height) / 2, accuracy: unitsPerPixel)
        let files = try EditorPreviewScene.particleFiles(objects: objects, is3D: false, framing: fitted)
        let general = try XCTUnwrap(try json(files["scene.json"])["general"] as? [String: Any])
        let projection = try XCTUnwrap(general["orthogonalprojection"] as? [String: Any])
        XCTAssertEqual(projection["width"] as? Int, frame.width)

        let empty = EditorPreviewScene.ContentBounds(pixelWidth: 8, pixelHeight: 8)
        XCTAssertNil(empty.rect(), "nothing drawn: the default framing stays")
    }

    /// A 64 × 40 grey picture with a white 8-pixel square `x` pixels from the left.
    private func card(squareAt x: Int) -> CGImage? {
        canvas(width: 64, height: 40, square: CGRect(x: x, y: 16, width: 8, height: 8))
    }

    /// A dark picture with a white rectangle at `square` (from the top left).
    private func canvas(width: Int, height: Int, square: CGRect) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let flipped = CGRect(x: square.minX, y: CGFloat(height) - square.maxY, width: square.width, height: square.height)
        context.fill(flipped)
        return context.makeImage()
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }
}
