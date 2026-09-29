import Metal
import simd

/// A Puppet Warp image layer's mesh (docs/models-plan.md §2.13, §4.3 P1): an image whose model JSON
/// names a `"puppet"` `.mdl` draws that mesh, textured by its own image, instead of its quad.
///
/// WE puts the mesh where the quad would be: in the scene for a layer without effects, or into the
/// image-sized buffer its effects start from (0x14020ae00 builds the geometry, 0x140206e5e and
/// 0x140209540 the materials). Here the mesh is always drawn into an image-sized albedo target
/// first, WE's `_rt_imageLayerAlbedo_<id>` (0x140207740): cleared to 0, identity model and view,
/// orthographic over the image's pixels. The layer then goes on as an ordinary image layer whose
/// image is that target: its effects, its prelighting (docs/lighting-plan.md §2.3) and its own
/// draw through its material read it. In the bind pose (every bone the identity) the target is the
/// picture the mesh assembles; M6/P2 pose the bones (`ScenePuppetPose`).
///
/// The mesh is the rig's first mesh, the only one WE reads (0x14020aeb9). Its vertices are in the
/// image's pixels, y up, centred on the image (every library rig: `(uv − ½) · size` with v flipped,
/// or an atlas laid out anew). WE scales its texture coordinates by the image's share of a padded
/// texture (0x14020b040); the copy here does the same.
final class ScenePuppetPlan {
    /// The `.mdl` the model JSON names.
    let rigPath: String
    /// The layer material's mesh pass (`ImageMaterialPlanBuilder.buildPuppetMesh`).
    let material: ImageMaterialPlan
    let combos: ImagePuppetCombos
    let format: MDLVertexFormat
    /// The mesh's interleaved vertices, texture coordinates scaled to the image inside the texture.
    let vertexData: Data
    let indexData: Data
    let usesUInt32Indices: Bool
    let indexCount: Int
    /// The image in the mesh's units: its full-resolution pixels (before any texture reduction).
    let imageSize: SIMD2<Float>
    /// The image's texels inside its (possibly padded) texture, from its top-left corner.
    let contentPixels: SIMD2<Int>
    /// Bind-pose bone matrices, parents first (the pose M6 starts from).
    let skeleton: MDLSkeleton
    /// The rig's clips (`MDLA`), which the image's animation layers name.
    let clips: [MDLAnimation]
    /// The image's authored `animationlayers` (`ScenePuppetAnimator` plays them).
    let animationLayers: [WEAnimationLayer]
    /// The rig's attachment points (`MDAT`), which children name in `attachment`.
    let attachments: [MDLAttachment]
    /// The first mesh's blend shapes (`MDMP`) and flags: its "morph_<n>" texture and uniforms.
    let morphs: MDLMorphTargets?
    let meshFlags: UInt32

    var boneCount: Int { combos.boneCount }

    init(rigPath: String, material: ImageMaterialPlan, combos: ImagePuppetCombos, mesh: MDLMesh, vertexData: Data,
         imageSize: SIMD2<Float>, contentPixels: SIMD2<Int>, skeleton: MDLSkeleton, clips: [MDLAnimation] = [],
         animationLayers: [WEAnimationLayer] = [], attachments: [MDLAttachment] = [], morphs: MDLMorphTargets? = nil) {
        self.rigPath = rigPath
        self.material = material
        self.combos = combos
        format = mesh.format
        self.vertexData = vertexData
        indexData = mesh.indexData
        usesUInt32Indices = mesh.usesUInt32Indices
        indexCount = mesh.indexCount
        self.imageSize = imageSize
        self.contentPixels = contentPixels
        self.skeleton = skeleton
        self.clips = clips
        self.animationLayers = animationLayers
        self.attachments = attachments
        self.morphs = morphs
        meshFlags = mesh.flags
    }

