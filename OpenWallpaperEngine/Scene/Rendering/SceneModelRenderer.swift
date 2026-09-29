import Metal
import simd

/// Draws model objects (docs/models-plan.md §2.6–2.8, §4.3 M5/M6): WE's model draw (0x1402222a0)
/// at the model's place in the object loop (`SceneModelDrawing`). Per model: its skeleton posed by
/// its animation layers (only while it is visible, 0x14021c480), the bounding sphere of its box
/// culled against the camera's frustum (0x1401e5a10), then each mesh in WE's draw-list order
/// through its material (`ModelMaterialPlan`) with its own pass state.
///
/// Each mesh is one interleaved vertex buffer and a triangle list, as the `.mdl` has them; the
/// vertex descriptor maps the translated shader's `a_*` inputs onto the mesh's attributes by their
/// D3D semantic, as WE's input layout does (0x1400d81a3), and an input the mesh lacks reads zeros
/// (open point 11). Pipelines compile off the render thread, keyed by the depth format, and share
/// the effects' binary archive; a mesh draws nothing until its pipeline is ready, and a pipeline
/// that fails is logged once. Call on the render thread, apart from the compiles.
final class SceneModelRenderer: SceneModelDrawing {
    private let device: MTLDevice
    private let archive: EffectPipelineArchive?
    private let uniformArena: SceneUniformArena
    private let zeroAttributes: MTLBuffer
    private let clampSampler: MTLSamplerState
    private let repeatSampler: MTLSamplerState
    /// `_rt_shadowAtlas`'s comparison sampler (`SceneShadowAtlas.makeSampler`).
    private let shadowSampler: MTLSamplerState
    /// WE's "morph" texture stand-in for a `MORPHING` mesh without targets, and the meshes' own.
    private let emptyMorphTexture: MTLTexture
    let morphTextures: SceneMorphTextureCache

    private let compileQueue = DispatchQueue(label: "owe.model-pipelines", qos: .userInitiated, attributes: .concurrent)
    /// Owns `pipelines`, `pending` and `failed`, which compile threads write.
    private let pipelineLock = NSLock()
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var pending = Set<String>()
    private var failed = Set<String>()

    /// The content's model objects by id. Render thread only.
    private var objects: [String: SceneModelObject] = [:]
    /// Each plan's GPU buffers, shared by the objects drawing it.
    private var buffers: [ObjectIdentifier: [MeshBuffers?]] = [:]
    /// Per object: each mesh's uniforms (the world differs per object).
    private var uniforms: [String: [ModelMaterialUniforms]] = [:]
    /// Per object with bones: its skeleton in motion (the same animator puppets use).
    private var animators: [String: ScenePuppetAnimator] = [:]
    /// The frame time each animator last advanced at (one evaluation a frame), and its pose's
    /// `g_Bones` components then, which the shadow, reflection and scene passes all write.
    private var advancedAt: [String: Double] = [:]
    private var boneComponents: [String: [Float]] = [:]
    /// Per plan with changing geometry (`SceneModelPlan.geometry`): the revision its buffers hold
    /// and each mesh's index count there.
    private var geometryRevisions: [ObjectIdentifier: UInt64] = [:]
    private var geometryIndexCounts: [ObjectIdentifier: [Int: Int]] = [:]
    /// Per plan and mesh: the triangle list its buffers were last made with and its largest index
    /// (`applyData` often changes only the vertices).
    private var largestIndices: [ObjectIdentifier: [Int: (indices: Data, count: Int, largest: Int?)]] = [:]
    /// The plans a script's `replaceData` put in place of the content's, by the content's plan.
    private var replacedPlans: [ObjectIdentifier: SceneModelPlan] = [:]

    struct MeshBuffers {
        /// The positions when the mesh's vertices are split (`SceneModelVertexStreams`), else the
        /// interleaved vertices.
        let vertices: MTLBuffer
        /// The other attributes of split vertices; nil when they are one stream.
        var attributes: MTLBuffer? = nil
        let indices: MTLBuffer

        var allocatedSize: Int { vertices.allocatedSize + (attributes?.allocatedSize ?? 0) + indices.allocatedSize }

        /// Binds the vertex streams the mesh's pipelines read (`vertexDescriptor`).
        func bindVertices(to encoder: MTLRenderCommandEncoder) {
            encoder.setVertexBuffer(vertices, offset: 0, index: SceneModelRenderer.meshBuffer)
            if let attributes { encoder.setVertexBuffer(attributes, offset: 0, index: SceneModelRenderer.meshAttributesBuffer) }
        }
    }

