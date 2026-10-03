import XCTest
import Metal
import AppKit
import simd
@testable import OpenWallpaperEngine

/// Instancing identical meshes (docs/models-plan.md §4.3 O, `ShaderInstancing`): the translator's
/// instanced path, which objects draw together, and the instanced scene and shadow passes against
/// the same objects drawn one by one, pixel for pixel.
final class ModelInstancingTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var cache: URL?
    private var materials: ModelMaterialPlanBuilder!
    private var renderer: SceneModelRenderer!
    private var depthStates: SceneDepthStates!

    static let size = 256

    override func setUpWithError() throws {
        let assets = ShaderVariantTests.weAssets
        try XCTSkipUnless(FileManager.default.fileExists(atPath: assets.appending(path: "shaders/generic4.frag").path),
                          "bundled WE shaders missing")
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
        let cache = FileManager.default.temporaryDirectory.appending(path: "owe-instancing-\(UUID().uuidString)")
        self.cache = cache
        materials = builder(cache: cache)
        renderer = try XCTUnwrap(SceneModelRenderer(device: device, archive: nil))
        depthStates = try XCTUnwrap(SceneDepthStates(device: device))
    }

    override func tearDownWithError() throws {
        if let cache { try? FileManager.default.removeItem(at: cache) } // scratch cleanup
    }

    private func builder(cache: URL, combos: SceneEngineCombos? = nil) -> ModelMaterialPlanBuilder {
        let roots = [Fixtures.url("ModelMaterials"), ShaderVariantTests.weAssets]
        let read: (String) -> Data? = { path in
            for root in roots {
                if let data = FileManager.default.contents(atPath: root.appending(path: path).path) { return data }
            }
            return nil
        }
        let translator = ShaderVariantTranslator(compiler: InProcessShaderCompiler(), cacheDirectory: cache)
        let texture: (String, String) -> SceneMetalTextureSource? = { _, _ in .image(NSImage(size: NSSize(width: 4, height: 4))) }
        if let combos {
            return ModelMaterialPlanBuilder(translator: translator, readFile: read, loadTexture: texture, sceneEngineCombos: combos)
        }
        return ModelMaterialPlanBuilder(translator: translator, readFile: read, loadTexture: texture)
    }

    private func plan(_ material: String = "materials/facecolor.json", builder: ModelMaterialPlanBuilder? = nil,
                      meshes count: Int = 1, deforms: Bool = false) throws -> SceneModelPlan {
        let mesh = ModelRenderTests.cube()
        let built = try (builder ?? materials).build(materialPath: material,
                                                     mesh: ModelMeshCombos(mesh: mesh, bones: 0, morphTargets: false))
        return SceneModelPlan(path: "\(material).mdl", meshes: (0..<count).map { index in
            SceneModelPlan.Mesh(index: index, material: built, format: mesh.format, vertexData: mesh.vertexData,
                                indexData: mesh.indexData, usesUInt32Indices: false, indexCount: mesh.indexCount,
                                deforms: deforms)
        }, bounds: MDLBounds(min: SIMD3(repeating: -1), max: SIMD3(repeating: 1)), skeleton: nil)
    }

    private static func world(_ origin: SIMD3<Float>, angle: Float = 0) -> simd_float4x4 {
        SceneWorldMatrix.local(SceneLocalTransform3D(origin: origin, scale: SIMD3(repeating: 0.6), angles: SIMD3(angle, angle * 2, 0)))
    }

    private static var content: SceneMetalContent {
        SceneMetalContent(size: SIMD2(256, 256), layers: [], particleSystems: [],
                          bloom: SceneBloomSettings(enabled: false, strength: 0, threshold: 0.7, tint: SIMD3(repeating: 1)))
    }

    // MARK: - Translation

    func testTheVertexStageReadsTheWorldFromTheInstanceUnderTheConstant() {
        let vertex = """
        #version 410
        uniform mat4 g_ModelMatrix;
        uniform mat4 g_ViewProjectionMatrix;
        in vec3 a_Position;
        void main() { gl_Position = g_ViewProjectionMatrix * (g_ModelMatrix * vec4(a_Position, 1.0)); }
        """
        let fragment = "#version 410\nout vec4 out_FragColor;\nvoid main() { out_FragColor = vec4(1.0); }\n"
        let result = ShaderInstancing.rewrite(vertex: vertex, fragment: fragment)
        XCTAssertTrue(result.instanceable)
        XCTAssertTrue(result.vertex.contains("uniform mat4 g_ModelMatrix;"), "the declaration keeps its name")
        XCTAssertTrue(result.vertex.contains("(OWE_I_g_ModelMatrix * vec4"))
        XCTAssertTrue(result.vertex.contains("layout(constant_id = 0) const bool OWE_INSTANCED = false;"))
        XCTAssertTrue(result.vertex.contains("in vec4 a_OWEInstanceModel3;"))
        XCTAssertFalse(result.vertex.contains("a_OWEInstanceMVP"), "only what the stage reads")
        let version = try! XCTUnwrap(result.vertex.range(of: "#version 410"))
        let constant = try! XCTUnwrap(result.vertex.range(of: "constant_id"))
        XCTAssertLessThan(version.upperBound, constant.lowerBound)
    }

    func testAPairReadingTheWorldElsewhereIsNotInstanceable() {
        let vertex = "#version 410\nuniform mat4 g_ModelMatrix;\nuniform mat4 g_ModelViewMatrix;\n"
            + "in vec3 a_Position;\nvoid main() { gl_Position = g_ModelViewMatrix * g_ModelMatrix * vec4(a_Position, 1.0); }\n"
        let plain = "#version 410\nuniform mat4 g_ModelMatrix;\nin vec3 a_Position;\n"
            + "void main() { gl_Position = g_ModelMatrix * vec4(a_Position, 1.0); }\n"
        let fragment = "#version 410\nuniform mat4 g_ModelMatrix;\nout vec4 out_FragColor;\n"
            + "void main() { out_FragColor = g_ModelMatrix[0]; }\n"
        let declaresOnly = "#version 410\nuniform mat4 g_ModelMatrix;\nout vec4 out_FragColor;\nvoid main() { out_FragColor = vec4(1.0); }\n"
        XCTAssertEqual(ShaderInstancing.rewrite(vertex: vertex, fragment: declaresOnly).instanceable, false, "g_ModelViewMatrix")
        let fragmentReads = ShaderInstancing.rewrite(vertex: plain, fragment: fragment)
        XCTAssertFalse(fragmentReads.instanceable, "the fragment stage reads the world")
        XCTAssertEqual(fragmentReads.vertex, plain, "kept as it was")
        XCTAssertTrue(ShaderInstancing.rewrite(vertex: plain, fragment: declaresOnly).instanceable, "a declaration alone")
        let mat3 = "#version 410\nuniform mat3 g_ModelMatrix;\nin vec3 a_Position;\nvoid main() { gl_Position = vec4(g_ModelMatrix * a_Position, 1.0); }\n"
        XCTAssertFalse(ShaderInstancing.rewrite(vertex: mat3, fragment: declaresOnly).instanceable, "another type than WE's")
    }

    func testTheShadowCastersInstanceTakesItsViewFromTheRecord() {
        let vertex = "#version 410\nuniform mat4 g_ModelMatrix;\nuniform mat4 g_ViewportViewProjectionMatrices[6];\n"
            + "in vec3 a_Position;\nvoid main() { gl_Position = g_ViewportViewProjectionMatrices[gl_InstanceID] * g_ModelMatrix * vec4(a_Position, 1.0);"
            + " gl_ViewportIndex = gl_InstanceID; }\n"
        let result = ShaderInstancing.rewrite(vertex: vertex, fragment: "#version 410\nvoid main() {}\n")
        XCTAssertTrue(result.instanceable)
        XCTAssertTrue(result.vertex.contains("g_ViewportViewProjectionMatrices[OWE_I_gl_InstanceID]"))
        XCTAssertTrue(result.vertex.contains("gl_ViewportIndex = OWE_I_gl_InstanceID;"))
        XCTAssertTrue(result.vertex.contains("in float a_OWEInstanceView;"))
    }

    /// Model materials translate with the path, which compiles; the pipelines with and without it
    /// are both made.
    func testModelVariantsAreInstanceableAndBothPipelinesCompile() throws {
        let cube = try plan()
        let variant = try XCTUnwrap(cube.meshes[0].material.pass.variant)
        XCTAssertEqual(variant.instanceable, true)
        XCTAssertTrue(variant.vertexMSL.contains("function_constant"), variant.vertexMSL)
        XCTAssertTrue(renderer.waitUntilReady(cube, pixelFormat: .bgra8Unorm))
        XCTAssertTrue(renderer.waitUntilReady(cube, pixelFormat: .bgra8Unorm, instanced: true))
    }

    // MARK: - Grouping

    func testOnlyUnposedAlikeObjectsShareAKey() throws {
        let cube = try plan(), other = try plan("materials/facecolor_red.json")
        let key = try XCTUnwrap(SceneModelRenderer.instanceKey(cube, hasAnimator: false))
        XCTAssertEqual(SceneModelRenderer.instanceKey(cube, hasAnimator: false), key, "the same plan")
        XCTAssertNotEqual(SceneModelRenderer.instanceKey(other, hasAnimator: false), key, "another material")
        XCTAssertNotEqual(SceneModelRenderer.instanceKey(cube, hasAnimator: false, mirrored: true), key, "mirrored")
        XCTAssertNil(SceneModelRenderer.instanceKey(cube, hasAnimator: true), "its own pose")
        XCTAssertNil(SceneModelRenderer.instanceKey(try plan(deforms: true), hasAnimator: false), "a deforming mesh")
        XCTAssertNotNil(SceneModelRenderer.instanceKey(try plan(meshes: 2), hasAnimator: false), "opaque meshes")
        XCTAssertNil(SceneModelRenderer.instanceKey(try plan("materials/facecolor_translucent.json", meshes: 2), hasAnimator: false),
                     "translucent meshes would draw in another order")
        XCTAssertNotNil(SceneModelRenderer.instanceKey(try plan("materials/facecolor_translucent.json"), hasAnimator: false),
                        "one translucent mesh keeps the objects' order")
    }

    // MARK: - Scene pass

    private struct Placed {
        var plan: SceneModelPlan
        var world: simd_float4x4
        var id: String
    }

    /// Draws `models` as one run of the object loop; RGBA bytes.
    private func render(_ models: [Placed], camera: SceneFrameCamera, instancing: Bool) throws -> [UInt8] {
        let objects = models.map { SceneModelObject(id: $0.id, name: $0.id, order: 0, authored: WESceneModel(source: .path("cube.mdl")),
                                                    plan: $0.plan) }
        renderer.setContent(objects, content: Self.content)
        renderer.instancing = instancing
        for model in models {
            XCTAssertTrue(renderer.waitUntilReady(model.plan, pixelFormat: .bgra8Unorm))
            XCTAssertTrue(renderer.waitUntilReady(model.plan, pixelFormat: .bgra8Unorm, instanced: true))
        }
        let target = try ModelRenderTests.target(device: device, size: Self.size)
        let depth = SceneDepthBuffer(device: device)
        XCTAssertTrue(depth.prepare(width: Self.size, height: Self.size, sampleCount: 1))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        depth.attach(to: pass, clear: true)
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: pass))
        var frame = BuiltinFrameContext(time: 1)
        frame.camera = camera
        frame.eyePosition = camera.eye
        let run = zip(models, objects).map { model, object in
            (model: object, draw: SceneModelDraw(world: model.world, camera: camera, frame: frame,
                                                 values: EffectGraphTests.FixedValues(), pixelFormat: .bgra8Unorm, sampleCount: 1,
                                                 depth: depthStates, mipMappedFrameBuffer: nil, assetTexture: { _, _ in nil }))
        }
        renderer.draw(run: run, encoder: encoder, commandBuffer: buffer)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        XCTAssertNil(buffer.error)
        return try TextureUploadTests.read(target, device: device)
    }

    /// N copies in a grid, turned differently, overlapping in depth.
    private func copies(_ plan: SceneModelPlan, count: Int, offset: SIMD3<Float> = .zero) -> [Placed] {
        (0..<count).map { index in
            let column = Float(index % 4), row = Float(index / 4)
            return Placed(plan: plan, world: Self.world(SIMD3(column * 1.1 - 1.6, row * 1.1 - 1.6, -Float(index) * 0.3) + offset,
                                                        angle: Float(index) * 0.4),
                          id: "copy\(index)")
        }
    }

    func testNCopiesDrawInstancedAsTheyDrawOneByOne() throws {
        let camera = ModelRenderTests.camera(eye: SIMD3(0.5, 1, 7))
        let models = copies(try plan(), count: 16)
        let single = try render(models, camera: camera, instancing: false)
        XCTAssertEqual(renderer.instancedDraws, 0)
        let drawsSingle = renderer.drawsEncoded
        let instanced = try render(models, camera: camera, instancing: true)
        XCTAssertEqual(renderer.instancedDraws, 1, "one draw for the mesh")
        XCTAssertEqual(renderer.instancesDrawn, 16)
        XCTAssertEqual(renderer.drawsEncoded - drawsSingle, 1)
        XCTAssertTrue(single.contains { $0 != 0 && $0 != 255 }, "something drew")
        XCTAssertEqual(instanced, single, "pixel for pixel")
    }

    func testAnotherObjectBreaksTheStretchAndKeepsTheOrder() throws {
        let camera = ModelRenderTests.camera(eye: SIMD3(0, 0, 7))
        let cube = try plan(), red = try plan("materials/facecolor_translucent.json")
        var models = copies(cube, count: 6)
        models.insert(Placed(plan: red, world: Self.world(SIMD3(0, 0, 1)), id: "between"), at: 3)
        let single = try render(models, camera: camera, instancing: false)
        let instanced = try render(models, camera: camera, instancing: true)
        XCTAssertEqual(renderer.instancedDraws, 2, "the copies before and after")
        XCTAssertEqual(renderer.instancesDrawn, 6)
        XCTAssertEqual(renderer.meshDraws["between"], 1)
        XCTAssertEqual(instanced, single)
    }

    func testCulledCopiesAreLeftOutOfTheInstances() throws {
        let camera = ModelRenderTests.camera(eye: SIMD3(0, 0, 7))
        var models = copies(try plan(), count: 8)
        models[2].world = Self.world(SIMD3(40, 0, 0))
        models[5].world = Self.world(SIMD3(0, 0, 30))
        let single = try render(models, camera: camera, instancing: false)
        let instanced = try render(models, camera: camera, instancing: true)
        XCTAssertEqual(renderer.culledModels, ["copy2", "copy5"])
        XCTAssertEqual(renderer.instancesDrawn, 6)
        XCTAssertNil(renderer.meshDraws["copy2"])
        XCTAssertEqual(instanced, single)
    }

    func testAMeshOutsideTheViewIsCulledPerInstance() throws {
        // Two meshes, the second with its own box far away from where the cubes are: the model's
        // box holds the view, the second mesh's sphere doesn't, so only the first draws.
        let cube = try plan(meshes: 2)
        let far = SceneModelPlan.Mesh(index: 1, material: cube.meshes[1].material, format: cube.meshes[1].format,
                                      vertexData: cube.meshes[1].vertexData, indexData: cube.meshes[1].indexData,
                                      usesUInt32Indices: false, indexCount: cube.meshes[1].indexCount,
                                      bounds: MDLBounds(min: SIMD3(200, 200, 200), max: SIMD3(201, 201, 201)))
        let split = SceneModelPlan(path: "split.mdl", meshes: [cube.meshes[0], far], bounds: MDLBounds(min: SIMD3(repeating: -1),
                                                                                                         max: SIMD3(repeating: 1)),
                                   skeleton: nil)
        let camera = ModelRenderTests.camera(eye: SIMD3(0, 0, 7))
        let models = copies(split, count: 4)
        let single = try render(models, camera: camera, instancing: false)
        let instanced = try render(models, camera: camera, instancing: true)
        XCTAssertEqual(renderer.instancedDraws, 1, "the far mesh draws no instance")
        XCTAssertEqual(renderer.meshDraws["copy0"], 1)
        XCTAssertEqual(instanced, single)
    }

    // MARK: - Shadow pass

    func testInstancedCastersDrawTheSameAtlas() throws {
        let budget = WELightConfig(point: 1, pointShadow: 1)
        let shadowBuilder = builder(cache: try XCTUnwrap(cache), combos: SceneEngineCombos(sceneOrtho: false, lightBudget: budget,
                                                                                          shadowQuality: 3))
        let cube = try plan(builder: shadowBuilder)
        let objects = (0..<9).map { SceneModelObject(id: "c\($0)", name: "c\($0)", order: $0,
                                                     authored: WESceneModel(source: .path("cube.mdl")), plan: cube) }
        renderer.setContent(objects, content: Self.content)
        let shadowPass = try XCTUnwrap(SceneShadowPass(device: device, archive: nil))
        XCTAssertTrue(shadowPass.waitUntilReady(cube))
        XCTAssertTrue(shadowPass.waitUntilReady(cube, instanced: true))
        let camera = SceneShadowRenderTests.camera
        var frame = BuiltinFrameContext(time: 1)
        frame.camera = camera
        frame.eyePosition = camera.eye
        frame.viewForward = camera.forward
        var light = SceneLight(kind: .point)
        light.color = SIMD3(repeating: 1)
        light.intensity = 2.5
        light.radius = 30
        light.castShadow = true
        let casters = objects.enumerated().map { index, object in
            SceneShadowPass.Caster(model: object, world: Self.world(SIMD3(Float(index % 3) * 2.5 - 2.5, 2, Float(index / 3) * 2.5 - 2.5),
                                                                    angle: Float(index) * 0.3))
        }
        func draw(instancing: Bool) throws -> [UInt8] {
            shadowPass.instancing = instancing
            shadowPass.setContent()
            let shadows = SceneLightPacker.lightingV1(
                [SceneLightPacker.Light(light: light, world: SceneShadowRenderTests.lightWorld(position: SIMD3(0.5, 7, 0.3),
                                                                                                direction: SIMD3(1, 0, 0)),
                                        localOrigin: .zero, visible: true, id: "light")],
                budget: budget, shadows: true, viewForward: camera.forward,
                shadowContext: SceneLightPacker.ShadowContext(quality: 3, eye: camera.eye, forward: camera.forward,
                                                              orthographic: false, atlasExtent: shadowPass.atlas.extent)).shadows
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            let atlas = try XCTUnwrap(shadowPass.encode(shadows, casters: casters, models: renderer, frame: frame,
                                                        values: EffectGraphTests.FixedValues(), assetTexture: { _, _ in nil },
                                                        commandBuffer: buffer))
            buffer.commit()
            buffer.waitUntilCompleted()
            XCTAssertNil(buffer.error)
            return try SceneShadowRenderTests.depthBytes(atlas, device: device, queue: queue)
        }
        _ = try draw(instancing: false) // makes the atlas at its size
        let single = try draw(instancing: false)
        let drawsSingle = shadowPass.casterDraws
        XCTAssertEqual(shadowPass.instancedCasterDraws, 0)
        let instanced = try draw(instancing: true)
        XCTAssertGreaterThan(shadowPass.instancedCasterDraws, 0)
        XCTAssertLessThan(shadowPass.casterDraws - drawsSingle, drawsSingle / 2, "fewer draws")
        XCTAssertTrue(single.contains { $0 != 0 }, "the cubes cast")
        XCTAssertEqual(instanced, single, "the same depth")
    }
}