    /// The mesh posed by `pose` (skinned as the vertex stage skins it; blend shapes left out), its
    /// bounds in the image's pixels (centred, y up). nil without plain positions, blend indices
    /// and weights.
    func posedBounds(_ pose: ScenePuppetPose) -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        guard let position = MDLVertexAttribute.named("a_Position").flatMap(format.offset(of:)),
              let indices = MDLVertexAttribute.named("a_BlendIndices").flatMap(format.offset(of:)),
              let weights = MDLVertexAttribute.named("a_BlendWeights").flatMap(format.offset(of:)) else { return nil }
        let stride = format.stride
        let count = stride > 0 ? vertexData.count / stride : 0
        guard count > 0 else { return nil }
        var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude), high = -low
        vertexData.withUnsafeBytes { raw in
            func float(_ at: Int) -> Float { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))) }
            for vertex in 0..<count {
                let base = vertex * stride
                let p = SIMD4<Float>(float(base + position), float(base + position + 4), float(base + position + 8), 1)
                var skinned = SIMD4<Float>.zero
                var weighted = false
                for k in 0..<4 {
                    let weight = float(base + weights + 4 * k)
                    let bone = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: base + indices + 4 * k, as: UInt32.self)))
                    guard weight != 0, bone < pose.bones.count else { continue }
                    skinned += weight * (pose.bones[bone] * p)
                    weighted = true
                }
                let point = weighted ? SIMD2(skinned.x, skinned.y) : SIMD2(p.x, p.y)
                guard point.x.isFinite, point.y.isFinite else { continue }
                low = simd_min(low, point)
                high = simd_max(high, point)
            }
        }
        return low.x <= high.x ? (low, high) : nil
    }

    /// The animator that poses this rig from the image's animation layers.
    func makeAnimator() -> ScenePuppetAnimator {
        ScenePuppetAnimator(skeleton: skeleton, clips: clips, layers: animationLayers,
                            morphRig: SceneMorphRig.puppet(morphs, meshFlags: meshFlags)) { [rigPath] layer in
            OWELog.error(.scene, "Puppet rig \(rigPath) has no clip \(layer.animation.map(String.init) ?? "(none)") for "
                         + "animation layer \(layer.name ?? "?"); WE makes no layer for it")
        }
    }

    /// The plan for `model`, the rig of an image drawing `source` (the material's `textures[0]`),
    /// `imageSize` pixels at full resolution. Throws when WE's draw can't be reproduced: no mesh, no
    /// skeleton (`BONECOUNT` 0 declares an empty bone array, which no shader compiles), an albedo
    /// that is a sprite sheet or a video, or a material that doesn't translate.
    static func make(model: MDLModel, rigPath: String, materialPath: String, source: SceneMetalTextureSource,
                     imageSize: SIMD2<Float>, animationLayers: [WEAnimationLayer] = [],
                     builder: ImageMaterialPlanBuilder) throws -> ScenePuppetPlan {
        guard let mesh = model.meshes.first, mesh.vertexCount > 0, mesh.indexCount > 0 else {
            throw ScenePuppetError.unsupported("\(rigPath) has no mesh")
        }
        // Every index drawn must name one of the mesh's vertices, so the draws read inside its buffer.
        if let largest = SceneModelRenderer.largestIndex(mesh.indexData, uint32: mesh.usesUInt32Indices, count: mesh.indexCount),
           largest >= mesh.vertexCount {
            throw ScenePuppetError.unsupported("\(rigPath) indexes vertex \(largest) of its \(mesh.vertexCount)")
        }
        guard let skeleton = model.skeleton, !skeleton.bones.isEmpty else {
            throw ScenePuppetError.unsupported("\(rigPath) has no skeleton")
        }
        guard imageSize.x > 0, imageSize.y > 0 else { throw ScenePuppetError.unsupported("an empty image") }
        let texture: SIMD2<Int>
        let content: SIMD2<Int>
        switch source {
        case let .dxt(compressed):
            texture = SIMD2(compressed.width, compressed.height)
            content = SIMD2(compressed.contentWidth, compressed.contentHeight)
        case let .image(image):
            let size = SceneMetalTextureSource.pixelSize(of: image)
            texture = SIMD2(Int(size.x), Int(size.y))
            content = texture
        case .animated:
            // WE prelights a sprite-sheet puppet through its `SPRITESHEET` albedo copy (0x14020a27e).
            throw ScenePuppetError.unsupported("a sprite-sheet albedo")
        case .video:
            throw ScenePuppetError.unsupported("a video albedo")
        case let .uploaded(info):
            // Plans are made from loaded content; an uploaded image keeps the sizes they read.
            let sheet = info.sheetPixelSize ?? SIMD2<Double>(info.pixelSize)
            texture = SIMD2(Int(sheet.x), Int(sheet.y))
            content = SIMD2(Int(info.pixelSize.x), Int(info.pixelSize.y))
        }
        guard content.x > 0, content.y > 0, texture.x >= content.x, texture.y >= content.y else {
            throw ScenePuppetError.unsupported("an empty texture")
        }
        let combos = ImagePuppetCombos(mesh: mesh, boneCount: skeleton.bones.count)
        guard let material = try builder.buildPuppetMesh(materialPath: materialPath, puppet: combos),
              material.pass.variant != nil else {
            throw ScenePuppetError.unsupported("\(materialPath) draws no image")
        }
        let fraction = SIMD2(Float(content.x) / Float(texture.x), Float(content.y) / Float(texture.y))
        return ScenePuppetPlan(rigPath: rigPath, material: material, combos: combos, mesh: mesh,
                               vertexData: scaledTexCoords(mesh, by: fraction), imageSize: imageSize,
                               contentPixels: content, skeleton: skeleton, clips: model.animations ?? [],
                               animationLayers: animationLayers, attachments: model.attachments ?? [],
                               morphs: model.morphTargets?.first { $0.mesh == 0 })
    }

    /// The vertices with the first texture coordinate's u and v multiplied by `scale`, as WE's copy
    /// does (0x14020afc4…0x14020b100: the offset past position … blend weights, two floats a vertex).
    static func scaledTexCoords(_ mesh: MDLMesh, by scale: SIMD2<Float>) -> Data {
        let texCoords = MDLVertexAttribute.all[7...9]
        guard scale != SIMD2(repeating: 1), texCoords.contains(where: mesh.format.contains) else { return mesh.vertexData }
        let offset = MDLVertexAttribute.all[..<7].reduce(0) { mesh.format.contains($1) ? $0 + $1.byteSize : $0 }
        let stride = mesh.format.stride
        var data = mesh.vertexData
        data.withUnsafeMutableBytes { raw in
            for vertex in 0..<mesh.vertexCount {
                for component in 0..<2 {
                    let at = vertex * stride + offset + 4 * component
                    let value = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
                    raw.storeBytes(of: (value * scale[component]).bitPattern.littleEndian, toByteOffset: at, as: UInt32.self)
                }
            }
        }
        return data
    }
}

