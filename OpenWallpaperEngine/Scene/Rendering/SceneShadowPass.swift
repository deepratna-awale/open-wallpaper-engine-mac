import Metal
import simd

/// Draws the frame's shadow maps into `_rt_shadowAtlas` (docs/models-plan.md §2.10; `wallpaper64.exe`
/// 0x140196530, called from the light packer before the reflection and scene passes).
///
/// - The atlas is cleared to 0 once, then the maps are drawn in batches of views: each point
///   light's six faces as one batch, then the spots and cascades six at a time, in the layout's
///   order (points first).
/// - A batch sets one viewport per view and draws every caster instanced once per view: the
///   material's shadow variant (`ModelMaterialPlan.shadowCaster`, `shadowcaster.vert`) takes
///   `g_ViewportViewProjectionMatrices[gl_InstanceID]` and writes the viewport index.
/// - Casters are the visible model objects with `castshadow` (models default to true) that are
///   opaque (a mesh blending normal or alpha-to-coverage), and of those only their opaque meshes;
///   one is skipped when its box's sphere lies outside every view of the batch.
/// - The state is WE's biased raster state: slope-scaled depth bias −4, no constant bias or clamp,
///   and, by WE's quirk (the biased back-cull state was made with culling off), no culling;
///   `shadowcaster.json`'s depth test and write, reversed (GREATER).
///
/// Call on the render thread, apart from the pipeline compiles.
final class SceneShadowPass {
    /// A caster this frame: a visible model object and its world matrix.
    struct Caster {
        let model: SceneModelObject
        let world: simd_float4x4
    }

    /// WE's slope-scaled depth bias (0x1400991bd).
    static let slopeScaledDepthBias: Float = -4
    /// At most this many views per batch (the matrices' array).
    static let viewsPerBatch = 6

    let atlas: SceneShadowAtlas
    private let device: MTLDevice
    private let archive: EffectPipelineArchive?
    private let uniformArena: SceneUniformArena
    private let depthState: MTLDepthStencilState
    private let zeroAttributes: MTLBuffer
    private let clampSampler: MTLSamplerState
    private let repeatSampler: MTLSamplerState
    private let emptyMorphTexture: MTLTexture

    private let compileQueue = DispatchQueue(label: "owe.shadow-pipelines", qos: .userInitiated, attributes: .concurrent)
    /// Owns `pipelines`, `pending` and `failed`, which compile threads write.
    private let pipelineLock = NSLock()
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var pending = Set<String>()
    private var failed = Set<String>()

    /// Per object, each mesh's shadow-variant uniforms. Render thread only.
    private var uniforms: [String: [ModelMaterialUniforms?]] = [:]

    /// Diagnostics and tests: batches and caster draws encoded, and the maps drawn last frame.
    private(set) var batchesEncoded = 0
    private(set) var casterDraws = 0
    private(set) var lastMapCount = 0

