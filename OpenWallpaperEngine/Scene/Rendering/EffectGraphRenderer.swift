import Metal
import QuartzCore
import simd

/// Runs WE effects on a layer's image with WE's own shaders.
///
/// Per layer: the input image is copied through the effect passes using two ping-pong targets at
/// the layer's size. A pass without a `target` renders the current image into the other ping-pong
/// buffer and becomes the current image (linux-wallpaperengine's per-pass swap); a pass with a
/// `target` renders into that effect FBO. `previous` is the effect's input. The result is the
/// processed image, which the scene pass then draws with the layer's transform and blending.
final class EffectGraphRenderer {
    private let device: MTLDevice
    private let quadPositions: MTLBuffer
    private let quadTexCoords: MTLBuffer
    private let zeroAttributes: MTLBuffer
    private let clampSampler: MTLSamplerState
    /// Asset samplers by the `.tex` flags that pick one (`clampUVs`, `noInterpolation`).
    private let assetSamplers: [UInt32: MTLSamplerState]
    /// Uniform blocks over 4 KB. Render thread only (see `SceneUniformArena`).
    let uniformArena: SceneUniformArena
    /// Chains drawn at their layer's on-screen size (`Context.footprint`); nil without its shaders.
    private lazy var detail = SceneEffectDetail(device: device)

    /// Pipelines compile off the render thread: a cold Metal compile costs tens of milliseconds
    /// per variant, which would otherwise stall frames. Guarded by `pipelineLock`.
    private let compileQueue = DispatchQueue(label: "owe.effect-pipelines", qos: .userInitiated, attributes: .concurrent)
    private let pipelineLock = NSLock()
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    /// Pipelines drawn with since the last `trimMemory` that dropped idle ones.
    private var usedPipelines = Set<String>()
    private var pendingPipelines = Set<String>()
    private var failedPipelines = Set<String>()
    /// Backend binaries of compiled pipelines, persisted across launches; nil disables it.
    let pipelineArchive: EffectPipelineArchive?

    /// Per layer: targets, uniform programs and readiness, resolved once and reused every frame
    /// so the steady state does no string building or dictionary work per pass.
    private var layers: [String: LayerState] = [:]

    private final class LayerState {
        var width: Int
        var height: Int
        var formats: [[MTLPixelFormat?]] = []
        /// The frame-buffer class and output formats the targets and pipelines were made for.
        var targetFormats = TargetFormats(frameBuffer: .rgba8Unorm, output: .rgba8Unorm)
        var ready = false
        /// Variant keys of the chain the programs were built for; a different chain rebuilds them.
        var chain: [[String]] = []
        var pingA: MTLTexture?
        var pingB: MTLTexture?
        var fbos: [[String: MTLTexture]] = []
        /// FBOs made since the last frame, with the colour each starts as (`EffectFBO.clear`).
        var pendingClears: [(texture: MTLTexture, color: MTLClearColor)] = []
        /// The size each target stands for when the chain is drawn below its size
        /// (`Context.inputStandInSize`), which the chain's built-ins report. Empty otherwise.
        var standInSizes: [ObjectIdentifier: SIMD2<Float>] = [:]
        /// The size the chain's buffers stand for (the input's, or `Context.inputStandInSize`).
        var standInSize = SIMD2<Int>(0, 0)
        /// How far the chain's blur-like buffers are reduced (`EffectResolutionPolicy`).
        var resolution = EffectResolutionPolicy.full
        var programs: [[UniformProgram?]] = []
        /// Each render pass's pipeline, resolved once the chain is ready; held so a trim never drops one in use.
        var pipelines: [[MTLRenderPipelineState?]] = []
        /// Last output of a chain that doesn't change over time, and what produced it. When the chain
        /// draws its last pass into the scene, the output is that pass's input, and `staticDrawn` the pass.
        var staticOutput: (key: StaticChainKey, output: MTLTexture)?
        var staticDrawn: DrawnLastPass?
        /// The output of the chain's leading effects when they don't change over time but later ones
        /// do (`staticPrefix`), kept in `prefixTarget` so the frame starts after them; and what produced it.
        var prefixOutput: (key: StaticChainKey, effects: Int)?
        var prefixTarget: MTLTexture?
        /// Scratch targets were handed to the spares once the chain's output was kept
        /// (`releaseScratch`); the next frame that draws the chain takes them back first.
        var scratchReleased = false

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// Everything a static chain's output depends on besides its plan. The input is held (not just
    /// its `ObjectIdentifier`, which can be reused once a texture is freed) and compared by identity.
    struct StaticChainKey {
        let input: MTLTexture
        let inputVersion: UInt64
        let color: SIMD3<Float>
        let alpha: Float
        /// `Context.scriptRevision`: script-set visibility or constants changed.
        let scriptRevision: Int
        /// The chain's live-bound constants this frame (timelines, user properties), in pass
        /// order: a paused or finished timeline's chain is reused like a static one (TF4).
        let dynamicValues: [Float]

        func matches(_ other: StaticChainKey) -> Bool {
            input === other.input && inputVersion == other.inputVersion
                && color == other.color && alpha == other.alpha && scriptRevision == other.scriptRevision
                && dynamicValues == other.dynamicValues
        }
    }

    /// A chain's frame-buffer class format (`rgba_backbuffer`, `rgb_backbuffer`) and the format of its
    /// ping-pong targets, which hold its output.
    struct TargetFormats: Equatable {
        var frameBuffer: MTLPixelFormat
        var output: MTLPixelFormat
    }

    /// Targets a layer gave back when its size changed, by size and format. Layers whose size
    /// changes with their content (text on a clock) take them back instead of allocating new ones,
    /// at exactly the size asked for, so a chain's output is the same as on fresh targets.
    private struct TargetKey: Hashable {
        let width: Int
        let height: Int
        let format: MTLPixelFormat
    }
    /// A spare target and when it was given back.
    private struct Spare {
        let texture: MTLTexture
        let since: TimeInterval
        /// Order of the hand-back, to break ties between spares given back at the same instant.
        let order: UInt64
    }
    private var spareTargets: [TargetKey: [Spare]] = [:]
    /// Bytes of targets in the spare list (tests and diagnostics).
    private(set) var spareBytes = 0
    private var spareCounter: UInt64 = 0
    private var lastSpareSweep: TimeInterval = 0
    /// Bytes of spare targets kept; past it the longest idle go first. Only spares are evicted,
    /// never a layer's own targets, so the budget never refuses or skips a render.
    let spareByteBudget: Int
    /// Spares unused this long are dropped. A minute covers every size a clock showing seconds
    /// cycles through, so it keeps reusing its targets.
    let spareIdleSeconds: TimeInterval
    /// A monotonic clock in seconds (injectable for tests).
    private let now: () -> TimeInterval

    /// Counters for tests and diagnostics.
    private(set) var passesEncoded = 0
    private(set) var layersReused = 0
    /// Times every effect pass when set (profiling; `EffectPassTimer`).
    var passTimer: EffectPassTimer?
    /// Frames that started after a kept static prefix (`staticPrefix`).
    private(set) var prefixesReused = 0
    private(set) var targetsAllocated = 0
    var failedPipelineCount: Int { pipelineLock.withLock { failedPipelines.count } }
    /// Pipeline compiles started (at most one per pipeline key).
    var pipelineCompileCount: Int { pipelineLock.withLock { pipelineCompiles } }
    private var pipelineCompiles = 0 // guarded by pipelineLock

    static let positionBuffer = 30
    static let texCoordBuffer = 29
    static let zeroBuffer = 28

    /// `pipelineArchiveDirectory` holds the persisted pipeline archive, shared by every renderer of
    /// the device; nil keeps none.
    init?(device: MTLDevice, pipelineArchiveDirectory: URL? = EffectPipelineArchive.defaultDirectory,
          spareByteBudget: Int = 256 << 20, spareIdleSeconds: TimeInterval = 60,
          now: @escaping () -> TimeInterval = CACurrentMediaTime) {
        self.device = device
        self.spareByteBudget = spareByteBudget
        self.spareIdleSeconds = spareIdleSeconds
        self.now = now
        uniformArena = SceneUniformArena(device: device)
        pipelineArchive = pipelineArchiveDirectory.map { EffectPipelineArchive.shared(device: device, directory: $0) }
        // Triangle strip over the full target; with the translator's GL-style y flip, texcoord
        // (0, 0) lands on the first row, so each pass maps its input 1:1.
        let positions: [Float] = [-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0]
        let texCoords: [Float] = [0, 0, 1, 0, 0, 1, 1, 1]
        guard let quadPositions = device.makeBuffer(bytes: positions, length: positions.count * 4),
              let quadTexCoords = device.makeBuffer(bytes: texCoords, length: texCoords.count * 4),
              let zeroAttributes = device.makeBuffer(length: 64) else { return nil }
        self.quadPositions = quadPositions
        self.quadTexCoords = quadTexCoords
        self.zeroAttributes = zeroAttributes
        var assetSamplers: [UInt32: MTLSamplerState] = [:]
        for raw in UInt32(0)...3 {
            guard let sampler = Self.makeSampler(device: device, flags: TEXFlags(rawValue: raw)) else { return nil }
            assetSamplers[raw] = sampler
        }
        guard let clamp = assetSamplers[TEXFlags.clampUVs.rawValue] else { return nil }
        clampSampler = clamp
        self.assetSamplers = assetSamplers
    }