    /// The layers whose image the content's models sample (`SceneModelDraw.layerComposite`).
    private(set) var compositeLayerIDs = Set<String>()

    /// The frame's built-ins and materials' bound constants, shared by the frame's draws.
    private let frameValues = SceneModelFrameValues()
    /// The last camera's planes: every model of a pass is culled against the same camera.
    private var lastFrustum: (viewProjection: simd_float4x4, frustum: SceneModelCulling.Frustum)?

    /// Meshes drawn and models culled, for tests and diagnostics.
    private(set) var drawsEncoded = 0
    private(set) var modelsCulled = 0
    /// Meshes drawn per model object, and the model objects culled, since the content was set
    /// (tests, diagnostics).
    private(set) var meshDraws: [String: Int] = [:]
    private(set) var culledModels = Set<String>()
    /// Whether each plan's meshes all end in an opaque distance fog (`SceneModelFogCulling`).
    private var fogsEveryMesh: [ObjectIdentifier: Bool] = [:]
    /// Compiled pipelines.
    var pipelineCount: Int { pipelineLock.withLock { pipelines.count } }
    /// Bytes of the meshes' buffers (diagnostics).
    var allocatedBytes: Int {
        buffers.values.reduce(0) { total, meshes in
            meshes.reduce(total) { $0 + ($1.map { $0.allocatedSize } ?? 0) }
        }
    }

