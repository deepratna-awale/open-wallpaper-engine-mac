import Foundation

/// One mesh's material, resolved at load (docs/models-plan.md §2.7, §4.3 M5): the variant WE's
/// shader translates to with the material's combos, the engine's (`SceneEngineCombos`) and the
/// mesh's (`ModelMeshCombos`), its textures, constants, blending and pass state. Every model
/// shader goes through here, WE's `generic*` and a project's own (`car`, `technoorbit`, …). A
/// final class so the renderer can key per-mesh state on its identity.
final class ModelMaterialPlan {
    /// The material JSON, for logging.
    let materialPath: String
    /// `variant`, textures (every slot an asset, `_rt_MipMappedFrameBuffer` or the engine's
    /// morph texture), constants and blending.
    let pass: SceneEffectPassPlan
    /// The first pass's `depthtest`, `depthwrite` and `cullmode`, with WE's defaults (test,
    /// write, back faces culled).
    let raster: SceneRasterState
    /// Texture slots sampled with clamp-to-edge (the `.tex` ClampUVs flag); the others repeat.
    let clampedSlots: Set<Int>
    let meshCombos: ModelMeshCombos

    init(materialPath: String, pass: SceneEffectPassPlan, raster: SceneRasterState, clampedSlots: Set<Int>,
         meshCombos: ModelMeshCombos) {
        self.materialPath = materialPath
        self.pass = pass
        self.raster = raster
        self.clampedSlots = clampedSlots
        self.meshCombos = meshCombos
    }

    /// WE's blending byte (+0x1f0): normal 0, translucent 1, additive 2, alphatocoverage 3.
    var blending: String { pass.blending.lowercased() }
    /// Blending normal or alpha-to-coverage: the mesh makes its model opaque (0x140225241) and
    /// draws before the translucent meshes (0x14021a620). Anything else is translucent.
    var isOpaque: Bool { ["normal", "alphatocoverage", "disabled", ""].contains(blending) }
    var alphaToCoverage: Bool { blending == "alphatocoverage" }
}

/// The combos WE's model builder lays over each mesh's material (0x140224c70; docs/models-plan.md
/// §2.7): `SKINNING` when the mesh has `a_BlendIndices`, `BONECOUNT` =
/// `min(nextPow2(max(bones, 16)), 128)` (16, 32, 64 or 128; a puppet's is exact instead),
/// `MORPHING` when the mesh has morph targets and `MORPHING_NORMALS` with mesh flag 0x400.
struct ModelMeshCombos: Hashable {
    var skinning: Bool
    var boneCount: Int
    var morphing: Bool
    var morphingNormals: Bool

    init(skinning: Bool, boneCount: Int, morphing: Bool = false, morphingNormals: Bool = false) {
        self.skinning = skinning
        self.boneCount = boneCount
        self.morphing = morphing
        self.morphingNormals = morphingNormals
    }

    /// `mesh` of a model with `bones` bones; `morphTargets` says whether the model's `MDMP` has
    /// targets for it.
    init(mesh: MDLMesh, bones: Int, morphTargets: Bool) {
        self.init(skinning: mesh.format.contains(.blendIndices), boneCount: Self.boneCount(bones),
                  morphing: morphTargets, morphingNormals: morphTargets && mesh.flags & 0x400 != 0)
    }

    /// `min(nextPow2(max(bones, 16)), 128)`.
    static func boneCount(_ bones: Int) -> Int {
        var count = 16
        while count < bones, count < 128 { count *= 2 }
        return count
    }

    var combos: [String: Int] {
        var combos = ["SKINNING": skinning ? 1 : 0, "BONECOUNT": boneCount]
        if morphing { combos["MORPHING"] = 1 }
        if morphingNormals { combos["MORPHING_NORMALS"] = 1 }
        return combos
    }

    /// `g_Texture5`, WE's "morph" texture of position (and normal) deltas: the engine binds it.
    static let morphSlot = 5
}