    /// WE's sampler for a texture: clamp with `clampUVs`, else repeat; nearest with
    /// `noInterpolation`, else bilinear.
    private static func makeSampler(device: MTLDevice, flags: TEXFlags) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        let filter: MTLSamplerMinMagFilter = flags.contains(.noInterpolation) ? .nearest : .linear
        descriptor.minFilter = filter
        descriptor.magFilter = filter
        descriptor.mipFilter = flags.contains(.noInterpolation) ? .nearest : .linear
        let address: MTLSamplerAddressMode = flags.contains(.clampUVs) ? .clampToEdge : .repeat
        descriptor.sAddressMode = address
        descriptor.tAddressMode = address
        return device.makeSamplerState(descriptor: descriptor)
    }

    /// Drops per-layer state, e.g. when the scene changes. Compiled pipelines are kept.
    func releaseTargets() {
        detail?.releaseAll()
        layers.removeAll()
        spareTargets.removeAll()
        spareBytes = 0
    }

    /// Memory pressure: drops the spare targets and free uniform chunks, and with
    /// `dropIdlePipelines` every pipeline not drawn with since the last trim (they recompile, from
    /// the binary archive, if needed again). Layers' own targets are in use and kept.
    func trimMemory(dropIdlePipelines: Bool) {
        spareTargets.removeAll()
        spareBytes = 0
        uniformArena.trim()
        guard dropIdlePipelines else { return }
        pipelineLock.withLock {
            pipelines = pipelines.filter { usedPipelines.contains($0.key) }
            usedPipelines.removeAll()
        }
    }

    /// Compiled pipelines, for tests and diagnostics.
    var pipelineCount: Int { pipelineLock.withLock { pipelines.count } }

    /// Frees one layer's state (e.g. a removed script clone). Its targets go to the spare list,
    /// which is safe while earlier command buffers still read them: later passes on the same
    /// queue are ordered after those reads. Pipelines are shared by variant, not owned by a
    /// layer, so a compile still in flight for this layer's chain just lands in the cache.
    /// Call on the render thread, like `apply`.
    func releaseLayer(_ stateId: String) {
        detail?.releaseLayer(stateId)
        guard let state = layers.removeValue(forKey: stateId) else { return }
        recycleTargets(state)
    }

    /// Layers holding state, for tests and diagnostics.
    var layerStateCount: Int { layers.count }
    /// Spare targets kept and their allocated bytes, for tests and diagnostics.
    var spareTargetCount: Int { spareTargets.values.reduce(0) { $0 + $1.count } }
    var spareTargetBytes: Int { spareBytes }

    struct Context {
        let frame: BuiltinFrameContext
        let values: SceneValueContext
        /// Texture for an asset input, materialised by the renderer.
        let assetTexture: (String, SceneMetalTextureSource) -> MTLTexture?
        /// The scene rendered so far, if a pass needs `_rt_FullFrameBuffer`.
        let sceneSnapshot: MTLTexture?
        /// `_rt_MipMappedFrameBuffer` (`SceneMipMappedFrameBuffer`), for a pass that samples it.
        var mipMappedFrameBuffer: MTLTexture? = nil
        /// Another layer's image after its effects this frame, by object id, for a pass sampling
        /// `_rt_imageLayerComposite_<id>_a` (`SceneEffectPlan.compositeLayerIDs`); nil unbinds it.
        var layerComposite: (String) -> MTLTexture? = { _ in nil }
        /// `_rt_Reflection` this frame (`ScenePlanarReflection`); nil unbinds it.
        var planarReflection: MTLTexture? = nil
        /// A system texture's image this frame (`SceneEffectPassPlan.systemTextures`); nil keeps
        /// the slot's authored input.
        var systemTexture: (SceneSystemTexture) -> MTLTexture? = { _ in nil }
        let layerColor: SIMD3<Float>
        let layerAlpha: Float
        /// Bump when `input`'s contents change while the texture object stays the same.
        var inputVersion: UInt64 = 0
        /// Image size inside a padded asset texture (the `.tex` width/height), when known; used
        /// for `g_TextureNResolution.zw`. nil means the whole texture is content.
        var assetContentSize: ((String, SceneMetalTextureSource) -> SIMD2<Float>?)? = nil
        /// Called with each animated constant's site and the value its uniform got this frame
        /// (`SceneDrawProbe`); nil records nothing.
        var recordAnimated: ((SceneAnimationSite, [Float]) -> Void)? = nil
        /// An animated asset texture's sprite frame this frame (`g_TextureNRotation/Translation`),
        /// whose texture `assetTexture` gives; nil for a still one.
        var assetSprite: ((String, SceneMetalTextureSource) -> BuiltinSpriteFrame?)? = nil
        /// Effects (indices into the chain) that are hidden this frame: built, but skipped.
        var hiddenEffects: Set<Int> = []
        /// Constants scripts set, by the effect's `effectIndex` (`IEffect.setMaterialProperty`).
        var constantWrites: [Int: [SceneScriptConstantWrite]] = [:]
        /// Bumped whenever `hiddenEffects` or `constantWrites` change.
        var scriptRevision = 0
        /// The size `g_TexelSize` is one over in every pass; nil uses each pass's target. WE's
        /// bloom passes step in texels of the full frame whatever their target (`SceneBloomChain`).
        var texelSizeReference: SIMD2<Float>? = nil
        /// WE's frame-buffer class format (`wallpaper64.exe` 0x1401e7572, 0x1401ea642): the layers'
        /// ping-pong targets and `rgba_backbuffer`/`rgb_backbuffer` FBOs are RGBA8 in LDR and
        /// RGBA16F in HDR.
        var frameBufferFormat = MTLPixelFormat.rgba8Unorm
        /// The ping-pong targets' format, where a chain's output lands; nil is `frameBufferFormat`.
        var outputFormat: MTLPixelFormat? = nil
        /// `g_RenderVar0…4` the engine sets on a pass, by the pass's `materialIndex`: an engine
        /// chain's (one effect, `SceneHDRChain`).
        var passRenderVars: [Int: [Int: SIMD4<Float>]] = [:]
        /// `g_EffectTextureProjectionMatrix`: where the layer's image lies on the screen
        /// (`effectTextureProjection(quad:sceneSize:)`); identity for a chain that isn't a layer's.
        var effectTextureProjection = matrix_identity_float4x4

        /// The input's on-screen size in pixels when the scene's detail matches the display
        /// (`SceneEffectDetail`); nil draws the chain at the input's size, as WE does. A smaller
        /// footprint runs the chain on a copy of the input scaled down to it, whose built-ins
        /// (`g_TextureNResolution`, `g_TexelSize`) report the sizes at the input's size, so every
        /// texel-sized step spans the same part of the image: the result is the full-size chain's,
        /// sampled at the smaller size.
        var footprint: SIMD2<Float>? = nil
        /// The size the input stands for when it was drawn below full detail already (a scene
        /// region or text at a scene target matched to a smaller display); nil for its own. Its
        /// built-ins report it, as for `footprint`.
        var inputStandInSize: SIMD2<Int>? = nil
        /// How far blur-like effect buffers may be reduced (`EffectResolutionPolicy`).
        var resolution = EffectResolutionPolicy.full

        var targetFormats: TargetFormats { TargetFormats(frameBuffer: frameBufferFormat, output: outputFormat ?? frameBufferFormat) }
    }

    /// Runs `effects` on `input` and returns the processed image, or nil when nothing rendered —
    /// including while the chain's pipelines are still compiling (the layer then draws plain).
    func apply(_ effects: [SceneEffectPlan], to image: MTLTexture, layerID: String,
               context: Context, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        run(effects, to: image, layerID: layerID, context: context, drawsLastPass: false, commandBuffer: commandBuffer).output
    }

    /// Runs `effects` on `input` up to their last pass, which the caller draws into the scene with
    /// `encode(_:into:scene:context:commandBuffer:)`, as WE draws a layer's last effect pass
    /// (docs/phase2-plan.md §2; `lastScenePass`). nil when nothing can be drawn: the chain has no
    /// such pass, or its pipelines are still compiling.
    func applyDrawingLastPass(_ effects: [SceneEffectPlan], to image: MTLTexture, layerID: String,
                              context: Context, commandBuffer: MTLCommandBuffer) -> DrawnLastPass? {
        run(effects, to: image, layerID: layerID, context: context, drawsLastPass: true, commandBuffer: commandBuffer).drawn
    }