    init?(device: MTLDevice, archive: EffectPipelineArchive?) {
        self.device = device
        self.archive = archive
        uniformArena = SceneUniformArena(device: device)
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
        guard let clamp = sampler(.clampToEdge), let wrap = sampler(.repeat), let zero = device.makeBuffer(length: 64),
              let morphTexture = device.makeTexture(descriptor: morph),
              let shadow = SceneShadowAtlas.makeSampler(device: device) else { return nil }
        morphTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt16](repeating: 0, count: 4),
                             bytesPerRow: 8)
        clampSampler = clamp
        repeatSampler = wrap
        shadowSampler = shadow
        zeroAttributes = zero
        emptyMorphTexture = morphTexture
        morphTextures = SceneMorphTextureCache(device: device)
    }

    // MARK: - SceneModelDrawing

    func setContent(_ models: [SceneModelObject], content: SceneMetalContent) {
        objects = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        compositeLayerIDs = Set(models.flatMap { $0.plan?.compositeLayerIDs ?? [] })
        buffers.removeAll()
        geometryRevisions.removeAll()
        geometryIndexCounts.removeAll()
        largestIndices.removeAll()
        replacedPlans.removeAll()
        uniforms.removeAll()
        animators.removeAll()
        advancedAt.removeAll()
        boneComponents.removeAll()
        meshDraws.removeAll()
        culledModels.removeAll()
        fogsEveryMesh.removeAll()
        morphTextures.removeAll()
    }

    /// A model a script created (`SceneScriptCreatedObject.model`), drawn from its next frame.
    func add(_ model: SceneModelObject) {
        objects[model.id] = model
        uniforms.removeValue(forKey: model.id)
        animators.removeValue(forKey: model.id)
        boneComponents.removeValue(forKey: model.id)
        compositeLayerIDs.formUnion(model.plan?.compositeLayerIDs ?? [])
    }

    /// A model a script destroyed.
    func remove(_ id: String) {
        objects.removeValue(forKey: id)
        uniforms.removeValue(forKey: id)
        animators.removeValue(forKey: id)
        advancedAt.removeValue(forKey: id)
        boneComponents.removeValue(forKey: id)
    }

    func isTranslucent(_ model: SceneModelObject) -> Bool {
        model.plan?.isTranslucent ?? false
    }

    func draw(_ model: SceneModelObject, _ draw: SceneModelDraw, encoder: MTLRenderCommandEncoder,
              commandBuffer: MTLCommandBuffer) {
        guard let authored = model.plan else { return }
        let plan = currentPlan(authored, objectID: model.id)
        // WE poses a visible model every frame, culled or not (0x14021c480).
        let bones = advance(model, plan: plan, frame: draw.frame, values: draw.values)
        let viewFrustum = frustum(draw.camera.viewProjection)
        guard viewFrustum.contains(SceneModelCulling.Sphere(plan.bounds, world: draw.world)) else {
            modelsCulled += 1
            culledModels.insert(model.id)
            return
        }
        if let clear = draw.clearColor, isHiddenByFog(plan, draw, clearColor: clear) {
            modelsCulled += 1
            culledModels.insert(model.id)
            return
        }
        let meshBuffers = self.meshBuffers(plan)
        let meshUniforms = self.uniforms(for: model.id, plan: plan)
        let depthFormat = draw.depth == nil ? MTLPixelFormat.invalid : SceneDepthStates.format
        let placement = draw.placement
        var drew = false
        for (index, mesh) in plan.meshes.enumerated() {
            // A mesh wholly outside the view draws nothing (its triangles are all clipped).
            if let bounds = mesh.bounds, !viewFrustum.contains(SceneModelCulling.Sphere(bounds, world: draw.world)) { continue }
            guard let buffers = meshBuffers[index], mesh.material.pass.variant != nil,
                  let pipeline = pipeline(for: mesh, pixelFormat: draw.pixelFormat, sampleCount: draw.sampleCount,
                                          depthFormat: depthFormat),
                  let bound = textures(of: mesh.material, draw, morph: morphTextures.texture(plan, mesh: mesh.index))
            else { continue }
            let program = meshUniforms[index]
            if program.size > 0 {
                let key = ModelMaterialUniforms.PassKey(
                    world: draw.world, view: draw.camera.view, viewProjection: placement.shaderViewProjection,
                    eye: draw.frame.eyePosition, screen: draw.frame.screenSize, target: draw.frame.screenSize,
                    textures: bound.map { SIMD4(Float($0.texture.width), Float($0.texture.height),
                                                $0.contentSize?.x ?? 0, $0.contentSize?.y ?? 0) })
                program.update(key: key, frame: draw.frame, values: draw.values, shared: (frameValues, mesh.material)) {
                    var pass = BuiltinPassContext(targetSize: draw.frame.screenSize)
                    pass.place(placement)
                    for entry in bound {
                        pass.textures[entry.slot] = EffectGraphRenderer.textureInfo(for: entry.texture, contentSize: entry.contentSize)
                    }
                    return pass
                }
                if let bones { program.writeBones(bones) }
                if mesh.material.meshCombos.morphing { program.writeMorphs(morphUniforms(model.id, plan: plan, mesh: mesh)) }
            }
            encoder.setRenderPipelineState(pipeline)
            if let depth = draw.depth {
                depth.apply(mesh.material.raster, to: encoder)
            } else {
                encoder.setCullMode(mesh.material.raster.cullMode)
            }
            // The planar reflection's mirror flips every triangle's winding (WE flips its cull mode).
            encoder.setFrontFacing(draw.mirrored ? .clockwise : Self.frontFacing)
            buffers.bindVertices(to: encoder)
            encoder.setVertexBuffer(zeroAttributes, offset: 0, index: EffectGraphRenderer.zeroBuffer)
            for entry in bound {
                encoder.setFragmentTexture(entry.texture, index: entry.slot)
                encoder.setFragmentSamplerState(entry.sampler, index: entry.slot)
                encoder.setVertexTexture(entry.texture, index: entry.slot)
                encoder.setVertexSamplerState(entry.sampler, index: entry.slot)
            }
            if program.size > 0 {
                program.bytes.withUnsafeBytes { raw in uniformArena.bind(raw, index: 0, to: encoder, commandBuffer: commandBuffer) }
            }
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount(of: mesh, in: plan),
                                          indexType: mesh.usesUInt32Indices ? .uint32 : .uint16,
                                          indexBuffer: buffers.indices, indexBufferOffset: 0)
            drawsEncoded += 1
            meshDraws[model.id, default: 0] += 1
            drew = true
        }
        // A pass without depth doesn't set its own cull state for the draws after.
        if drew, draw.depth == nil { encoder.setCullMode(.none) }
    }

    /// WE's front faces (`FrontCounterClockwise = FALSE`, 0x1400990f9): clockwise on D3D's
    /// y-down render target, which is counter-clockwise in clip space, where Metal decides the
    /// winding. A `.mdl` winds its outward faces counter-clockwise (right-handed), and WE draws
    /// them (3734636606's boxes are closed from outside).
    static let frontFacing = MTLWinding.counterClockwise

    // MARK: - Bones and attachments

    /// The model's animator, made on first use; nil for a model without bones.
    func animator(for id: String) -> ScenePuppetAnimator? {
        if let animator = animators[id] { return animator }
        guard let model = objects[id], let plan = model.plan,
              let animator = plan.makeAnimator(layers: model.animationLayers, objectName: model.name,
                                               rootMotion: model.authored.rootMotion) else { return nil }
        animators[id] = animator
        return animator
    }

    /// Poses the model once this frame (only while visible, which is when the renderer draws it)
    /// and returns its `g_Bones` components; nil for a model without bones. The shadow pass poses
    /// its casters so before the scene pass draws them. `objectWorld` is the object's world
    /// matrix, which root motion moves the object through.
    func advance(_ model: SceneModelObject, plan: SceneModelPlan, frame: BuiltinFrameContext,
                 values: SceneValueContext, objectWorld: simd_float4x4 = matrix_identity_float4x4) -> [Float]? {
        guard let animator = animator(for: model.id) else { return nil }
        if advancedAt[model.id] != frame.time {
            advancedAt[model.id] = frame.time
            animator.advance(delta: Float(frame.frameTime), values: values, objectWorld: objectWorld)
            boneComponents[model.id] = animator.pose.boneComponents
        }
        if let components = boneComponents[model.id] { return components }
        let components = animator.pose.boneComponents
        boneComponents[model.id] = components
        return components
    }

    /// Whether the model's clips move it (root motion), so its world is needed as it advances.
    func hasRootMotion(_ id: String) -> Bool { animator(for: id)?.stack.hasRootMotion ?? false }

    /// What root motion moved the model by (`SceneRootMotion`); nil when it has none.
    func rootMotion(of id: String) -> SceneRootMotion.Motion? {
        guard let motion = animators[id]?.rootMotion, !motion.isZero else { return nil }
        return motion
    }

    /// The model objects with a posed skeleton (script feedback).
    var riggedObjectIDs: [String] { objects.values.filter { $0.plan?.skeleton?.bones.isEmpty == false }.map(\.id) }

    /// A script's call on a model's animation layers (models have no bone API, §2.8).
    func perform(_ command: SceneScriptRigCommand, on id: String) {
        switch command {
        case .setLocal, .setWorld, .setBlendShape: return
        default: animator(for: id)?.perform(command)
        }
    }

    /// Bone attachments on models (0x1402248c0): `boneWorld · MDAT matrix` of the parent model's
    /// attachment point, as its animator last posed it (its bind pose before the first frame).
    var attachments: SceneModelAttachments {
        SceneModelAttachments { [unowned self] id in
            guard let plan = self.objects[id]?.plan, !plan.attachments.isEmpty, let animator = self.animator(for: id) else {
                return nil
            }
            return (plan.attachments, animator.worlds)
        }
    }

    // MARK: - Culling

    /// The model lies wholly beyond the distance fog's end, which paints it the clear colour
    /// (`SceneModelFogCulling`).
    private func isHiddenByFog(_ plan: SceneModelPlan, _ draw: SceneModelDraw, clearColor: SIMD3<Float>) -> Bool {
        let fog = draw.frame.lighting.fog
        guard SceneModelFogCulling.coversWithClearColor(fog, clearColor: clearColor),
              SceneModelFogCulling.isBeyondFog(plan.bounds, world: draw.world, eye: draw.frame.eyePosition, fog: fog)
        else { return false }
        let key = ObjectIdentifier(plan)
        if let known = fogsEveryMesh[key] { return known }
        let fogs = SceneModelFogCulling.fogsEveryMesh(plan)
        fogsEveryMesh[key] = fogs
        return fogs
    }

    /// WE's cull test (0x1402222f2…0x1401e5a10, `SceneModelCulling`): the box's min and max corners
    /// through the world matrix, the sphere through them (centre their midpoint, radius half their
    /// distance), kept unless it lies wholly outside one of the frustum's six planes (WE's clip
    /// space: x, y in ±w, z in 0…w).
    private func frustum(_ viewProjection: simd_float4x4) -> SceneModelCulling.Frustum {
        if let lastFrustum, lastFrustum.viewProjection == viewProjection { return lastFrustum.frustum }
        let frustum = SceneModelCulling.Frustum(viewProjection)
        lastFrustum = (viewProjection, frustum)
        return frustum
    }

    static func isInsideFrustum(_ bounds: MDLBounds, world: simd_float4x4, viewProjection: simd_float4x4) -> Bool {
        SceneModelCulling.Frustum(viewProjection).contains(SceneModelCulling.Sphere(bounds, world: world))
    }

    // MARK: - Resources

    /// The plan `plan`'s model draws with now: a new one once a script replaced its data
    /// (`SceneModelGeometrySource.replacement`); the object's uniforms are made again for it.
    func currentPlan(_ plan: SceneModelPlan, objectID: String) -> SceneModelPlan {
        let key = ObjectIdentifier(plan)
        let current = replacedPlans[key] ?? plan
        guard let replacement = current.geometry?.replacement(for: current) else { return current }
        forget(current)
        replacedPlans[key] = replacement
        uniforms.removeValue(forKey: objectID)
        return replacement
    }

    /// Drops what the renderer made for `plan` once another plan draws in its place. The caches
    /// are keyed by the plan's `ObjectIdentifier`, which a later plan reuses once this one is
    /// freed: kept, a new plan would take this one's buffers (another mesh count) as its own.
    private func forget(_ plan: SceneModelPlan) {
        let key = ObjectIdentifier(plan)
        buffers[key] = nil
        geometryRevisions[key] = nil
        geometryIndexCounts[key] = nil
        largestIndices[key] = nil
        morphTextures.remove(plan)
    }

    func meshBuffers(_ plan: SceneModelPlan) -> [MeshBuffers?] {
        let key = ObjectIdentifier(plan)
        if let source = plan.geometry { refreshGeometry(plan, from: source) }
        if let existing = buffers[key] { return existing }
        let made = plan.meshes.map { mesh -> MeshBuffers? in
            makeBuffers(mesh, of: plan, vertices: mesh.vertexData, indices: mesh.indexData, indexCount: mesh.indexCount)
        }
        buffers[key] = made
        return made
    }

    /// A script's `applyData` since the last draw: new buffers for the plan's meshes (the frames
    /// in flight keep the ones they encoded). Geometry that no longer matches the plan's meshes
    /// (`replaceData` with other shapes) keeps what was drawn, logged once.
    private func refreshGeometry(_ plan: SceneModelPlan, from source: SceneModelGeometrySource) {
        let key = ObjectIdentifier(plan)
        guard let geometry = source.geometry(newerThan: geometryRevisions[key] ?? 0) else { return }
        geometryRevisions[key] = geometry.revision
        guard plan.meshes.allSatisfy({ $0.index < geometry.meshes.count }) else {
            OWELog.error(.scene, "\(plan.path): its model data no longer has the shapes it was planned with; kept as drawn")
            return
        }
        var counts: [Int: Int] = [:]
        buffers[key] = plan.meshes.map { mesh -> MeshBuffers? in
            let data = geometry.meshes[mesh.index]
            counts[mesh.index] = data.indexCount
            guard !data.vertices.isEmpty, !data.indices.isEmpty else { return nil }
            return makeBuffers(mesh, of: plan, vertices: data.vertices, indices: data.indices, indexCount: data.indexCount)
        }
        geometryIndexCounts[key] = counts
    }

    /// A mesh's buffers. A script's model data may index past its vertices (`createModelData`
    /// takes any index, `applyData` may shrink the vertices under them), and Metal doesn't define
    /// such a fetch; D3D11, WE's API, reads zeros there, so the vertices are padded with zeros up
    /// to the largest index drawn.
    private func makeBuffers(_ mesh: SceneModelPlan.Mesh, of plan: SceneModelPlan, vertices: Data, indices: Data,
                             indexCount: Int) -> MeshBuffers? {
        guard !vertices.isEmpty, !indices.isEmpty else { return nil }
        let key = ObjectIdentifier(plan)
        let largest: Int?
        if let known = largestIndices[key]?[mesh.index], known.count == indexCount, known.indices == indices {
            largest = known.largest
        } else {
            largest = Self.largestIndex(indices, uint32: mesh.usesUInt32Indices, count: indexCount)
            largestIndices[key, default: [:]][mesh.index] = (indices, indexCount, largest)
        }
        let stride = mesh.format.stride
        let needed = stride > 0 ? (largest.map { ($0 + 1) * stride } ?? 0) : 0
        var padded = vertices
        if needed > padded.count { padded.append(Data(count: needed - padded.count)) }
        guard let indexBuffer = indices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) })
        else { return nil }
        if let streams = SceneModelVertexStreams(mesh.format), stride > 0 {
            let count = padded.count / stride
            guard count > 0, let positions = device.makeBuffer(length: count * streams.positionStride),
                  let attributes = device.makeBuffer(length: count * streams.attributeStride) else { return nil }
            padded.withUnsafeBytes { streams.split($0, positions: positions.contents(), attributes: attributes.contents()) }
            return MeshBuffers(vertices: positions, attributes: attributes, indices: indexBuffer)
        }
        guard let vertexBuffer = padded.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) })
        else { return nil }
        return MeshBuffers(vertices: vertexBuffer, indices: indexBuffer)
    }

    /// The largest of the first `count` indices (fewer when the list is shorter); nil without any.
    static func largestIndex(_ indices: Data, uint32: Bool, count: Int) -> Int? {
        indices.withUnsafeBytes { raw -> Int? in
            let size = uint32 ? 4 : 2
            let available = min(count, raw.count / size)
            guard available > 0 else { return nil }
            var largest = 0
            for index in 0..<available {
                let value = uint32 ? Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
                    : Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self)))
                largest = max(largest, value)
            }
            return largest
        }
    }

    /// How many indices of `mesh` draw: its plan's, or what its model data has now.
    func indexCount(of mesh: SceneModelPlan.Mesh, in plan: SceneModelPlan) -> Int {
        geometryIndexCounts[ObjectIdentifier(plan)]?[mesh.index] ?? mesh.indexCount
    }

    private func uniforms(for id: String, plan: SceneModelPlan) -> [ModelMaterialUniforms] {
        if let existing = uniforms[id], existing.count == plan.meshes.count { return existing }
        let made = plan.meshes.map { ModelMaterialUniforms(layout: $0.material.pass.variant?.uniforms, constants: $0.material.pass.constants) }
        uniforms[id] = made
        return made
    }

    private typealias BoundTexture = (slot: Int, texture: MTLTexture, sampler: MTLSamplerState, contentSize: SIMD2<Float>?)

    /// The textures the mesh's pass reads this frame; nil when one isn't there.
    private func textures(of material: ModelMaterialPlan, _ draw: SceneModelDraw, morph: MTLTexture?) -> [BoundTexture]? {
        var bound: [BoundTexture] = []
        for slot in material.pass.variant?.textureSlots ?? [] {
            let sampler = material.clampedSlots.contains(slot) ? clampSampler : repeatSampler
            guard let input = material.pass.textures[slot] else {
                if material.meshCombos.morphing, slot == ModelMeshCombos.morphSlot {
                    bound.append((slot, morph ?? emptyMorphTexture, clampSampler, nil))
                }
                continue
            }
            switch input {
            case .asset(let key, let source):
                guard let texture = draw.assetTexture(key, source) else { return nil }
                bound.append((slot, texture, sampler, source.contentSize))
            case .mipMappedFrameBuffer:
                guard let texture = draw.mipMappedFrameBuffer else { return nil }
                bound.append((slot, texture, clampSampler, nil))
            case .fbo(SceneShadowAtlas.name):
                guard let atlas = draw.shadowAtlas else { return nil }
                bound.append((slot, atlas, shadowSampler, nil))
            case .fbo(ScenePlanarReflection.name):
                guard let reflection = draw.planarReflection else { return nil }
                bound.append((slot, reflection, clampSampler, nil))
            case .fbo(SceneLightCookie.name):
                // The last packed cookie spot's texture. Without one WE's alias is empty, which
                // D3D reads as zeros: the zero texel stands in.
                if let cookie = draw.frame.lighting.cookie, let texture = draw.assetTexture(cookie.key, cookie.source) {
                    bound.append((slot, texture, clampSampler, cookie.source.contentSize))
                } else {
                    bound.append((slot, emptyMorphTexture, clampSampler, nil))
                }
            case .fbo(let name):
                guard let id = ModelMaterialPlanBuilder.compositeLayerID(name), let texture = draw.layerComposite(id) else {
                    return nil
                }
                // Render targets clamp, as the scene's own do [I].
                bound.append((slot, texture, clampSampler, nil))
            case .current, .previous, .sceneSnapshot:
                return nil
            }
        }
        return bound
    }

    /// Memory pressure: drops free uniform chunks.
    func trimMemory() {
        uniformArena.trim()
    }

    // MARK: - Pipelines

    /// The mesh's positions, or its interleaved vertices when they are one stream.
    static let meshBuffer = EffectGraphRenderer.positionBuffer
    /// The mesh's other attributes when its vertices are split (`SceneModelVertexStreams`).
    static let meshAttributesBuffer = 27

    static func pipelineKey(_ mesh: SceneModelPlan.Mesh, pixelFormat: MTLPixelFormat, sampleCount: Int,
                            depthFormat: MTLPixelFormat) -> String {
        "model|\(mesh.material.pass.variantKey)|\(mesh.format.rawValue)|\(mesh.material.blending)|\(pixelFormat.rawValue)"
            + "|x\(sampleCount)|d\(depthFormat.rawValue)"
    }

    /// Blocks until every mesh's pipeline compiled or failed (tests, prewarming). True when all are ready.
    func waitUntilReady(_ plan: SceneModelPlan, pixelFormat: MTLPixelFormat, sampleCount: Int = 1,
                        depthFormat: MTLPixelFormat = SceneDepthStates.format, timeout: TimeInterval = 120) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        for mesh in plan.meshes {
            let key = Self.pipelineKey(mesh, pixelFormat: pixelFormat, sampleCount: sampleCount, depthFormat: depthFormat)
            while pipeline(for: mesh, pixelFormat: pixelFormat, sampleCount: sampleCount, depthFormat: depthFormat) == nil {
                if pipelineLock.withLock({ failed.contains(key) }) || Date() > deadline { return false }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        return true
    }

    private func pipeline(for mesh: SceneModelPlan.Mesh, pixelFormat: MTLPixelFormat, sampleCount: Int,
                          depthFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = Self.pipelineKey(mesh, pixelFormat: pixelFormat, sampleCount: sampleCount, depthFormat: depthFormat)
        let state: (pipeline: MTLRenderPipelineState?, busy: Bool) = pipelineLock.withLock {
            (pipelines[key], pending.contains(key) || failed.contains(key))
        }
        if let pipeline = state.pipeline { return pipeline }
        if !state.busy, let variant = mesh.material.pass.variant {
            compile(variant, mesh: mesh, pixelFormat: pixelFormat, sampleCount: sampleCount, depthFormat: depthFormat, key: key)
        }
        return nil
    }

    private func compile(_ variant: TranslatedShaderVariant, mesh: SceneModelPlan.Mesh, pixelFormat: MTLPixelFormat,
                         sampleCount: Int, depthFormat: MTLPixelFormat, key: String) {
        pipelineLock.withLock { _ = pending.insert(key) }
        let device = self.device
        let archive = self.archive
        let format = mesh.format
        let blending = mesh.material.blending
        let material = mesh.material.materialPath
        compileQueue.async { [weak self] in
            let result: MTLRenderPipelineState?
            do {
                result = try EffectGraphRenderer.makePipeline(
                    Self.pipelineDescriptor(variant, format: format, blending: blending, pixelFormat: pixelFormat,
                                            sampleCount: sampleCount, depthFormat: depthFormat, device: device),
                    device: device, archive: archive, key: key)
            } catch {
                OWELog.error(.shader, "Model material \(material) can't draw through its shader; the mesh draws nothing: \(error)")
                result = nil
            }
            guard let self else { return }
            self.pipelineLock.withLock {
                self.pending.remove(key)
                if let result { self.pipelines[key] = result } else { self.failed.insert(key) }
            }
        }
    }

    /// The pipeline of a mesh's variant: WE's blending (`alphatocoverage` as Metal's alpha to
    /// coverage, without blending), the mesh's vertex layout.
    static func pipelineDescriptor(_ variant: TranslatedShaderVariant, format: MDLVertexFormat, blending: String,
                                   pixelFormat: MTLPixelFormat, sampleCount: Int, depthFormat: MTLPixelFormat,
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
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.rasterSampleCount = sampleCount
        descriptor.depthAttachmentPixelFormat = depthFormat
        if blending == "alphatocoverage" {
            descriptor.isAlphaToCoverageEnabled = true
        } else if let blend = EffectGraphRenderer.blendMode(blending) {
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = blend.source
            attachment.sourceAlphaBlendFactor = blend.source
            attachment.destinationRGBBlendFactor = blend.destination
            attachment.destinationAlphaBlendFactor = blend.destination
        }
        descriptor.vertexDescriptor = vertexDescriptor(for: vertex, attributes: variant.attributes, format: format)
        return descriptor
    }

    /// The mesh's interleaved attributes at the locations the translated stage reads them from
    /// (`ShaderPairRewriter.attributeLocations`). An input takes the mesh's attribute of the same
    /// D3D semantic and index (a `vec2 a_TexCoord` reads the first two components of a mesh's
    /// `a_TexCoordVec4`, as WE's input layout binds by semantic [I]); one the mesh lacks reads zeros.
    static func vertexDescriptor(for function: MTLFunction, attributes: [String: Int],
                                 format: MDLVertexFormat) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        var names: [Int: [String]] = [:]
        for (name, location) in attributes { names[location, default: []].append(name) }
        var usesZero = false, usesAttributes = false
        let streams = SceneModelVertexStreams(format)
        for input in function.vertexAttributes ?? [] where input.isActive {
            let element = descriptor.attributes[input.attributeIndex]!
            let isInteger = [.uint, .uint2, .uint3, .uint4, .int, .int2, .int3, .int4].contains(input.attributeType)
            if let attribute = meshAttribute(for: names[input.attributeIndex] ?? [], in: format),
               let offset = format.offset(of: attribute) {
                element.format = ScenePuppetRenderer.vertexFormat(attribute)
                if let streams, let location = streams.location(of: attribute, in: format) {
                    element.offset = location.offset
                    element.bufferIndex = location.stream == 0 ? meshBuffer : meshAttributesBuffer
                    if location.stream == 1 { usesAttributes = true }
                } else {
                    element.offset = offset
                    element.bufferIndex = meshBuffer
                }
            } else {
                element.format = isInteger ? .uint4 : .float4
                element.offset = 0
                element.bufferIndex = EffectGraphRenderer.zeroBuffer
                usesZero = true
            }
        }
        descriptor.layouts[meshBuffer].stride = streams?.positionStride ?? format.stride
        if let streams, usesAttributes { descriptor.layouts[meshAttributesBuffer].stride = streams.attributeStride }
        if usesZero {
            descriptor.layouts[EffectGraphRenderer.zeroBuffer].stride = 16
            descriptor.layouts[EffectGraphRenderer.zeroBuffer].stepFunction = .constant
            descriptor.layouts[EffectGraphRenderer.zeroBuffer].stepRate = 0
        }
        return descriptor
    }

    /// The mesh attribute a shader input named one of `names` reads: the same attribute when the
    /// mesh has it, else the first of the mesh's attributes with the input's semantic and index.
    static func meshAttribute(for names: [String], in format: MDLVertexFormat) -> MDLVertexAttribute? {
        let wanted = names.compactMap(MDLVertexAttribute.named)
        if let exact = wanted.first(where: format.contains) { return exact }
        for shader in wanted {
            if let match = MDLVertexAttribute.all.first(where: {
                format.contains($0) && $0.semantic == shader.semantic && $0.semanticIndex == shader.semanticIndex
            }) { return match }
        }
        return nil
    }
}

/// Bone attachments on model objects (docs/models-plan.md §2.6): M3's `SceneAttachmentProviding`
/// for a child of a model, `world = parentWorld · boneWorld[bone] · attachment matrix · local`
/// (0x1401dd7d0, 0x140224970), with `ScenePuppetAttachments`' matrix rule.
struct SceneModelAttachments: SceneAttachmentProviding {
    /// The parent model's attachment points and bone matrices (model space), by object id.
    let rig: (String) -> (attachments: [MDLAttachment], worlds: [simd_float4x4])?

    func attachmentWorld(_ object: SceneAttachedObject) -> simd_float4x4? {
        guard let (attachments, worlds) = rig(object.parentID) else { return nil }
        return ScenePuppetAttachments.matrix(named: object.attachment, in: attachments, worlds: worlds)
    }
}

/// Several attachment providers asked in turn (models' and puppets'): an object's parent is one
/// of them at most.
struct SceneAttachmentProviders: SceneAttachmentProviding {
    let providers: [SceneAttachmentProviding]

    func attachmentWorld(_ object: SceneAttachedObject) -> simd_float4x4? {
        providers.lazy.compactMap { $0.attachmentWorld(object) }.first
    }
}