/// Builds a mesh's `ModelMaterialPlan` from its material JSON.
struct ModelMaterialPlanBuilder {
    let translator: ShaderVariantTranslator
    /// Reads a file relative to the wallpaper, falling back to the WE assets.
    let readFile: (String) -> Data?
    /// Loads a texture by WE name relative to a material path.
    let loadTexture: (_ name: String, _ materialPath: String) -> SceneMetalTextureSource?
    /// The combos WE's engine lays over every material of the scene (`LIGHTS_*`, `HDR`, `REVERSEDEPTH`).
    var sceneEngineCombos = SceneEngineCombos()

    /// Combos the app fixes on every model material: `FOG` stays off (docs/lighting-plan.md,
    /// general fog isn't implemented; WE's own `FOG_DIST`/`FOG_HEIGHT` are the engine's).
    static let appCombos = ["FOG": 0]

    func build(materialPath: String, mesh: ModelMeshCombos) throws -> ModelMaterialPlan {
        guard let data = readFile(materialPath) else { throw ModelMaterialPlanError.missing(materialPath) }
        let material: MaterialDocument
        do {
            material = try decodeTolerant(MaterialDocument.self, from: data)
        } catch {
            throw ModelMaterialPlanError.invalid(materialPath, error)
        }
        guard let materialPass = material.passes.first else { throw ModelMaterialPlanError.missing("\(materialPath) passes") }
        if material.passes.count > 1 {
            OWELog.info(.scene, "Model material \(materialPath) has \(material.passes.count) passes; its first is drawn")
        }
        let loader = ShaderSourceLoader(readFile: readFile)
        let vertex = try loader.load(materialPass.shader, stage: .vertex)
        let fragment = try loader.load(materialPass.shader, stage: .fragment)
        let images = ImageMaterialPlanBuilder(translator: translator, readFile: readFile, loadTexture: loadTexture,
                                              sceneEngineCombos: sceneEngineCombos)

        var listed: [Int: SceneEffectTextureInput] = [:]
        var headers: [Int: Data] = [:]
        for (slot, name) in materialPass.textures.enumerated() {
            guard let name, !name.isEmpty else { continue }
            listed[slot] = try textureInput(named: name, materialPath: materialPath)
            if listed[slot] != nil, !name.hasPrefix("_rt_") { headers[slot] = images.textureHeader(name, materialPath: materialPath) }
        }
        let formats = ImageMaterialPlanBuilder.formatCombos(vertex.samplers + fragment.samplers, headers: headers)
        // A pass blending alpha-to-coverage gets `ALPHATOCOVERAGE` (0x140154bc1, 0x1401564a4).
        let coverage = materialPass.blending?.lowercased() == "alphatocoverage" ? ["ALPHATOCOVERAGE": 1] : [:]
        let combos = sceneEngineCombos.applied(to: ShaderVariantTranslator.resolveCombos(
            vertex: vertex, fragment: fragment, overrides: [materialPass.combos, coverage, mesh.combos, Self.appCombos, formats],
            boundTextureSlots: Set(listed.keys),
            textureFlags: headers.compactMapValues { TEXImageFormat.texiWord(1, in: $0) }))

        let uniforms = (vertex.uniforms + fragment.uniforms).filter { !$0.isSampler }
            .reduce(into: [ShaderUniformDeclaration]()) { result, uniform in
                if !result.contains(where: { $0.name == uniform.name }) { result.append(uniform) }
            }
        let constants = ShaderConstantResolver.resolve(
            uniforms: uniforms.map { .init(name: $0.name, glslType: $0.type, arrayCount: $0.arrayCount ?? 1, annotation: $0.annotation) },
            material: materialPass.constantSources(uniforms: uniforms), instance: [:])

        let variant = try translator.variant(vertex: vertex, fragment: fragment, combos: combos)
        // SPIRV-Cross emits only the textures a stage uses; one it doesn't emit needs nothing bound.
        let msl = variant.vertexMSL + variant.fragmentMSL
        let sampled = Set(variant.textureSlots).filter { msl.contains("[[texture(\($0))]]") }
        var inputs = listed.filter { sampled.contains($0.key) }
        for sampler in vertex.samplers + fragment.samplers {
            guard let slot = sampler.textureSlot, sampled.contains(slot), inputs[slot] == nil,
                  let name = sampler.defaultTexture else { continue }
            inputs[slot] = try textureInput(named: name, materialPath: materialPath)
        }
        let engineBound: Set<Int> = mesh.morphing ? [ModelMeshCombos.morphSlot] : []
        if let unbound = sampled.subtracting(inputs.keys).subtracting(engineBound).min() {
            throw ModelMaterialPlanError.unsupported("g_Texture\(unbound) has no texture")
        }
        let pass = SceneEffectPassPlan(command: .render,
                                       variantKey: ShaderVariantTranslator.cacheKey(vertex: vertex, fragment: fragment, combos: combos),
                                       variant: variant, blending: materialPass.blending ?? "normal", target: nil,
                                       textures: inputs, constants: constants)
        var clampedSlots = Set<Int>()
        for (slot, input) in inputs {
            switch input {
            case .mipMappedFrameBuffer: clampedSlots.insert(slot)
            case .asset(let key, _):
                if images.textureClamps(String(key.dropFirst(materialPath.count + 1)), materialPath: materialPath) {
                    clampedSlots.insert(slot)
                }
            default: break
            }
        }
        return ModelMaterialPlan(materialPath: materialPath, pass: pass,
                                 raster: SceneRasterState(depthtest: materialPass.depthtest, depthwrite: materialPass.depthwrite,
                                                          cullmode: materialPass.cullmode),
                                 clampedSlots: clampedSlots, meshCombos: mesh)
    }