    private func run(_ effects: [SceneEffectPlan], to image: MTLTexture, layerID: String, context: Context,
                     drawsLastPass: Bool, commandBuffer: MTLCommandBuffer) -> (output: MTLTexture?, drawn: DrawnLastPass?) {
        let last = drawsLastPass ? Self.lastScenePass(effects, hidden: context.hiddenEffects) : nil
        if drawsLastPass, last == nil { return (nil, nil) }
        sweepIdleSpares()
        var input = image
        var standIn = context.inputStandInSize ?? SIMD2(image.width, image.height)
        if let footprint = context.footprint, let detail {
            let detailed = detail.input(for: image, version: context.inputVersion, layerID: layerID,
                                        footprint: footprint, commandBuffer: commandBuffer)
            input = detailed.texture
            standIn = detailed.standIn ?? standIn
        } else {
            detail?.releaseLayer(layerID)
        }
        let width = input.width
        let height = input.height
        let state: LayerState
        let targetFormats = context.targetFormats
        // Compared in place, without building the chain's keys every frame (N5).
        let chain = effects.map { $0.passes.map(\.variantKey) }
        if let existing = layers[layerID], existing.chain == chain, existing.targetFormats == targetFormats {
            state = existing
        } else {
            if let stale = layers[layerID] { recycleTargets(stale) }
            state = LayerState(width: width, height: height)
            state.chain = effects.map { $0.passes.map(\.variantKey) }
            state.targetFormats = targetFormats
            layers[layerID] = state
        }
        if !state.ready {
            guard let formats = readyFormats(effects, targetFormats: targetFormats) else { return (nil, nil) }
            state.formats = formats
            state.pipelines = resolvedPipelines(effects, formats: formats)
            state.programs = effects.map { effect in
                effect.passes.map { pass in pass.variant.map { UniformProgram(layout: $0.uniforms, constants: pass.constants) } }
            }
            state.resolution = context.resolution
            allocateTargets(state, effects: effects, width: width, height: height, standIn: standIn)
            state.ready = true
        } else if state.width != width || state.height != height || state.standInSize != standIn
                    || state.resolution != context.resolution {
            recycleTargets(state)
            state.resolution = context.resolution
            allocateTargets(state, effects: effects, width: width, height: height, standIn: standIn)
        }
        // The leading effects that don't change over time, when later ones do: their output is kept
        // and the frame starts after them while it stays valid.
        let prefix = Self.staticPrefix(effects, programs: state.programs, hidden: context.hiddenEffects)
        var prefixValueCount = 0
        var dynamicValues: [Float] = []
        for (effectIndex, programs) in state.programs.enumerated() where !context.hiddenEffects.contains(effectIndex) {
            defer { if effectIndex < prefix { prefixValueCount = dynamicValues.count } }
            for program in programs { program?.appendDynamicValues(to: &dynamicValues, values: context.values) }
            // A sprite sheet's frame changes the output like a live constant does.
            guard let assetSprite = context.assetSprite else { continue }
            for pass in effects[effectIndex].passes {
                for case .asset(let key, let source) in pass.textures.values {
                    guard let sprite = assetSprite(key, source) else { continue }
                    dynamicValues += [sprite.rotation.x, sprite.rotation.y, sprite.rotation.z, sprite.rotation.w,
                                      sprite.translation.x, sprite.translation.y]
                }
            }
        }
        let staticKey = StaticChainKey(input: input, inputVersion: context.inputVersion,
                                       color: context.layerColor, alpha: context.layerAlpha,
                                       scriptRevision: context.scriptRevision, dynamicValues: dynamicValues)
        let prefixKey = prefix > 0
            ? StaticChainKey(input: input, inputVersion: context.inputVersion, color: context.layerColor,
                             alpha: context.layerAlpha, scriptRevision: context.scriptRevision,
                             dynamicValues: Array(dynamicValues.prefix(prefixValueCount)))
            : nil
        // A scene snapshot, or the last frame's copy, keeps its texture identity while its contents
        // change every frame.
        let readsScene = context.sceneSnapshot != nil
            || effects.contains { $0.passes.contains(where: \.readsMipMappedFrameBuffer) }
            // The artwork changes with the song while the chain's inputs and constants don't.
            || effects.contains { $0.passes.contains { !$0.systemTextures.isEmpty } }
        if !readsScene, let cached = state.staticOutput, cached.key.matches(staticKey),
           (state.staticDrawn != nil) == drawsLastPass {
            layersReused += 1
            return drawsLastPass ? (nil, state.staticDrawn) : (cached.output, nil)
        }
        if state.scratchReleased { reacquireScratch(state, effects: effects) }
        clearNewTargets(state, commandBuffer: commandBuffer)
        var current = input
        var didRender = false
        var reusable = true
        var firstEffect = 0
        if !readsScene, let prefixKey, let cached = state.prefixOutput, cached.effects == prefix,
           cached.key.matches(prefixKey), let kept = state.prefixTarget {
            current = kept
            firstEffect = prefix
            didRender = true
            prefixesReused += 1
        }
        var keepsPrefix = prefixKey != nil && firstEffect == 0 && !readsScene
        var drawn: DrawnLastPass?
        chain: for (effectIndex, effect) in effects.enumerated() where effectIndex >= firstEffect && !context.hiddenEffects.contains(effectIndex) {
            if keepsPrefix, effectIndex >= prefix, let prefixKey {
                keepsPrefix = false
                keepPrefix(current, of: state, input: input, key: prefixKey, effects: prefix, commandBuffer: commandBuffer)
            }
            let previous = current
            var fbos = state.fbos[effectIndex]
            if effect.carriesFrames { reusable = false }
            for (passIndex, pass) in effect.passes.enumerated() {
                switch pass.command {
                case .copy(let source, let destination):
                    guard let from = fbos[source] ?? (source == "previous" ? previous : nil), let to = fbos[destination],
                          from.width == to.width, from.height == to.height, from.pixelFormat == to.pixelFormat,
                          let blit = commandBuffer.makeBlitCommandEncoder() else { continue }
                    blit.copy(from: from, to: to)
                    blit.endEncoding()
                case .swap(let first, let second):
                    // A swapped pair carries this frame's buffers into the next (`carriesFrames`).
                    let a = fbos[first]
                    fbos[first] = fbos[second]
                    fbos[second] = a
                case .render:
                    guard let variant = pass.variant, let program = state.programs[effectIndex][passIndex],
                          let format = state.formats[effectIndex][passIndex],
                          let pipeline = state.pipelines[effectIndex][passIndex] else { continue }
                    let standInSizes = StandIn(input: input, inputSize: standIn, targets: state.standInSizes,
                                               label: passTimer == nil ? "" : Self.passLabel(layerID, effect: effect, pass: passIndex))
                    if let last, last == (effectIndex, passIndex) {
                        // Drawn into the scene by the caller, from what the chain holds now.
                        drawn = DrawnLastPass(pass: pass, variant: variant, program: program, current: current,
                                              previous: previous, fbos: fbos, standIn: standInSizes,
                                              targetSize: SIMD2(Float(state.standInSize.x), Float(state.standInSize.y)),
                                              scriptWrites: context.constantWrites[effect.effectIndex] ?? [],
                                              repeatingFBOs: Set(effect.fbos.filter { $0.uvs == "repeat" }.map(\.name)))
                        state.fbos[effectIndex] = fbos
                        break chain
                    }
                    let output: MTLTexture
                    if let name = pass.target {
                        guard let fbo = fbos[name] else { continue }
                        output = fbo
                    } else {
                        // The ping-pong target the current image isn't in, made on first use: a
                        // one-pass chain (the engine's, most layers') never needs the second.
                        guard let ping = pingTarget(of: state, second: current === state.pingA) else { continue }
                        output = ping
                    }
                    reusable = reusable && program.isReusable && !pass.readsSceneSnapshot && !pass.readsMipMappedFrameBuffer
                    encode(pass, pipeline: pipeline, program: program, variant: variant, output: output,
                           current: current, previous: previous, fbos: fbos, context: context,
                           standIn: standInSizes,
                           scriptWrites: context.constantWrites[effect.effectIndex] ?? [],
                           repeatingFBOs: Set(effect.fbos.filter { $0.uvs == "repeat" }.map(\.name)),
                           commandBuffer: commandBuffer)
                    didRender = true
                    if pass.target == nil { current = output }
                }
            }
            // Swaps last: the next frame starts from the buffers this one left.
            state.fbos[effectIndex] = fbos
        }
        if let drawn {
            // The passes before the last are kept as a static chain's output is; the last is drawn
            // every frame.
            state.staticOutput = reusable && !readsScene ? (staticKey, current) : nil
            state.staticDrawn = drawn
            if state.staticOutput != nil {
                releaseScratch(state, keeping: [drawn.current, drawn.previous] + Array(drawn.fbos.values))
            }
            return (nil, drawn)
        }
        guard didRender, !drawsLastPass else { return (nil, nil) }
        // A chain with no time, audio or pointer input produces the same image every frame while
        // its input and live-bound values stay; skip it until they change (bandwidth is the main
        // per-frame cost).
        state.staticOutput = reusable && !readsScene ? (staticKey, current) : nil
        state.staticDrawn = nil
        if state.staticOutput != nil { releaseScratch(state, keeping: [current]) }
        return (current, nil)
    }

    /// The pass WE draws into the scene: the last visible effect's last pass, when it renders into
    /// the layer's buffers. WE's object draw (0x1401e8aa0) runs the passes into the layer's buffers
    /// until one is left of those that render into them (+0x320 counts them, 0x1401e952b; the loop
    /// stops at 0x1401e9ae7), then draws the rest of that effect (0x1401ea140) with its last one
    /// (the effect's +0x144, 0x1401ec22b) through the layer's quad and matrices into the scene
    /// (0x1401ec2b2, 0x1401ec5f8…0x1401ec674). nil when the chain doesn't end with such a pass.
    static func lastScenePass(_ effects: [SceneEffectPlan], hidden: Set<Int>) -> (effect: Int, pass: Int)? {
        guard let effect = effects.indices.last(where: { !hidden.contains($0) }),
              let index = effects[effect].passes.indices.last else { return nil }
        let pass = effects[effect].passes[index]
        guard case .render = pass.command, pass.target == nil, pass.variant != nil else { return nil }
        return (effect, index)
    }