enum ScenePuppetError: Error, CustomStringConvertible {
    case unsupported(String)

    var description: String {
        switch self {
        case .unsupported(let reason): return "unsupported: \(reason)"
        }
    }
}

/// The rect of the mesh's space (the image's pixels, centred, y up) a puppet's albedo target
/// covers. WE draws a puppet without effects in the scene through its mesh (docs/models-plan.md
/// §2.13), so vertices a pose moves past the image's rect still draw; with effects the mesh goes
/// into the image-sized buffer the effects start from, which clips it at the image. The canvas of
/// a layer without effects covers the posed mesh as well as the image; the layer's quad grows to
/// it, and every texture laid out through the mesh keeps its layout (the canvas in the image's
/// texels).
struct ScenePuppetCanvas: Equatable {
    var min: SIMD2<Float>
    var max: SIMD2<Float>

    static func image(_ size: SIMD2<Float>) -> ScenePuppetCanvas { ScenePuppetCanvas(min: -size / 2, max: size / 2) }

    var size: SIMD2<Float> { max - min }
    var center: SIMD2<Float> { (min + max) / 2 }

    /// The image's rect grown to cover `bounds`, each side in steps of an eighth of the image (so
    /// a moving pose doesn't resize it every frame), never smaller than `current`.
    static func covering(_ bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?, imageSize: SIMD2<Float>,
                         current: ScenePuppetCanvas?) -> ScenePuppetCanvas {
        let image = ScenePuppetCanvas.image(imageSize)
        var canvas = current ?? image
        guard let bounds else { return canvas }
        let step = imageSize / 8
        func grown(_ over: SIMD2<Float>) -> SIMD2<Float> {
            let steps = (simd_max(over, .zero) / step).rounded(.up)
            return steps * step
        }
        canvas.min = simd_min(canvas.min, image.min - grown(image.min - bounds.min))
        canvas.max = simd_max(canvas.max, image.max + grown(bounds.max - image.max))
        return canvas
    }

    /// Canvas pixels onto the viewport: x min…max → −1…1, y max → −1 (GL clip, the target's first
    /// row, as the translated stage flips y), z ±1000 → 0…1.
    var projection: simd_float4x4 {
        let size = self.size, center = self.center
        return simd_float4x4(columns: (SIMD4(2 / size.x, 0, 0, 0), SIMD4(0, -2 / size.y, 0, 0),
                                       SIMD4(0, 0, 1 / 2000, 0), SIMD4(-2 * center.x / size.x, 2 * center.y / size.y, 0.5, 1)))
    }
}

/// The bone palette a puppet's mesh is drawn with: `g_Bones` and `g_BonesAlpha` (0x140206430).
/// Each bone maps a bind-pose mesh position to its posed one, column vectors (`p′ = bone · p`),
/// i.e. WE's `boneWorld · inverseBind` (row vectors, 0x1402220a0) transposed; the shader reads its
/// upper 3×4 (`mat4x3`). The bind pose is every bone the identity with alpha 1.
struct ScenePuppetPose: Equatable {
    var bones: [simd_float4x4]
    var bonesAlpha: [Float]
    /// The blend shapes' uniforms (`SceneMorphRig.puppetUniforms`); nil for a rig without targets.
    var morph: SceneMorphUniforms? = nil

    static func bind(boneCount: Int) -> ScenePuppetPose {
        ScenePuppetPose(bones: Array(repeating: matrix_identity_float4x4, count: boneCount),
                        bonesAlpha: Array(repeating: 1, count: boneCount))
    }

    /// `g_Bones` as `mat4x3` components: per bone its four columns' x, y and z.
    var boneComponents: [Float] {
        bones.flatMap { bone in
            [bone.columns.0, bone.columns.1, bone.columns.2, bone.columns.3].flatMap { [$0.x, $0.y, $0.z] }
        }
    }
}