    init?(device: MTLDevice, archive: EffectPipelineArchive?) {
        self.device = device
        self.archive = archive
        atlas = SceneShadowAtlas(device: device)
        uniformArena = SceneUniformArena(device: device)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = true
        func sampler(_ mode: MTLSamplerAddressMode) -> MTLSamplerState? {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            descriptor.sAddressMode = mode
            descriptor.tAddressMode = mode
            return device.makeSamplerState(descriptor: descriptor)
        }
        let morph = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        morph.usage = .shaderRead
        guard let state = device.makeDepthStencilState(descriptor: depth), let zero = device.makeBuffer(length: 64),
              let clamp = sampler(.clampToEdge), let wrap = sampler(.repeat),
              let morphTexture = device.makeTexture(descriptor: morph) else { return nil }
        morphTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt16](repeating: 0, count: 4),
                             bytesPerRow: 8)
        depthState = state
        zeroAttributes = zero
        clampSampler = clamp
        repeatSampler = wrap
        emptyMorphTexture = morphTexture
    }

    /// A new content: its objects' uniforms go.
    func setContent() {
        uniforms.removeAll()
    }

    /// A model a script destroyed.
    func remove(_ id: String) {
        uniforms.removeValue(forKey: id)
    }

    /// Whether a model object casts: its `castshadow`, true unless authored (the model factory
    /// sets flag 0x800, 0x1401901b1); a bound value's fallback, as the content is rebuilt when a
    /// user property changes.
    static func castsShadow(_ model: SceneModelObject) -> Bool {
        guard let value = model.renderValues[.castshadow].flatMap(literal) else { return true }
        switch value {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .string(let text): return !["false", "0", ""].contains(text.lowercased())
        case .object: return true
        }
    }

    private static func literal(_ value: SceneRawValue) -> SceneRawValue? {
        if case .object(let object) = value { return object.value.flatMap(literal) }
        return value
    }

    /// Draws `shadows`' maps with `casters` and returns the atlas the frame's materials read: the
    /// maps, or the cleared stand-in when there are none yet.
    func encode(_ shadows: SceneShadowFrame, casters: [Caster], models: SceneModelRenderer, frame: BuiltinFrameContext,
                values: SceneValueContext, assetTexture: (String, SceneMetalTextureSource) -> MTLTexture?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        lastMapCount = shadows.maps.count
        guard !shadows.maps.isEmpty else { return atlas.bound(commandBuffer: commandBuffer) }
        guard let texture = atlas.texture(extent: shadows.extent) else { return atlas.bound(commandBuffer: commandBuffer) }
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = texture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 0
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = SceneShadowAtlas.name
        encoder.setDepthStencilState(depthState)
        encoder.setDepthBias(0, slopeScale: Self.slopeScaledDepthBias, clamp: 0)
        encoder.setCullMode(.none)
        encoder.setFrontFacing(SceneModelRenderer.frontFacing)
        let posed = casters.compactMap { caster -> (Caster, SceneModelPlan, [Float]?)? in
            guard let plan = caster.model.plan, !plan.isTranslucent,
                  plan.meshes.contains(where: { $0.material.shadowCaster != nil }) else { return nil }
            return (caster, plan, models.advance(caster.model, plan: plan, frame: frame, values: values))
        }
        for batch in Self.batches(shadows.maps) {
            encoder.setViewports(batch.viewports.map { rect in
                MTLViewport(originX: Double(rect.x), originY: Double(rect.y), width: Double(rect.z), height: Double(rect.w),
                            znear: 0, zfar: 1)
            })
            batchesEncoded += 1
            let matrices = batch.views.map { Self.clipFixup * $0 }
            for (caster, plan, bones) in posed where batch.views.contains(where: {
                SceneModelRenderer.isInsideFrustum(plan.bounds, world: caster.world, viewProjection: $0)
            }) {
                drawCaster(caster, plan: plan, bones: bones, matrices: matrices, models: models, frame: frame, values: values,
                           assetTexture: assetTexture, encoder: encoder, commandBuffer: commandBuffer)
            }
        }
        encoder.endEncoding()
        return texture
    }

    /// The translated vertex stages negate y and write z as (z + w) / 2 (`fixup_clipspace`,
    /// `flip_vert_y`), which the scene's depth only compares. The atlas's depth is compared
    /// against WE's own z (`CalculateProjectedCoords`), so the casters' matrices undo both: what
    /// the stage writes is WE's clip position, z included.
    static let clipFixup = simd_float4x4(rows: [SIMD4(1, 0, 0, 0), SIMD4(0, -1, 0, 0), SIMD4(0, 0, 2, -1), SIMD4(0, 0, 0, 1)])

    /// A batch of views: their render matrices and viewport rectangles.
    struct Batch: Equatable {
        var views: [simd_float4x4]
        var viewports: [SIMD4<Int>]
    }

    /// The layout's order (points first, then larger maps), each point one batch of its six faces,
    /// the other maps six views at a time (0x1401939ed…0x1401963a2).
    static func batches(_ maps: [SceneShadowMap]) -> [Batch] {
        let order = maps.indices.sorted { a, b in
            let keyA = SceneShadowAtlasLayout.key(.init(size: maps[a].size, isPoint: maps[a].isPoint))
            let keyB = SceneShadowAtlasLayout.key(.init(size: maps[b].size, isPoint: maps[b].isPoint))
            return keyA != keyB ? keyA > keyB : a < b
        }
        var batches: [Batch] = []
        var pending = Batch(views: [], viewports: [])
        for index in order {
            let map = maps[index]
            if map.isPoint {
                batches.append(Batch(views: map.renderViews, viewports: map.viewports))
                continue
            }
            if pending.views.count == viewsPerBatch {
                batches.append(pending)
                pending = Batch(views: [], viewports: [])
            }
            pending.views += map.renderViews
            pending.viewports += map.viewports
        }
        if !pending.views.isEmpty { batches.append(pending) }
        return batches
    }

    // MARK: - Casters

    private func drawCaster(_ caster: Caster, plan: SceneModelPlan, bones: [Float]?, matrices: [simd_float4x4],
                            models: SceneModelRenderer, frame: BuiltinFrameContext, values: SceneValueContext,
                            assetTexture: (String, SceneMetalTextureSource) -> MTLTexture?,
                            encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {
        let buffers = models.meshBuffers(plan)
        let meshUniforms = uniforms(for: caster.model.id, plan: plan)
        let placement = SceneLayerPlacement(world: caster.world, size: SIMD2(1, 1), camera: frame.camera)
        let flatMatrices = matrices.flatMap { [$0.columns.0, $0.columns.1, $0.columns.2, $0.columns.3] }
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }
        for (index, mesh) in plan.meshes.enumerated() where mesh.material.isOpaque {
            guard let material = mesh.material.shadowCaster, let variant = material.pass.variant,
                  let meshBuffers = buffers[index], let pipeline = pipeline(for: mesh, material: material, variant: variant),
                  let bound = textures(of: material, assetTexture: assetTexture) else { continue }
            if let program = meshUniforms[index], program.size > 0 {
                let key = ModelMaterialUniforms.PassKey(
                    world: caster.world, view: frame.camera.view, viewProjection: placement.shaderViewProjection,
                    eye: frame.eyePosition, screen: frame.screenSize, target: frame.screenSize,
                    textures: bound.map { SIMD4(Float($0.texture.width), Float($0.texture.height), 0, 0) })
                program.update(key: key, frame: frame, values: values) {
                    var pass = BuiltinPassContext(targetSize: frame.screenSize)
                    pass.place(placement)
                    for entry in bound {
                        pass.textures[entry.slot] = EffectGraphRenderer.textureInfo(for: entry.texture, contentSize: nil)
                    }
                    return pass
                }
                program.write(flatMatrices, member: "g_ViewportViewProjectionMatrices")
                if let bones { program.writeBones(bones) }
                program.bytes.withUnsafeBytes { raw in uniformArena.bind(raw, index: 0, to: encoder, commandBuffer: commandBuffer) }
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(meshBuffers.vertices, offset: 0, index: SceneModelRenderer.meshBuffer)
            encoder.setVertexBuffer(zeroAttributes, offset: 0, index: EffectGraphRenderer.zeroBuffer)
            for entry in bound {
                encoder.setFragmentTexture(entry.texture, index: entry.slot)
                encoder.setFragmentSamplerState(entry.sampler, index: entry.slot)
                encoder.setVertexTexture(entry.texture, index: entry.slot)
                encoder.setVertexSamplerState(entry.sampler, index: entry.slot)
            }
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                          indexType: mesh.usesUInt32Indices ? .uint32 : .uint16,
                                          indexBuffer: meshBuffers.indices, indexBufferOffset: 0,
                                          instanceCount: matrices.count)
            casterDraws += 1
        }
    }

    private func uniforms(for id: String, plan: SceneModelPlan) -> [ModelMaterialUniforms?] {
        if let existing = uniforms[id], existing.count == plan.meshes.count { return existing }
        let made = plan.meshes.map { mesh in
            mesh.material.shadowCaster.map { ModelMaterialUniforms(layout: $0.pass.variant?.uniforms, constants: $0.pass.constants) }
        }
        uniforms[id] = made
        return made
    }

    private typealias BoundTexture = (slot: Int, texture: MTLTexture, sampler: MTLSamplerState)

    /// The shadow variant's textures: the material's by slot, the empty morph texture for the
    /// engine's; nil when one isn't there this frame.
    private func textures(of material: ModelMaterialPlan,
                          assetTexture: (String, SceneMetalTextureSource) -> MTLTexture?) -> [BoundTexture]? {
        var bound: [BoundTexture] = []
        for slot in material.pass.variant?.textureSlots ?? [] {
            let sampler = material.clampedSlots.contains(slot) ? clampSampler : repeatSampler
            switch material.pass.textures[slot] {
            case .asset(let key, let source)?:
                guard let texture = assetTexture(key, source) else { return nil }
                bound.append((slot, texture, sampler))
            case nil:
                bound.append((slot, emptyMorphTexture, clampSampler))
            default:
                return nil
            }
        }
        return bound
    }

    // MARK: - Pipelines

    static func pipelineKey(_ mesh: SceneModelPlan.Mesh, material: ModelMaterialPlan) -> String {
        "shadow|\(material.pass.variantKey)|\(mesh.format.rawValue)|\(material.blending)|d\(SceneShadowAtlas.pixelFormat.rawValue)"
    }

    /// Blocks until every caster mesh of `plan` compiled or failed (tests). True when all are ready.
    func waitUntilReady(_ plan: SceneModelPlan, timeout: TimeInterval = 120) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        for mesh in plan.meshes where mesh.material.isOpaque {
            guard let material = mesh.material.shadowCaster, let variant = material.pass.variant else { continue }
            let key = Self.pipelineKey(mesh, material: material)
            while pipeline(for: mesh, material: material, variant: variant) == nil {
                if pipelineLock.withLock({ failed.contains(key) }) || Date() > deadline { return false }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        return true
    }

    private func pipeline(for mesh: SceneModelPlan.Mesh, material: ModelMaterialPlan,
                          variant: TranslatedShaderVariant) -> MTLRenderPipelineState? {
        let key = Self.pipelineKey(mesh, material: material)
        let state: (pipeline: MTLRenderPipelineState?, busy: Bool) = pipelineLock.withLock {
            (pipelines[key], pending.contains(key) || failed.contains(key))
        }
        if let pipeline = state.pipeline { return pipeline }
        guard !state.busy else { return nil }
        pipelineLock.withLock { _ = pending.insert(key) }
        let device = self.device, archive = self.archive, format = mesh.format, name = material.materialPath
        compileQueue.async { [weak self] in
            let result: MTLRenderPipelineState?
            do {
                result = try EffectGraphRenderer.makePipeline(Self.pipelineDescriptor(variant, format: format, device: device),
                                                              device: device, archive: archive, key: key)
            } catch {
                OWELog.error(.shader, "Model material \(name) can't draw into the shadow atlas; the mesh casts no shadow: \(error)")
                result = nil
            }
            guard let self else { return }
            self.pipelineLock.withLock {
                self.pending.remove(key)
                if let result { self.pipelines[key] = result } else { self.failed.insert(key) }
            }
        }
        return nil
    }

    /// A shadow variant's pipeline: depth only, the mesh's vertex layout. An alpha-to-coverage
    /// caster discards below half coverage (`shadowcaster.frag`); the atlas has one sample, so
    /// coverage itself would change nothing.
    static func pipelineDescriptor(_ variant: TranslatedShaderVariant, format: MDLVertexFormat,
                                   device: MTLDevice) throws -> MTLRenderPipelineDescriptor {
        let vertexLibrary = try device.makeLibrary(source: variant.vertexMSL, options: nil)
        let fragmentLibrary = try device.makeLibrary(source: variant.fragmentMSL, options: nil)
        guard let vertex = vertexLibrary.makeFunction(name: "main0"),
              let fragment = fragmentLibrary.makeFunction(name: "main0") else {
            throw ShaderCompilerError.failed(step: "metal", output: "entry point main0 missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.depthAttachmentPixelFormat = SceneShadowAtlas.pixelFormat
        descriptor.rasterSampleCount = 1
        descriptor.inputPrimitiveTopology = .triangle
        descriptor.vertexDescriptor = SceneModelRenderer.vertexDescriptor(for: vertex, attributes: variant.attributes, format: format)
        return descriptor
    }
}