    /// Where a chain's last pass draws: the layer's quad in the scene, and the scene pass it draws into.
    struct ScenePlacement {
        /// The quad's corners in model space, as a triangle strip (x, y, z each), and their texture
        /// coordinates in the chain's buffers.
        var positions: [Float]
        var texCoords: [SIMD2<Float>]
        /// `g_ModelMatrix`, `g_ViewMatrix` and `g_ViewProjectionMatrix` (the pass's
        /// `g_ModelViewProjectionMatrix` is their product): the layer's, as its material has them.
        var model: simd_float4x4
        var view = matrix_identity_float4x4
        var viewProjection: simd_float4x4
        /// The layer material's blending (WE copies the material's blend and depth state into the
        /// last pass: vtable +0x108 = 0x140209160).
        var blending: String
        /// The scene pass's colour format, samples and depth format (`.invalid` without depth).
        var pixelFormat: MTLPixelFormat
        var sampleCount = 1
        var depthFormat = MTLPixelFormat.invalid
    }

    /// A chain's last pass, run up to it (`applyDrawingLastPass`): what it samples, kept until it
    /// is drawn into the scene.
    final class DrawnLastPass {
        fileprivate let pass: SceneEffectPassPlan
        fileprivate let variant: TranslatedShaderVariant
        fileprivate let program: UniformProgram
        fileprivate let current: MTLTexture
        fileprivate let previous: MTLTexture
        fileprivate let fbos: [String: MTLTexture]
        fileprivate let standIn: StandIn
        /// The size of the chain's buffers (or what they stand for): the built-ins' target size.
        fileprivate let targetSize: SIMD2<Float>
        fileprivate let scriptWrites: [SceneScriptConstantWrite]
        fileprivate let repeatingFBOs: Set<String>
        /// The last effect's input (`previous`).
        var input: MTLTexture { previous }

        fileprivate init(pass: SceneEffectPassPlan, variant: TranslatedShaderVariant, program: UniformProgram,
                         current: MTLTexture, previous: MTLTexture, fbos: [String: MTLTexture], standIn: StandIn,
                         targetSize: SIMD2<Float>, scriptWrites: [SceneScriptConstantWrite], repeatingFBOs: Set<String>) {
            self.pass = pass
            self.variant = variant
            self.program = program
            self.current = current
            self.previous = previous
            self.fbos = fbos
            self.standIn = standIn
            self.targetSize = targetSize
            self.scriptWrites = scriptWrites
            self.repeatingFBOs = repeatingFBOs
        }
    }

    /// Whether `effects`' last pass (`lastScenePass`) can draw into `scene` now; starts its compile.
    func scenePassIsReady(_ effects: [SceneEffectPlan], hidden: Set<Int>, scene: ScenePlacement) -> Bool {
        guard let last = Self.lastScenePass(effects, hidden: hidden) else { return false }
        return scenePipeline(effects[last.effect].passes[last.pass], scene: scene) != nil
    }

    private static func scenePipelineKey(_ pass: SceneEffectPassPlan, scene: ScenePlacement) -> String {
        "\(pass.variantKey)|\(scene.pixelFormat.rawValue)|\(scene.blending)|scene|x\(scene.sampleCount)|d\(scene.depthFormat.rawValue)"
    }

    /// The last pass's pipeline into the scene, or nil while it compiles (the compile starts here)
    /// or after it failed.
    private func scenePipeline(_ pass: SceneEffectPassPlan, scene: ScenePlacement) -> MTLRenderPipelineState? {
        guard let variant = pass.variant else { return nil }
        let key = Self.scenePipelineKey(pass, scene: scene)
        let state: (pipeline: MTLRenderPipelineState?, start: Bool) = pipelineLock.withLock {
            if let pipeline = pipelines[key] {
                usedPipelines.insert(key)
                return (pipeline, false)
            }
            if failedPipelines.contains(key) { return (nil, false) }
            return (nil, pendingPipelines.insert(key).inserted)
        }
        if state.start {
            compile(pass, variant: variant, format: scene.pixelFormat, key: key, blending: scene.blending,
                    sampleCount: scene.sampleCount, depthFormat: scene.depthFormat)
        }
        return state.pipeline
    }

    /// Draws a chain's last pass (`applyDrawingLastPass`) through `scene` into `encoder`'s pass, the
    /// scene's. False when its pipeline isn't ready. Leaves the encoder's pipeline state changed.
    @discardableResult
    func encode(_ drawn: DrawnLastPass, into encoder: MTLRenderCommandEncoder, scene: ScenePlacement,
                context: Context, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let pipeline = scenePipeline(drawn.pass, scene: scene), scene.positions.count == 12,
              scene.texCoords.count == 4 else { return false }
        passesEncoded += 1
        encoder.setRenderPipelineState(pipeline)
        var positions = scene.positions
        var texCoords = scene.texCoords
        encoder.setVertexBytes(&positions, length: MemoryLayout<Float>.stride * positions.count, index: Self.positionBuffer)
        encoder.setVertexBytes(&texCoords, length: MemoryLayout<SIMD2<Float>>.stride * texCoords.count,
                               index: Self.texCoordBuffer)
        encoder.setVertexBuffer(zeroAttributes, offset: 0, index: Self.zeroBuffer)
        draw(drawn.pass, program: drawn.program, variant: drawn.variant, current: drawn.current, previous: drawn.previous,
             fbos: drawn.fbos, context: context, standIn: drawn.standIn, scriptWrites: drawn.scriptWrites,
             repeatingFBOs: drawn.repeatingFBOs, targetSize: context.texelSizeReference ?? drawn.targetSize,
             scene: scene, encoder: encoder, commandBuffer: commandBuffer)
        return true
    }

    /// "layer effect pass", for `passTimer`.
    private static func passLabel(_ layerID: String, effect: SceneEffectPlan, pass: Int) -> String {
        let name = (effect.file as NSString).deletingLastPathComponent.split(separator: "/").last.map(String.init) ?? effect.file
        return "\(layerID) \(name) \(pass)"
    }

    /// How many of the chain's leading effects (by index, hidden ones included) give an output that
    /// doesn't change over time, when some later visible effect does: 0 when the whole chain is
    /// static (its output is kept whole) or its first visible effect varies.
    static func staticPrefix(_ effects: [SceneEffectPlan], programs: [[UniformProgram?]], hidden: Set<Int>) -> Int {
        func isStatic(_ index: Int) -> Bool {
            !effects[index].carriesFrames && zip(effects[index].passes, programs[index]).allSatisfy { pass, program in
                guard case .render = pass.command else { return true }
                return (program?.isReusable ?? true) && !pass.readsSceneSnapshot && !pass.readsMipMappedFrameBuffer
                    && pass.systemTextures.isEmpty
            }
        }
        var prefix = 0
        while prefix < effects.count, hidden.contains(prefix) || isStatic(prefix) { prefix += 1 }
        let visibleBefore = (0..<prefix).contains { !hidden.contains($0) }
        let variesLater = (prefix..<effects.count).contains { !hidden.contains($0) }
        return visibleBefore && variesLater ? prefix : 0
    }