/// Draws puppets' meshes into their albedo targets (`ScenePuppetPlan`). Pipelines compile off the
/// render thread and share the effects' binary archive; until a layer's is ready its target stays
/// transparent (the layer shows nothing rather than its unassembled atlas). A target is redrawn
/// only when what it is drawn from changed: the pose, the albedo texture, or a user-bound constant.
/// Call on the render thread, apart from the compiles.
final class ScenePuppetRenderer {
    private let device: MTLDevice
    private let archive: EffectPipelineArchive?
    private let unpremultiply: MTLComputePipelineState
    /// Lays another image-space texture out like the posed mesh (`warp`).
    private let warpPipeline: MTLRenderPipelineState
    private let clampSampler: MTLSamplerState
    private let repeatSampler: MTLSamplerState
    private let zeroAttributes: MTLBuffer
    /// WE's "morph_<n>" texture stand-in for a `MORPHING` mesh without targets.
    private let emptyMorphTexture: MTLTexture
    private let uniformArena: SceneUniformArena

    private let compileQueue = DispatchQueue(label: "owe.puppet-pipelines", qos: .userInitiated, attributes: .concurrent)
    /// Owns `pipelines`, `pending` and `failed`, which compile threads write.
    private let pipelineLock = NSLock()
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var pending = Set<String>()
    private var failed = Set<String>()

    /// The premultiplied draw every puppet shares, grown to the largest image drawn. Render thread only.
    private var scratch: MTLTexture?
    /// Per layer instance. Render thread only.
    private var layers: [String: LayerState] = [:]
    /// Warped textures by layer id and texture key. Render thread only.
    private var warps: [String: [String: WarpState]] = [:]

    private final class WarpState {
        let target: MTLTexture
        var drawnPose: ScenePuppetPose?
        var drawnSource: ObjectIdentifier?
        var drawnCanvas: ScenePuppetCanvas?

        init(target: MTLTexture) { self.target = target }
    }

    private final class LayerState {
        let plan: ScenePuppetPlan
        let uniforms: ImageMaterialUniforms
        let vertices: MTLBuffer
        let indices: MTLBuffer
        /// The rig's "morph_<n>" texture (`SceneMorphTexture.puppet`); nil without targets.
        let morphTexture: MTLTexture?
        var target: MTLTexture?
        var drawnPose: ScenePuppetPose?
        var drawnSource: ObjectIdentifier?
        var drawnCanvas: ScenePuppetCanvas?
        /// The canvas a layer without effects grows to (`canvas(_:layerID:pose:)`).
        var canvas: ScenePuppetCanvas?