    /// nil (logged) for a texture that isn't there: the slot stays unbound, and so does its combo.
    private func textureInput(named name: String, materialPath: String) throws -> SceneEffectTextureInput? {
        if name == SceneMipMappedFrameBuffer.name { return .mipMappedFrameBuffer }
        // Another layer's image after its effects (a dependency of the model, drawn whether it is
        // visible or not): the renderer hands it out by layer id (`SceneModelDraw.layerComposite`).
        if Self.compositeLayerID(name) != nil { return .fbo(name) }
        if name.hasPrefix("_rt_") || name.hasPrefix("_alias_") {
            // `_rt_shadowAtlas` (M8), `_rt_Reflection` (M9), `_alias_lightCookie` and the scene's
            // own buffers have no source for a model yet.
            throw ModelMaterialPlanError.unsupported("render target \(name)")
        }
        guard let source = loadTexture(name, materialPath) else {
            OWELog.error(.scene, "Texture \(name) not found for \(materialPath)")
            return nil
        }
        return .asset(key: "\(materialPath)|\(name)", source: source)
    }
}

extension ModelMaterialPlanBuilder {
    /// The layer id of `_rt_imageLayerComposite_<id>_a` (WE's buffer the layer's image and its
    /// effects are drawn into, 0x1401ea642); nil for any other name.
    static func compositeLayerID(_ name: String) -> String? {
        let prefix = "_rt_imageLayerComposite_"
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard let end = rest.firstIndex(of: "_"), rest[rest.index(after: end)...] == "a" else { return nil }
        let id = rest[..<end]
        return !id.isEmpty && id.allSatisfy(\.isNumber) ? String(id) : nil
    }
}

enum ModelMaterialPlanError: Error, CustomStringConvertible {
    case missing(String)
    case invalid(String, Error)
    case unsupported(String)

    var description: String {
        switch self {
        case .missing(let path): return "missing \(path)"
        case .invalid(let path, let error): return "\(path): \(error)"
        case .unsupported(let reason): return "unsupported: \(reason)"
        }
    }
}