    /// Keeps `output`, the chain's image after its static prefix, for the frames that follow.
    private func keepPrefix(_ output: MTLTexture, of state: LayerState, input: MTLTexture, key: StaticChainKey,
                            effects: Int, commandBuffer: MTLCommandBuffer) {
        state.prefixOutput = nil
        // A prefix that drew nothing into the chain leaves the input, which needs no keeping.
        guard output !== input else { return }
        if state.prefixTarget.map({ $0.width != output.width || $0.height != output.height || $0.pixelFormat != output.pixelFormat }) ?? true {
            state.prefixTarget.map(recycle)
            state.prefixTarget = target(width: output.width, height: output.height, format: output.pixelFormat)
            if let kept = state.prefixTarget, let size = state.standInSizes[ObjectIdentifier(output)] {
                state.standInSizes[ObjectIdentifier(kept)] = size
            }
        }
        guard let kept = state.prefixTarget, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: output, to: kept)
        blit.endEncoding()
        state.prefixOutput = (key, effects)
    }

    // MARK: - Pipelines

    /// Target format of every render pass (per effect, per pass), or nil while any pipeline is
    /// still compiling. Compiles are started here; a pipeline that failed just skips its pass.
    private func readyFormats(_ effects: [SceneEffectPlan], targetFormats: TargetFormats) -> [[MTLPixelFormat?]]? {
        var formats: [[MTLPixelFormat?]] = []
        var ready = true
        for effect in effects {
            let fboFormats = Dictionary(effect.fbos.map { ($0.name, Self.pixelFormat($0.format, frameBuffer: targetFormats.frameBuffer)) },
                                        uniquingKeysWith: { a, _ in a })
            var effectFormats: [MTLPixelFormat?] = []
            for pass in effect.passes {
                guard case .render = pass.command, let variant = pass.variant else {
                    effectFormats.append(nil)
                    continue
                }
                let format = pass.target.flatMap { fboFormats[$0] } ?? targetFormats.output
                effectFormats.append(format)
                let key = Self.pipelineKey(pass, format: format)
                // Checked and claimed in one step, so callers on two threads never both compile it.
                let state: (done: Bool, start: Bool) = pipelineLock.withLock {
                    if pipelines[key] != nil { usedPipelines.insert(key) }
                    if pipelines[key] != nil || failedPipelines.contains(key) { return (true, false) }
                    return (false, pendingPipelines.insert(key).inserted)
                }
                if state.done { continue }
                ready = false
                if state.start { compile(pass, variant: variant, format: format, key: key) }
            }
            formats.append(effectFormats)
        }
        return ready ? formats : nil
    }

    /// Every render pass's pipeline once `readyFormats` found them all compiled (a failed one is
    /// nil, and its pass is skipped). Held by the layer, so a trim that drops idle pipelines from
    /// the cache never drops one a layer still draws with.
    private func resolvedPipelines(_ effects: [SceneEffectPlan], formats: [[MTLPixelFormat?]]) -> [[MTLRenderPipelineState?]] {
        pipelineLock.withLock {
            effects.enumerated().map { effectIndex, effect in
                effect.passes.enumerated().map { passIndex, pass in
                    formats[effectIndex][passIndex].flatMap { pipelines[Self.pipelineKey(pass, format: $0)] }
                }
            }
        }
    }

    private static func pipelineKey(_ pass: SceneEffectPassPlan, format: MTLPixelFormat) -> String {
        "\(pass.variantKey)|\(format.rawValue)|\(pass.blending)"
    }

    /// Compiles a pipeline claimed in `pendingPipelines` by the caller: `pass` into `format`, with
    /// its own blending or `blending`, `sampleCount` samples and a `depthFormat` depth attachment.
    private func compile(_ pass: SceneEffectPassPlan, variant: TranslatedShaderVariant, format: MTLPixelFormat, key: String,
                         blending: String? = nil, sampleCount: Int = 1, depthFormat: MTLPixelFormat = .invalid) {
        pipelineLock.withLock { pipelineCompiles += 1 }
        let device = self.device
        let blending = blending ?? pass.blending
        let archive = pipelineArchive
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
                descriptor.colorAttachments[0].pixelFormat = format
                descriptor.rasterSampleCount = sampleCount
                descriptor.depthAttachmentPixelFormat = depthFormat
                if let blend = Self.blendMode(blending) {
                    let attachment = descriptor.colorAttachments[0]!
                    attachment.isBlendingEnabled = true
                    attachment.sourceRGBBlendFactor = blend.source
                    attachment.sourceAlphaBlendFactor = blend.source
                    attachment.destinationRGBBlendFactor = blend.destination
                    attachment.destinationAlphaBlendFactor = blend.destination
                }
                descriptor.vertexDescriptor = Self.vertexDescriptor(for: vertex)
                result = try Self.makePipeline(descriptor, device: device, archive: archive, key: key)
            } catch {
                OWELog.error(.shader, "Effect pipeline failed (\(key.prefix(12))): \(error)")
                result = nil
            }
            guard let self else { return }
            self.pipelineLock.withLock {
                self.pendingPipelines.remove(key)
                self.landedPipelines &+= 1
                if let result { self.pipelines[key] = result } else { self.failedPipelines.insert(key) }
            }
        }
    }

    /// Takes the pipeline from the archive when it has it; otherwise compiles it and adds it.
    static func makePipeline(_ descriptor: MTLRenderPipelineDescriptor, device: MTLDevice,
                             archive: EffectPipelineArchive?, key: String) throws -> MTLRenderPipelineState {
        guard let archive else { return try device.makeRenderPipelineState(descriptor: descriptor) }
        let archives = archive.archives
        if !archives.isEmpty {
            descriptor.binaryArchives = archives
            // Optional: a miss is the normal case for a new pipeline and falls through to a full compile.
            if let hit = try? device.makeRenderPipelineState(descriptor: descriptor, options: [.failOnBinaryArchiveMiss]).0 {
                archive.recordHit(descriptor, key: key)
                return hit
            }
        }
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        archive.add(descriptor, key: key)
        return pipeline
    }

    /// Whether a pipeline is still compiling off the render thread (shader prewarm).
    /// Compiles finished so far, however they ended: a frame drawn before one landed is redrawn.
    var pipelinesLanded: Int {
        pipelineLock.withLock { landedPipelines }
    }
    private var landedPipelines = 0

    var hasPendingPipelines: Bool {
        pipelineLock.withLock { !pendingPipelines.isEmpty }
    }

    /// Blocks until every pipeline these effects need has compiled or failed (tests, prewarming).
    func waitUntilReady(_ effects: [SceneEffectPlan], width: Int, height: Int,
                        targetFormats: TargetFormats = TargetFormats(frameBuffer: .rgba8Unorm, output: .rgba8Unorm),
                        timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while readyFormats(effects, targetFormats: targetFormats) == nil {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

    // MARK: - Passes

    /// The sizes a chain's textures stand for (`Context.inputStandInSize`).
    fileprivate struct StandIn {
        let input: MTLTexture
        let inputSize: SIMD2<Int>
        let targets: [ObjectIdentifier: SIMD2<Float>]
        /// The layer, for `passTimer`.
        var label = ""

        /// The size `texture` reports to the built-ins; nil for its own.
        func size(of texture: MTLTexture) -> SIMD2<Float>? {
            if texture === input { return SIMD2(Float(inputSize.x), Float(inputSize.y)) }
            return targets[ObjectIdentifier(texture)]
        }
    }

    private func encode(_ pass: SceneEffectPassPlan, pipeline: MTLRenderPipelineState, program: UniformProgram,
                        variant: TranslatedShaderVariant, output: MTLTexture,
                        current: MTLTexture, previous: MTLTexture, fbos: [String: MTLTexture],
                        context: Context, standIn: StandIn, scriptWrites: [SceneScriptConstantWrite],
                        repeatingFBOs: Set<String> = [], commandBuffer: MTLCommandBuffer) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = output
        // Blended passes composite over what's already there; others overwrite every pixel.
        descriptor.colorAttachments[0].loadAction = Self.blendMode(pass.blending) == nil ? .dontCare : .load
        descriptor.colorAttachments[0].storeAction = .store
        passTimer?.attach(to: descriptor, label: "\(standIn.label) \(output.width)x\(output.height)",
                          pixels: output.width * output.height)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        defer { encoder.endEncoding() }
        passesEncoded += 1
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(quadPositions, offset: 0, index: Self.positionBuffer)
        encoder.setVertexBuffer(quadTexCoords, offset: 0, index: Self.texCoordBuffer)
        encoder.setVertexBuffer(zeroAttributes, offset: 0, index: Self.zeroBuffer)
        let targetSize = context.texelSizeReference ?? standIn.size(of: output)
            ?? SIMD2<Float>(Float(output.width), Float(output.height))
        draw(pass, program: program, variant: variant, current: current, previous: previous, fbos: fbos, context: context,
             standIn: standIn, scriptWrites: scriptWrites, repeatingFBOs: repeatingFBOs, targetSize: targetSize,
             scene: nil, encoder: encoder, commandBuffer: commandBuffer)
    }

    /// Binds `pass`'s textures and uniforms and draws its quad into `encoder`'s pass. `targetSize` is
    /// what the built-ins take for the pass's target (`g_TexelSize`); `scene` places the quad in the
    /// scene (the chain's last pass, `encode(_:into:scene:context:commandBuffer:)`), nil fills the target.
    private func draw(_ pass: SceneEffectPassPlan, program: UniformProgram, variant: TranslatedShaderVariant,
                      current: MTLTexture, previous: MTLTexture, fbos: [String: MTLTexture], context: Context,
                      standIn: StandIn, scriptWrites: [SceneScriptConstantWrite], repeatingFBOs: Set<String>,
                      targetSize: SIMD2<Float>, scene: ScenePlacement?, encoder: MTLRenderCommandEncoder,
                      commandBuffer: MTLCommandBuffer) {
        var textureInfo: [Int: BuiltinTextureInfo] = [:]
        for slot in variant.textureSlots {
            guard let input = pass.textures[slot] else { continue }
            var texture: MTLTexture?
            var contentSize: SIMD2<Float>?
            var sprite: BuiltinSpriteFrame?
            var sampler = clampSampler
            switch input {
            case .current: texture = current
            case .previous: texture = previous
            case .fbo(let name):
                texture = fbos[name] ?? ModelMaterialPlanBuilder.compositeLayerID(name).flatMap(context.layerComposite)
                    ?? (name == ScenePlanarReflection.name ? context.planarReflection : nil)
                // An FBO declared with `"uvs": "repeat"` tiles (glitter's tile); others clamp.
                if repeatingFBOs.contains(name) { sampler = assetSamplers[0] ?? clampSampler }
            case .sceneSnapshot: texture = context.sceneSnapshot
            case .mipMappedFrameBuffer: texture = context.mipMappedFrameBuffer
            case .asset(let key, let source):
                texture = context.assetTexture(key, source)
                contentSize = context.assetContentSize?(key, source)
                sprite = context.assetSprite?(key, source)
                let flags = (pass.textureFlags[slot] ?? []).intersection([.clampUVs, .noInterpolation])
                sampler = assetSamplers[flags.rawValue] ?? clampSampler
            }
            // A system texture (the now-playing artwork) replaces the slot's input while there is one.
            if let kind = pass.systemTextures[slot], let system = context.systemTexture(kind) {
                texture = system
                contentSize = nil
                sprite = nil
                sampler = clampSampler
            }
            guard let texture else { continue }
            encoder.setFragmentTexture(texture, index: slot)
            encoder.setFragmentSamplerState(sampler, index: slot)
            encoder.setVertexTexture(texture, index: slot)
            encoder.setVertexSamplerState(sampler, index: slot)
            if program.needsTextureInfo {
                var info = Self.textureInfo(for: texture, contentSize: contentSize)
                if let size = standIn.size(of: texture) {
                    info.allocatedSize = size
                    info.contentSize = size
                }
                info.spriteRotation = sprite?.rotation
                info.spriteTranslation = sprite?.translation
                textureInfo[slot] = info
            }
        }

        if program.size > 0 {
            var passContext = BuiltinPassContext(targetSize: targetSize)
            if let scene {
                passContext.modelMatrix = scene.model
                passContext.viewMatrix = scene.view
                passContext.viewProjection = scene.viewProjection
                passContext.modelViewProjection = scene.viewProjection * scene.model
            }
            passContext.textures = textureInfo
            passContext.color = context.layerColor
            passContext.alpha = context.layerAlpha
            passContext.renderVars = context.passRenderVars[pass.materialIndex] ?? [:]
            passContext.effectTextureProjection = context.effectTextureProjection
            program.update(frame: context.frame, pass: passContext, values: context.values)
            program.write(scriptWrites.filter { $0.reaches(material: pass.materialIndex) })
            if let record = context.recordAnimated { program.recordAnimated(record) }
            program.bytes.withUnsafeBytes { raw in
                uniformArena.bind(raw, index: 0, to: encoder, commandBuffer: commandBuffer)
            }
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// `g_EffectTextureProjectionMatrix` of a layer drawn as `quad` in an orthographic scene of
    /// `sceneSize`: from the effect's texture space (x right, y up, −1…1 across the layer's image)
    /// to the screen's (−1…1, y up). Cursor effects take the pointer through its inverse into the
    /// layer's image (x-ray's sprite, cursor ripple's and the fluid simulation's force), and depth
    /// parallax turns the parallax direction by it, so they follow a moved, scaled or rotated layer.
    static func effectTextureProjection(quad: SceneQuadGeometry, sceneSize: SIMD2<Float>) -> simd_float4x4 {
        let size = simd_max(sceneSize, SIMD2(1, 1))
        let axisX = quad.axisX / size, axisY = quad.axisY / size
        let centre = quad.center / size * 2 - 1
        return simd_float4x4(columns: (SIMD4(axisX.x, axisX.y, 0, 0), SIMD4(axisY.x, axisY.y, 0, 0),
                                       SIMD4(0, 0, 1, 0), SIMD4(centre.x, centre.y, 0, 1)))
    }

    /// Position and texcoord come from the quad; any other attribute a shader reads is zero.
    static func vertexDescriptor(for function: MTLFunction) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        for attribute in function.vertexAttributes ?? [] where attribute.isActive {
            let index = attribute.attributeIndex
            let element = descriptor.attributes[index]!
            element.offset = 0
            switch index {
            case 0:
                element.format = .float3
                element.bufferIndex = positionBuffer
            case 1:
                element.format = .float2
                element.bufferIndex = texCoordBuffer
            default:
                element.format = .float4
                element.bufferIndex = zeroBuffer
            }
        }
        // Only buffers some attribute reads may have a layout, or Metal rejects the descriptor.
        let used = Set((function.vertexAttributes ?? []).filter(\.isActive).map {
            descriptor.attributes[$0.attributeIndex]!.bufferIndex
        })
        if used.contains(positionBuffer) { descriptor.layouts[positionBuffer].stride = 12 }
        if used.contains(texCoordBuffer) { descriptor.layouts[texCoordBuffer].stride = 8 }
        if used.contains(zeroBuffer) {
            descriptor.layouts[zeroBuffer].stride = 16
            descriptor.layouts[zeroBuffer].stepFunction = .constant
            descriptor.layouts[zeroBuffer].stepRate = 0
        }
        return descriptor
    }

    // MARK: - Targets

    /// Built-in texture info: allocated size is the GPU texture, content size the image inside it
    /// (clamped to the allocation; the allocation when unknown).
    static func textureInfo(for texture: MTLTexture, contentSize: SIMD2<Float>?) -> BuiltinTextureInfo {
        let allocated = SIMD2<Float>(Float(texture.width), Float(texture.height))
        var content = allocated
        if let contentSize, contentSize.x > 0, contentSize.y > 0 {
            content = simd_min(contentSize, allocated)
        }
        return BuiltinTextureInfo(allocatedSize: allocated, contentSize: content, spriteRotation: nil,
                                  spriteTranslation: nil, mipCount: texture.mipmapLevelCount)
    }

    private func allocateTargets(_ state: LayerState, effects: [SceneEffectPlan], width: Int, height: Int,
                                 standIn: SIMD2<Int>? = nil) {
        state.width = width
        state.height = height
        state.staticOutput = nil
        state.staticDrawn = nil
        state.prefixOutput = nil
        state.scratchReleased = false
        let standIn = standIn ?? SIMD2(width, height)
        state.standInSize = standIn
        state.standInSizes = [:]
        let drawnSmaller = standIn != SIMD2(width, height)
        func remember(_ texture: MTLTexture?, standsFor size: SIMD2<Int>, reduced: Bool = false) {
            guard drawnSmaller || reduced, let texture else { return }
            state.standInSizes[ObjectIdentifier(texture)] = SIMD2(Float(size.x), Float(size.y))
        }
        // The ping-pong targets are made when a pass first draws into one (`pingTarget`).
        state.pingA = nil
        state.pingB = nil
        state.fbos = effects.map { effect in
            Dictionary(effect.fbos.compactMap { fbo -> (String, MTLTexture)? in
                let (size, reducedFrom) = state.resolution.fboSize(fbo, in: effect, width: width, height: height)
                let format = Self.pixelFormat(fbo.format, frameBuffer: state.targetFormats.frameBuffer)
                let texture = target(width: size.x, height: size.y, format: format)
                remember(texture, standsFor: Self.fboSize(fbo, width: standIn.x, height: standIn.y), reduced: reducedFrom != nil)
                if let texture { state.pendingClears.append((texture, Self.clearColor(fbo.clear))) }
                return texture.map { (fbo.name, $0) }
            }, uniquingKeysWith: { a, _ in a })
        }
    }


    /// An FBO's `clear` ("r g b a"); transparent black when it has none. Pooled targets hold
    /// whatever they last held, and a simulation's buffers (`effects/fluidsimulation`) read
    /// themselves from the previous frame, so garbage (a NaN) would stay in them for good.
    static func clearColor(_ authored: String?) -> MTLClearColor {
        let parts = (authored ?? "").split(separator: " ").compactMap { Double($0) }
        func part(_ index: Int) -> Double { index < parts.count && parts[index].isFinite ? parts[index] : 0 }
        return MTLClearColor(red: part(0), green: part(1), blue: part(2), alpha: part(3))
    }

    /// Clears the FBOs made since the last frame to their start colour, before any pass reads one.
    private func clearNewTargets(_ state: LayerState, commandBuffer: MTLCommandBuffer) {
        for (texture, color) in state.pendingClears {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = color
            pass.colorAttachments[0].storeAction = .store
            commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }
        state.pendingClears.removeAll()
    }

    /// The layer's first or `second` ping-pong target, made at the chain's size on first use.
    private func pingTarget(of state: LayerState, second: Bool) -> MTLTexture? {
        if let existing = second ? state.pingB : state.pingA { return existing }
        guard let made = target(width: state.width, height: state.height, format: state.targetFormats.output) else { return nil }
        if state.standInSize != SIMD2(state.width, state.height) {
            state.standInSizes[ObjectIdentifier(made)] = SIMD2(Float(state.standInSize.x), Float(state.standInSize.y))
        }
        if second { state.pingB = made } else { state.pingA = made }
        return made
    }

    /// Hands the targets a kept chain output no longer needs to the spare list: every ping, FBO and
    /// prefix target except `keeping` (the output, or what the last pass samples). The chain can't
    /// carry frames (`reusable`), so every FBO it reads is written earlier in the same frame and a
    /// target taken back holds nothing the chain depends on.
    private func releaseScratch(_ state: LayerState, keeping: [MTLTexture]) {
        let kept = Set(keeping.map(ObjectIdentifier.init))
        func release(_ texture: MTLTexture?) -> MTLTexture? {
            guard let texture, !kept.contains(ObjectIdentifier(texture)) else { return texture }
            state.standInSizes[ObjectIdentifier(texture)] = nil
            recycle(texture)
            return nil
        }
        state.pingA = release(state.pingA)
        state.pingB = release(state.pingB)
        if state.prefixTarget.flatMap(release) == nil {
            state.prefixTarget = nil
            state.prefixOutput = nil
        }
        state.fbos = state.fbos.map { fbos in fbos.compactMapValues(release) }
        state.scratchReleased = true
    }

    /// Takes back the FBOs `releaseScratch` handed out, at the size and format they had, cleared
    /// to their start colour as new ones are. Ping targets come back on first use (`pingTarget`).
    private func reacquireScratch(_ state: LayerState, effects: [SceneEffectPlan]) {
        state.scratchReleased = false
        let drawnSmaller = state.standInSize != SIMD2(state.width, state.height)
        for (index, effect) in effects.enumerated() where index < state.fbos.count {
            for fbo in effect.fbos where state.fbos[index][fbo.name] == nil {
                let (size, reducedFrom) = state.resolution.fboSize(fbo, in: effect, width: state.width, height: state.height)
                let format = Self.pixelFormat(fbo.format, frameBuffer: state.targetFormats.frameBuffer)
                guard let texture = target(width: size.x, height: size.y, format: format) else { continue }
                if drawnSmaller || reducedFrom != nil {
                    let standsFor = Self.fboSize(fbo, width: state.standInSize.x, height: state.standInSize.y)
                    state.standInSizes[ObjectIdentifier(texture)] = SIMD2(Float(standsFor.x), Float(standsFor.y))
                }
                state.pendingClears.append((texture, Self.clearColor(fbo.clear)))
                state.fbos[index][fbo.name] = texture
            }
        }
    }

    /// Hands a layer's targets to the spare list. Contents don't matter: every pass either
    /// overwrites its target or (blended) runs after one that did.
    private func recycleTargets(_ state: LayerState) {
        let owned = [state.pingA, state.pingB, state.prefixTarget].compactMap { $0 } + state.fbos.flatMap(\.values)
        state.pingA = nil
        state.pingB = nil
        state.prefixTarget = nil
        state.fbos = []
        state.staticOutput = nil
        state.staticDrawn = nil
        state.prefixOutput = nil
        owned.forEach(recycle)
    }

    /// Hands one target to the spare list (`evictSpares`).
    private func recycle(_ texture: MTLTexture) {
        let key = TargetKey(width: texture.width, height: texture.height, format: texture.pixelFormat)
        spareCounter += 1
        spareTargets[key, default: []].append(Spare(texture: texture, since: now(), order: spareCounter))
        spareBytes += texture.allocatedSize
        evictSpares()
    }

    /// At most once a second: drops spares idle past `spareIdleSeconds` even while no layer
    /// changes size.
    private func sweepIdleSpares() {
        guard !spareTargets.isEmpty else { return }
        let time = now()
        guard time - lastSpareSweep >= 1 else { return }
        lastSpareSweep = time
        evictSpares()
    }

    /// Drops spares idle past `spareIdleSeconds`, then the longest idle until the rest fit
    /// `spareByteBudget`. Each size's list stays oldest first, so `target` takes the newest.
    private func evictSpares() {
        let cutoff = now() - spareIdleSeconds
        var kept: [(key: TargetKey, spare: Spare)] = []
        for (key, spares) in spareTargets {
            for spare in spares where spare.since >= cutoff { kept.append((key, spare)) }
        }
        kept.sort { ($0.spare.since, $0.spare.order) < ($1.spare.since, $1.spare.order) }
        var total = kept.reduce(0) { $0 + $1.spare.texture.allocatedSize }
        var first = 0
        while total > spareByteBudget, first < kept.count {
            total -= kept[first].spare.texture.allocatedSize
            first += 1
        }
        spareTargets.removeAll(keepingCapacity: true)
        for entry in kept[first...] { spareTargets[entry.key, default: []].append(entry.spare) }
        spareBytes = total
    }

    private func target(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let key = TargetKey(width: max(width, 1), height: max(height, 1), format: format)
        if var spares = spareTargets[key], let spare = spares.popLast() {
            spareTargets[key] = spares.isEmpty ? nil : spares
            spareBytes -= spare.texture.allocatedSize
            return spare.texture
        }
        targetsAllocated += 1
        return makeTarget(width: width, height: height, format: format)
    }

    private func makeTarget(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(width, 1),
                                                                  height: max(height, 1), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // An sRGB output is read back as its encoded bytes (`SceneHDRChain.encodedView`).
        if format == .rgba8Unorm_srgb || format == .bgra8Unorm_srgb { descriptor.usage.insert(.pixelFormatView) }
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// `scale` divides the layer size; `fit` bounds the larger side.
    static func fboSize(_ fbo: EffectFBO, width: Int, height: Int) -> SIMD2<Int> {
        // A fixed `width`/`height` (glitter's 256² tile) doesn't follow the layer.
        if let fixedWidth = fbo.width, let fixedHeight = fbo.height, fixedWidth > 0, fixedHeight > 0 {
            return SIMD2(fixedWidth, fixedHeight)
        }
        var w = Double(width) / Double(max(fbo.scale, 1))
        var h = Double(height) / Double(max(fbo.scale, 1))
        if let fit = fbo.fit, fit > 0 {
            let factor = Double(fit) / max(w, h)
            w *= factor
            h *= factor
        }
        // Saturating: a zero-sized layer or an extreme `fit` gives a 1-pixel side, not a stop.
        return SIMD2(Int(saturating: w.rounded(), in: 1...Int.max), Int(saturating: h.rounded(), in: 1...Int.max))
    }

    /// `frameBuffer` is WE's frame-buffer class format, which `rgba_backbuffer` and
    /// `rgb_backbuffer` name (`Context.frameBufferFormat`).
    static func pixelFormat(_ format: String, frameBuffer: MTLPixelFormat = .rgba8Unorm) -> MTLPixelFormat {
        switch format.lowercased() {
        case "rgba_backbuffer", "rgb_backbuffer": return frameBuffer
        case "r16f": return .r16Float
        case "rg1616f": return .rg16Float
        case "rgba16161616f", "rgba16f": return .rgba16Float
        case "r8": return .r8Unorm
        case "rg88": return .rg8Unorm
        default: return .rgba8Unorm
        }
    }

    /// WE material blending → blend factors; nil means no blending (overwrite).
    ///
    /// `normal` and `disabled` overwrite. Any other value also overwrites and is logged once:
    /// WE's full list of values isn't known, and the bundled assets and library use only these.
    static func blendMode(_ blending: String) -> (source: MTLBlendFactor, destination: MTLBlendFactor)? {
        switch blending.lowercased() {
        case "translucent": return (.sourceAlpha, .oneMinusSourceAlpha)
        case "additive": return (.sourceAlpha, .one)
        case "normal", "disabled", "": return nil
        default:
            let first = unknownBlendingLock.withLock { unknownBlending.insert(blending).inserted }
            if first { OWELog.error(.shader, "Unknown material blending \"\(blending)\"; drawing it as normal") }
            return nil
        }
    }

    /// Blending values `blendMode` didn't know, each logged once. Global because materials of
    /// every renderer share the table; `unknownBlendingLock` owns it.
    private static let unknownBlendingLock = NSLock()
    nonisolated(unsafe) private static var unknownBlending = Set<String>() // guarded by unknownBlendingLock

    /// Unknown blending values seen so far (tests, diagnostics).
    static var unknownBlendingValues: Set<String> { unknownBlendingLock.withLock { unknownBlending } }
}

/// A pass's `WEUniforms` bytes: static values written once, dynamic constants and live built-ins
/// patched each frame. Avoids per-frame dictionaries and allocations on the render thread.
final class UniformProgram {
    private(set) var bytes: [UInt8]
    let size: Int
    /// True when only the live-bound constants can change between frames (no time, audio or
    /// pointer built-in): an output is reusable while their values (`appendDynamicValues`) stay.
    let isReusable: Bool
    let needsTextureInfo: Bool
    private let dynamic: [(member: UniformMember, constant: ShaderConstantResolver.DynamicConstant)]
    /// Members scripts can set, by the lower-cased scene.json key they answer to.
    private let scriptTargets: [String: [(member: UniformMember, binding: ShaderConstantResolver.ScriptBinding)]]
    /// Built-ins that only depend on the pass's targets and textures: written when those change.
    private let passBuiltins: [UniformMember]
    /// Built-ins that follow the placement or the camera (`BuiltinUniforms.Key.followsCamera`):
    /// written when those change, which a camera path or shake does every frame.
    private let cameraBuiltins: [(member: UniformMember, key: BuiltinUniforms.Key)]
    /// Built-ins that change every frame (time, pointer, audio).
    private let frameBuiltins: [UniformMember]
    private var passSignature: [Float] = []
    private var cameraSignature: CameraSignature?

    /// What `cameraBuiltins` are computed from.
    private struct CameraSignature: Equatable {
        var modelViewProjection, modelMatrix, viewMatrix, viewProjection, effectTextureProjection: simd_float4x4
        var altModelMatrix, altViewProjection: simd_float4x4?
        var eye, viewUp, viewRight, viewForward: SIMD3<Float>

        init(frame: BuiltinFrameContext, pass: BuiltinPassContext) {
            modelViewProjection = pass.modelViewProjection
            modelMatrix = pass.modelMatrix
            viewMatrix = pass.viewMatrix
            viewProjection = pass.viewProjection
            effectTextureProjection = pass.effectTextureProjection
            altModelMatrix = pass.altModelMatrix
            altViewProjection = pass.altViewProjection
            eye = frame.eyePosition
            viewUp = frame.viewUp
            viewRight = frame.viewRight
            viewForward = frame.viewForward
        }
    }

    /// Built-ins whose value changes from frame to frame.
    static let timeVarying: Set<String> = Set(["g_Time", "g_Frametime", "g_Daytime", "g_DayTime", "g_PointerPosition",
                                               "g_PointerPositionLast", "g_PointerState", "g_ParallaxPosition"])
        .union(SceneFrameLighting.uniformNames)

    init(layout: UniformLayout?, constants: ShaderConstantResolver.ResolvedConstants) {
        size = layout?.size ?? 0
        bytes = [UInt8](repeating: 0, count: size)
        let dynamicByName = Dictionary(constants.dynamic.map { ($0.uniform, $0) }, uniquingKeysWith: { a, _ in a })
        var dynamic: [(UniformMember, ShaderConstantResolver.DynamicConstant)] = []
        var builtins: [UniformMember] = []
        for member in (layout?.members.values).map(Array.init) ?? [] {
            // A stage's own copy of a uniform (`ShaderUniformDeclaration.stageLocalNames`) takes
            // the shared value when its planner didn't resolve it apart.
            let shared = member.name.hasSuffix(ShaderUniformDeclaration.fragmentSuffix)
                ? String(member.name.dropLast(ShaderUniformDeclaration.fragmentSuffix.count)) : member.name
            if let constant = dynamicByName[member.name] ?? dynamicByName[shared] {
                dynamic.append((member, constant))
            } else if let value = constants.staticValues[member.name] ?? constants.staticValues[shared] {
                UniformWriter.write(value.components, member: member, into: &bytes)
            } else if BuiltinUniforms.isBuiltin(member.name) {
                builtins.append(member)
            }
        }
        self.dynamic = dynamic
        var scriptTargets: [String: [(member: UniformMember, binding: ShaderConstantResolver.ScriptBinding)]] = [:]
        let members = layout?.members ?? [:]
        for binding in constants.scriptBindings {
            guard let member = members[binding.uniform] else { continue }
            for key in Set(binding.keys) { scriptTargets[key, default: []].append((member, binding)) }
        }
        self.scriptTargets = scriptTargets
        let varies = { (member: UniformMember) in
            Self.timeVarying.contains(member.name) || member.name.hasPrefix("g_AudioSpectrum")
        }
        frameBuiltins = builtins.filter(varies)
        let fixed = builtins.filter { !varies($0) }
        let camera: [(member: UniformMember, key: BuiltinUniforms.Key)] = fixed.compactMap { member in
            BuiltinUniforms.Key(member.name).flatMap { $0.followsCamera ? (member, $0) : nil }
        }
        let cameraNames = Set(camera.map(\.member.name))
        cameraBuiltins = camera
        passBuiltins = fixed.filter { !cameraNames.contains($0.name) }
        needsTextureInfo = builtins.contains { $0.name.hasPrefix("g_Texture") }
        isReusable = frameBuiltins.isEmpty
    }

    /// Hands `record` each animated constant's site and the floats its uniform holds (script writes
    /// included): what the GPU gets. Integer and matrix members aren't read back.
    func recordAnimated(_ record: (SceneAnimationSite, [Float]) -> Void) {
        for (member, constant) in dynamic {
            guard let site = constant.source.animationSite, member.type.hasPrefix("float") || member.type.hasPrefix("vec")
            else { continue }
            let count = min(constant.count, 4)
            guard member.offset + count * 4 <= bytes.count else { continue }
            let values = (0..<count).map { component in
                bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: member.offset + component * 4, as: Float.self) }
            }
            record(site, values)
        }
    }

    /// Appends the live-bound constants' values this frame, as `update` writes them.
    func appendDynamicValues(to values: inout [Float], values context: SceneValueContext) {
        for (_, constant) in dynamic {
            values += ShaderConstantResolver.shape(SceneValueResolver.resolve(constant.source, in: context),
                                                   count: constant.count, isInt: constant.isInt).components
        }
    }

    /// Writes what scripts set (`setMaterialProperty`, `IMaterial` members) over the constants,
    /// in the order they were set: the last write of a key wins, as it does in the scripts.
    func write(_ scriptWrites: [SceneScriptConstantWrite]) {
        for write in scriptWrites {
            for (member, binding) in scriptTargets[write.name.lowercased()] ?? [] {
                let value = ShaderConstantResolver.shape(ShaderValue(components: write.value),
                                                         count: binding.count, isInt: binding.isInt)
                UniformWriter.write(value.components, member: member, into: &bytes)
            }
        }
    }

    func update(frame: BuiltinFrameContext, pass: BuiltinPassContext, values: SceneValueContext) {
        for (member, constant) in dynamic {
            let value = ShaderConstantResolver.shape(SceneValueResolver.resolve(constant.source, in: values),
                                                     count: constant.count, isInt: constant.isInt)
            UniformWriter.write(value.components, member: member, into: &bytes)
        }
        write(frameBuiltins, frame: frame, pass: pass)
        // Name lookups are string work; do them only when the targets actually change.
        var signature: [Float] = [frame.screenSize.x, frame.screenSize.y, pass.targetSize.x, pass.targetSize.y, pass.alpha,
                                  pass.color.x, pass.color.y, pass.color.z, frame.textureReductionScale]
        for slot in pass.textures.keys.sorted() {
            let info = pass.textures[slot]!
            signature += [Float(slot), info.allocatedSize.x, info.allocatedSize.y, info.contentSize.x, info.contentSize.y]
            if let rotation = info.spriteRotation, let translation = info.spriteTranslation {
                signature += [rotation.x, rotation.y, rotation.z, rotation.w, translation.x, translation.y]
            }
        }
        for index in pass.renderVars.keys.sorted() {
            let value = pass.renderVars[index]!
            signature += [Float(index), value.x, value.y, value.z, value.w]
        }
        if signature != passSignature {
            passSignature = signature
            write(passBuiltins, frame: frame, pass: pass)
        }
        guard !cameraBuiltins.isEmpty else { return }
        let camera = CameraSignature(frame: frame, pass: pass)
        if camera != cameraSignature {
            cameraSignature = camera
            for (member, key) in cameraBuiltins {
                UniformWriter.write(BuiltinUniforms.value(key, frame: frame, pass: pass), member: member, into: &bytes)
            }
        }
    }

    private func write(_ members: [UniformMember], frame: BuiltinFrameContext, pass: BuiltinPassContext) {
        for member in members {
            if let components = BuiltinUniforms.value(named: member.name, frame: frame, pass: pass,
                                                      arrayCount: member.count > 1 ? member.count : nil) {
                UniformWriter.write(components, member: member, into: &bytes)
            }
        }
    }
}