        init?(plan: ScenePuppetPlan, device: MTLDevice) {
            self.plan = plan
            // White, opaque and at brightness 1: the layer's own draw applies its colour, alpha and
            // brightness (and a legacy material's factors for them) to the target once.
            uniforms = ImageMaterialUniforms(layout: plan.material.pass.variant?.uniforms, constants: plan.material.pass.constants,
                                             liveFactors: [:])
            guard let vertices = plan.vertexData.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }),
                  let indices = plan.indexData.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) })
            else { return nil }
            self.vertices = vertices
            self.indices = indices
            morphTexture = plan.morphs.flatMap { morphs -> MTLTexture? in
                guard !morphs.targets.isEmpty else { return nil }
                return SceneMorphTexture.makeTexture(SceneMorphTexture.puppet(morphs, meshFlags: plan.meshFlags),
                                                     device: device, label: "morph_puppet")
            }
        }
    }

    /// Mesh draws encoded, for tests and diagnostics.
    private(set) var drawsEncoded = 0
    /// Bytes of the albedo targets and the scratch (diagnostics).
    var allocatedBytes: Int {
        layers.values.reduce(scratch?.allocatedSize ?? 0) { $0 + ($1.target?.allocatedSize ?? 0) }
            + warps.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.target.allocatedSize } }
    }

    static let scratchFormat: MTLPixelFormat = .rgba16Float
    /// The albedo target's format: the layer images' (8-bit, not sRGB-encoded; `SceneTextureUpload`).
    static let targetFormat: MTLPixelFormat = .rgba8Unorm

    init?(device: MTLDevice, archive: EffectPipelineArchive?) {
        self.device = device
        self.archive = archive
        uniformArena = SceneUniformArena(device: device)
        do {
            guard let library = device.makeDefaultLibrary(),
                  let function = library.makeFunction(name: "scenePuppetUnpremultiply"),
                  let warpVertex = library.makeFunction(name: "scenePuppetWarpVertex"),
                  let warpFragment = library.makeFunction(name: "scenePuppetWarpFragment") else { return nil }
            unpremultiply = try device.makeComputePipelineState(function: function)
            let warp = MTLRenderPipelineDescriptor()
            warp.vertexFunction = warpVertex
            warp.fragmentFunction = warpFragment
            warp.colorAttachments[0].pixelFormat = Self.warpFormat
            warpPipeline = try device.makeRenderPipelineState(descriptor: warp)
        } catch {
            OWELog.error(.scene, "The puppet albedo pipeline failed: \(error)")
            return nil
        }
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
        guard let clamp = sampler(.clampToEdge), let wrap = sampler(.repeat),
              let zero = device.makeBuffer(length: 64), let morphTexture = device.makeTexture(descriptor: morph) else { return nil }
        morphTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt16](repeating: 0, count: 4),
                             bytesPerRow: 8)
        clampSampler = clamp
        repeatSampler = wrap
        zeroAttributes = zero
        emptyMorphTexture = morphTexture
    }

    /// Whether the layer's mesh has been drawn into its image (the pipeline was ready).
    func hasDrawn(_ layerID: String) -> Bool { layers[layerID]?.drawnPose != nil }

    /// Drops per-layer state when the content changes. Compiled pipelines are kept.
    func releaseAll() {
        layers.removeAll()
        warps.removeAll()
        scratch = nil
    }

    /// Frees one layer's state (e.g. a removed script clone).
    func releaseLayer(_ layerID: String) {
        layers.removeValue(forKey: layerID)
        warps.removeValue(forKey: layerID)
    }

    /// Memory pressure: the scratch is remade by the next draw that needs it.
    func trimMemory() {
        scratch = nil
        uniformArena.trim()
    }

    /// What a puppet's draw needs this frame.
    struct Draw {
        let layerID: String
        /// The layer image (the material's `textures[0]`), as uploaded.
        let source: MTLTexture
        let pose: ScenePuppetPose
        let frame: BuiltinFrameContext
        let values: SceneValueContext
        let assetTexture: (String, SceneMetalTextureSource) -> MTLTexture?
        /// What of the mesh's space the target covers; nil for the image's rect.
        var canvas: ScenePuppetCanvas? = nil
    }

    /// The canvas of a puppet layer without effects posed by `pose`: its image grown to cover the
    /// posed mesh, never shrinking while the layer lives (`ScenePuppetCanvas.covering`).
    func canvas(_ plan: ScenePuppetPlan, layerID: String, pose: ScenePuppetPose) -> ScenePuppetCanvas {
        guard let state = layerState(plan, layerID: layerID) else { return .image(plan.imageSize) }
        let canvas = ScenePuppetCanvas.covering(plan.posedBounds(pose), imageSize: plan.imageSize, current: state.canvas)
        state.canvas = canvas
        return canvas
    }

    private func layerState(_ plan: ScenePuppetPlan, layerID: String) -> LayerState? {
        if let existing = layers[layerID], existing.plan === plan { return existing }
        guard let made = LayerState(plan: plan, device: device) else { return nil }
        layers[layerID] = made
        return made
    }

    /// The layer's albedo target this frame, in `draw.source`'s texture layout (same size, the
    /// image in its top-left content texels), redrawn into `commandBuffer` when needed. Encodes its
    /// own passes, so call it outside any open render pass. nil when no target can be made.
    func albedo(_ plan: ScenePuppetPlan, _ draw: Draw, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let state = layerState(plan, layerID: draw.layerID) else { return nil }
        let size = SIMD2(draw.source.width, draw.source.height)
        if state.target.map({ SIMD2($0.width, $0.height) }) != size {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.targetFormat, width: size.x,
                                                                      height: size.y, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            state.target = device.makeTexture(descriptor: descriptor)
            state.drawnPose = nil
        }
        guard let target = state.target else { return nil }
        let source = ObjectIdentifier(draw.source)
        let unchanged = state.drawnPose == draw.pose && state.drawnSource == source && state.drawnCanvas == draw.canvas
            && plan.material.pass.constants.dynamic.isEmpty
        if unchanged { return target }

        let content = simd_min(plan.contentPixels, size)
        guard let scratch = scratchTexture(covering: content) else { return nil }
        let drawn = encodeMesh(plan, state: state, draw, into: scratch, content: content, commandBuffer: commandBuffer)
        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return nil }
        compute.setComputePipelineState(unpremultiply)
        compute.setTexture(scratch, index: 0)
        compute.setTexture(target, index: 1)
        // Nothing drawn yet (compiling): the target is cleared, the layer transparent.
        var extent = drawn ? SIMD2(UInt32(content.x), UInt32(content.y)) : .zero
        compute.setBytes(&extent, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 0)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        compute.dispatchThreadgroups(MTLSize(width: (size.x + 15) / 16, height: (size.y + 15) / 16, depth: 1),
                                     threadsPerThreadgroup: group)
        compute.endEncoding()
        if drawn {
            state.drawnPose = draw.pose
            state.drawnSource = source
            state.drawnCanvas = draw.canvas
        }
        return target
    }

    /// A warped texture's format: float, so sampling it returns what sampling the source did.
    static let warpFormat: MTLPixelFormat = .rgba16Float

    /// `texture` (an image-space texture of the layer's material other than its image: a normal
    /// map, a PBR mask) laid out like the posed mesh, in `texture`'s own layout (its image in the
    /// top-left `contentSize` texels), redrawn only when the pose or the texture changed. For a
    /// lit puppet without effects, WE draws the mesh in the scene through the layer's material, so
    /// every texture is sampled at the mesh's coordinates (0x14020a5d2, docs/models-plan.md §2.13);
    /// the layer's quad drawn with its image and these textures laid out through the mesh is that
    /// draw for a flat layer. The coordinates are the mesh's, scaled to the image's share of its
    /// padded texture, for every texture, as WE's copy of the mesh has them. nil when the mesh
    /// has no plain position, blend indices, weights or texture coordinate.
    func warp(_ plan: ScenePuppetPlan, layerID: String, key: String, texture: MTLTexture, contentSize: SIMD2<Float>?,
              pose: ScenePuppetPose, canvas: ScenePuppetCanvas? = nil, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let state = layers[layerID], state.plan === plan else { return nil }
        let format = plan.format
        guard let position = MDLVertexAttribute.named("a_Position").flatMap(format.offset(of:)),
              let indices = MDLVertexAttribute.named("a_BlendIndices").flatMap(format.offset(of:)),
              let weights = MDLVertexAttribute.named("a_BlendWeights").flatMap(format.offset(of:)),
              let texCoord = MDLVertexAttribute.all[7...9].lazy.compactMap(format.offset(of:)).first else { return nil }
        let warp: WarpState
        if let existing = warps[layerID]?[key], existing.target.width == texture.width,
           existing.target.height == texture.height {
            warp = existing
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.warpFormat, width: texture.width,
                                                                      height: texture.height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
            warp = WarpState(target: target)
            warps[layerID, default: [:]][key] = warp
        }
        let source = ObjectIdentifier(texture)
        if warp.drawnPose == pose, warp.drawnSource == source, warp.drawnCanvas == canvas { return warp.target }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = warp.target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let content = contentSize.map { SIMD2(Int(saturating: $0.x.rounded()), Int(saturating: $0.y.rounded())) } ?? SIMD2(texture.width, texture.height)
        struct Uniforms {
            var projection: simd_float4x4
            var uvScale: SIMD2<Float>
            var positionOffset, indicesOffset, weightsOffset, texCoordOffset, stride, boneCount: UInt32
        }
        var uniforms = Uniforms(projection: (canvas ?? .image(plan.imageSize)).projection, uvScale: SIMD2(1, 1),
                                positionOffset: UInt32(position), indicesOffset: UInt32(indices),
                                weightsOffset: UInt32(weights), texCoordOffset: UInt32(texCoord),
                                stride: UInt32(format.stride), boneCount: UInt32(pose.bones.count))
        let bones = pose.bones.isEmpty ? [matrix_identity_float4x4] : pose.bones
        encoder.setRenderPipelineState(warpPipeline)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(min(content.x, texture.width)),
                                        height: Double(min(content.y, texture.height)), znear: 0, zfar: 1))
        encoder.setCullMode(plan.material.cullsBackFaces ? .back : .none)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(state.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        guard let palette = bones.withUnsafeBytes({ uniformArena.allocate($0, for: commandBuffer) }) else {
            encoder.endEncoding()
            return nil
        }
        encoder.setVertexBuffer(palette.buffer, offset: palette.offset, index: 2)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(clampSampler, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: plan.indexCount,
                                      indexType: plan.usesUInt32Indices ? .uint32 : .uint16,
                                      indexBuffer: state.indices, indexBufferOffset: 0)
        encoder.endEncoding()
        warp.drawnPose = pose
        warp.drawnSource = source
        warp.drawnCanvas = canvas
        return warp.target
    }

    /// The mesh into `scratch`'s top-left `content` texels, premultiplied, cleared to 0 first.
    /// False while the pipeline compiles or failed, or an input is missing.
    private func encodeMesh(_ plan: ScenePuppetPlan, state: LayerState, _ draw: Draw, into scratch: MTLTexture,
                            content: SIMD2<Int>, commandBuffer: MTLCommandBuffer) -> Bool {
        let pass = plan.material.pass
        let pipeline = self.pipeline(for: plan)
        let bound = pipeline == nil ? nil : textures(of: plan, draw, morph: state.morphTexture)
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = scratch
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }
        defer { encoder.endEncoding() }
        guard let pipeline, let bound else { return false }

        // Identity model and view; orthographic over the image's pixels (WE's z range ±1000), the
        // image's top on the target's first row like every layer image.
        let projection = (draw.canvas ?? .image(plan.imageSize)).projection
        if state.uniforms.size > 0 {
            let key = ImageMaterialUniforms.PassKey(
                model: matrix_identity_float4x4, viewProjection: projection, color: SIMD3(repeating: 1), alpha: 1,
                brightness: 1, spriteRotation: SIMD4(1, 0, 0, 1), spriteTranslation: .zero, screen: draw.frame.screenSize,
                textures: bound.map { SIMD4(Float($0.texture.width), Float($0.texture.height),
                                            $0.contentSize?.x ?? 0, $0.contentSize?.y ?? 0) })
            state.uniforms.update(key: key, frame: draw.frame, values: draw.values) {
                var context = BuiltinPassContext(targetSize: SIMD2(Float(content.x), Float(content.y)))
                context.viewProjection = projection
                context.modelViewProjection = projection
                for entry in bound {
                    context.textures[entry.slot] = EffectGraphRenderer.textureInfo(for: entry.texture, contentSize: entry.contentSize)
                }
                return context
            }
        }
        var bytes = state.uniforms.bytes
        if let layout = pass.variant?.uniforms {
            Self.writePose(draw.pose, layout: layout, into: &bytes)
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(content.x), height: Double(content.y),
                                        znear: 0, zfar: 1))
        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: content.x, height: content.y))
        encoder.setCullMode(plan.material.cullsBackFaces ? .back : .none)
        // D3D's default: clockwise triangles face the viewer (FrontCounterClockwise false).
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(state.vertices, offset: 0, index: Self.meshBuffer)
        encoder.setVertexBuffer(zeroAttributes, offset: 0, index: EffectGraphRenderer.zeroBuffer)
        for entry in bound {
            encoder.setFragmentTexture(entry.texture, index: entry.slot)
            encoder.setFragmentSamplerState(entry.sampler, index: entry.slot)
            encoder.setVertexTexture(entry.texture, index: entry.slot)
            encoder.setVertexSamplerState(entry.sampler, index: entry.slot)
        }
        if !bytes.isEmpty {
            bytes.withUnsafeBytes { raw in uniformArena.bind(raw, index: 0, to: encoder, commandBuffer: commandBuffer) }
        }
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: plan.indexCount,
                                      indexType: plan.usesUInt32Indices ? .uint32 : .uint16,
                                      indexBuffer: state.indices, indexBufferOffset: 0)
        drawsEncoded += 1
        return true
    }

    /// `g_Bones`, `g_BonesAlpha` and the morph uniforms (zero without targets: none applies).
    static func writePose(_ pose: ScenePuppetPose, layout: UniformLayout, into bytes: inout [UInt8]) {
        pose.morph?.write(into: &bytes, layout: layout)
        if let member = layout.members["g_Bones"] {
            UniformWriter.write(pose.boneComponents, member: member, into: &bytes)
        }
        if let member = layout.members["g_BonesAlpha"] {
            UniformWriter.write(pose.bonesAlpha, member: member, into: &bytes)
        }
    }

    private typealias BoundTexture = (slot: Int, texture: MTLTexture, sampler: MTLSamplerState, contentSize: SIMD2<Float>?)

    /// The textures the mesh pass reads; nil when one isn't there this frame.
    private func textures(of plan: ScenePuppetPlan, _ draw: Draw, morph: MTLTexture?) -> [BoundTexture]? {
        var bound: [BoundTexture] = []
        let pass = plan.material.pass
        for slot in pass.variant?.textureSlots ?? [] {
            let sampler = plan.material.clampedSlots.contains(slot) ? clampSampler : repeatSampler
            guard let input = pass.textures[slot] else {
                if plan.combos.morphing, slot == ImagePuppetCombos.morphSlot {
                    bound.append((slot, morph ?? emptyMorphTexture, clampSampler, nil))
                }
                continue
            }
            switch input {
            case .current, .previous:
                let content = SIMD2(Float(plan.contentPixels.x), Float(plan.contentPixels.y))
                let whole = SIMD2(Float(draw.source.width), Float(draw.source.height))
                bound.append((slot, draw.source, sampler, content == whole ? nil : content))
            case .asset(let key, let source):
                guard let texture = draw.assetTexture(key, source) else { return nil }
                bound.append((slot, texture, sampler, source.contentSize))
            case .sceneSnapshot, .mipMappedFrameBuffer, .fbo:
                // Only a lit or blended pass reads the scene; the mesh pass is neither.
                return nil
            }
        }
        return bound
    }

    private func scratchTexture(covering content: SIMD2<Int>) -> MTLTexture? {
        if let scratch, scratch.width >= content.x, scratch.height >= content.y { return scratch }
        let width = max(content.x, scratch?.width ?? 0), height = max(content.y, scratch?.height ?? 0)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.scratchFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        scratch = device.makeTexture(descriptor: descriptor)
        return scratch
    }

    // MARK: - Pipelines

    /// The mesh's interleaved vertices.
    static let meshBuffer = EffectGraphRenderer.positionBuffer

    static func pipelineKey(_ plan: ScenePuppetPlan) -> String {
        "puppet|\(plan.material.pass.variantKey)|\(plan.format.rawValue)|\(plan.material.pass.blending.lowercased())"
    }

    /// Blocks until the plan's pipeline compiled or failed (tests, prewarming). True when it is ready.
    func waitUntilReady(_ plan: ScenePuppetPlan, timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let key = Self.pipelineKey(plan)
        while pipeline(for: plan) == nil {
            if pipelineLock.withLock({ failed.contains(key) }) || Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

    private func pipeline(for plan: ScenePuppetPlan) -> MTLRenderPipelineState? {
        let key = Self.pipelineKey(plan)
        let state: (pipeline: MTLRenderPipelineState?, busy: Bool) = pipelineLock.withLock {
            (pipelines[key], pending.contains(key) || failed.contains(key))
        }
        if let pipeline = state.pipeline { return pipeline }
        if !state.busy, let variant = plan.material.pass.variant {
            compile(variant, plan: plan, key: key)
        }
        return nil
    }

    private func compile(_ variant: TranslatedShaderVariant, plan: ScenePuppetPlan, key: String) {
        pipelineLock.withLock { _ = pending.insert(key) }
        let device = self.device
        let archive = self.archive
        let format = plan.format
        let blending = plan.material.pass.blending
        let material = plan.material.materialPath
        compileQueue.async { [weak self] in
            let result: MTLRenderPipelineState?
            do {
                let vertexLibrary = try device.makeLibrary(source: variant.vertexMSL, options: nil)
                let fragmentLibrary = try device.makeLibrary(source: variant.fragmentMSL, options: nil)
                guard let vertex = vertexLibrary.makeFunction(name: "main0"),
                      let fragment = fragmentLibrary.makeFunction(name: "main0") else {
                    throw ShaderCompilerError.failed(step: "metal", output: "entry point main0 missing")
                }
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                descriptor.colorAttachments[0].pixelFormat = Self.scratchFormat
                Self.applyBlending(blending, to: descriptor.colorAttachments[0])
                descriptor.vertexDescriptor = Self.vertexDescriptor(for: vertex, attributes: variant.attributes, format: format)
                result = try EffectGraphRenderer.makePipeline(descriptor, device: device, archive: archive, key: key)
            } catch {
                OWELog.error(.shader, "Puppet mesh material \(material) can't draw through its shader; the layer shows nothing: \(error)")
                result = nil
            }
            guard let self else { return }
            self.pipelineLock.withLock {
                self.pending.remove(key)
                if let result { self.pipelines[key] = result } else { self.failed.insert(key) }
            }
        }
    }

    /// Triangles over each other: premultiplied "over" (WE's translucent and additive draws
    /// composite over the ones before them), unblended for `normal`, which replaces.
    static func applyBlending(_ blending: String, to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        guard EffectGraphRenderer.blendMode(blending) != nil else { return }
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    /// The mesh's interleaved attributes at the locations the translated stage reads them from
    /// (`ShaderPairRewriter.attributeLocations`); an input the mesh lacks reads zeros, as WE's input
    /// layout leaves it (docs/models-plan.md §5, open point 11).
    static func vertexDescriptor(for function: MTLFunction, attributes: [String: Int],
                                 format: MDLVertexFormat) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        let names = Dictionary(attributes.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        var usesZero = false
        for input in function.vertexAttributes ?? [] where input.isActive {
            let element = descriptor.attributes[input.attributeIndex]!
            let isInteger = [.uint, .uint2, .uint3, .uint4, .int, .int2, .int3, .int4].contains(input.attributeType)
            if let name = names[input.attributeIndex], let attribute = MDLVertexAttribute.named(name),
               let offset = format.offset(of: attribute) {
                element.format = vertexFormat(attribute)
                element.offset = offset
                element.bufferIndex = meshBuffer
            } else {
                element.format = isInteger ? .uint4 : .float4
                element.offset = 0
                element.bufferIndex = EffectGraphRenderer.zeroBuffer
                usesZero = true
            }
        }
        descriptor.layouts[meshBuffer].stride = format.stride
        if usesZero {
            descriptor.layouts[EffectGraphRenderer.zeroBuffer].stride = 16
            descriptor.layouts[EffectGraphRenderer.zeroBuffer].stepFunction = .constant
            descriptor.layouts[EffectGraphRenderer.zeroBuffer].stepRate = 0
        }
        return descriptor
    }

    static func vertexFormat(_ attribute: MDLVertexAttribute) -> MTLVertexFormat {
        switch (attribute.componentType, attribute.components) {
        case (.uint32, _): return .uint4
        case (.float32, 2): return .float2
        case (.float32, 3): return .float3
        default: return .float4
        }
    }
}