/// Writes values into a std140 `WEUniforms` block as SPIRV-Cross laid it out.
enum UniformWriter {
    static func write(_ components: [Float], member: UniformMember, into bytes: inout [UInt8]) {
        let isInteger = member.type.hasPrefix("int") || member.type.hasPrefix("ivec")
            || member.type.hasPrefix("uint") || member.type.hasPrefix("uvec") || member.type == "bool"
        let perElement = componentsPerElement(member.type)
        let columns = matrixColumns(member.type)
        // One store per component into the buffer's memory: the shadow pass writes each caster's
        // view matrices through here, and per-byte copies made it most of a model scene's frame.
        let rows = columns.flatMap { member.matrixStride > 0 ? perElement / $0 : nil }
        let count = min(member.count * perElement, components.count)
        if !isInteger, member.offset >= 0 {
            copyRuns(components, count: count, member: member, perElement: perElement, run: rows ?? perElement,
                     into: &bytes)
            return
        }
        components.withUnsafeBufferPointer { values in
            bytes.withUnsafeMutableBytes { raw in
                var index = 0
                while index < count {
                    let element = index / perElement, component = index % perElement
                    let base = member.offset + element * member.arrayStride
                    let offset = rows.map { base + (component / $0) * member.matrixStride + (component % $0) * 4 }
                        ?? base + component * 4
                    if offset >= 0, offset + 4 <= raw.count {
                        let value = values[index]
                        raw.storeBytes(of: isInteger ? integerBits(value) : value.bitPattern, toByteOffset: offset, as: UInt32.self)
                    }
                    index += 1
                }
            }
        }
    }

    /// Floats as they stand, one copy per contiguous run: an element's components, or a matrix
    /// column's `run` rows (the model shaders' bones and view matrices are hundreds of floats a
    /// draw). The same bytes as a store per component, a run cut where the buffer ends.
    private static func copyRuns(_ components: [Float], count: Int, member: UniformMember, perElement: Int, run: Int,
                                 into bytes: inout [UInt8]) {
        components.withUnsafeBufferPointer { values in
            bytes.withUnsafeMutableBytes { raw in
                guard let source = values.baseAddress, let target = raw.baseAddress else { return }
                var index = 0
                while index < count {
                    let element = index / perElement, component = index % perElement
                    let offset = member.offset + element * member.arrayStride + (component / run) * member.matrixStride
                    let length = min(run, count - index)
                    let fits = min(length, max(0, (raw.count - offset) / 4))
                    if fits > 0 { (target + offset).copyMemory(from: source + index, byteCount: fits * 4) }
                    index += length
                }
            }
        }
    }

    /// Rounds to the nearest Int32, clamping out-of-range values; NaN becomes 0.
    static func integerBits(_ value: Float) -> UInt32 {
        guard !value.isNaN else { return 0 }
        let rounded = value.rounded()
        // Float(Int32.max) rounds up to 2^31, so compare against that, not the Int32.
        if rounded >= 2_147_483_648 { return UInt32(bitPattern: Int32.max) }
        if rounded <= -2_147_483_648 { return UInt32(bitPattern: Int32.min) }
        return UInt32(bitPattern: Int32(rounded))
    }

    static func componentsPerElement(_ type: String) -> Int {
        switch type {
        case "vec2", "ivec2", "uvec2": return 2
        case "vec3", "ivec3", "uvec3": return 3
        case "vec4", "ivec4", "uvec4": return 4
        case "mat2": return 4
        case "mat3": return 9
        case "mat4": return 16
        case "mat4x3": return 12
        case "mat3x4": return 12
        default: return 1
        }
    }

    static func matrixColumns(_ type: String) -> Int? {
        switch type {
        case "mat2": return 2
        case "mat3", "mat3x4": return 3
        case "mat4", "mat4x3": return 4
        default: return nil
        }
    }
}
