import Cocoa
import MetalKit
import CryptoKit
import OWESceneEditing

private struct PreparedLayer {
    let frames: [RenderTextureFrame]
    let layer: SceneMetalLayer
    /// Where the layer's own transform comes from each frame.
    let motion: SceneObjectMotion
    /// The particle systems to draw before this layer: every system whose authored order is below
    /// this (`SceneRendererScripts.drawOrder`).
    var particleBarrier: Int

    init(frames: [RenderTextureFrame], layer: SceneMetalLayer) {
        self.frames = frames
        self.layer = layer
        motion = SceneObjectMotion(layer: layer)
        particleBarrier = layer.order
    }
}

/// What a visible layer is drawn with this frame: its scripted/animated opacity and colour and
/// its placed quad. Computed once, before effects run, so effects see the same values.
private struct LayerDraw {
    let opacity: Float
    let color: SIMD4<Float>
    let brightness: Float
    /// World-space quad, parallax and camera shake included.
    let quad: SceneQuadGeometry
    let musicSyncLevel: Double
    /// The layer drawn through a 3D camera (a perspective scene's, or a `perspective` layer's in an
    /// orthographic scene, docs/models-plan.md §2.4); nil draws `quad` in the scene's plane.
    var placement: SceneLayerPlacement? = nil
}

/// Frame-wide camera motion applied to every layer.
private struct CameraMotion {
    /// This frame's parallax and `cameraparallaxamount` (times the app's amount), when objects
    /// are displaced: parallax on in an orthographic scene.
    let parallax: (state: SceneCameraParallax, amount: Float)?
    /// How far camera shake moved the camera, where the renderer moves the scene the other way
    /// instead: an orthographic scene, whose layers aren't drawn through the camera.
    let shake: SIMD2<Float>
    /// The shake a perspective scene's camera carries (`SceneCameraRigInput.shake`); zero in an
    /// orthographic scene.
    var cameraShake = SIMD3<Float>.zero
    let audioLevel: Double
}

struct RenderTextureFrame {
    let texture: MTLTexture
    let duration: Float
    let uvOrigin: SIMD2<Float>
    let uvAxisX: SIMD2<Float>
    let uvAxisY: SIMD2<Float>
    /// Text only: the glyphs' coverage, which WE's `font` material samples; nil for colour glyphs.
    var coverage: MTLTexture? = nil
    /// Text only: the block's centre from the object's origin, unscaled (`SceneTextLayout.boxCenter`).
    var textCenter = SIMD2<Float>.zero
}

final class SceneMetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    /// The drawables' format, which the layer and copy pipelines draw in.
    let pixelFormat: MTLPixelFormat
    let commandQueue: MTLCommandQueue
    /// The scene pass's own pipelines, in the scene target's format (`SceneLayerPipelines`).
    private let layerPipelines: SceneLayerPipelines
    private var renderPipeline: MTLRenderPipelineState { scenePassPipelines.normal }
    private var additiveRenderPipeline: MTLRenderPipelineState { scenePassPipelines.additive }
    /// The layer pipelines for the scene target's format, this frame's sample count and depth.
    private var scenePassPipelines: SceneLayerPipelines.Pipelines {
        // The drawable's when the scene draws straight into it (S2).
        guard let format = (sceneRenderTarget ?? lastDrawableScene)?.pixelFormat else { return layerPipelines.pipelines(for: nil) }
        return layerPipelines.pipelines(for: format, sampleCount: sceneSampleCount, depthFormat: sceneDepthFormat)
            ?? layerPipelines.pipelines(for: format)
    }
    /// An unblended copy in the drawables' format: a shared frame onto a display (`present(in:)`).
    private let copyPipeline: MTLRenderPipelineState
    /// Everything after the scene pass, up to the drawable (bloom and the composite).
    let postProcess: ScenePostProcess
    /// WE's work on the finished frame before its bloom (`SceneFrameStages`).
    private let frameStages: [SceneFrameStage]
    /// The stage that keeps `_rt_MipMappedFrameBuffer` (internal for tests and diagnostics), and
    /// its target for this frame's draws.
    let mipMappedFrameBuffer: SceneMipMappedFrameBuffer?
    private var mipMappedTarget: MTLTexture?
    /// The volumetrics stage (tests and diagnostics).
    var volumetrics: SceneVolumetrics? { frameStages.lazy.compactMap { $0 as? SceneVolumetrics }.first }
    private let dxtDecodePipeline: MTLComputePipelineState
    private let textureLoader: MTKTextureLoader
    private let renderTargetPool: SceneRenderTargetPool
    /// This frame's scene snapshot target (`sceneSnapshot`), leased on first use, and which part
    /// of it matches the scene drawn so far.
    private var sceneCopy: MTLTexture?
    /// This frame's scene snapshot goes into `_rt_MipMappedFrameBuffer`'s level 0
    /// (`SceneMipMappedFrameBuffer.snapshotCanShare`).
    private var snapshotSharesMipMappedTarget = false
    private(set) var snapshotTracker = SceneSnapshotTracker()
    /// Trims rebuildable memory when the system asks (`trimMemory`).
    private var memoryPressure: SceneMemoryPressure?
    /// Runs authored effects through Wallpaper Engine's own shaders.
    private lazy var effectGraph = EffectGraphRenderer(device: device, pipelineArchiveDirectory: pipelineArchiveDirectory)
    /// Where the effect pipeline archive lives (`EffectGraphRenderer`); nil keeps none.
    private let pipelineArchiveDirectory: URL?
    /// How much larger full detail would draw this frame's scene target (1 unless the scene is
    /// matched to a display smaller than it, `GSSceneDetail.matchDisplay`): the size effects on
    /// scene regions and text, and the bloom, stand for.
    private var fullDetailScale: Float = 1
    /// Scales a scene drawn at the render scale up to its target (`GSUpscaling`).
    private lazy var upscaler = SceneUpscaler(device: device)
    /// This frame is drawn below its target size and scaled up after the scene pass, so it
    /// can't be drawn straight into the output.
    private var drawsAtRenderScale = false
    /// Bumped for every prelit image an effect chain starts from (`runEffects`).
    private var prelitVersion: UInt64 = 0
    /// Times the effect passes when set (profiling; `EffectPassTimer`).
    var effectPassTimer: EffectPassTimer? {
        get { effectGraph?.passTimer }
        set { effectGraph?.passTimer = newValue }
    }
    /// Draws particle systems through their WE material.
    private lazy var particleMaterials = ParticleMaterialRenderer(device: device)
    /// Draws image layers through their own WE material.
    private lazy var imageMaterials = ImageMaterialRenderer(device: device, archive: effectGraph?.pipelineArchive)
    /// Draws Puppet Warp layers' meshes into their images (`ScenePuppetRenderer`).
    private lazy var puppets = ScenePuppetRenderer(device: device, archive: effectGraph?.pipelineArchive)
    /// Puppet layers' images this frame, by layer id: what `textureFrame(for:)` hands out for them.
    private var puppetAlbedos: [String: MTLTexture] = [:]
    /// Puppet layers' skeletons in motion, by layer id (`ScenePuppetAnimator`).
    private var puppetAnimators: [String: ScenePuppetAnimator] = [:]
    /// A puppet without effects: its material's other textures laid out like its posed mesh, by
    /// layer id and texture key (`ScenePuppetRenderer.warp`).
    private var puppetWarps: [String: [String: MTLTexture]] = [:]
    /// A puppet without effects: what of its mesh's space its image covers, which its quad grows
    /// to (`ScenePuppetCanvas`), by layer id.
    private var puppetCanvases: [String: ScenePuppetCanvas] = [:]
    /// Asset textures used by effect passes, materialised once per content.
    private var effectAssetTextures: [String: MTLTexture] = [:]
    /// Each decoded image's upload, by the image: layers, clones, particle systems and effect
    /// assets that load the same image (the loader hands them one `NSImage`) share one texture.
    /// Keyed weakly by the image itself, so an entry goes with the last copy of the image and the
    /// renderer never keeps the pixels alive; cleared with the content.
    private let uploadedImages = NSMapTable<NSImage, UploadedFrames>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    private final class UploadedFrames {
        let frames: [RenderTextureFrame]
        init(_ frames: [RenderTextureFrame]) { self.frames = frames }
    }
    private let uploadedImagesLock = NSLock()
    /// Particle textures with their mip chains (`ParticleTextureMipmaps`), by the uploaded texture
    /// they were made from, which each entry holds so its identifier isn't reused. Under
    /// `uploadedImagesLock`; cleared with the content.
    private var particleMipmaps: [ObjectIdentifier: (source: MTLTexture, chained: MTLTexture)] = [:]
    /// Animated asset textures' sprite frames, by the same key.
    private var effectAssetFrames: [String: [RenderTextureFrame]] = [:]
    /// Textureless layers' effect inputs (`solidEffectInput`), by layer id; once per content.
    private var solidEffectInputs: [String: MTLTexture] = [:]
    /// The media system textures, while the content has a layer that shows one.
    private var mediaTextures: SceneMediaTextures?
    /// Scene-input layers drawn through a 3D camera get the scene under them through this.
    private lazy var regionProjection = SceneRegionProjection(device: device)
    /// Scene time since the content loaded, speed applied; drives animations, `g_Time`,
    /// particles and scripts alike.
    private var clock = SceneClock()
    /// Test harnesses: while true the scene clock stands still (`SceneClock.hold`). The app never sets it.
    var holdsClock = false
    /// The frame being rendered only redraws the scene as it stands (`redrawShared`).
    private var redrawing = false
    /// The renderer draws the screen saver's loop video (`ScreenSaverLoopRenderer`): scripts see
    /// `engine.isScreensaver()` true. Set before the first frame.
    var rendersScreenSaver = false
    /// While true the scene's clock text layers (`SceneClockLayers`) draw nothing: set for the
    /// screen saver's loop video and while capturing the loading snapshot the lock screen shows.
    var hidesClockLayers = false
    /// The current content's clock text layers.
    private(set) var clockLayerIDs: Set<String> = []
    /// The frames drawn (`BuiltinFrameContext.serial`).
    private var frameSerial: UInt64 = 0
    /// The wall clock `clock` follows (tests step it).
    var wallTime: () -> CFTimeInterval = { CACurrentMediaTime() }
    /// The playback rate `clock` runs at, when set (tests); otherwise the Animation Speed of this
    /// instance's own property store (`ScenePlaybackSpeed`), WE's `rate`.
    var playbackRate: (() -> Double)?
    /// Advances the audio spectrum by one frame at a playback rate: this renderer's own smoothing
    /// of the app's capture, made on the first frame (tests feed their own). Each renderer steps
    /// its own, so several scenes don't step one another's and a web page's never depends on them.
    var audioSpectrumFrame: (Double) -> AudioSpectrumSnapshot = {
        var clock: AudioSpectrumClock?
        return { (playbackRate: Double) -> AudioSpectrumSnapshot in
            let current: AudioSpectrumClock = clock ?? WallpaperServices.shared.makeAudioSpectrumClock(publishes: true)
            clock = current
            return current.advanceFrame(playbackRate: playbackRate)
        }
    }()
    /// The wallpaper is paused (the app's pause, or every display it shows on): the clock eases to
    /// a stop as WE's does (`SceneClock.paused`), and `onPlaybackStopped` fires on each frame drawn
    /// once it stood still, so the displays can stop drawing.
    var pausesPlayback = false
    var onPlaybackStopped: (() -> Void)?
    /// Runs `block` on the thread that owns this renderer's state (thread boundary): content and
    /// script objects prepared in the background land through it. The main queue by default, for a
    /// renderer drawn by its view's own timer; a scene instance's renderer uses its render thread.
    /// A render loop owns this renderer (`SceneRenderLoop`): a frame anywhere but its render
    /// thread is a thread-guard hit. Without one (tests, prewarm) the thread drawing it counts as
    /// the render thread while it draws. Set once, before the first frame.
    var drawsOnRenderThreadOnly = false
    var performOnRenderThread: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    /// The paused clock has eased to a stop.
    var hasStoppedPlayback: Bool { clock.hasStopped }
    /// A script's fog on/off switch was reported (`frameLighting`).
    private var loggedFogToggle = false

    /// Scene seconds since the content loaded, rate applied (`g_Time`).
    var sceneTime: Double { clock.time }
    /// Mixed into the seed of every particle system the next content prepares. 0 replays a
    /// wallpaper's particles the same way each time; another value draws another random outcome
    /// (tests average a system of a few particles over several).
    var particleSeed: UInt32 = 0
    /// The wallpaper instance's timelines and texture clocks (docs/timeline-plan.md §2), advanced
    /// once per frame by `clock`'s delta, before the scripts run.
    let timelines = SceneRendererAnimations()
    /// The instance's `SceneAnimationSet`; nil without a scene document.
    var animations: SceneAnimationSet? { timelines.set }
    /// Records what each frame draws while set (tests and diagnostics, `SceneDrawProbe`).
    var drawProbe: SceneDrawProbe?
    private let contentQueue = DispatchQueue(label: "SceneMetalRenderer.content", qos: .userInitiated)
    private let contentGenerationLock = NSLock()
    private var contentGeneration = 0
    private var sceneSize = SIMD2<Float>(1920, 1080)
    private var layers: [PreparedLayer] = [] {
        didSet { layerCompositeOrder = nil }
    }
    /// Which layers other layers' effects sample, and the order that prepares them first; made
    /// again whenever `layers` changes.
    private var layerCompositeOrder: SceneLayerCompositeOrder?
    private var particleInstances: [LayerUniform] = []
    private var particleInstanceStorage: MTLBuffer?

    private var particleSystems: [ParticleSystemRuntime] = []
    /// Steps particle systems on the GPU; nil runs them on the CPU (`ParticleCPUSimulation`).
    private let particleSimulator: ParticleGPUSimulator?
    /// This frame's GPU steps, reused across frames.
    private var particleRequests: [ParticleGPUSimulator.Request] = []
    /// The wallpaper instance's scripts and what their last frame left.
    let scripts: SceneRendererScripts
    /// The scene's sound layers; the view sets their gain (`sounds.setTargetGain`).
    let sounds: SceneSoundLayers
    /// Particle systems and sounds scripts created, by object id, kept across content rebuilds
    /// like `scriptLayers`.
    private var scriptParticles: [String: (systems: [ParticleSystemRuntime], motion: SceneObjectMotion)] = [:]
    private var scriptSounds: [Int: SceneSoundContent] = [:]
    /// Layers scripts created (`thisScene.createLayer`), kept across content rebuilds, by id, with
    /// their base `visible`.
    private var scriptLayers: [String: (entry: PreparedLayer, visible: Bool)] = [:]
    /// Model objects scripts created, by id: the model, its 3D node and its motion.
    private var scriptModels: [String: ScriptModel] = [:]
    private typealias ScriptModel = (model: SceneModelObject, node: SceneTransformHierarchy3D.Node, motion: SceneObjectMotion)
    /// Layers scripts destroyed while they were still being built.
    private var destroyedScriptLayers = Set<String>()
    /// Parents scripts set (`ILayer.setParent`), by object id, kept across content rebuilds like
    /// `scriptLayers`: the parent's id (nil: a root) and the attachment it hangs from.
    private var scriptParents: [String: (parent: String?, attachment: String?)] = [:]
    /// `emitParticles` counts waiting for their system's next step, by object id.
    private var pendingEmits: [String: Int] = [:]
    /// How many particle systems are drawn (tests, diagnostics).
    var particleSystemCount: Int { particleSystems.lazy.filter { $0.simulation == nil }.count }
    /// Layers drawn through their material, and prelighting passes run (tests, diagnostics).
    var imageMaterialDraws: Int { imageMaterials?.drawsEncoded ?? 0 }
    var imageMaterialPrelitDraws: Int { imageMaterials?.prelitDraws ?? 0 }
    /// Puppet meshes drawn into their images (tests, diagnostics).
    var puppetMeshDraws: Int { puppets?.drawsEncoded ?? 0 }
    /// A puppet layer's image once its mesh has been drawn, and the texture the mesh samples (tests,
    /// diagnostics).
    func puppetImage(ofLayer id: String) -> (source: MTLTexture, image: MTLTexture)? {
        guard puppets?.hasDrawn(id) == true, let image = puppetAlbedos[id],
              let source = layers.first(where: { $0.layer.id == id })?.frames.first?.texture else { return nil }
        return (source, image)
    }
    /// Whether the posed mesh has laid a puppet layer's effect output out (tests, diagnostics). A
    /// rig that rearranges an atlas runs its effects on its texture and draws no image of its own.
    func puppetLaidOutEffects(ofLayer id: String) -> Bool { puppets?.hasLaidOut(id, key: "_effects") == true }
    /// A puppet layer's pose as its image was last drawn (tests, diagnostics).
    func puppetPose(ofLayer id: String) -> ScenePuppetPose? { puppetAnimators[id]?.pose }
    /// The pose `puppetImage(ofLayer:)` holds: the bind pose for a layer with effects, which the
    /// posed mesh lays out after them (`posedEffectOutput`); the layer's pose otherwise.
    func puppetImagePose(ofLayer id: String) -> ScenePuppetPose? {
        guard let pose = puppetPose(ofLayer: id) else { return nil }
        return puppetHasEffects(id) ? .bind(boneCount: pose.bones.count) : pose
    }
    /// What of a puppet's mesh space `puppetImage(ofLayer:)` covers, when not the image's rect
    /// (tests, diagnostics): a layer with effects draws its bind pose into the image's rect, and
    /// only the posed layout of their output covers the canvas.
    func puppetCanvas(ofLayer id: String) -> ScenePuppetCanvas? { puppetHasEffects(id) ? nil : puppetCanvases[id] }
    private func puppetHasEffects(_ id: String) -> Bool {
        layers.first { $0.layer.id == id }.map { !$0.layer.weEffects.isEmpty } ?? false
    }
    /// Effect passes encoded so far, for tests.
    var effectPassesEncoded: Int { effectGraph?.passesEncoded ?? 0 }
    /// Whether an effect pipeline is still compiling (shader prewarm waits for them).
    var hasPendingEffectPipelines: Bool { effectGraph?.hasPendingPipelines ?? false }

    /// One live particle as the last committed step left it (tests, diagnostics).
    struct ParticleSample {
        var age: Float
        var lifetime: Float
        var size: Float
        var alpha: Float
        var color: SIMD4<Float>
    }

    /// Every particle system's particles by scene object (a child under its family root's id),
    /// read back from the GPU state, else the CPU simulation's. Blocks until the GPU is done.
    func particleSamples() -> [(objectID: String?, particles: [ParticleSample])] {
        particleSystems.map { system in
            if let simulator = particleSimulator, system.gpu != nil {
                let states = simulator.snapshot(system, queue: commandQueue)
                return (particleObjectID(system), states.map {
                    ParticleSample(age: $0.life.x, lifetime: $0.life.y, size: $0.life.z, alpha: $0.alphaRotation.x,
                                   color: $0.color)
                })
            }
            return (particleObjectID(system), system.particles.map {
                ParticleSample(age: $0.age, lifetime: $0.lifetime, size: $0.size, alpha: $0.alpha, color: $0.color)
            })
        }
    }
    /// The last frame's scene target, before the post-process (tests, diagnostics).
    var lastSceneTarget: MTLTexture? { sceneRenderTarget ?? lastDrawableScene }
    /// The drawable the last frame drew its scene straight into (S2), not held.
    private weak var lastDrawableScene: MTLTexture?
    /// The bytes of the frame's own targets, by holder (diagnostics, test-risks LR10); the effect
    /// graph's layer and bloom buffers aren't among them.
    var frameTargetBytes: [String: Int] {
        ["scene target": sceneRenderTarget?.allocatedSize ?? 0,
         "mip-mapped frame buffer": mipMappedFrameBuffer?.texture?.allocatedSize ?? 0,
         "target pool (snapshots, regions)": renderTargetPool.residentBytes,
         "volumetrics": volumetrics?.residentBytes ?? 0,
         "prelit images": imageMaterials?.prelitBytes ?? 0,
         "puppet images": puppets?.allocatedBytes ?? 0,
         "scene depth": depthBuffer.residentBytes,
         "planar reflection": planarReflection?.residentBytes ?? 0]
    }
    /// A drawn layer's effect plans (tests, diagnostics).
    func effectPlans(ofLayer id: String) -> [SceneEffectPlan] {
        layers.first { $0.layer.id == id }?.layer.weEffects ?? []
    }
    /// Script-created layers still being built (tests wait for them).
    private(set) var pendingScriptLayers = 0
    /// Rebuilt objects (`replaceObjects`) being prepared.
    private(set) var pendingReplacements = 0
    /// The last `setContent` has been applied (its layers and scripts are in place).
    private(set) var hasContent = false
    /// Which object each authored scene index is, for the draw order scripts set.
    private var objectIDs: [Int] = []
    private var camera = SceneCameraEffects()
    /// The content's `general`, to resolve `camera` again when a user property bound to it
    /// changes (`refreshCamera()`); nil keeps the content's.
    private var cameraGeneral: WESceneGeneral?
    /// `general.clearcolor` (`SceneMetalContent.clearColor`); a script's `thisScene.clearcolor` wins.
    private var clearColor = SceneGeneralDefaults.clearColor
    /// WE's parallax camera position, eased across frames (`SceneCameraParallax`).
    private var cameraParallax = SceneCameraParallax(sceneSize: SIMD2<Float>(1920, 1080))
    /// Whose user properties this renderer's frames read (see `SceneMetalContent.wallpaperKey`).
    private var wallpaperKey = ""
    /// What the objects' and effects' visibility follows (`SceneMetalContent.userVisibility`).
    private var userVisibility = SceneUserVisibility()
    /// Each object's binding revision (`SceneBindingRevisions`), bumped by property changes.
    private(set) var bindingRevisions = SceneBindingRevisions()
    /// Layers' base values (`baseValues`) by layer id, per binding revision.
    private var baseValueCaches: [String: SceneBindingCache<SceneLayerBaseValues>] = [:]
    /// The Wallpaper Editor's live edits over the built content (`SceneEditorLive`).
    private var editorLive = SceneEditorLive()
    private var placement: WallpaperPlacement = .fill
    /// Drawable pixels per view point (the backing scale), refreshed every frame.
    private var drawablePixelsPerPoint: Float = 1
    /// Last frame's normalised pointer, for `g_PointerPositionLast`; nil until the first frame.
    private var lastPointer: SIMD2<Float>?
    /// Where the cursor was last seen on this renderer's display.
    private var cursorTracker = SceneCursorTracker()
    private var bloom = SceneBloomSettings(enabled: false, strength: 0, threshold: 0.7, tint: SIMD3<Float>(repeating: 1))
    /// The scene's lighting settings and light objects (`SceneMetalContent.lighting`).
    private var lighting = SceneLightingContent()
    /// Where each frame's camera comes from (`SceneCameraRigs.make(for:)`).
    private var cameraRig: any SceneCameraRig = SceneOrthographicCameraRig()
    /// Every object's authored 3D transform (`SceneSpatialContent.transforms`), for the rig's live values.
    private var cameraTransforms = SceneTransformHierarchy3D.empty
    /// The content's 3D side (`SceneSpatialContent`): projection, draw order, the 3D hierarchies,
    /// model objects and the objects' `sortorder`/`depthtest`.
    private var spatial = SceneSpatialContent()
    /// Draws model objects at their place in the object loop (docs/models-plan.md M5); nil draws none.
    var modelDrawing: (any SceneModelDrawing)?
    /// Draws the frame's shadow maps into `_rt_shadowAtlas` (docs/models-plan.md §2.10).
    private(set) var shadowPass: SceneShadowPass?
    /// This frame's `_rt_shadowAtlas` (`drawShadows`).
    private var frameShadowAtlas: MTLTexture?
    /// Draws `_rt_Reflection` (docs/models-plan.md §2.11), and this frame's (`drawReflection`).
    private(set) var planarReflection: ScenePlanarReflection?
    private var frameReflection: MTLTexture?
    /// WE's depth-stencil states and this frame's depth buffer (docs/models-plan.md §2.4): a
    /// perspective scene's pass has one.
    private lazy var depthStates = SceneDepthStates(device: device)
    private lazy var depthBuffer = SceneDepthBuffer(device: device)
    /// The content is a perspective scene (`SceneCameraEffects.orthographic`, from `general`'s
    /// projection): its objects draw through the frame camera. A content made without a scene
    /// document (a preview, tests) is orthographic.
    private var isPerspective: Bool { !camera.orthographic }
    /// This frame's depth attachment format (`.invalid`: the pass has none).
    private var sceneDepthFormat = MTLPixelFormat.invalid
    /// The depth states for this frame's draws; nil when the pass has no depth.
    private var frameDepth: SceneDepthStates? { sceneDepthFormat == .invalid ? nil : depthStates }
    /// Each object's own 3D transform this frame (`live3D`), evaluated once.
    private var frameLocals3D: [String: SceneLocalTransform3D] = [:]
    /// This frame's orthographic zoom (`orthographicZoom()`), taken with the transforms.
    private var frameZoom = SceneOrthographicZoom.none
    /// `collisionmodel` targets already reported as not collidable (`particleCapsules`).
    private var reportedCollisionTargets = Set<String>()
    /// The user's quality settings (post-processing, reflection, shadows, volumetrics); the view sets them.
    var renderSettings = SceneRenderSettings()
    private var sceneRenderTarget: MTLTexture?
    /// The scene pass's multisampled target with WE's MSAA setting, resolved into `sceneRenderTarget`
    /// at the end of every stretch of the pass (WE's `_rt_FullFrameBufferMultiSampled`).
    private var sceneMultisampleTarget: MTLTexture?
    /// This frame's scene-pass samples per pixel (1 without MSAA).
    private var sceneSampleCount = 1
    /// This frame's prelit images (`prelit`), by layer id.
    private var prelitImages: [String: MTLTexture] = [:]
    /// Animated layers' current frames, cut out of their atlases for their effects (`effectInput`).
    private lazy var spriteFrameInputs = SceneSpriteFrameInputs(device: device)
    /// This frame's cut-out frame versions (`SceneSpriteFrameInputs.Input.version`), by layer id.
    private var spriteFrameVersions: [String: UInt64] = [:]
    /// A shared scene's finished frame, the scene target's size (`sharedFrame`).
    private var sharedFrameTarget: MTLTexture?
    private var sceneRenderTargetSize = SIMD2<Int>.zero
    /// Whether the drawable's size has settled, for an exactly sized scene target (S1).
    /// Render-target pixels per scene unit this frame (see `SceneRenderResolution`).
    private var renderPixelsPerUnit: Float = 1
    /// Rendered text, by string and style. Capped at 128 entries and 32 MB of rasters not drawn this
    /// frame: a clock with seconds never reuses its old strings, and at 128 entries of ~1.5 MB (a
    /// 1000x300 px raster plus its coverage) it held ~190 MB, 300 MB or more on Retina/5K. 32 MB
    /// still keeps 20 such rasters (and the full 128 small labels) for scripts that cycle or toggle
    /// strings; every string a frame draws stays regardless (`beginGeneration`).
    private var textFrameCache = SceneLRUCache<String, SceneTextRasterResult>(
        capacity: 128, costLimit: SceneMetalRenderer.textCacheByteBudget)
    static let textCacheByteBudget = 32 << 20
    /// Rasterises changed strings off the render thread (`SceneTextRasterQueue`).
    private let textRaster: SceneTextRasterQueue
    /// Changed strings still rasterising or waiting for a frame to take them (for tests).
    var pendingTextRasters: Int { textRaster.inFlight }
    /// Each text layer's raster scale: quantised and retained while it animates, exact once it
    /// settles (`SceneTextRasterScale.Tracker`).
    private var textRasterScales: [String: SceneTextRasterScale.Tracker] = [:]
    /// Parent graph of the current content; layer origins are relative to their parents.
    private var transforms = SceneTransformHierarchy.empty
    /// Each layer's local transform, evaluated once per frame so a parent's scripts run once
    /// however many children read it.
    private var frameLocals: [String: SceneLocalTransform] = [:]
    private var layerIndexByStateId: [String: Int] = [:]
    /// Objects that aren't drawn layers (groups, particle systems), by id: their live transform.
    private var objectMotions: [String: SceneObjectMotion] = [:]
    /// The most recently committed frame, so state a removal frees can wait for it.
    private(set) var lastCommandBuffer: MTLCommandBuffer?
    /// A shared scene's latest finished frame (`renderShared`), which its displays present.
    private(set) var sharedFrame: MTLTexture?
    /// The last `present(in:)`'s command buffer (tests and benchmarks).
    private(set) var lastPresentCommandBuffer: MTLCommandBuffer?
    /// A screen's EDR headroom (tests set their own); a view without a window has none.
    var displayHeadroom: (NSScreen?) -> SceneDisplayHeadroom = { SceneDisplayHeadroom(screen: $0) }

    /// `view`'s screen's headroom: from its main-thread snapshot when a render thread draws it.
    private func viewHeadroom(_ view: MTKView) -> SceneDisplayHeadroom {
        SceneViewSnapshots.snapshot(of: view)?.headroom ?? displayHeadroom(view.window?.screen)
    }
    /// How the last frame reached the display (`SceneDisplayOutput`).
    private(set) var displayOutput = SceneDisplayOutput.standard
    /// The headroom of each view a shared frame was presented on since the last one was drawn.
    private var sharedHeadrooms: [ObjectIdentifier: SceneDisplayHeadroom] = [:]
    /// Destroyed script layers' ids, freed once the frame that last drew them completes.
    private var deferredReleases = SceneDeferredReleases()
    /// Where the cursor was last seen on this display, in display pixels from the top-left.
    private var lastCursorScreenPixels = SIMD2<Double>(repeating: 0)
    /// This renderer's view of the desktop's left clicks.
    private var clickReader = DesktopClickReader()
    /// The last drawn frame's camera motion and text sizes (by layer id), for the next script frame.
    private var lastCameraMotion: CameraMotion?
    /// Per-layer dependencies, coverage, class and this frame's dirty state
    /// (docs/efficiency-plan-2d.md WP1-A); built with the content, off the main thread.
    private(set) var layerAnalysis: SceneLayerAnalysis?
    /// Keeps system audio capture on while the content reacts to audio (`needsAudio`).
    private var audioCaptureLease: AudioCaptureLease?
    /// Whether the loaded content reacts to audio (`needsAudio`); false before it is analysed.
    var contentReadsAudio: Bool {
        guard let layerAnalysis else { return false }
        return Self.needsAudio(layerAnalysis, particles: particleSystems.map(\.configuration))
    }
    /// Adaptive rate and idle skipping (`FramePacing`, WP2-C): the instance sets its limits and
    /// ticks the displays at its rate; an idle frame returns before anything is encoded.
    var framePacing = FramePacing()
    /// Off with `OWE_IDLE_SKIP=0` (comparisons): every frame is drawn, the rate still adapts.
    /// Bumped when a video layer has a new frame (`SceneLayerFrameInputs.videoRevision`).
    private var videoRevision: UInt64 = 0
    private var analysedTime: Double = 0
    var skipsIdleFrames = ProcessInfo.processInfo.environment["OWE_IDLE_SKIP"] != "0"
    /// Frames encoded so far: a shared scene's displays present only a new one.
    private(set) var encodedFrames: UInt64 = 0
    private var pacedParallax = SIMD2<Float>(0.5, 0.5)
    /// What the analysis last saw of the frame's shape: a change marks every layer dirty.
    private var analysedShape: (layers: Int, target: SIMD2<Float>) = (0, .zero)
    /// A pipeline was compiling last frame: the frame after one lands changes too.
    private var analysedWarmUp = true
    /// `pipelinesLanded` as the last analysed frame saw it.
    private var analysedLanded = 0
    /// `scripts.userVisibilityRevision` the analysis last saw.
    private var analysedUserVisibility = 0
    /// The blur-like buffer divisor (1, 2, 4) over the slider's (`OWE_BLUR_DIVISOR` for comparisons).
    var blurDivisorOverride = ProcessInfo.processInfo.environment["OWE_BLUR_DIVISOR"].flatMap(Int.init)
    private func effectResolution(of layerID: String) -> EffectResolutionPolicy {
        let divisor = blurDivisorOverride ?? framePacing.limits.policy.blurResolutionDivisor
        guard divisor > 1 else { return .full }
        let layer = layerAnalysis.flatMap { analysis in analysis.index(of: layerID).map { analysis.layers[$0] } }
        let sharp = layer.map { $0.contentClass == .text || ($0.contentClass == .lineArt && $0.classifiedFromPixels) } ?? false
        return EffectResolutionPolicy(divisor: divisor, sharpContent: sharp)
    }
    private var lastTextSizes: [String: SIMD2<Float>] = [:]
    /// Told how long each frame took on the CPU, including the wait for a drawable.
    var frameTimeObserver: ((CFTimeInterval) -> Void)?

    /// Where particle systems are simulated. The CPU simulation is the reference the GPU one is
    /// tested against (`ParticleSimulationParityTests`), and the fallback when compute is unavailable.
    enum ParticleSimulation {
        case gpu, cpu
    }

    /// A renderer that draws into `view` itself (`draw(in:)`). `scriptServices` runs the scenes'
    /// SceneScripts (nil runs none); `screenID` names the display whose script storage they use.
    convenience init?(view: MTKView, particleSimulation: ParticleSimulation = .gpu, scriptServices: SceneScriptServices? = nil,
                      screenID: String = "", pipelineArchiveDirectory: URL? = EffectPipelineArchive.defaultDirectory) {
        self.init(pixelFormat: view.colorPixelFormat, particleSimulation: particleSimulation,
                  scriptServices: scriptServices, screenID: screenID, pipelineArchiveDirectory: pipelineArchiveDirectory)
        configure(view)
        // Drawn by the view's own timer, on the main thread.
        view.isPaused = false
        view.delegate = self
    }

    /// A renderer for drawables of `pixelFormat`. A shared scene's displays each show its frames
    /// through their own view (`configure`, `renderShared`, `present(in:)`).
    init?(pixelFormat: MTLPixelFormat, particleSimulation: ParticleSimulation = .gpu,
          scriptServices: SceneScriptServices? = nil, screenID: String = "",
          pipelineArchiveDirectory: URL? = EffectPipelineArchive.defaultDirectory) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneVertex"),
              let fragment = library.makeFunction(name: "sceneFragment"),
              let placedVertex = library.makeFunction(name: "sceneVertex3D"),
              let copyFragment = library.makeFunction(name: "sceneCopyFragment"),
              let decode = library.makeFunction(name: "decodeDXT"),
              let decodePipeline = try? device.makeComputePipelineState(function: decode) else {
            return nil
        }

        let descriptor = SceneLayerPipelines.layerDescriptor(vertex: vertex, fragment: fragment, format: pixelFormat)
        let layerPipelines: SceneLayerPipelines
        do {
            // The drawable's format, and the HDR scene target's (docs/lighting-plan.md §2.6).
            layerPipelines = try SceneLayerPipelines(device: device, vertex: vertex, fragment: fragment,
                                                     copyFragment: copyFragment, placedVertex: placedVertex,
                                                     formats: [pixelFormat, .rgba16Float])
        } catch {
            OWELog.error(.scene, "The scene pipelines can't be made: \(error)")
            return nil
        }

        guard let postProcess = ScenePostProcess(device: device, layerDescriptor: descriptor) else {
            return nil
        }

        switch particleSimulation {
        case .gpu:
            do {
                particleSimulator = try ParticleGPUSimulator(device: device)
            } catch {
                OWELog.error(.scene, "GPU particle simulation unavailable, simulating on the CPU: \(error)")
                particleSimulator = nil
            }
        case .cpu:
            particleSimulator = nil
        }
        self.device = device
        self.pipelineArchiveDirectory = pipelineArchiveDirectory
        self.pixelFormat = pixelFormat
        self.copyPipeline = layerPipelines.pipelines(for: pixelFormat).copy
        self.postProcess = postProcess
        let frameStages = SceneFrameStages.make(device: device)
        self.frameStages = frameStages
        self.mipMappedFrameBuffer = frameStages.lazy.compactMap { $0 as? SceneMipMappedFrameBuffer }.first
        self.commandQueue = commandQueue
        self.layerPipelines = layerPipelines
        self.dxtDecodePipeline = decodePipeline
        self.textureLoader = MTKTextureLoader(device: device)
        self.textRaster = SceneTextRasterQueue(device: device, loader: textureLoader)
        self.renderTargetPool = SceneRenderTargetPool(device: device)
        scripts = SceneRendererScripts(services: scriptServices, screenID: screenID)
        sounds = SceneSoundLayers(label: screenID.isEmpty ? "sounds" : "sounds \(screenID)")
        super.init()
        // Created objects are built on the script thread, so they draw in the frame that made them.
        scripts.prepareCreated = { [weak self] created, id in self?.prepare(created, id: String(id)) }
        modelDrawing = SceneModelRenderer(device: device, archive: effectGraph?.pipelineArchive)
        shadowPass = SceneShadowPass(device: device, archive: effectGraph?.pipelineArchive)
        planarReflection = ScenePlanarReflection(device: device)
        memoryPressure = SceneMemoryPressure { [weak self] level in self?.trimMemory(level) }
        sounds.locate = { [weak self] id in self?.soundWorldPosition(id) }
    }

    /// Sets `view` up to show this renderer's frames, on its device. It leaves the view's own timer
    /// as it is: a scene instance's view stays paused, drawn only by its link on the render thread
    /// (`SceneRenderLoop`). Its delegate is whoever draws it: this renderer, or a shared scene's presenter.
    func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = pixelFormat
        view.framebufferOnly = false
        // The composite never wrote the drawable's alpha; a scene drawn straight into it (S2)
        // does, and the desktop shows colour only.
        view.layer?.isOpaque = true
        view.enableSetNeedsDisplay = false
    }

    /// Drops what can be rebuilt under memory pressure: free pooled targets, cached text other than
    /// the layers' current strings, spare effect targets and free uniform chunks; when critical,
    /// also effect asset textures and pipelines idle since the last critical trim. Leased and
    /// persistent targets, layers' own targets and anything the current frame uses stay.
    func trimMemory(_ level: SceneMemoryPressure.Level) {
        let before = renderTargetPool.residentBytes
        renderTargetPool.removeAll()
        textFrameCache.trim(to: layers.filter { $0.layer.text != nil }.count)
        effectGraph?.trimMemory(dropIdlePipelines: level == .critical)
        imageMaterials?.trimMemory(dropIdlePipelines: level == .critical)
        puppets?.trimMemory()
        particleMaterials?.trimMemory(dropIdlePipelines: level == .critical)
        if level == .critical {
            effectAssetTextures.removeAll()
            effectAssetFrames.removeAll()
            solidEffectInputs.removeAll()
            clearUploadedImages()
        }
        OWELog.info(.scene, "Memory pressure (\(level)): freed \((before - renderTargetPool.residentBytes) >> 20) MB of pooled targets")
    }

    /// User properties `names` changed: the scripts get `applyUserProperties`. With
    /// `applyVisibility` (while the user edits properties) objects and effects follow their
    /// user-bound `visible` at once, without a content rebuild (`SceneLiveBindingSites`).
    /// User properties `names` changed: the scripts get them (`applyUserProperties`), the owners of
    /// the bindings that read them (`UserPropertyBindingTable.changes(for:)`) move to a new binding
    /// revision, which every cache baking a bound value keys on, and the visibility is taken again.
    /// Structural changes arrive separately, as rebuilt objects (`replaceObjects`).
    func userPropertiesDidChange(_ names: Set<String>, owners: Set<UserPropertyBindingOwner>) {
        scripts.userPropertiesDidChange(names)
        guard !owners.isEmpty else { return }
        if owners.contains(.scene) { refreshCamera() }
        bindingRevisions.bump(owners)
        refreshParticleRevisions()
        applyUserVisibility()
        framePacing.wake(.interactive, at: wallTime())
    }

    /// Resolves `general.camera…` against the current user properties: a property bound to
    /// them applies from the next frame, without a content rebuild (`cameraMotion`).
    private func refreshCamera() {
        guard let cameraGeneral else { return }
        camera = SceneCameraEffects(cameraGeneral, in: LiveSceneValueContext(wallpaper: wallpaperKey))
    }

    /// Resolves the content's visibility against the current user properties (`SceneUserVisibility`).
    private func applyUserVisibility() {
        guard !userVisibility.sites.isEmpty else { return }
        let key = wallpaperKey
        let resolved = userVisibility.resolve { WallpaperServices.shared.userPropertyString($0, wallpaper: key) }
        scripts.applyUserVisibility(objects: resolved.objects, effects: resolved.effects)
    }

    /// The Wallpaper Editor's edits since the content was built, drawn from the next frame; nil or
    /// empty draws the content as built.
    func setEditorLiveValues(_ values: SceneEditLiveValues?) {
        let next = SceneEditorLive(values ?? SceneEditLiveValues(), revision: editorLive.revision &+ 1)
        guard !(next.isEmpty && editorLive.isEmpty) else { return }
        editorLive = next
        frameLocals.removeAll(keepingCapacity: true)
        framePacing.wake(.interactive, at: wallTime())
    }

    /// Drops every prepared layer, releasing any video stream those layers hold.
    func releaseContent() {
        setContent(nil)
    }

    func setContent(_ content: SceneMetalContent?) {
        clockLayerIDs = content?.scripts.map { SceneClockLayers.ids(in: $0.document) } ?? []
        baseValueCaches.removeAll()
        effectAssetTextures.removeAll()
        clearUploadedImages()
        effectAssetFrames.removeAll()
        solidEffectInputs.removeAll()
        mediaTextures = nil
        effectGraph?.releaseTargets()
        particleMaterials?.releaseAll()
        imageMaterials?.releaseAll()
        puppets?.releaseAll()
        spriteFrameInputs.releaseAll()
        puppetAlbedos.removeAll()
        puppetAnimators.removeAll()
        puppetWarps.removeAll()
        puppetCanvases.removeAll()
        contentGenerationLock.lock()
        contentGeneration &+= 1
        let generation = contentGeneration
        contentGenerationLock.unlock()

        guard let content else {
            layerAnalysis = nil
            audioCaptureLease = nil
            layers = []
            particleSystems = []
            objectMotions = [:]
            scripts.stop()
            timelines.clear()
            sounds.stopAll()
            scriptParticles.removeAll()
            scriptSounds.removeAll()
            scriptLayers.removeAll()
            scriptModels.removeAll()
            destroyedScriptLayers.removeAll()
            pendingEmits.removeAll()
            objectIDs = []
            hasContent = false
            textFrameCache.removeAll()
            textRaster.reset()
            textRasterScales.removeAll()
            clock = SceneClock()
            transforms = .empty
            spatial = SceneSpatialContent()
            depthBuffer.releaseAll()
            planarReflection?.release()
            lastPointer = nil
            lastCameraMotion = nil
            lastTextSizes.removeAll()
            cameraParallax = SceneCameraParallax(sceneSize: sceneSize)
            cursorTracker = SceneCursorTracker()
            deferredReleases.removeAll()
            lastCommandBuffer = nil
            return
        }
        // Subscribed before the scripts start, so the artwork the session already has is there.
        let bindsSystemTexture = content.layers.contains { layer in
            layer.systemImage != nil
                || layer.weEffects.contains { $0.passes.contains { !$0.systemTextures.isEmpty } }
        }
        if bindsSystemTexture, let media = scripts.services?.media {
            mediaTextures = SceneMediaTextures(source: media, device: device)
        }
        contentQueue.async { [weak self] in
            guard let self, self.isCurrentContentGeneration(generation) else { return }
            // Each layer's upload is independent; built side by side, kept in layer order.
            var built = [[RenderTextureFrame]?](repeating: nil, count: content.layers.count)
            built.withUnsafeMutableBufferPointer { slots in
                let slots = slots
                DispatchQueue.concurrentPerform(iterations: content.layers.count) { index in
                    slots[index] = self.makeTextureFrames(from: content.layers[index].source)
                }
            }
            let preparedLayers: [PreparedLayer] = zip(built, content.layers).compactMap { frames, layer in
                guard let frames, !frames.isEmpty else { return nil }
                return PreparedLayer(frames: frames, layer: Self.droppingPixels(layer))
            }
            let imageSources = Dictionary(preparedLayers.compactMap { entry -> (String, ParticleEmitterImagePoints.Source)? in
                guard let frame = entry.frames.first else { return nil }
                let size = entry.layer.source.pixelSize
                return (entry.layer.id, .init(texture: frame.texture, uvExtent: SIMD2(frame.uvAxisX.x, frame.uvAxisY.y),
                                              imageSize: SIMD2(Int(size.x), Int(size.y))))
            }, uniquingKeysWith: { first, _ in first })
            var imagePoints: [String: [SIMD4<Int32>]] = [:]
            let runtimes: [ParticleSystemRuntime?] = content.particleSystems.enumerated().map { index, system in
                var system = system
                ParticleEmitterImagePoints.fill(&system.emitterImages, sources: imageSources, device: self.device,
                                                queue: self.commandQueue, cache: &imagePoints)
                guard let texture = self.particleTexture(from: system.source, spriteSheet: system.spriteSheet != nil) else { return nil }
                let fallback = system.fallbackSource.flatMap { self.makeTextureFrames(from: $0)?.first?.texture }
                Self.dropPixels(&system)
                // Seeded by position in the scene, so a wallpaper's particles replay the same way.
                let seed = UInt32(index) &+ self.particleSeed &* 0x9E37_79B9
                return ParticleSystemRuntime(texture: texture, configuration: system, seed: ParticleRandom.pcg(seed),
                                             fallbackTexture: fallback)
            }
            ParticleSystemRuntime.linkFamilies(runtimes)
            let preparedParticleSystems = ParticleSystemRuntime.addingRendererDraws(runtimes.compactMap { $0 })
            guard self.isCurrentContentGeneration(generation) else { return }
            // The models' meshes go to the GPU here, off the render thread, so the first frame
            // drawing them has nothing to upload.
            for model in content.spatial.models { _ = model.plan?.upload(device: self.device) }
            let analysis = SceneLayerAnalysis.make(content: content)
            // Thread boundary: content queue → render thread.
            self.performOnRenderThread { [weak self] in
                guard let self, self.isCurrentContentGeneration(generation) else { return }
                self.sceneSize = content.size
                self.sharedFrame = nil
                self.bloom = content.bloom
                self.lighting = content.lighting
                self.cameraRig = SceneCameraRigs.make(for: content)
                self.cameraTransforms = content.spatial.transforms
                self.spatial = content.spatial
                self.modelDrawing?.setContent(content.spatial.models, content: content)
                self.shadowPass?.setContent()
                self.planarReflection?.setContent()
                for stage in self.frameStages { stage.setContent(content) }
                self.postProcess.setContent(content)
                self.particleSystems = preparedParticleSystems
                self.layerAnalysis = analysis
                let needsAudio = Self.needsAudio(analysis, particles: preparedParticleSystems.map(\.configuration))
                if needsAudio != (self.audioCaptureLease != nil) {
                    self.audioCaptureLease = needsAudio ? WallpaperServices.shared.acquireAudioCapture() : nil
                }
                self.framePacing.changesOnItsOwn = FramePacing.changesOnItsOwn(
                    analysis, particles: !preparedParticleSystems.isEmpty, cameraShake: content.camera.shake)
                self.framePacing.wake(.interactive, at: self.wallTime())
                self.transforms = content.transforms
                self.objectMotions = content.motions
                self.objectIDs = content.objectIDs
                self.wallpaperKey = content.wallpaperKey
                self.camera = content.camera
                self.cameraGeneral = content.general
                self.clearColor = content.clearColor
                self.cameraParallax = SceneCameraParallax(sceneSize: content.size, enabled: Self.parallaxEnabled(content.camera))
                self.lastCameraMotion = nil
                self.lastTextSizes.removeAll()
                self.textFrameCache.removeAll()
                self.textRaster.reset()
                self.textRasterScales.removeAll()
                let running = self.scripts.wallpaper
                self.scripts.setContent(content.scripts, visibility: content.visibility,
                                        parents: content.transforms.nodes.compactMapValues(\.parentID))
                self.userVisibility = content.userVisibility
                // A property changed while the content was being built shows in it at once.
                self.applyUserVisibility()
                self.timelines.setTimelines(content.timelines,
                                            restart: self.scripts.wallpaper != nil && self.scripts.wallpaper !== running)
                if self.scripts.wallpaper == nil || self.scripts.wallpaper !== running {
                    // New scripts: the old ones' layers are gone with them.
                    self.scriptLayers.removeAll()
                    self.destroyedScriptLayers.removeAll()
                    self.pendingEmits.removeAll()
                    self.scriptParticles.removeAll()
                    self.scriptSounds.removeAll()
                    self.scriptModels.removeAll()
                    self.scriptParents.removeAll()
                }
                for (id, created) in self.scriptModels { self.addScriptModel(id, created) }
                for (id, parent) in self.scriptParents { self.reparent(id, to: parent.parent, attachment: parent.attachment) }
                for (id, created) in self.scriptParticles {
                    self.particleSystems += created.systems
                    self.objectMotions[id] = created.motion
                }
                self.sounds.setContent(content.sounds + self.scriptSounds.keys.sorted().compactMap { self.scriptSounds[$0] })
                for (id, created) in self.scriptLayers { self.scripts.setBaseVisibility(created.visible, for: id) }
                self.layers = preparedLayers + self.scriptLayers.values.map(\.entry)
                self.timelines.registerTextures(self.layers.compactMap(Self.textureAnimation))
                self.orderLayers()
                self.hasContent = true
                self.clock = SceneClock()
            }
        }
    }

    private var currentContentGeneration: Int {
        contentGenerationLock.lock()
        defer { contentGenerationLock.unlock() }
        return contentGeneration
    }

    private func isCurrentContentGeneration(_ generation: Int) -> Bool {
        contentGenerationLock.lock()
        defer { contentGenerationLock.unlock() }
        return contentGeneration == generation
    }

    func setPlacement(_ placement: WallpaperPlacement) {
        self.placement = placement
    }

    /// Applies what scripts changed in the scene's structure: builds the layers `createLayer` made
    /// (off the main thread, through the loader; drawn once ready), drops destroyed ones (their GPU
    /// state freed after the in-flight frame) and queues `emitParticles` counts.
    private func applyScriptEvents(_ events: [SceneScriptRenderEvent]) {
        var removed: [String] = []
        for event in events {
            switch event {
            case .create(let id, let object):
                timelines.addObject(object, id: id)
                buildScriptLayer(String(id), object: object)
            case let .setParent(id, parentID, attachment):
                let key = String(id)
                scriptParents[key] = (parentID.map(String.init), attachment)
                reparent(key, to: parentID.map(String.init), attachment: attachment)
            case .destroy(let id):
                let key = String(id)
                scriptParents.removeValue(forKey: key)
                let createdParticles = scriptParticles.removeValue(forKey: key)
                let createdSound = scriptSounds.removeValue(forKey: id)
                let createdModel = scriptModels.removeValue(forKey: key)
                _ = scripts.wallpaper?.takePrepared(id)
                if scriptLayers.removeValue(forKey: key) == nil, createdParticles == nil, createdSound == nil, createdModel == nil {
                    destroyedScriptLayers.insert(key)
                }
                if createdModel != nil {
                    spatial.models.removeAll { $0.id == key }
                    spatial.transforms.remove(key)
                    objectMotions.removeValue(forKey: key)
                    models?.remove(key)
                    shadowPass?.remove(key)
                }
                layers.removeAll { $0.layer.id == key }
                textRasterScales.removeValue(forKey: key)
                if createdParticles != nil {
                    particleSystems.removeAll { particleObjectID($0) == key }
                    objectMotions.removeValue(forKey: key)
                }
                sounds.remove(id)
                timelines.removeObject(id)
                removed.append(key)
            case .emit(let id, let count):
                pendingEmits[String(id), default: 0] += count ?? 1
            case .sound(let id, let playback):
                sounds.perform(playback, on: id)
            case .video(let id, let command):
                let key = String(id)
                for entry in layers where entry.layer.id == key {
                    if case let .video(stream) = entry.layer.source { stream.perform(command) }
                }
            case let .animation(site, time, flags, rate, frame):
                timelines.restore(site, time: time, flags: flags, rate: rate, seenAt: frame)
            case let .textureAnimation(id, control, frame):
                timelines.restoreTexture(control, object: id, seenAt: frame)
            case let .rig(id, command):
                performRigCommand(command, on: String(id))
            }
        }
        if !removed.isEmpty {
            // The last frame that drew these may still be on the GPU; free their effect targets
            // once it has finished (`releaseFinishedEffectState`).
            deferredReleases.enqueue(removed, after: lastCommandBuffer)
        }
    }

    /// Swaps in objects rebuilt after a structural user-property change (`SceneObjectReplacement`):
    /// their textures are uploaded and their particle systems made off the render thread, then
    /// their layers and systems replace the old ones between two frames. The old ones' effect,
    /// material and puppet state is released (targets go to the spare list, which later passes on
    /// the queue are ordered after), and the rest of the scene keeps running. Dropped when the
    /// content changed meanwhile: that content was built with the change.
    func replaceObjects(_ replacement: SceneObjectReplacement) {
        let generation = currentContentGeneration
        let content = replacement.content
        pendingReplacements += 1
        contentQueue.async { [weak self] in
            guard let self else { return }
            var prepared: [PreparedLayer] = []
            var systems: [ParticleSystemRuntime] = []
            var analysis: SceneLayerAnalysis?
            if self.isCurrentContentGeneration(generation) {
                prepared = content.layers.compactMap { layer in
                    guard let frames = self.makeTextureFrames(from: layer.source), !frames.isEmpty else { return nil }
                    return PreparedLayer(frames: frames, layer: Self.droppingPixels(layer))
                }
                let runtimes: [ParticleSystemRuntime?] = content.particleSystems.map { system in
                    var system = system
                    guard let texture = self.particleTexture(from: system.source, spriteSheet: system.spriteSheet != nil) else { return nil }
                    let fallback = system.fallbackSource.flatMap { self.makeTextureFrames(from: $0)?.first?.texture }
                    Self.dropPixels(&system)
                    // Seeded by position in the scene, as the whole content's systems are.
                    let seed = UInt32(truncatingIfNeeded: system.order) &+ self.particleSeed &* 0x9E37_79B9
                    return ParticleSystemRuntime(texture: texture, configuration: system, seed: ParticleRandom.pcg(seed),
                                                 fallbackTexture: fallback)
                }
                ParticleSystemRuntime.linkFamilies(runtimes)
                systems = ParticleSystemRuntime.addingRendererDraws(runtimes.compactMap { $0 })
                analysis = SceneLayerAnalysis.make(content: content)
            }
            // Thread boundary: content queue → render thread.
            self.performOnRenderThread { [weak self] in
                guard let self else { return }
                self.pendingReplacements -= 1
                guard self.isCurrentContentGeneration(generation), let analysis else { return }
                self.install(replacement.objectIDs, layers: prepared, systems: systems, motions: content.motions,
                             analysis: analysis)
            }
        }
    }

    private func install(_ ids: Set<String>, layers prepared: [PreparedLayer], systems: [ParticleSystemRuntime],
                         motions: [String: SceneObjectMotion], analysis: SceneLayerAnalysis) {
        layers.removeAll { ids.contains($0.layer.id) }
        particleSystems.removeAll { particleObjectID($0).map(ids.contains) ?? false }
        for id in ids {
            effectGraph?.releaseLayer(id)
            imageMaterials?.releaseLayer(id)
            puppets?.releaseLayer(id)
            spriteFrameInputs.releaseLayer(id)
            puppetAlbedos.removeValue(forKey: id)
            puppetAnimators.removeValue(forKey: id)
            puppetWarps.removeValue(forKey: id)
            puppetCanvases.removeValue(forKey: id)
            textRasterScales.removeValue(forKey: id)
            lastTextSizes.removeValue(forKey: id)
            baseValueCaches.removeValue(forKey: id)
            if let motion = motions[id] { objectMotions[id] = motion }
        }
        textFrameCache.removeAll()
        particleSystems += systems
        layers += prepared
        for entry in prepared { registerTextureAnimation(entry) }
        layerAnalysis = layerAnalysis?.replacing(ids, with: analysis) ?? analysis
        bindingRevisions.bump(Set(ids.compactMap { Int($0).map(UserPropertyBindingOwner.object) }))
        refreshParticleRevisions()
        orderLayers()
        framePacing.wake(.interactive, at: wallTime())
    }

    // MARK: - Timelines

    /// An animated texture's layer shares its texture's clock (§2.7), frame times in sheet order.
    private func registerTextureAnimation(_ entry: PreparedLayer) {
        guard let animation = Self.textureAnimation(entry) else { return }
        timelines.registerTexture(object: animation.id, texture: animation.texture, frameTimes: animation.frameTimes)
    }

    private static func textureAnimation(_ entry: PreparedLayer) -> (id: Int, texture: String, frameTimes: [Float])? {
        guard let key = entry.layer.textureKey, let id = Int(entry.layer.id) else { return nil }
        return (id, key, entry.frames.map(\.duration))
    }

    /// Builds an object a script created through the loader, off the main thread: a layer, a
    /// particle system (with its children) or a sound.
    private func buildScriptLayer(_ id: String, object: [String: SceneJSON]) {
        var visible = true
        if case .bool(let flag)? = object["visible"] { visible = flag }
        // Built on the script thread already: drawn in this frame, as WE's createLayer is.
        if let key = Int(id), let built = scripts.wallpaper?.takePrepared(key) as? PreparedScriptObject {
            destroyedScriptLayers.remove(id)
            installScriptObject(built, id: id, visible: visible)
            return
        }
        guard let makeLayer = scripts.makeLayer else { return }
        let generation = currentContentGeneration
        let wallpaper = scripts.wallpaper
        pendingScriptLayers += 1
        contentQueue.async { [weak self] in
            guard let self else { return }
            let built: PreparedScriptObject? = {
                guard self.isCurrentContentGeneration(generation) else { return nil }
                guard let created = makeLayer(object) else {
                    OWELog.error(.script, "createLayer: object \(id) can't be built")
                    return nil
                }
                return self.prepare(created, id: id)
            }()
            // Thread boundary: content queue → render thread.
            self.performOnRenderThread { [weak self] in
                guard let self else { return }
                self.pendingScriptLayers -= 1
                guard let built, self.isCurrentContentGeneration(generation), self.scripts.wallpaper === wallpaper else { return }
                guard self.destroyedScriptLayers.remove(id) == nil else { return }
                self.installScriptObject(built, id: id, visible: visible)
            }
        }
    }

    /// Starts drawing a created object, in the scripts' order.
    private func installScriptObject(_ built: PreparedScriptObject, id: String, visible: Bool) {
        scripts.setBaseVisibility(visible, for: id)
        switch built {
        case .layer(let entry):
            scriptLayers[id] = (entry, visible)
            layers.append(entry)
            registerTextureAnimation(entry)
        case .particles(let systems, let motion):
            scriptParticles[id] = (systems, motion)
            objectMotions[id] = motion
            particleSystems.append(contentsOf: systems)
        case .sound(let content):
            scriptSounds[content.id] = content
            sounds.add(content)
        case let .model(model, node, motion):
            scriptModels[id] = (model, node, motion)
            addScriptModel(id, (model, node, motion))
        }
        orderLayers()
    }

    /// A created object with its textures loaded (off the main thread).
    private enum PreparedScriptObject {
        case layer(PreparedLayer)
        case particles([ParticleSystemRuntime], motion: SceneObjectMotion)
        case sound(SceneSoundContent)
        case model(SceneModelObject, node: SceneTransformHierarchy3D.Node, motion: SceneObjectMotion)
    }

    private func prepare(_ created: SceneScriptCreatedObject, id: String) -> PreparedScriptObject? {
        switch created {
        case .layer(var layer):
            layer.order = Int.max
            guard let frames = makeTextureFrames(from: layer.source), !frames.isEmpty else { return nil }
            return .layer(PreparedLayer(frames: frames, layer: Self.droppingPixels(layer)))
        case .particles(let systems, let motion):
            // Above every authored object, like WE's createLayer; the scripts' order places it.
            let runtimes: [ParticleSystemRuntime?] = systems.enumerated().map { index, system in
                var system = system
                system.order = Int(Int32.max)
                guard let texture = particleTexture(from: system.source, spriteSheet: system.spriteSheet != nil) else { return nil }
                let fallback = system.fallbackSource.flatMap { makeTextureFrames(from: $0)?.first?.texture }
                Self.dropPixels(&system)
                let seed = UInt32(truncatingIfNeeded: (Int(id) ?? 0) &* 31 &+ index)
                return ParticleSystemRuntime(texture: texture, configuration: system, seed: ParticleRandom.pcg(seed),
                                             fallbackTexture: fallback)
            }
            ParticleSystemRuntime.linkFamilies(runtimes)
            let prepared = ParticleSystemRuntime.addingRendererDraws(runtimes.compactMap { $0 })
            return prepared.isEmpty ? nil : .particles(prepared, motion: motion)
        case .sound(let content):
            return .sound(content)
        case let .model(model, node, motion):
            var model = model
            model.id = id
            _ = model.plan?.upload(device: device)
            return .model(model, node: node, motion: motion)
        }
    }

    /// A model a script created, drawn from now on like the scene's own (after them, as WE's
    /// createLayer appends).
    private func addScriptModel(_ id: String, _ created: ScriptModel) {
        spatial.models.removeAll { $0.id == id }
        spatial.models.append(created.model)
        spatial.transforms.insert(id, node: created.node)
        if let parent = scriptParents[id] { spatial.transforms.setParent(id, to: parent.parent, attachment: parent.attachment) }
        objectMotions[id] = created.motion
        models?.add(created.model)
    }

    /// `ILayer.setParent` in every parent graph the renderer composes worlds with, and in the
    /// visibility chain (a hidden parent hides its children).
    private func reparent(_ id: String, to parent: String?, attachment: String?) {
        transforms.setParent(id, to: parent, attachment: attachment)
        spatial.transforms.setParent(id, to: parent, attachment: attachment)
        cameraTransforms.setParent(id, to: parent, attachment: attachment)
        cameraRig.setParent(id, to: parent, attachment: attachment)
        scripts.setParent(parent, for: id)
        // The analysis worked out lineages and bounds under the old parents; without this, idle
        // skipping could keep the old pose on screen.
        if let analysis = layerAnalysis?.reparented(nodes: transforms.nodes, motions: objectMotions) {
            layerAnalysis = analysis
            if audioCaptureLease == nil, Self.needsAudio(analysis, particles: particleSystems.map(\.configuration)) {
                audioCaptureLease = WallpaperServices.shared.acquireAudioCapture()
            }
        }
    }

    /// Puts `layers` in draw order (the scene's, or the one scripts set) with each layer's
    /// particle barrier.
    private func orderLayers() {
        // A renderer after a system's first sits where the system does.
        let systems = particleSystems.filter { $0.simulation == nil }.map { system -> (id: String?, order: Int) in
            let order = system.configuration.order
            if order >= 0 && order < objectIDs.count { return (String(objectIDs[order]), order) }
            return (particleObjectID(system), order)
        }
        let order = SceneRendererScripts.drawOrder(layers: layers.map { ($0.layer.id, $0.layer.order) },
                                                   systems: systems, scriptOrder: scripts.state.order)
        var ordered: [PreparedLayer] = []
        ordered.reserveCapacity(layers.count)
        for (index, position) in order.sequence.enumerated() {
            var entry = layers[position]
            entry.particleBarrier = order.barriers[index]
            ordered.append(entry)
        }
        layers = ordered
    }

    /// Frees the effect state of destroyed script layers whose last frame the GPU has finished.
    private func releaseFinishedEffectState() {
        guard deferredReleases.count > 0 else { return }
        deferredReleases.drain(live: Set(layers.map(\.layer.id))) { id in
            effectGraph?.releaseLayer(id)
            imageMaterials?.releaseLayer(id)
            puppets?.releaseLayer(id)
            spriteFrameInputs.releaseLayer(id)
            puppetAlbedos.removeValue(forKey: id)
            puppetAnimators.removeValue(forKey: id)
            puppetWarps.removeValue(forKey: id)
            puppetCanvases.removeValue(forKey: id)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Renders a frame for `view` alone and presents it there.
    func draw(in view: MTKView) {
        if drawsOnRenderThreadOnly { ThreadGuards.assertRenderThread("A scene frame") }
        ThreadGuards.renderFrame { renderFrame(.view(view)) }
    }

    /// Renders one frame for all the displays of a shared scene, at the largest scene target any
    /// of them needs; the cursor comes from the display it is on. Each display then shows the
    /// frame at its own size (`present(in:)`). The first viewport is the driving display, whose
    /// resolution scripts see.
    func renderShared(_ viewports: [SceneViewport]) {
        guard !viewports.isEmpty else { return }
        if drawsOnRenderThreadOnly { ThreadGuards.assertRenderThread("A shared scene frame") }
        ThreadGuards.renderFrame { renderFrame(.shared(viewports)) }
    }

    /// Draws the shared frame again (a loading snapshot, the lock screen's frame without the clock)
    /// without stepping the scene: no script frame, no clock, timeline or particle step. WE never
    /// steps a scene to take a picture of it.
    func redrawShared(_ viewports: [SceneViewport]) {
        redrawing = true
        defer { redrawing = false }
        renderShared(viewports)
    }

    /// Shows the latest shared frame (`renderShared`) on `view`, at its size and the user's
    /// placement: one pass per display.
    func present(in view: MTKView) {
        let headroom = viewHeadroom(view)
        sharedHeadrooms[ObjectIdentifier(view)] = headroom
        guard let frame = sharedFrame else { return }
        // The view shows the frame in its own format: EDR when the frame was drawn for it.
        let extended = frame.pixelFormat == SceneDisplayOutput.extendedPixelFormat && pixelFormat != frame.pixelFormat
        (extended ? SceneDisplayOutput.extendedRange(headroom: headroom.current) : .standard).apply(to: view, standard: pixelFormat)
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let size = SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height))
        let pointWidth = SceneViewSnapshots.snapshot(of: view).map { CGFloat($0.pointSize.x) } ?? view.bounds.width
        let pixelsPerPoint = pointWidth > 0 ? size.x / Float(pointWidth) : 1
        encodePlaced(frame, onto: encoder, size: size, pixelsPerPoint: pixelsPerPoint,
                     pipeline: extended ? layerPipelines.pipelines(for: frame.pixelFormat).copy : copyPipeline)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        lastPresentCommandBuffer = commandBuffer
    }

    /// Draws `frame` onto a `size`-pixel target at the user's placement, as a display shows it.
    private func encodePlaced(_ frame: MTLTexture, onto encoder: MTLRenderCommandEncoder, size: SIMD2<Float>,
                              pixelsPerPoint: Float, pipeline: MTLRenderPipelineState) {
        var uniform = layerUniform(position: sceneSize / 2, size: sceneSize, opacity: 1, drawableSize: size,
                                   placement: placement, pixelsPerPoint: pixelsPerPoint)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniform, length: MemoryLayout<LayerUniform>.stride, index: 0)
        encoder.setFragmentTexture(frame, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Draws the latest shared frame (`renderShared`) into `target`, in the drawables' format, as
    /// `present(in:)` shows it on a display of that size (a loading snapshot). False without one.
    func encodeSharedFrame(into target: MTLTexture, pixelsPerPoint: Float, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let frame = sharedFrame, target.pixelFormat == pixelFormat else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = SceneFrameDestination.clearColor
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encodePlaced(frame, onto: encoder, size: SIMD2(Float(target.width), Float(target.height)),
                     pixelsPerPoint: pixelsPerPoint, pipeline: copyPipeline)
        encoder.endEncoding()
        return true
    }

    /// Frees the shared frame: a scene on one display draws straight onto its drawable and only
    /// rendered one for a loading snapshot. The GPU keeps what in-flight work still reads.
    func releaseSharedFrame() {
        sharedFrame = nil
        sharedFrameTarget = nil
    }

    /// Where a frame goes: one view's drawable, or a shared scene's finished frame.
    private enum FrameOutput {
        case view(MTKView)
        case shared([SceneViewport])
    }

    /// The frame's pass onto `output` (nil for a shared frame until its size is known), its
    /// viewports and the placement the post-process composites with.
    private func frameDestination(_ output: FrameOutput) -> SceneFrameDestination? {
        switch output {
        case .view(let view):
            // The drawable is taken late (`lateOutput`, F1): its size and format are the view's,
            // which `selectDisplayOutput` set up.
            let size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
            guard size.x >= 1, size.y >= 1 else { return nil }
            let format = SceneViewSnapshots.snapshot(of: view)?.layer?.pixelFormat ?? view.colorPixelFormat
            return SceneFrameDestination(descriptor: nil, drawable: nil, pixelFormat: format,
                                         placement: placement, viewports: [SceneViewport(view, drawableSize: size)])
        case .shared(let viewports):
            // The finished frame keeps the scene's aspect; each display places it when presenting.
            return SceneFrameDestination(descriptor: nil, drawable: nil, pixelFormat: pixelFormat, placement: .stretch,
                                         viewports: viewports)
        }
    }

    /// How this frame reaches the display (`SceneDisplayOutput`): EDR while the content draws in
    /// HDR under "displayhdr" and the screen has headroom, the view set up for it; a shared frame
    /// takes the least headroom of the views it was shown on since the last one.
    private func selectDisplayOutput(_ output: FrameOutput) {
        let headroom: SceneDisplayHeadroom
        switch output {
        case .view(let view):
            headroom = viewHeadroom(view)
        case .shared:
            let shown = Array(sharedHeadrooms.values)
            sharedHeadrooms.removeAll(keepingCapacity: true)
            headroom = shown.isEmpty ? SceneDisplayHeadroom()
                : SceneDisplayHeadroom(potential: shown.map(\.potential).min() ?? 1, current: shown.map(\.current).min() ?? 1)
        }
        displayOutput = SceneDisplayOutput.select(postProcessing: renderSettings.postProcessing, drawsHDR: postProcess.drawsHDR,
                                                  headroom: headroom)
        if case .view(let view) = output { displayOutput.apply(to: view, standard: pixelFormat) }
    }

    /// The pass onto a shared scene's finished frame, the size of `scene`, in this frame's output
    /// format (`displayOutput`).
    private func sharedFramePass(matching scene: MTLTexture) -> MTLRenderPassDescriptor? {
        let format = displayOutput.pixelFormat(standard: pixelFormat)
        if sharedFrameTarget?.width != scene.width || sharedFrameTarget?.height != scene.height
            || sharedFrameTarget?.pixelFormat != format {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: scene.width,
                                                                      height: scene.height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            sharedFrameTarget = device.makeTexture(descriptor: descriptor)
            if sharedFrameTarget == nil {
                OWELog.error(.scene, "Could not allocate the \(scene.width)×\(scene.height) shared frame")
            }
        }
        guard let target = sharedFrameTarget else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = SceneFrameDestination.clearColor
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    /// This frame's scene target and, when the scene draws straight into its output, that output.
    private struct FrameTargets {
        var scene: MTLTexture
        /// Set when `scene` is the output (S2): the drawable's pass (or nil for a shared frame's,
        /// which is `scene` itself) and the drawable.
        var output: (descriptor: MTLRenderPassDescriptor?, drawable: CAMetalDrawable?)?
        var sceneIsOutput: Bool { output != nil }
    }

    /// Off with `OWE_COMPOSITE_SKIP=0` (comparisons): the composite always runs.
    var skipsIdentityComposite = ProcessInfo.processInfo.environment["OWE_COMPOSITE_SKIP"] != "0"
    /// Frames drawn straight into their output, the composite skipped (tests, diagnostics).
    private(set) var compositesSkipped = 0

    /// The scene target for this frame. When the post-process would change nothing and the
    /// composite would be a 1:1 copy (`ScenePostProcess.passesThrough`), the scene is drawn straight
    /// into its output instead (S2): the view's drawable, taken now, or for a shared frame the
    /// scene target is the frame its displays present. Else the scene's own target.
    private func frameTargets(_ output: FrameOutput, destination: SceneFrameDestination, format: MTLPixelFormat,
                              size: SIMD2<Int>, frame: BuiltinFrameContext) -> FrameTargets? {
        let outputSize = SIMD2<Float>(Float(size.x), Float(size.y))
        let passesThrough = skipsIdentityComposite && !drawsAtRenderScale && !postProcess.drawsHDR && format == destination.pixelFormat
            && postProcess.passesThrough(
                bloom: liveBloom(), extras: appExtras(), settings: renderSettings, colorCorrection: colorCorrection(),
                display: displayOutput, sceneSize: size, outputSize: size,
                placement: layerUniform(position: sceneSize / 2, size: sceneSize, opacity: 1, drawableSize: outputSize,
                                        placement: destination.placement))
        if passesThrough {
            switch output {
            case .view(let view):
                if let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                   drawable.texture.width == size.x, drawable.texture.height == size.y,
                   drawable.texture.pixelFormat == format {
                    // The scene's own target isn't needed while it draws into the drawable.
                    sceneRenderTarget = nil
                    sceneRenderTargetSize = .zero
                    lastDrawableScene = drawable.texture
                    return FrameTargets(scene: drawable.texture, output: (descriptor, drawable))
                }
            case .shared:
                if let scene = sceneRenderTarget(pixelFormat: format, size: size) {
                    sharedFrameTarget = nil
                    return FrameTargets(scene: scene, output: (Self.outputPass(onto: scene), nil))
                }
            }
        }
        return sceneRenderTarget(pixelFormat: format, size: size).map { FrameTargets(scene: $0, output: nil) }
    }

    /// The pass the post-process composites onto, taken once the frame's work is encoded (F1): the
    /// view's drawable, or the shared frame. Nil (the frame isn't shown) without a drawable.
    private func lateOutput(_ output: FrameOutput, matching scene: MTLTexture)
        -> (descriptor: MTLRenderPassDescriptor?, drawable: CAMetalDrawable?) {
        switch output {
        case .view(let view):
            guard let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return (nil, nil) }
            return (descriptor, drawable)
        case .shared:
            return (sharedFramePass(matching: scene), nil)
        }
    }

    /// A pass whose attachment is `texture` as it stands: what the post-process's steps read when
    /// the scene is its own output (nothing composites onto it).
    private static func outputPass(onto texture: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    private func renderFrame(_ output: FrameOutput) {
        let frameStart = CACurrentMediaTime()
        let frameSignpost = OWESignpost.begin(OWESignpost.render, "frame")
        WallpaperServices.shared.beginFrame(wallpaper: wallpaperKey)
        renderTargetPool.endFrame()
        textFrameCache.beginGeneration()
        defer {
            // Compiles this frame started: the next frame draws differently once they land.
            if layerAnalysis != nil, pipelinesCompiling { analysedWarmUp = true }
            WallpaperServices.shared.endFrame()
            frameSignpost.end()
            frameTimeObserver?(CACurrentMediaTime() - frameStart)
            if OWEFrameMetrics.isReportingEnabled {
                OWEFrameMetrics.recordFrame(seconds: CACurrentMediaTime() - frameStart,
                                            layers: layers.count,
                                            particles: particleSystems.reduce(0) {
                                                $1.simulation != nil ? $0 : $0 + ($1.gpu?.completedCount ?? $1.particles.count)
                                            })
            }
        }

        selectDisplayOutput(output)
        guard let destination = frameDestination(output) else { return }
        let viewports = destination.viewports
        drawablePixelsPerPoint = viewports[0].pixelsPerPoint
        // The largest target any display needs, so each shows the scene at its own density.
        let renderDrawable = SceneRenderResolution.drawableSize(viewports, resolution: renderSettings.renderResolution,
                                                                sceneSize: sceneSize)
        renderPixelsPerUnit = SceneRenderResolution.pixelsPerUnit(sceneSize: sceneSize, drawableSize: renderDrawable,
                                                                  matchDisplay: renderSettings.sceneDetail == .matchDisplay)
        // The target the frame is upscaled to when drawn at the render scale (`GSUpscaling`).
        var upscaledTargetSize: SIMD2<Int>?
        // A scene that is one plain video draws it at exactly the display's density, so a target the
        // size of the drawable lets the video draw straight into it in one pass (S2), not into a
        // larger target resampled again by the composite.
        if let exact = videoOnlyPixelsPerUnit(renderDrawable) {
            renderPixelsPerUnit = exact
        } else if renderSettings.drawnScale < 1 {
            upscaledTargetSize = SceneRenderResolution.targetSize(sceneSize: sceneSize, pixelsPerUnit: renderPixelsPerUnit)
            renderPixelsPerUnit = SceneRenderResolution.drawnPixelsPerUnit(renderPixelsPerUnit, scale: renderSettings.drawnScale)
        }
        drawsAtRenderScale = upscaledTargetSize != nil
        // A scene matched to a smaller display is drawn below full detail: what its buffers stand for.
        fullDetailScale = SceneRenderResolution.pixelsPerUnit(sceneSize: sceneSize, drawableSize: renderDrawable) / renderPixelsPerUnit
        // A content drawn in HDR draws into RGBA16F (docs/lighting-plan.md §2.6).
        let scenePixelFormat: MTLPixelFormat = postProcess.drawsHDR ? .rgba16Float : destination.pixelFormat
        let sceneTargetSize = SceneRenderResolution.targetSize(sceneSize: sceneSize, pixelsPerUnit: renderPixelsPerUnit)

        // Layers and particles are drawn in scene units onto a target at the output's pixel
        // density; placement scaling happens once, in the final composite pass.
        let drawableSize = SIMD2<Float>(Float(sceneTargetSize.x), Float(sceneTargetSize.y))
        clock.paused = pausesPlayback
        let rate = playbackRate?() ?? ScenePlaybackSpeed.speed(ofStore: wallpaperKey)
        if redrawing { clock.standStill() } else if holdsClock { clock.hold(at: wallTime()) } else { clock.advance(to: wallTime(), speed: rate) }
        let sceneTime = clock.time
        if clock.hasStopped { onPlaybackStopped?() }
        let time = Float(sceneTime)
        // What a script frame that overran the last draw's wait left (they run on their own thread, §4.5).
        let orderBefore = scripts.state.order
        if !redrawing { applyScriptEvents(scripts.beginFrame()) }
        // WE writes every timeline before the scripts run; a script's calls act on the next advance.
        let animationEvents = redrawing ? [] : timelines.advance(by: Float(clock.delta))
        drawProbe?.beginFrame()
        let cursorSample = cursorTracker.update(sceneCursor(viewports), sceneSize: sceneSize)
        let cursor = cursorSample.position
        // WE's scripts and `g_PointerState` see only clicks that land on the wallpaper.
        let leftDown = cursorSample.onDisplay
            && clickReader.isDown(scripts.services?.clicks?.state ?? DesktopClickMonitor.State())
        releaseFinishedEffectState()
        prelitImages.removeAll(keepingCapacity: true)
        spriteFrameVersions.removeAll(keepingCapacity: true)
        beginTransformFrame()
        advanceRigs()
        if scripts.isRunning && !redrawing {

            // Like WE, the scripts run before the frame that shows what they did (§4.4): this
            // frame's clock, cursor and animated values go in, and their results are drawn now
            // unless they overrun the wait (then they show from the next draw on).
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            submitScriptFrame(viewports: viewports, cursor: cursorSample, leftDown: leftDown,
                              animationEvents: animationEvents)
            scripts.record(since: start, newFrame: false)
            applyScriptEvents(scripts.finishFrame(waitingUpTo: scripts.frameWait))
            beginTransformFrame()
        }
        if scripts.state.order != orderBefore {
            orderLayers()
            beginTransformFrame()
        }
        updateSounds()
        var dynamicTextures: [Int: MTLTexture] = [:]
        // Layers whose effects' last pass draws into the scene (`runEffectsDrawingLastPass`).
        var drawnLastPasses: [Int: EffectGraphRenderer.DrawnLastPass] = [:]
        // Advanced once per frame: every advance smooths the spectrum one step further.
        var effectFrame = BuiltinFrameContext()
        frameSerial &+= 1
        effectFrame.serial = frameSerial
        effectFrame.time = sceneTime
        effectFrame.frameTime = clock.delta
        effectFrame.daytime = BuiltinFrameContext.daytime(at: Date())
        let pointer = simd_clamp(cursor / max(sceneSize, SIMD2(1, 1)), SIMD2(0, 0), SIMD2(1, 1))
        effectFrame.pointer = pointer
        effectFrame.pointerLast = lastPointer ?? pointer
        lastPointer = pointer
        effectFrame.pointerState = BuiltinFrameContext.pointerState(primaryDown: leftDown)
        effectFrame.screenSize = drawableSize
        effectFrame.textureReductionScale = Float(renderSettings.textureReduction)
        effectFrame.audio = audioSpectrumFrame(SceneClock.rate(rate))
        let motion = cameraMotion(pointer: pointer, time: time, deltaTime: Float(clock.delta))
        effectFrame.parallax = cameraParallax.isActive ? cameraParallax.shaderPosition(sceneSize: sceneSize) : SIMD2(0.5, 0.5)
        // WE's camera eye and forward (ctx+0x68, ctx+0x160). An orthographic scene's camera stays
        // still and the objects move by the shake instead (`SceneFrameLightingInput.cameraShake`).
        effectFrame.camera = cameraRig.frameCamera(cameraRigInput(time: sceneTime, motion: motion))
        effectFrame.eyePosition = effectFrame.camera.eye
        effectFrame.viewForward = effectFrame.camera.forward
        // Spatialized sounds are placed against it from the next update on.
        sounds.listener = SceneSoundSpatialization.Listener(camera: effectFrame.camera,
                                                            orthographicSize: isPerspective ? nil : sceneSize)
        effectFrame.lighting = frameLighting(eye: effectFrame.eyePosition, forward: effectFrame.viewForward,
                                             shake: motion.shake)
        analyseLayers(effectFrame: effectFrame, motion: motion, drawableSize: drawableSize)
        guard redrawing || paceFrame(effectFrame, at: wallTime()) else { return }
        // Only a frame that is drawn takes its targets, and the drawable only once its work is
        // encoded (F1), unless the scene draws straight into it (`FrameTargets`, S2).
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let targets = frameTargets(output, destination: destination, format: scenePixelFormat, size: sceneTargetSize,
                                         frame: effectFrame) else { return }
        let sceneTexture = targets.scene
        if targets.sceneIsOutput { compositesSkipped += 1 }
        let multisampledScene = sceneMultisample(for: sceneTexture)
        // Draws sample the last frame's copy; this frame's is made after the scene pass.
        mipMappedTarget = mipMappedFrameBuffer?.target(matching: sceneTexture, commandBuffer: commandBuffer)
        encodedFrames &+= 1
        drawProbe?.record(lighting: effectFrame.lighting)
        frameShadowAtlas = drawShadows(frame: effectFrame, commandBuffer: commandBuffer)
        // Text is rasterised first so its effects run on the finished text, like an image layer's.
        var textFrames: [Int: (frame: RenderTextureFrame, baseSize: SIMD2<Float>)] = [:]
        // Only visible layers get an entry; the draw loop skips the rest.
        var draws: [Int: LayerDraw] = [:]
        layerComposites.removeAll(keepingCapacity: true)
        let compositeOrder = self.compositeOrder()
        for layerIndex in compositeOrder.sequence {
            let entry = layers[layerIndex]
            // Hidden layers keep their transforms (scripts and hit tests read them) but draw nothing,
            // except into the image a model or another layer samples (`_rt_imageLayerComposite_<id>_a`).
            let visible = scripts.isVisible(entry.layer.id)
                && !(hidesClockLayers && clockLayerIDs.contains(entry.layer.id))
            let isCompositeSource = compositeOrder.sources.contains(entry.layer.id)
                || models?.compositeLayerIDs.contains(entry.layer.id) == true
            guard visible || isCompositeSource else { continue }
            if entry.layer.text != nil {
                // Drawn through a camera, text is as dense on screen as its projection makes it.
                let onScreen = layerPlacement(entry, size: layerBaseSize(entry), musicSyncLevel: 0, motion: motion,
                                              camera: effectFrame.camera)?.pixelsPerUnit(targetSize: drawableSize)
                    ?? { let world = frameZoom.plane * worldTransform(entry); return max(world.axisScale.x, world.axisScale.y) * renderPixelsPerUnit }()
                let pixelsPerUnit = SceneTextRasterScale.layer(onScreen: onScreen,
                                                               hasEffects: !entry.layer.weEffects.isEmpty)
                textFrames[layerIndex] = layerTextFrame(entry, boxSize: layerBaseSize(entry),
                                                        pixelsPerUnit: pixelsPerUnit)
            }
            // A puppet's mesh draws its image before anything reads it: its effects, its own draw.
            if let puppet = entry.layer.puppet {
                drawPuppet(puppet, entry, frame: effectFrame, compositeSource: isCompositeSource, commandBuffer: commandBuffer)
            }
            // Text's block is centred on its lines, not on the origin (`SceneTextLayout.boxCenter`);
            // a puppet's quad covers its canvas (`ScenePuppetCanvas`).
            var baseSize = textFrames[layerIndex]?.baseSize ?? layerBaseSize(entry)
            var contentOffset = textFrames[layerIndex]?.frame.textCenter ?? .zero
            if let canvas = puppetCanvases[entry.layer.id], let puppet = entry.layer.puppet {
                let scale = baseSize / puppet.imageSize
                baseSize = canvas.size * scale
                contentOffset = canvas.center * scale
            }
            var draw = layerDraw(entry, baseSize: baseSize, motion: motion, contentOffset: contentOffset)
            draw.placement = layerPlacement(entry, size: baseSize,
                                            musicSyncLevel: draw.musicSyncLevel, motion: motion, camera: effectFrame.camera)
            draw.placement?.offset += contentOffset
            // A hidden layer that runs in the scene pass still makes the image its readers sample.
            let runsInScene = entry.layer.readsScene || compositeOrder.inScene.contains(entry.layer.id)
            if visible || runsInScene { draws[layerIndex] = draw }
            // Layers that read the scene run inside the scene pass, once what's beneath them is drawn,
            // and so do the layers that sample them (`SceneLayerCompositeOrder.inScene`).
            if runsInScene { continue }
            if !entry.layer.weEffects.isEmpty {
                let input = solidEffectInput(entry.layer, commandBuffer: commandBuffer)
                    ?? effectInput(entry, image: textFrames[layerIndex]?.frame ?? textureFrame(for: entry), commandBuffer: commandBuffer)
                drawnLastPasses[layerIndex] = visible ? runEffectsDrawingLastPass(
                    entry, draw: draw, input: input, compositeSource: isCompositeSource, sceneFormat: sceneTexture.pixelFormat,
                    frame: effectFrame, commandBuffer: commandBuffer) : nil
                if drawnLastPasses[layerIndex] == nil {
                    dynamicTextures[layerIndex] = posedEffectOutput(
                        runEffects(entry, draw: draw, input: input, snapshot: nil, frame: effectFrame, commandBuffer: commandBuffer),
                        of: entry, camera: effectFrame.camera, commandBuffer: commandBuffer)
                }
            }
            if isCompositeSource {
                layerComposites[entry.layer.id] = dynamicTextures[layerIndex]
                    ?? solidEffectInput(entry.layer, commandBuffer: commandBuffer)
                    ?? compositeText(entry) ?? textureFrame(for: entry).texture
            }
        }
        // The next script frame reads this frame's text sizes and camera (WE's cursor pass and
        // `size` see the last drawn frame).
        lastTextSizes.removeAll(keepingCapacity: true)
        for (index, frame) in textFrames { lastTextSizes[layers[index].layer.id] = frame.baseSize }
        lastCameraMotion = motion

        // WE clears the scene to `general.clearcolor` (the composite's letterbox stays black).
        let clear = scripts.state.scene.vector3(.clearcolor) ?? clearColor
        let sceneRenderPass = MTLRenderPassDescriptor()
        Self.attachScene(sceneTexture, multisampled: multisampledScene, to: sceneRenderPass)
        sceneRenderPass.colorAttachments[0].loadAction = .clear
        sceneRenderPass.colorAttachments[0].clearColor = MTLClearColor(red: Double(clear.x), green: Double(clear.y),
                                                                       blue: Double(clear.z), alpha: 1)
        attachSceneDepth(to: sceneRenderPass, scene: sceneTexture)
        // One instanced draw per system rather than one per particle (or per rope segment, which
        // multiplies out to thousands on trail renderers).
        particleInstances.removeAll(keepingCapacity: true)
        particleRequests.removeAll(keepingCapacity: true)
        var particleBatches: [(system: ParticleSystemRuntime, base: Int, count: Int, material: Bool, simulated: Bool)] = []
        // Systems are drawn in scene.json order, between the layers around them.
        let orderedSystems = particleSystems.enumerated()
            .sorted { ($0.element.configuration.order, $0.offset) < ($1.element.configuration.order, $1.offset) }
            .map(\.element)
        let particleSignpost = OWESignpost.begin(OWESignpost.render, "updateParticles")
        // Each visible system's step this frame, for the renderers after its first.
        var steppedInputs: [ObjectIdentifier: ParticleFrameInputs] = [:]
        for system in orderedSystems {
            let base = particleInstances.count
            let prewarm: [ParticleFrameInputs]
            var inputs: ParticleFrameInputs
            if let simulation = system.simulation {
                // A renderer after a system's first draws the particles that system's step (just
                // before, in the same order) left, with its own orientation; a hidden system's none.
                guard let stepped = steppedInputs[ObjectIdentifier(simulation)] else { continue }
                system.followSimulation()
                prewarm = []
                inputs = stepped
                inputs.drawSizeScale = system.drawSizeScale
                inputs.spriteLinear = system.spriteLinear
            } else {
                // A hidden system (its own `visible` or a parent's) draws nothing; WE clears it once and
                // keeps its time running with emission off (`ParticleFrameInputs.hidden`).
                let objectID = particleObjectID(system)
                if let objectID, !scripts.isVisible(objectID) {
                    stepHiddenParticles(system, deltaTime: Float(clock.delta), pixelFormat: sceneTexture.pixelFormat)
                    continue
                }
                let script = objectID.flatMap(scripts.object)
                let scripted = script.flatMap(SceneScriptInstanceOverrides.init)
                let emitter = emitterWorld(system.configuration, motion: motion)
                // `starttime`: the system's first frame comes after WE's pre-simulation.
                // WE's engine frame time and frame-rate limit steer drag and the operators' half steps
                // (`ParticleFrameInputs.dragDeltaTime`, `substeps`); the pre-simulation runs in this frame.
                let layerWorld = { [self] (id: String) in emitterImageLayerWorld(id, motion: motion) }
                let modelCapsules = { [self] (id: String) in particleCapsules(id, for: system) }
                prewarm = ParticlePrewarm.steps(system).map {
                    ParticleFrameInputs.advance(system, deltaTime: $0, cursor: cursor, emitter: emitter, values: timelines.values,
                                                scripted: scripted,
                                                audio: effectFrame.audio, frameTime: Float(clock.delta),
                                                frameRateLimit: destination.frameRateLimit, layerWorld: layerWorld,
                                                modelCapsules: modelCapsules)
                }
                // A script's `pause()` holds the system as it is; `stop()` clears it until `play()`.
                let paused = script?.playback == .pause
                inputs = ParticleFrameInputs.advance(system, deltaTime: paused ? 0 : Float(clock.delta), cursor: cursor,
                                                     emitter: emitter, values: timelines.values, scripted: scripted,
                                                     audio: effectFrame.audio,
                                                     frameTime: Float(clock.delta), frameRateLimit: destination.frameRateLimit,
                                                     layerWorld: layerWorld, modelCapsules: modelCapsules)
                Self.applyScriptPlayback(script?.playback, emitting: objectID.flatMap { pendingEmits.removeValue(forKey: $0) },
                                         to: &inputs)
                steppedInputs[ObjectIdentifier(system)] = inputs
            }
            if particleSimulator != nil {
                // The GPU steps the system and writes whichever records it is drawn from.
                let rendererName = system.configuration.rendererName
                if let simulated = particleMaterials?.prepareSimulated(system, pixelFormat: sceneTexture.pixelFormat,
                                                                       sampleCount: sceneSampleCount,
                                                                       depthFormat: sceneDepthFormat) {
                    let kind = ParticleGPUDrawKind.material(simulated.format, rendererName: rendererName)
                    for step in prewarm {
                        particleRequests.append(.init(system: system, inputs: step, kind: kind, materialVertexCount: simulated.vertexCount,
                                                      writesRecords: false))
                    }
                    particleRequests.append(.init(system: system, inputs: inputs, kind: kind,
                                                  materialVertexCount: simulated.vertexCount, renderVar: simulated.renderVar))
                    particleBatches.append((system, base, 0, true, true))
                } else {
                    let kind = ParticleGPUDrawKind.fallback(rendererName: rendererName)
                    for step in prewarm { particleRequests.append(.init(system: system, inputs: step, kind: kind, writesRecords: false)) }
                    particleRequests.append(.init(system: system, inputs: inputs, kind: kind))
                    particleBatches.append((system, base, 0, false, true))
                }
                continue
            }
            if system.simulation == nil {
                for step in prewarm { ParticleCPUSimulation.step(system, inputs: step) }
                ParticleCPUSimulation.step(system, inputs: inputs)
            }
            if particleMaterials?.prepare(system, pixelFormat: sceneTexture.pixelFormat, sampleCount: sceneSampleCount,
                                          depthFormat: sceneDepthFormat,
                                          opacity: { [unowned self] in self.particleOpacity($0, in: system) }) == true {
                particleBatches.append((system, base, 0, true, false))
                continue
            }
            if system.configuration.rendererName == "rope" {
                appendRope(system, drawableSize: drawableSize)
            } else {
                for particle in system.particles {
                    if system.configuration.rendererName == "ropetrail" {
                        appendRopeTrail(particle, system: system, drawableSize: drawableSize)
                    } else if system.configuration.rendererName.contains("trail") {
                        appendParticleTrail(particle, system: system, drawableSize: drawableSize)
                    } else {
                        var uniform = layerUniform(position: particle.position,
                                                   size: SIMD2<Float>(repeating: particle.size),
                                                   opacity: particleOpacity(particle, in: system),
                                                   drawableSize: drawableSize, placement: .stretch)
                        uniform.particleShape = 1
                        uniform.rotation = particle.rotation
                        let axes = system.spriteAxes(size: particle.size, rotation: particle.rotation,
                                                     scale: drawableSize / sceneSize)
                        uniform.quadAxisX = axes.x
                        uniform.quadAxisY = axes.y
                        uniform.color = particle.color
                        let uv = spriteSheetUV(for: particle, configuration: system.configuration)
                        uniform.uvOrigin = uv.origin
                        uniform.uvAxisX = SIMD2<Float>(uv.size.x, 0)
                        uniform.uvAxisY = SIMD2<Float>(0, uv.size.y)
                        particleInstances.append(uniform)
                    }
                }
            }
            particleBatches.append((system, base, particleInstances.count - base, false, false))
        }
        particleSignpost.end()
        particleSimulator?.encode(particleRequests, sceneSize: sceneSize, targetSize: drawableSize,
                                  commandBuffer: commandBuffer)
        frameReflection = drawReflection(frame: effectFrame, scene: sceneTexture, draws: draws,
                                         image: { [unowned self] in textFrames[$0]?.frame ?? self.textureFrame(for: self.layers[$0]) },
                                         effectOutputs: dynamicTextures,
                                         batches: particleBatches.map { ($0.system, $0.material) }, commandBuffer: commandBuffer)
        guard var encoder = commandBuffer.makeRenderCommandEncoder(descriptor: sceneRenderPass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        let particleBuffer = particleInstanceBuffer(for: particleInstances.count)
        if let particleBuffer {
            particleInstances.withUnsafeBytes { source in
                particleBuffer.contents().copyMemory(from: source.baseAddress!, byteCount: source.count)
            }
        }
        // WE's object loop (docs/models-plan.md §2.4): the layers and models in draw order, each
        // after the particle systems whose key is below its barrier.
        let sequence = drawSequence(batches: particleBatches.map(\.system), forward: effectFrame.camera.forward)
        particleBatches = sequence.batchOrder.map { particleBatches[$0] }
        var nextParticleBatch = 0
        /// One instanced draw per system, for every system whose key is below `order`. False when the
        /// scene pass couldn't resume after a snapshot.
        func drawParticleBatches(before order: Int) -> Bool {
            var drew = false
            while nextParticleBatch < particleBatches.count, sequence.batchKeys[nextParticleBatch] < order {
                let batch = particleBatches[nextParticleBatch]
                nextParticleBatch += 1
                if batch.material, drawsReducedResolution(batch.system) {
                    // A run of large additive systems draws at half resolution and is added back
                    // in its place (`SceneRenderSettings.reducedResolutionParticles`); addition
                    // commutes, so a system whose half-resolution pipeline still compiles draws
                    // at full resolution right after.
                    var group = [batch.system]
                    while nextParticleBatch < particleBatches.count, sequence.batchKeys[nextParticleBatch] < order,
                          particleBatches[nextParticleBatch].material,
                          drawsReducedResolution(particleBatches[nextParticleBatch].system) {
                        group.append(particleBatches[nextParticleBatch].system)
                        nextParticleBatch += 1
                    }
                    func context(_ system: ParticleSystemRuntime) -> ParticleMaterialRenderer.DrawContext {
                        .init(sceneSize: sceneSize, frame: effectFrame, values: timelines.values,
                              assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
                              mipMappedFrameBuffer: mipMappedTarget, shadowAtlas: frameShadowAtlas,
                              placement: particlePlacement(system, camera: effectFrame.camera))
                    }
                    endScenePass(encoder, resumes: true)
                    let reduced = drawReducedResolution(group, scene: sceneTexture, commandBuffer: commandBuffer, context: context)
                    guard let resumed = resumeScenePass(on: sceneTexture, commandBuffer: commandBuffer) else { return false }
                    encoder = resumed
                    if let half = reduced.target {
                        var uniform = layerUniform(position: sceneSize / 2, size: sceneSize, opacity: 1,
                                                   drawableSize: SIMD2(Float(sceneTexture.width), Float(sceneTexture.height)),
                                                   placement: .stretch)
                        encoder.setRenderPipelineState(scenePassPipelines.addCopy)
                        encoder.setVertexBytes(&uniform, length: MemoryLayout<LayerUniform>.stride, index: 0)
                        encoder.setFragmentTexture(half, index: 0)
                        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    }
                    for system in reduced.left {
                        particleMaterials?.draw(system, encoder: encoder, commandBuffer: commandBuffer, context: context(system))
                    }
                    drew = true
                    continue
                }
                if batch.material {
                    var snapshot: MTLTexture?
                    let placement = particlePlacement(batch.system, camera: effectFrame.camera)
                    if particleMaterials?.readsSceneSnapshot(batch.system) == true {
                        // Refraction reads the scene drawn up to this system (`_rt_FullFrameBuffer`):
                        // only around its particles when that is known, else all of it.
                        endScenePass(encoder, resumes: true)
                        let pixels = SIMD2(sceneTexture.width, sceneTexture.height)
                        let needed = placement != nil ? nil
                            : particleMaterials?.sceneSnapshotRect(batch.system, sceneSize: sceneSize, targetSize: pixels)
                        snapshot = sceneSnapshot(of: sceneTexture, commandBuffer: commandBuffer, needing: needed)
                        guard let resumed = resumeScenePass(on: sceneTexture, commandBuffer: commandBuffer) else { return false }
                        encoder = resumed
                    }
                    particleMaterials?.draw(batch.system, encoder: encoder, commandBuffer: commandBuffer, context: .init(
                        sceneSize: sceneSize, frame: effectFrame,
                        values: timelines.values,
                        assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
                        sceneSnapshot: snapshot, mipMappedFrameBuffer: mipMappedTarget, shadowAtlas: frameShadowAtlas,
                        depth: frameDepth, placement: placement))
                    drew = true
                    continue
                }
                let pipeline = batch.system.configuration.blending == "additive" ? additiveRenderPipeline : renderPipeline
                // The built-in draw has no material: nothing to test against [I].
                frameDepth?.apply(.disabled, to: encoder)
                if batch.simulated {
                    // The built-in quads the GPU step wrote, counted by its indirect arguments.
                    guard let gpu = batch.system.gpu, gpu.isReady, let records = gpu.records,
                          gpu.recordKind?.isFallback == true else { continue }
                    encoder.setVertexBuffer(records, offset: 0, index: 0)
                    encoder.setFragmentBuffer(records, offset: 0, index: 0)
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setFragmentTexture(batch.system.fallbackTexture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, indirectBuffer: gpu.control,
                                           indirectBufferOffset: ParticleGPUSystem.Control.fallbackDrawOffset)
                    drew = true
                    continue
                }
                guard batch.count > 0, let particleBuffer else { continue }
                // Layer draws rebind index 0 with setVertexBytes, so bind the instances per draw.
                encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(particleBuffer, offset: 0, index: 0)
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(batch.system.fallbackTexture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                       instanceCount: batch.count, baseInstance: batch.base)
                drew = true
            }
            if drew { encoder.setRenderPipelineState(renderPipeline) }
            return true
        }
        sceneCopy = nil
        snapshotSharesMipMappedTarget = mipMappedTarget != nil && SceneMipMappedFrameBuffer.snapshotCanShare(
            layers: layers.lazy.map(\.layer), particleSystems: particleSystems.map(\.configuration),
            reflection: renderSettings.reflection)
        snapshotTracker.reset()
        let targetSize = SIMD2(sceneTexture.width, sceneTexture.height)
        for (item, barrier) in sequence.items {
            let batchesBefore = nextParticleBatch
            guard drawParticleBatches(before: barrier) else { return }
            // Particles cover no rect we track: the snapshot no longer matches anywhere.
            if nextParticleBatch != batchesBefore { snapshotTracker.sceneDrawn(in: nil) }
            guard case .layer(let layerIndex) = item else {
                if case .model(let index) = item {
                    drawModel(index, frame: effectFrame, pixelFormat: sceneTexture.pixelFormat, encoder: encoder,
                              commandBuffer: commandBuffer)
                    snapshotTracker.sceneDrawn(in: nil)
                }
                continue
            }
            let entry = layers[layerIndex]
            // Hidden layers (script `visible = false`) draw nothing, their raw texture included.
            guard let draw = draws[layerIndex] else { continue }
            var layerSnapshot: MTLTexture?
            if entry.layer.readsScene || compositeOrder.inScene.contains(entry.layer.id) {
                // Metal can't sample the attachment it's drawing into: pause the scene pass, run
                // this layer's effects on what's drawn so far (`_rt_FullFrameBuffer`), resume. The
                // effects read the target itself while the pass is paused; only a material that
                // reads the scene from inside the resumed pass needs a copy of it.
                endScenePass(encoder, resumes: true)
                var snapshot: MTLTexture? = sceneTexture
                if entry.layer.imageMaterial?.readsSceneSnapshot == true {
                    // A material or scene input reads the scene under its own quad; an effect anywhere.
                    let needed = entry.layer.effectsReadScene || draw.placement != nil ? nil
                        : SceneSnapshotTracker.pixelRect(of: draw.quad, sceneSize: sceneSize, targetSize: targetSize)
                            ?? SceneSnapshotTracker.Rect.empty
                    snapshot = sceneSnapshot(of: sceneTexture, commandBuffer: commandBuffer, needing: needed)
                    layerSnapshot = snapshot
                }
                let input = entry.layer.sceneInput
                    ? snapshot.flatMap { sceneRegion(of: $0, under: draw.quad, placement: draw.placement, reducedFor: entry.layer,
                                                     commandBuffer: commandBuffer) }
                    : solidEffectInput(entry.layer, commandBuffer: commandBuffer)
                        ?? effectInput(entry, image: textFrames[layerIndex]?.frame ?? textureFrame(for: entry),
                                       commandBuffer: commandBuffer)
                dynamicTextures[layerIndex] = posedEffectOutput(input.flatMap {
                    runEffects(entry, draw: draw, input: $0, snapshot: snapshot, frame: effectFrame, commandBuffer: commandBuffer)
                }, of: entry, camera: effectFrame.camera, commandBuffer: commandBuffer)
                guard let resumed = resumeScenePass(on: sceneTexture, commandBuffer: commandBuffer) else { return }
                encoder = resumed
                // Its composite is what readers drawn after it sample (`_rt_imageLayerComposite_<id>_a`).
                if compositeOrder.sources.contains(entry.layer.id) || models?.compositeLayerIDs.contains(entry.layer.id) == true {
                    layerComposites[entry.layer.id] = dynamicTextures[layerIndex] ?? input
                }
                if !scripts.isVisible(entry.layer.id) { continue }
                // Until its effects are ready the layer has nothing of its own to draw.
                if entry.layer.sceneInput, dynamicTextures[layerIndex] == nil { continue }
            }
            // Drawn below, natively or through its material; through a camera, anywhere.
            if draw.placement != nil {
                snapshotTracker.sceneDrawn(in: nil)
            } else if let drawn = SceneSnapshotTracker.pixelRect(of: draw.quad, sceneSize: sceneSize, targetSize: targetSize) {
                snapshotTracker.sceneDrawn(in: drawn)
            }
            encodeLayer(entry, draw, image: textFrames[layerIndex]?.frame ?? textureFrame(for: entry),
                        effectOutput: dynamicTextures[layerIndex], drawnLastPass: drawnLastPasses[layerIndex],
                        snapshot: layerSnapshot, frame: effectFrame,
                        target: LayerTarget(size: drawableSize, pixelFormat: sceneTexture.pixelFormat,
                                            sampleCount: sceneSampleCount, depth: frameDepth, pipelines: scenePassPipelines),
                        encoder: encoder, commandBuffer: commandBuffer)
        }
        guard drawParticleBatches(before: .max) else { return }
        endScenePass(encoder, resumes: false)

        var stageContext = SceneFrameStageContext(scene: sceneTexture, commandBuffer: commandBuffer, sceneSize: sceneSize,
                                                  frame: effectFrame, settings: renderSettings)
        stageContext.assetTexture = { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) }
        stageContext.sceneDepth = frameDepth == nil ? nil : depthBuffer.texture
        stageContext.shadowAtlas = frameShadowAtlas
        for stage in frameStages { stage.encode(stageContext) }
        // The drawable (F1: taken now, after the frame's work is encoded) or the shared frame.
        // Drawn at the render scale: scaled up to the full target before the post-process.
        var postScene: MTLTexture = sceneTexture
        var postFullDetailScale = fullDetailScale
        if let upscaledTargetSize, !targets.sceneIsOutput,
           upscaler.path(settings: renderSettings, format: sceneTexture.pixelFormat) == .metalFX,
           let upscaled = upscaler.upscale(sceneTexture, to: upscaledTargetSize, commandBuffer: commandBuffer) {
            postScene = upscaled
            postFullDetailScale = fullDetailScale * Float(sceneTexture.width) / Float(max(upscaled.width, 1))
        }
        let (descriptor, drawable) = targets.output ?? lateOutput(output, matching: postScene)
        if let descriptor {
            // What the post-process composites onto: the drawable, or the shared frame.
            let realDrawableSize = SIMD2<Float>(Float(descriptor.colorAttachments[0].texture?.width ?? sceneTexture.width),
                                                Float(descriptor.colorAttachments[0].texture?.height ?? sceneTexture.height))
            // The scene-resolution target goes onto the real drawable, placement applied exactly once.
            postProcess.encode(ScenePostProcess.Frame(
                scene: postScene, output: descriptor, commandBuffer: commandBuffer,
                placement: layerUniform(position: sceneSize / 2, size: sceneSize, opacity: 1, drawableSize: realDrawableSize,
                                        placement: destination.placement),
                bloom: liveBloom(), extras: appExtras(), settings: renderSettings,
                colorCorrection: colorCorrection(),
                effects: effectGraph, builtins: effectFrame, values: timelines.values, fullDetailScale: postFullDetailScale,
                display: displayOutput, sceneIsOutput: targets.sceneIsOutput))
            if let drawable {
                commandBuffer.present(drawable)
            } else {
                sharedFrame = descriptor.colorAttachments[0].texture
            }
        }
        // A video frame's pixel buffer returns to the decoder's pool once released; hold each one
        // this frame sampled until the GPU is done reading it.
        for entry in layers { if case let .video(stream) = entry.layer.source { stream.holdCurrentFrame(until: commandBuffer) } }
        // "Pause when VRAM is exhausted" (`VideoMemoryWatch`): a frame that ran out of memory.
        commandBuffer.addCompletedHandler { buffer in
            guard buffer.status == .error, VideoMemoryWatch.isOutOfMemory(buffer.error) else { return }
            NotificationCenter.default.post(name: .videoMemoryCommandBufferFailed, object: nil)
        }
        commandBuffer.commit()
        lastCommandBuffer = commandBuffer
    }

    /// The scene's bloom this frame: `thisScene.bloom`, `bloomstrength` and `bloomthreshold` once a
    /// script set them, else their timelines, else the content's.
    private func liveBloom() -> ScenePostProcess.Bloom {
        let scene = scripts.state.scene
        return ScenePostProcess.Bloom(
            enabled: scene.flag(.bloom) ?? bloom.enabled,
            strength: scene.scalar(.bloomstrength) ?? timelines.sceneScalar(.bloomstrength) ?? bloom.strength,
            threshold: scene.scalar(.bloomthreshold) ?? timelines.sceneScalar(.bloomthreshold) ?? bloom.threshold,
            tint: bloom.tint, hdr: liveHDRBloom())
    }

    /// The HDR bloom's `bloomhdr*` this frame: a bound script's, else its timeline's, else the
    /// content's. Whether the scene draws in HDR stays the content's (WE decides it at load).
    private func liveHDRBloom() -> SceneHDRBloomSettings {
        var hdr = bloom.hdr
        hdr.strength = sceneSetting(.bloomhdrstrength) ?? hdr.strength
        hdr.threshold = sceneSetting(.bloomhdrthreshold) ?? hdr.threshold
        hdr.feather = sceneSetting(.bloomhdrfeather) ?? hdr.feather
        hdr.scatter = sceneSetting(.bloomhdrscatter) ?? hdr.scatter
        // An int property: WE's converter truncates (`ToInt32`).
        if let iterations = sceneSetting(.bloomhdriterations), iterations.isFinite, abs(iterations) < 1e9 {
            hdr.iterations = Int(iterations)
        }
        return hdr
    }

    /// The app's own whole-scene adjustments, from this wallpaper's user properties.
    private func appExtras() -> ScenePostProcess.AppExtras {
        let services = WallpaperServices.shared
        return ScenePostProcess.AppExtras(bloom: services.userPropertyValue("_owe_bloom", fallback: 1),
                                          saturation: services.userPropertyValue("_owe_saturation", fallback: 1),
                                          hue: services.userPropertyValue("_owe_hue", fallback: 0),
                                          blur: services.userPropertyValue("_owe_blur", fallback: 1))
    }

    /// WE's image filter and colour options, from this wallpaper's user properties.
    private func colorCorrection() -> SceneColorCorrectionSettings {
        let services = WallpaperServices.shared
        return SceneColorCorrectionSettings { services.userPropertyString($0.rawValue) }
    }

    /// This frame's lighting (`SceneFrameLighting`), from the objects' live transforms and
    /// visibility, the scripts' scene colours and the user's shadows setting.
    private func frameLighting(eye: SIMD3<Float>, forward: SIMD3<Float>, shake: SIMD2<Float>) -> SceneFrameLighting {
        let scene = scripts.state.scene
        var frame = SceneFrameLighting.frame(lighting, input: SceneFrameLightingInput(

            local: { [unowned self] id in self.liveLocal(id) ?? self.transforms.nodes[id]?.local },
            parentWorld: { [unowned self] id in self.transforms.parentWorld(of: id) { self.liveLocal($0) } },
            isVisible: { [unowned self] id in self.scripts.isVisible(id) },
            world3D: isPerspective ? { [unowned self] id in self.world3D(id, in: self.spatial.transforms) } : nil,
            sceneColor: { scene.vector3($0) },
            live: { [unowned self] object in
                object.live(script: self.scripts.object(object.id), animation: self.timelines.object(object.id),
                            timeline: { self.timelines.objectField(object.id, $0) })
            },
            shadows: renderSettings.shadows != .disabled, shadowQuality: renderSettings.shadows.level,
            reducedShadowMaps: renderSettings.cheaperShadows,
            orthographic: !isPerspective, shadowAtlasExtent: shadowPass?.atlas.extent ?? .zero, cameraShake: shake,
            eyePosition: eye, viewForward: forward, zoom: frameZoom))
        frame.fog = frame.fog.live(number: { [unowned self] in self.sceneSetting($0) }, color: { scene.vector3($0) })
        if !loggedFogToggle, frame.fog.distance != lighting.settings.fog.distance || frame.fog.height != lighting.settings.fog.height {
            loggedFogToggle = true
            OWELog.error(.scene, "A script turned the scene's fog on or off: the materials keep the fog combos they were built with, so only its colours, ranges and densities follow the script")
        }
        return frame

    }


    /// This frame's `_rt_shadowAtlas` (docs/models-plan.md §2.10): the lighting's shadow maps
    /// drawn with the visible model objects that cast, before the scene pass reads them, or the
    /// cleared stand-in without maps.
    private func drawShadows(frame: BuiltinFrameContext, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let shadowPass, let models else { return nil }
        let casters = spatial.models.filter { scripts.isVisible($0.id) && SceneShadowPass.castsShadow($0) }
            .map { SceneShadowPass.Caster(model: $0, world: drawnWorld3D($0.id)) }
        return shadowPass.encode(frame.lighting.shadows, casters: casters, models: models, frame: frame, values: timelines.values,
                                 assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
                                 commandBuffer: commandBuffer)
    }

    /// The pass a layer's quad draws into: its target's format and samples, its depth states (nil
    /// without depth) and the native layer pipelines for it.
    private struct LayerTarget {
        /// The target's size in pixels.
        var size: SIMD2<Float>
        var pixelFormat: MTLPixelFormat
        var sampleCount: Int
        var depth: SceneDepthStates?
        var pipelines: SceneLayerPipelines.Pipelines
    }

    /// Draws a layer's quad into `encoder`'s pass: through its material, or natively when it has
    /// none or its material can't draw this frame. `image` is its texture frame (its text raster
    /// for a text layer), `effectOutput` what its effects made this frame, `snapshot` the scene
    /// under it for a material that reads it. Leaves `target.pipelines.normal` set.
    private func encodeLayer(_ entry: PreparedLayer, _ draw: LayerDraw, image: RenderTextureFrame,
                             effectOutput: MTLTexture?, drawnLastPass: EffectGraphRenderer.DrawnLastPass? = nil,
                             snapshot layerSnapshot: MTLTexture?, frame: BuiltinFrameContext,
                             target: LayerTarget, encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {
        // Effects that started from the frame cut out of the atlas (`effectInput`) made one frame:
        // the layer draws their output whole.
        let textureFrame = effectOutput != nil && spriteFrameVersions[entry.layer.id] != nil
            ? RenderTextureFrame(texture: image.texture, duration: image.duration, uvOrigin: .zero,
                                 uvAxisX: SIMD2(1, 0), uvAxisY: SIMD2(0, 1))
            : image
        // The effects' last pass draws the layer: through its quad, with its material's blending and
        // depth state (`runEffectsDrawingLastPass`).
        if let drawnLastPass, let effectGraph, let plan = entry.layer.imageMaterial {
            target.depth?.apply(layerRaster(entry), to: encoder)
            let placement = lastPassPlacement(plan, draw: draw, image: textureFrame, sceneFormat: target.pixelFormat)
            let context = effectContext(entry, draw: draw, input: drawnLastPass.input, snapshot: nil, frame: frame)
            let drew = effectGraph.encode(drawnLastPass, into: encoder, scene: placement, context: context,
                                          commandBuffer: commandBuffer)
            encoder.setRenderPipelineState(target.pipelines.normal)
            if drew { return }
        }
        var uniform = layerUniform(position: draw.quad.center, size: draw.quad.extent,
                                   opacity: draw.opacity, drawableSize: target.size, placement: .stretch)
        setQuadAxes(&uniform, quad: draw.quad)
        // Text is rasterised white; its user colour tints it when drawn, like its authored one.
        // Text with font effects or layer effects has its colours in its raster (`textFill`).
        let textTint = entry.layer.text == nil ? SIMD3<Float>(repeating: 1) : self.textTint(layerID: entry.layer.id)
        uniform.color = entry.layer.text?.effects == nil && entry.layer.weEffects.isEmpty ? draw.color * SIMD4(textTint, 1)
            : SIMD4(1, 1, 1, draw.color.w)
        let materialEffects = entry.layer.effects
        uniform.effects = SIMD4<Float>(materialEffects.brightness * draw.brightness, materialEffects.contrast,
                                       materialEffects.saturation
                                           * (1 + (entry.layer.musicSync?.saturationAmount ?? 0) * Float(draw.musicSyncLevel)),
                                       materialEffects.bloom * WallpaperServices.shared.userPropertyValue("_owe_bloom", fallback: 1))
        uniform.blur = materialEffects.blur * WallpaperServices.shared.userPropertyValue("_owe_blur", fallback: 1)
        uniform.colorEffects = SIMD4<Float>(materialEffects.exposure, materialEffects.gamma,
                                            materialEffects.hue, materialEffects.bloomThreshold)
        uniform.transform = SIMD4<Float>(materialEffects.transformAngle, materialEffects.transformOffset.x,
                                         materialEffects.transformOffset.y, materialEffects.transformScale.x)
        uniform.transformScaleY = materialEffects.transformScale.y
        uniform.uvOrigin = textureFrame.uvOrigin
        uniform.uvAxisX = textureFrame.uvAxisX
        uniform.uvAxisY = textureFrame.uvAxisY
        // A text layer's `font` material reads the glyphs' coverage; colour glyphs have none.
        // A prelit layer whose chain rendered nothing (every effect hidden, or compiling) draws
        // its prelit image: its own draw has the lighting off, so the raw image would be unlit.
        let materialTexture = entry.layer.text == nil
            ? effectOutput ?? prelitImages[entry.layer.id] ?? textureFrame.texture
            : textureFrame.coverage
        if let plan = entry.layer.imageMaterial, let imageMaterials, let materialTexture, imageMaterials.draw(plan, ImageMaterialRenderer.Draw(
               layerID: entry.layer.id, quad: draw.quad, sceneSize: sceneSize,
               color: SIMD3(draw.color.x, draw.color.y, draw.color.z) * textTint, alpha: draw.opacity, brightness: draw.brightness,
               texture: materialTexture, contentSize: entry.layer.source.contentSize,
               uvOrigin: textureFrame.uvOrigin, uvAxisX: textureFrame.uvAxisX, uvAxisY: textureFrame.uvAxisY,
               sceneSnapshot: layerSnapshot, mipMappedFrameBuffer: mipMappedTarget, shadowAtlas: frameShadowAtlas,
               frame: frame,
               values: timelines.values,
               assetTexture: { [unowned self] key, source in
                   self.puppetWarps[entry.layer.id]?[key] ?? self.effectAssetTexture(key: key, source: source)
               },
               assetSprite: { [unowned self] key, source in self.effectAssetSprite(key: key, source: source) },
               ignoredAdjustments: !ImageMaterialRenderer.nativeAdjustmentsAreIdentity(uniform, brightness: draw.brightness),
               placement: draw.placement, raster: layerRaster(entry)),
               pixelFormat: target.pixelFormat, sampleCount: target.sampleCount, depth: target.depth, encoder: encoder,
               commandBuffer: commandBuffer) {
            encoder.setRenderPipelineState(target.pipelines.normal)
            return
        }
        target.depth?.apply(layerRaster(entry), to: encoder)
        let additive = entry.layer.additive
        if var placed = draw.placement?.native,
           let pipeline = additive ? target.pipelines.placedAdditive : target.pipelines.placedNormal {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&placed, length: MemoryLayout<LayerPlacement3D>.stride, index: 1)
        } else if additive {
            encoder.setRenderPipelineState(target.pipelines.additive)
        }
        encoder.setVertexBytes(&uniform, length: MemoryLayout<LayerUniform>.stride, index: 0)
        encoder.setFragmentBytes(&uniform, length: MemoryLayout<LayerUniform>.stride, index: 0)
        encoder.setFragmentTexture(effectOutput ?? textureFrame.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        if draw.placement != nil || additive { encoder.setRenderPipelineState(target.pipelines.normal) }
    }

    /// This frame's `_rt_Reflection` (docs/models-plan.md §2.11): while a model is reflective, the
    /// visible reflected objects drawn through the mirrored camera in the object loop's order (its
    /// sort keyed on the mirrored forward, as WE sorts inside the mirrored pass), or the clear
    /// colour with the reflection setting off; nil while no model is reflective. It is drawn once
    /// the layers' effects and the particle systems' steps of this frame are encoded, before the
    /// scene pass that samples it: the layers draw this frame's images, as WE's object draws do.
    /// `draws`, `image` (a layer's texture frame, or text raster) and `effectOutputs` are the scene
    /// pass's, by layer index; `batches` its particle systems, and which of them draw through their
    /// material.
    private func drawReflection(frame: BuiltinFrameContext, scene: MTLTexture, draws: [Int: LayerDraw],
                                image: (Int) -> RenderTextureFrame, effectOutputs: [Int: MTLTexture],
                                batches: [(system: ParticleSystemRuntime, material: Bool)],
                                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let planarReflection, let modelDrawing, let depthStates, planarReflection.isNeeded(spatial.models) else {
            if planarReflection?.texture != nil { planarReflection?.release() }
            return nil
        }
        let reflectedModels = Set(planarReflection.reflectedList(spatial.models))
        let sequence = drawSequence(batches: batches.map(\.system), forward: ScenePlanarReflection.mirrored(frame.camera).forward)
        var objects: [ScenePlanarReflection.Object] = []
        var next = 0
        func systems(before barrier: Int) {
            while next < sequence.batchOrder.count, sequence.batchKeys[next] < barrier {
                let batch = batches[sequence.batchOrder[next]]
                next += 1
                if batch.material, let object = reflectedSystem(batch.system) { objects.append(object) }
            }
        }
        for (item, barrier) in sequence.items {
            systems(before: barrier)
            switch item {
            case .model(let index):
                let model = spatial.models[index]
                guard reflectedModels.contains(index), scripts.isVisible(model.id) else { continue }
                objects.append(.model(model, world: drawnWorld3D(model.id)))
            case .layer(let index):
                guard let draw = draws[index] else { continue }
                if let object = reflectedLayer(index, draw, image: image(index), effectOutput: effectOutputs[index]) {
                    objects.append(object)
                }
            case .particles:
                continue
            }
        }
        systems(before: .max)
        let pass = ScenePlanarReflection.Pass(
            width: scene.width, height: scene.height, pixelFormat: scene.pixelFormat,
            clearColor: scripts.state.scene.vector3(.clearcolor) ?? clearColor, enabled: renderSettings.reflection,
            objects: objects,
            frame: frame, values: timelines.values, mipMappedFrameBuffer: mipMappedTarget, shadowAtlas: frameShadowAtlas,
            assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
            layerComposite: { [unowned self] id in self.layerComposites[id] })
        return planarReflection.encode(pass, drawing: modelDrawing, depthStates: depthStates, commandBuffer: commandBuffer)
    }

    /// A layer's draw into the planar reflection, or nil when it isn't in the reflected list (its
    /// `reflected`, or a shape) or hidden. Drawn as in the scene pass with the mirrored camera:
    /// through it where the scene pass draws through the frame camera (a perspective scene's
    /// layers; an orthographic scene's, whose view the mirror makes a camera placement), and
    /// unchanged where WE's view doesn't reach the layer (a fullscreen layer in screen space, a
    /// `perspective` layer through its own temporary camera, 0x1401e5b60). A layer whose image
    /// is made inside the scene pass (it reads the scene, or samples a layer that does) isn't
    /// drawn: its image doesn't exist yet (docs/models-plan.md §4.3 M9).
    private func reflectedLayer(_ index: Int, _ draw: LayerDraw, image: RenderTextureFrame,
                                effectOutput: MTLTexture?) -> ScenePlanarReflection.Object? {
        let entry = layers[index]
        let id = entry.layer.id
        guard scripts.isVisible(id), spatial.isReflected(id), !entry.layer.readsScene,
              !compositeOrder().inScene.contains(id) else { return nil }
        return .other(id: id) { [unowned self] mirrored in
            var reflected = draw
            if self.isPerspective, var placement = draw.placement {
                placement.camera = mirrored.frame.camera
                reflected.placement = placement
            } else if !self.isPerspective, draw.placement == nil, !entry.layer.fillsScene {
                reflected.placement = SceneLayerPlacement(world: ImageMaterialRenderer.modelMatrix(draw.quad),
                                                          size: draw.quad.extent, camera: mirrored.frame.camera)
            }
            guard let pipelines = self.layerPipelines.pipelines(for: mirrored.pixelFormat, sampleCount: 1,
                                                                depthFormat: SceneDepthStates.format) else { return }
            mirrored.encoder.setRenderPipelineState(pipelines.normal)
            let size = SIMD2<Float>(Float(self.sceneRenderTargetSize.x), Float(self.sceneRenderTargetSize.y))
            self.encodeLayer(entry, reflected, image: image, effectOutput: effectOutput, snapshot: nil, frame: mirrored.frame,
                             target: LayerTarget(size: size, pixelFormat: mirrored.pixelFormat, sampleCount: 1,
                                                 depth: mirrored.depth, pipelines: pipelines),
                             encoder: mirrored.encoder, commandBuffer: mirrored.commandBuffer)
        }
    }

    /// A particle system's draw into the planar reflection through its material, or nil when it
    /// isn't in the reflected list or reads the scene drawn so far (refraction; that scene isn't
    /// the reflection's). Its camera is the mirrored one, except a `perspective` system's
    /// temporary camera in an orthographic scene, which WE's view doesn't reach.
    private func reflectedSystem(_ system: ParticleSystemRuntime) -> ScenePlanarReflection.Object? {
        guard let particleMaterials, !particleMaterials.readsSceneSnapshot(system) else { return nil }
        let id = particleObjectID(system)
        if let id, !spatial.isReflected(id) { return nil }
        return .other(id: id ?? "particles") { [unowned self] mirrored in
            // `particlePlacement` keeps a `perspective` system's temporary camera; an orthographic
            // scene's other systems take the mirrored orthographic view.
            let placement = self.particlePlacement(system, camera: mirrored.frame.camera)
                ?? ParticleMaterialUniforms.Placement(camera: mirrored.frame.camera)
            particleMaterials.draw(system, alsoInto: mirrored.pixelFormat, sampleCount: 1, depthFormat: SceneDepthStates.format,
                                   encoder: mirrored.encoder, commandBuffer: mirrored.commandBuffer, context: .init(
                                       sceneSize: self.sceneSize, frame: mirrored.frame, values: self.timelines.values,
                                       assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
                                       sceneSnapshot: nil, mipMappedFrameBuffer: self.mipMappedTarget, shadowAtlas: self.frameShadowAtlas,
                                       depth: mirrored.depth, placement: placement))
        }
    }

    /// WE's sound layers each frame, on the scene clock: the wallpaper gain's fade takes the
    /// frame's wall step, as WE's main loop fades the wallpaper volume (0x1401113f8…0x140111444);
    /// then the volumes scripts set, and the layers' timers, which take the objects' update step
    /// (0x1401891a0: the scene's step, rate and pause ease applied; the sound's update divides it
    /// by a render-context value its constructor sets to 1, 0x1401f4f93, 0x14017c81e [I: nothing
    /// else was seen to change it]).
    private func updateSounds() {
        sounds.advanceFade(frameSeconds: clock.frame)
        guard !sounds.isEmpty else { return }
        for id in sounds.ids {
            if let volume = scripts.object(String(id))?.scalar(.volume) ?? timelines.object(String(id))?.volume {
                sounds.setVolume(volume, of: id)
            }
        }
        sounds.update(deltaTime: clock.delta)
    }

    /// A sound object's world position this frame (its world matrix's translation, parents,
    /// timelines and scripts included), where a `spatialization` sound plays from.
    private func soundWorldPosition(_ id: Int) -> SIMD3<Float> {
        let translation = world3D(String(id), in: spatial.transforms).columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }

    /// Hands the scripts this frame: the clock, the display and cursor, and every object at this
    /// frame's time with the last drawn frame's transforms, text sizes and camera
    /// (docs/scenescript-plan.md §4.4). They run on their own thread; `finishFrame` waits for them.
    private func submitScriptFrame(viewports: [SceneViewport],
                                   cursor: (position: SIMD2<Float>, onDisplay: Bool), leftDown: Bool,
                                   animationEvents: [SceneAnimationEvent]) {
        // The screen the scene is drawn for: its points under Render Resolution "Display".
        let toScreen = scriptScreenScale(viewports[0])
        let drawableSize = viewports[0].drawableSize * toScreen
        var input = SceneScriptFrameInput()
        input.deltaTime = clock.delta
        timelines.describe(into: &input, events: animationEvents)
        input.environment = SceneScriptEngineEnvironment(
            screenResolution: SIMD2(Double(drawableSize.x), Double(drawableSize.y)),
            canvasSize: SIMD2(Double(sceneSize.x), Double(sceneSize.y)), placement: placement,
            pixelsPerPoint: Double(drawablePixelsPerPoint * toScreen), isScreensaver: rendersScreenSaver)
        input.environment.zoom = frameZoom
        input.input = SceneScriptInput(cursorScreenPosition: cursorScreenPixels(viewports) * Double(toScreen),
                                       cursorLeftDown: leftDown)
        // The cursor tracks the drawn plane; scripts and their hit tests see WE's world under it.
        input.cursorScenePosition = frameZoom.worldPoint(drawn: cursor.position)
        input.shakeOffset = lastCameraMotion?.shake ?? .zero
        if let parallax = lastCameraMotion?.parallax {
            input.parallax = SceneScriptCursorFrame.Parallax(state: parallax.state, amount: parallax.amount)
        }
        for entry in layers {
            guard let id = Int(entry.layer.id) else { continue }
            let script = scripts.object(entry.layer.id)
            let base = baseValues(entry)
            let animation = timelines.object(entry.layer.id)
            let own = entry.motion.local(animation: animation, script: script, scriptValues: false)
            input.objects[id] = SceneScriptObjectFeedback(
                origin: own.origin, scale: own.scale, angle: own.angle,
                alpha: baseOpacity(entry, base: base),
                color: animation?.color ?? SIMD3(base.color.x, base.color.y, base.color.z),
                brightness: animation?.brightness ?? base.brightness,
                visible: scripts.baseVisible(entry.layer.id),
                size: lastTextSizes[entry.layer.id] ?? layerBaseSize(entry),
                world: worldTransform(entry), animated: animation?.fields ?? SceneScriptOwnedFields())
            if case let .video(stream) = entry.layer.source {
                input.objects[id]?.playing = stream.isPlaying
                input.objects[id]?.videoTime = stream.currentSeconds
            }
        }
        for (key, objectMotion) in objectMotions {
            guard let id = Int(key) else { continue }
            let animation = timelines.object(key)
            let own = objectMotion.local(animation: animation, script: scripts.object(key), scriptValues: false)
            input.objects[id] = SceneScriptObjectFeedback(
                origin: own.origin, scale: own.scale, angle: own.angle, alpha: nil, color: nil, brightness: nil,
                visible: scripts.baseVisible(key), size: nil,
                world: transforms.world(of: key, live: { [self] id in liveLocal(id) }, attachments: puppetAttachments.affine),
                animated: animation?.fields ?? SceneScriptOwnedFields(), playing: sounds.isPlaying(id))
        }
        for entry in layers where entry.layer.puppet != nil {
            guard let id = Int(entry.layer.id), let animator = puppetAnimators[entry.layer.id] else { continue }
            let world = ScenePuppetAttachments.matrix(worldTransform(entry))
            input.rigs[id] = SceneScriptRigFeedback(layers: animator.layerStates, locals: animator.locals,
                                                    worlds: animator.worlds.map { world * $0 }, ended: animator.takeEnded(),
                                                    blendShapeWeights: animator.blendShapeWeights, events: animator.takeEvents())
        }
        for key in models?.riggedObjectIDs ?? [] {
            guard let id = Int(key), let animator = models?.animator(for: key) else { continue }
            let world = world3D(key, in: spatial.transforms)
            input.rigs[id] = SceneScriptRigFeedback(layers: animator.layerStates, locals: animator.locals,
                                                    worlds: animator.worlds.map { world * $0 }, ended: animator.takeEnded(),
                                                    events: animator.takeEvents())
        }

        scripts.submit(input)
    }

    /// The cursor in display pixels from the top-left of the wallpaper's view on the display it is
    /// on (`input.cursorScreenPosition`); where it was last seen while it is on none of them.
    /// Screen pixels the scripts see per drawable pixel: 1 / pixels per point when the scene is
    /// drawn at the display's points (`GSRenderResolution.display`), else 1.
    private func scriptScreenScale(_ viewport: SceneViewport) -> Float {
        guard renderSettings.renderResolution == .display, viewport.pixelsPerPoint > 0 else { return 1 }
        return 1 / viewport.pixelsPerPoint
    }

    private func cursorScreenPixels(_ viewports: [SceneViewport]) -> SIMD2<Double> {
        guard let pixels = viewports.lazy.compactMap(\.cursorScreenPixels).first else { return lastCursorScreenPixels }
        lastCursorScreenPixels = pixels
        return pixels
    }

    /// The scene's own `general.cameraparallax` (possibly user-bound, or set by a script) or the
    /// app's parallax toggle.
    private var parallaxEnabled: Bool {
        if let scripted = scripts.state.scene.flag(.cameraparallax) { return scripted }
        return Self.parallaxEnabled(camera)
    }

    /// The scene's `general.cameraparallax` (as resolved) or the app's parallax toggle, before scripts.
    static func parallaxEnabled(_ camera: SceneCameraEffects) -> Bool {
        camera.parallax || WallpaperServices.shared.userPropertyString("_owe_effect_enabled_parallax") == "true"
    }

    /// WE's camera shake, then its parallax (`SceneCameraShake`, `SceneCameraParallax`), in the
    /// order its scene update runs them: the parallax target includes the shaken eye. Scripts'
    /// `thisScene.camerashake…`/`cameraparallax…` settings override the scene's.
    private func cameraMotion(pointer: SIMD2<Float>, time: Float, deltaTime: Float) -> CameraMotion {
        let scene = scripts.state.scene
        let shaking = scene.flag(.camerashake) ?? camera.shake
        let shake: SIMD3<Float> = shaking
            ? SceneCameraShake.cameraOffset(time: time, speed: sceneSetting(.camerashakespeed) ?? camera.shakeSpeed,
                                            amplitude: sceneSetting(.camerashakeamplitude) ?? camera.shakeAmplitude,
                                            roughness: sceneSetting(.camerashakeroughness) ?? camera.shakeRoughness,
                                            orthographicHeight: camera.orthographic ? sceneSize.y : nil)
            : .zero
        var parallax: (state: SceneCameraParallax, amount: Float)?
        // Read every frame: turning parallax on or off eases in or out (`SceneCameraParallax.weight`).
        cameraParallax.ease(enabled: parallaxEnabled, deltaTime: deltaTime)
        if cameraParallax.isActive {
            cameraParallax.update(cursor: pointer, eye: SIMD2(shake.x, shake.y), sceneSize: sceneSize,
                                  influence: sceneSetting(.cameraparallaxmouseinfluence) ?? camera.parallaxMouseInfluence,
                                  delay: sceneSetting(.cameraparallaxdelay) ?? camera.parallaxDelay,
                                  deltaTime: deltaTime)
            // `_owe_effect_parallax_amount` is an app extra, 1 (WE's amount) by default.
            let amount = (sceneSetting(.cameraparallaxamount) ?? camera.parallaxAmount)
                * WallpaperServices.shared.userPropertyValue("_owe_effect_parallax_amount", fallback: 1)
            if camera.orthographic { parallax = (cameraParallax, amount) }
        }
        // WE moves the camera by the shake (0x140199580). A perspective scene's camera carries it;
        // an orthographic scene's layers are drawn without the camera, so they move the other way.
        guard camera.orthographic else {
            return CameraMotion(parallax: parallax, shake: .zero, cameraShake: shake,
                                audioLevel: WallpaperServices.shared.audioLevel)
        }
        return CameraMotion(parallax: parallax, shake: SIMD2(shake.x, shake.y),
                            audioLevel: WallpaperServices.shared.audioLevel)
    }

    /// A number of the scene's settings this frame: a script's, else its timeline's; nil leaves
    /// the authored (or user-bound) one.
    private func sceneSetting(_ field: SceneScriptSceneField) -> Float? {
        scripts.state.scene.scalar(field) ?? timelines.sceneScalar(field)
    }

    /// What the camera rig needs this frame (`SceneCameraRigInput`): the camera layers' live
    /// visibility and transforms, the shake and the settings scripts and timelines set, and the
    /// default camera `thisScene.setCameraTransforms` set.
    private func cameraRigInput(time: Double, motion: CameraMotion) -> SceneCameraRigInput {
        var input = SceneCameraRigInput(sceneSize: sceneSize, aspect: sceneSize.x / max(sceneSize.y, 1), time: time,
                                        deltaTime: Float(clock.delta))
        input.shake = motion.cameraShake
        input.isVisible = { [unowned self] id in scripts.object(id)?.flag(.visible) ?? scripts.baseVisible(id) }
        input.live = { [unowned self] id in
            // Only what scripts or timelines move differs from the authored transform the rig holds.
            let script = scripts.object(id), animation = timelines.object(id)
            guard script != nil || animation != nil, let authored = cameraTransforms.nodes[id]?.local,
                  let motion = objectMotions[id] ?? layers.first(where: { $0.layer.id == id })?.motion else { return nil }
            return motion.local3D(authored: authored, animation: animation, script: script)
        }
        input.layerFov = { [unowned self] id in scripts.object(id)?.scalar(.fov) }
        input.fov = sceneSetting(.fov)
        input.nearZ = sceneSetting(.nearz)
        input.farZ = sceneSetting(.farz)
        input.cameraFade = scripts.state.scene.flag(.camerafade)
        input.scriptCamera = scripts.state.scene.scriptCamera
        return input
    }

    /// The parallax offset of a layer: its root object's live origin and `parallaxDepth`.
    private func parallaxOffset(_ entry: PreparedLayer, local: SceneLocalTransform,
                                motion: CameraMotion) -> SIMD2<Float> {
        guard let parallax = motion.parallax else { return .zero }
        let rootID = transforms.root(of: entry.layer.id)
        if rootID == entry.layer.id {
            let depth = entry.layer.parallaxDepth
            let scripted = scripts.object(rootID)?.vector2(.parallaxDepth) ?? timelines.object(rootID)?.parallaxDepth
            return parallax.state.offset(rootOrigin: local.origin, rootDepth: scripted ?? SIMD2(depth.x, depth.y),
                                         amount: parallax.amount)
        }
        guard let node = transforms.nodes[rootID] else { return .zero }
        let rootLocal = liveLocal(rootID) ?? node.local
        return parallax.state.offset(rootOrigin: rootLocal.origin, rootDepth: parallaxDepth(of: rootID, node: node),
                                     amount: parallax.amount)
    }

    /// A root object's `parallaxDepth`: a script's, else its timeline's, else authored.
    private func parallaxDepth(of id: String, node: SceneTransformHierarchy.Node) -> SIMD2<Float> {
        scripts.object(id)?.vector2(.parallaxDepth) ?? timelines.object(id)?.parallaxDepth ?? node.parallaxDepth
    }

    /// A visible layer's opacity, colour and placed quad this frame: what scripts wrote, then the
    /// timeline, then authored (moved by user bindings).
    private func layerDraw(_ entry: PreparedLayer, baseSize: SIMD2<Float>,
                           motion: CameraMotion, contentOffset: SIMD2<Float> = .zero) -> LayerDraw {
        let base = baseValues(entry)
        let script = scripts.object(entry.layer.id)
        var opacity = script?.scalar(.alpha) ?? baseOpacity(entry, base: base)
        if entry.layer.text != nil {
            opacity *= WallpaperServices.shared.userPropertyValue("_owe_text_\(entry.layer.id)_opacity", fallback: 1)
        }
        var local = evaluatedLocal(entry)
        let own = local
        let parallaxOffset = parallaxOffset(entry, local: local, motion: motion)
        let musicSyncLevel = entry.layer.musicSync?.levelSource.map { $0() } ?? motion.audioLevel
        local.scale *= 1 + (entry.layer.musicSync?.zoomAmount ?? 0) * Float(musicSyncLevel)
        local.angle += entry.layer.musicSync.map { $0.tiltAmount * Float(musicSyncLevel) * .pi / 180 } ?? 0
        // A fullscreen layer is drawn in screen space (`passthrough` without `TRANSFORM`), which
        // the orthographic zoom doesn't scale.
        let view = entry.layer.fillsScene ? SceneAffineTransform.identity : frameZoom.plane
        let quad = SceneQuadGeometry(world: view * worldTransform(entry, local: local),
                                     size: baseSize, alignment: entry.layer.alignment)
        // WE draws a layer where its transform and the camera put it; an oversized layer (sized
        // to hide its edges while it moves) isn't pinned inside the scene.
        let center = quad.center + view.linear * (parallaxOffset - motion.shake)
            + quad.axisX * (contentOffset.x / max(baseSize.x, .leastNormalMagnitude))
            + quad.axisY * (contentOffset.y / max(baseSize.y, .leastNormalMagnitude))
        let animation = timelines.object(entry.layer.id)
        let rgb = script?.vector3(.color) ?? animation?.color
        let color = rgb.map { SIMD4<Float>($0.x, $0.y, $0.z, base.color.w) } ?? base.color
        let brightness = renderSettings.appliesBrightness
            ? script?.scalar(.brightness) ?? animation?.brightness ?? base.brightness : 1
        drawProbe?.record(layer: entry.layer.id, .init(opacity: opacity, color: color, brightness: brightness, local: own))
        return LayerDraw(opacity: opacity, color: color, brightness: brightness,
                         quad: SceneQuadGeometry(center: center, axisX: quad.axisX, axisY: quad.axisY),
                         musicSyncLevel: musicSyncLevel)
    }

    /// A layer's opacity before scripts: its timeline's value this frame, else authored or user-bound.
    private func baseOpacity(_ entry: PreparedLayer, base: SceneLayerBaseValues) -> Float {
        timelines.object(entry.layer.id)?.alpha ?? base.opacity
    }

    /// The layer's unscaled size this frame: a script bound to `size` (WE's image property is
    /// writable and drawn every frame, wallpaper64.exe 0x1401e8bb0), else its timeline, else authored.
    private func layerBaseSize(_ entry: PreparedLayer) -> SIMD2<Float> {
        scripts.object(entry.layer.id)?.vector2(.size) ?? timelines.object(entry.layer.id)?.size ?? entry.layer.size
    }

    /// A text layer's current string (a script's, else authored), laid out and rasterised (through
    /// the text cache) at `pixelsPerUnit`, with the block size the layout settled on.
    private func layerTextFrame(_ entry: PreparedLayer, boxSize: SIMD2<Float>,
                                pixelsPerUnit: Float) -> (frame: RenderTextureFrame, baseSize: SIMD2<Float>) {
        guard let authored = entry.layer.text else { return (textureFrame(for: entry), boxSize) }
        let scripted = scripts.text(authored, of: entry.layer.id)
        return makeTextFrame(scripted.text, value: scripted.value, pointSize: scripted.pointSize, boxSize: boxSize,
                             pixelsPerUnit: pixelsPerUnit, layerID: entry.layer.id,
                             fill: authored.effects == nil && entry.layer.weEffects.isEmpty ? nil : textFill(entry))
            ?? (textureFrame(for: entry), boxSize)
    }

    /// A text layer's colour this frame (a script's, else its timeline's, else authored, with the
    /// user's text colour), which text with font effects rasterises with (`SceneTextEffects`).
    private func textFill(_ entry: PreparedLayer) -> SIMD3<Float> {
        let base = baseValues(entry).color
        let color = scripts.object(entry.layer.id)?.vector3(.color) ?? timelines.object(entry.layer.id)?.color
            ?? SIMD3(base.x, base.y, base.z)
        return color * textTint(layerID: entry.layer.id)
    }

    // MARK: - Depth, draw order and 3D placement (docs/models-plan.md §2.4)

    /// Gives the pass WE's depth buffer (`SceneDepthBuffer`), cleared to the far depth, and sets
    /// `sceneDepthFormat` for this frame's pipelines: a perspective scene's, and an orthographic
    /// one's with model objects, whose models, and whatever tests depth, then test as in WE (MG6).
    /// WE's frame buffer always has depth (0x14017f59c); an orthographic scene without models
    /// keeps none here, which draws the same while every object lies at z = 0 [I].
    private func attachSceneDepth(to pass: MTLRenderPassDescriptor, scene: MTLTexture) {
        sceneDepthFormat = .invalid
        guard isPerspective || !spatial.models.isEmpty, depthStates != nil,
              layerPipelines.pipelines(for: scene.pixelFormat, sampleCount: sceneSampleCount,
                                       depthFormat: SceneDepthStates.format) != nil,
              depthBuffer.prepare(width: scene.width, height: scene.height, sampleCount: sceneSampleCount) else {
            if depthBuffer.texture != nil { depthBuffer.releaseAll() }
            return
        }
        sceneDepthFormat = SceneDepthStates.format
        depthBuffer.attach(to: pass, clear: true)
    }

    /// Where a layer's quad lands through a 3D camera this frame: every layer of a perspective
    /// scene but a fullscreen one (WE draws those in screen space: `passthrough` without
    /// `TRANSFORM`), and a `perspective` layer of an orthographic scene through its temporary
    /// camera (0x1401e5b60), moved by the parallax and shake the 2D path moves it by (the camera
    /// keeps the view's offset). Nil for the rest, which draw in the scene's plane.
    private func layerPlacement(_ entry: PreparedLayer, size: SIMD2<Float>, musicSyncLevel: Double, motion: CameraMotion,
                                camera: SceneFrameCamera) -> SceneLayerPlacement? {
        guard !entry.layer.fillsScene else { return nil }
        let offset = SceneAlignment.centerOffset(entry.layer.alignment, size: size)
        if isPerspective {
            let world = layerWorld3D(entry, in: spatial.transforms, musicSyncLevel: musicSyncLevel)
            return SceneLayerPlacement(world: world, size: size, offset: offset, camera: camera)
        }
        guard entry.layer.perspective else { return nil }
        var world = layerWorld3D(entry, in: spatial.transforms, musicSyncLevel: musicSyncLevel)
        let shift = parallaxOffset(entry, local: evaluatedLocal(entry), motion: motion) - motion.shake
        world.columns.3 += SIMD4(shift.x, shift.y, 0, 0)
        var temporary = SceneLayerPlacement.perspectiveLayerCamera(sceneSize: sceneSize, fov: Float(spatial.camera.sceneFov))
        temporary.projection = frameZoom.projection(temporary.projection)
        return SceneLayerPlacement(world: world, size: size, offset: offset, camera: temporary)
    }

    /// A layer's world matrix with its music sync (a video's zoom and tilt, applied to its own
    /// scale and `angles.z` as the 2D path applies them).
    private func layerWorld3D(_ entry: PreparedLayer, in hierarchy: SceneTransformHierarchy3D,
                              musicSyncLevel: Double) -> simd_float4x4 {
        let id = entry.layer.id
        guard let sync = entry.layer.musicSync else { return world3D(id, in: hierarchy) }
        var own = live3D(id, in: hierarchy) ?? hierarchy.nodes[id]?.local ?? .identity
        let zoom = 1 + sync.zoomAmount * Float(musicSyncLevel)
        own.scale *= SIMD3(zoom, zoom, 1)
        own.angles.z += sync.tiltAmount * Float(musicSyncLevel) * .pi / 180
        return hierarchy.world(of: id, local: own, live: { [unowned self] in self.live3D($0, in: hierarchy) })
    }

    /// An object's world matrix this frame (M3's hierarchy): its own and its ancestors' live
    /// transforms, parents first.
    private func world3D(_ id: String, in hierarchy: SceneTransformHierarchy3D) -> simd_float4x4 {
        hierarchy.world(of: id, local: live3D(id, in: hierarchy), live: { [unowned self] in self.live3D($0, in: hierarchy) },
                        attachments: SceneAttachmentProviders(providers: [models?.attachments as SceneAttachmentProviding?, puppetAttachments].compactMap { $0 }))
    }

    /// An object's world matrix where it is drawn: in an orthographic scene, in the zoom's drawn
    /// space (`SceneOrthographicZoom.space`), where the lights it is lit by are packed too;
    /// `world3D` (WE's world, what scripts see) elsewhere.
    private func drawnWorld3D(_ id: String) -> simd_float4x4 {
        frameZoom.space * world3D(id, in: spatial.transforms)
    }

    /// The model renderer (`SceneModelRenderer`), when that is what draws the models.
    private var models: SceneModelRenderer? { modelDrawing as? SceneModelRenderer }
    /// This frame's images of the layers models and other layers sample, by layer id.
    private var layerComposites: [String: MTLTexture] = [:]

    /// `layerCompositeOrder`, made from the layers' effects when `layers` changed.
    private func compositeOrder() -> SceneLayerCompositeOrder {
        if let layerCompositeOrder { return layerCompositeOrder }
        let order = SceneLayerCompositeOrder(layers: layers.map { entry in
            (entry.layer.id, entry.layer.weEffects.reduce(into: Set<String>()) { $0.formUnion($1.compositeLayerIDs) })
        }, readingScene: Set(layers.filter(\.layer.readsScene).map(\.layer.id)))
        layerCompositeOrder = order
        return order
    }

    /// A text layer's composite without effects: its text in its colour, one pixel a scene unit,
    /// as WE draws it into a buffer of its size (effects would run there, `SceneTextRasterScale`).
    private func compositeText(_ entry: PreparedLayer) -> MTLTexture? {
        guard let authored = entry.layer.text else { return nil }
        let scripted = scripts.text(authored, of: entry.layer.id)
        return makeTextFrame(scripted.text, value: scripted.value, pointSize: scripted.pointSize, boxSize: layerBaseSize(entry),
                             pixelsPerUnit: 1, layerID: entry.layer.id, fill: textFill(entry))?.frame.texture
    }

    /// An object's own 3D transform this frame (`SceneObjectMotion.local3D`: scripts, then
    /// timelines, then authored moved by the user bindings), evaluated once per frame; nil for an
    /// object without a motion, whose authored node stands. An object a script created has no
    /// authored node: its 2D transform stands in.
    private func live3D(_ id: String, in hierarchy: SceneTransformHierarchy3D) -> SceneLocalTransform3D? {
        if let cached = frameLocals3D[id] { return cached }
        guard let motion = layerIndexByStateId[id].map({ layers[$0].motion }) ?? objectMotions[id] else { return nil }
        let authored = hierarchy.nodes[id]?.local ?? SceneLocalTransform3D(objectLocal(motion, id: id))
        let local = motion.local3D(authored: authored, animation: timelines.object(id), script: scripts.object(id))
        frameLocals3D[id] = local
        return local
    }

    /// The depth and cull state a layer draws with where the pass has depth: a text object's (its
    /// `depthtest`, `SceneRasterState.text`), else its material's first pass; a layer without a
    /// material (composition and shape layers) neither tests nor writes.
    private func layerRaster(_ entry: PreparedLayer) -> SceneRasterState {
        if entry.layer.text != nil { return .text(depthTest: spatial.depthTest(of: entry.layer.id) ?? false) }
        return entry.layer.imageMaterial?.raster ?? .disabled
    }

    /// A particle system drawn through a perspective scene's camera (docs/models-plan.md §2.12):
    /// the camera, and the matrix from the scene plane the system is simulated in (its object's 2D
    /// transform) to where its 3D world matrix puts it. Nil in an orthographic scene.
    private func particlePlacement(_ system: ParticleSystemRuntime,
                                   camera: SceneFrameCamera) -> ParticleMaterialUniforms.Placement? {
        guard isPerspective else {
            // A `perspective` system (flag 4) of an orthographic scene: WE pushes the temporary
            // camera a perspective layer gets (0x140236761 → 0x1401e5b60) and keeps g_EyePosition.
            guard system.configuration.perspective else { return nil }
            // Its emitter is already in the zoom's drawn plane (`emitterWorld`), so the camera
            // isn't zoomed again.
            var temporary = SceneLayerPlacement.perspectiveLayerCamera(sceneSize: sceneSize, fov: Float(spatial.camera.sceneFov))
            temporary.eye = SIMD3(sceneSize.x / 2, sceneSize.y / 2, ParticleMaterialUniforms.eyeDistance)
            return ParticleMaterialUniforms.Placement(camera: temporary)
        }
        return ParticleMaterialUniforms.Placement(camera: camera, model: particleSpaceModel(system))
    }

    /// The matrix from the space a system's particles are simulated in (the scene plane its
    /// object's 2D transform places them in, and their depth) to where its 3D world matrix puts
    /// them: identity in an orthographic scene, or when the two agree.
    private func particleSpaceModel(_ system: ParticleSystemRuntime) -> simd_float4x4 {
        guard isPerspective, let id = particleObjectID(system) else { return matrix_identity_float4x4 }
        let planar = transforms.world(of: id, live: { [self] id in liveLocal(id) }, attachments: puppetAttachments.affine)
        let x = planar.linear.columns.0, y = planar.linear.columns.1, t = planar.translation
        let embedded = simd_float4x4(columns: (SIMD4<Float>(x.x, x.y, 0, 0), SIMD4<Float>(y.x, y.y, 0, 0),
                                               SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(t.x, t.y, 0, 1)))
        guard abs(simd_determinant(planar.linear)) > 1e-12 else { return matrix_identity_float4x4 }
        return world3D(id, in: spatial.transforms) * embedded.inverse
    }

    /// The capsules a `collisionmodel` operator of `system` collides with (docs/models-plan.md
    /// §2.12): model object `id`'s bones as last posed (its bind pose before its first frame) or
    /// its box, through its world matrix, in the space the system's particles are simulated in.
    /// WE also takes a puppet image; that isn't supported here (logged once).
    private func particleCapsules(_ id: String, for system: ParticleSystemRuntime) -> [ParticleCapsule] {
        guard let plan = spatial.models.first(where: { $0.id == id })?.plan else {
            if reportedCollisionTargets.insert(id).inserted {
                OWELog.error(.scene, "Particle collisionmodel: object \(id) isn't a drawable model; its particles don't collide with it")
            }
            return []
        }
        let space = particleSpaceModel(system)
        let toParticles = abs(space.determinant) > 1e-12 ? space.inverse : matrix_identity_float4x4
        return ParticleCapsule.capsules(boneVectors: plan.skeleton?.boneVectors,
                                        boneWorlds: models?.animator(for: id)?.worlds ?? [], bounds: plan.bounds,
                                        world: toParticles * drawnWorld3D(id))
    }

    /// Draws model object `index` (`SceneSpatialContent.models`) through `modelDrawing` at its
    /// place in the object loop, unless it is hidden.
    private func drawModel(_ index: Int, frame: BuiltinFrameContext, pixelFormat: MTLPixelFormat,
                           encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {
        guard let modelDrawing, spatial.models.indices.contains(index) else { return }
        let model = spatial.models[index]
        guard scripts.isVisible(model.id) else { return }
        modelDrawing.draw(model, SceneModelDraw(
            world: drawnWorld3D(model.id), camera: frame.camera, frame: frame,
            values: timelines.values, pixelFormat: pixelFormat, sampleCount: sceneSampleCount, depth: frameDepth,
            mipMappedFrameBuffer: mipMappedTarget,
            assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
            layerComposite: { [unowned self] id in self.layerComposites[id] }, shadowAtlas: frameShadowAtlas,
            planarReflection: frameReflection),
            encoder: encoder, commandBuffer: commandBuffer)
        encoder.setRenderPipelineState(renderPipeline)
    }

    /// This frame's object loop: the layers and models in draw order, each with the barrier below
    /// which the particle systems are drawn before it, and the order and keys of the systems.
    private struct DrawSequence {
        var items: [(item: SceneDrawItem, barrier: Int)] = []
        /// `batches`' indices in draw order, and each one's key.
        var batchOrder: [Int] = []
        var batchKeys: [Int] = []
    }

    /// WE's object loop (0x14018aac0): scene order (or the order scripts set) keeps each layer's
    /// particle barrier and each system's scene index; a model goes before the first layer
    /// authored after it. `customsortorder` and `transparentsorting` then sort the whole list
    /// (`SceneDrawOrderMode.ordered`), and each object's position becomes its key.
    private func drawSequence(batches: [ParticleSystemRuntime], forward: SIMD3<Float>) -> DrawSequence {
        // Each model goes before the first layer authored after it, models before one layer in scene order.
        let layerOrders = layers.map(\.layer.order)
        var modelsBefore = [[Int]](repeating: [], count: layers.count + 1)
        if modelDrawing != nil {
            for (index, model) in spatial.models.enumerated() {
                modelsBefore[layerOrders.firstIndex { $0 > model.order } ?? layers.count].append(index)
            }
        }
        var items: [(item: SceneDrawItem, barrier: Int)] = []
        for position in 0...layers.count {
            items += modelsBefore[position].map { (item: SceneDrawItem.model($0), barrier: spatial.models[$0].order) }
            if position < layers.count { items.append((.layer(position), layers[position].particleBarrier)) }
        }
        let keys = batches.map(\.configuration.order)
        guard spatial.drawOrder.reorders else {
            return DrawSequence(items: items, batchOrder: Array(batches.indices), batchKeys: keys)
        }
        var list: [SceneDrawItem] = []
        var next = 0
        for (item, barrier) in items {
            while next < batches.count, keys[next] < barrier {
                list.append(.particles(next))
                next += 1
            }
            list.append(item)
        }
        list += (next..<batches.count).map { SceneDrawItem.particles($0) }
        let ordered = spatial.drawOrder.ordered(list.map { drawEntry($0, batches: batches) }, forward: forward)
        var sequence = DrawSequence()
        for (position, item) in ordered.enumerated() {
            if case .particles(let batch) = item {
                sequence.batchOrder.append(batch)
                sequence.batchKeys.append(position)
            } else {
                sequence.items.append((item, position))
            }
        }
        return sequence
    }

    /// An object as the draw-order modes see it (`SceneDrawEntry`).
    private func drawEntry(_ item: SceneDrawItem, batches: [ParticleSystemRuntime]) -> SceneDrawEntry {
        var entry = SceneDrawEntry(item: item)
        let id: String?
        switch item {
        case .layer(let index):
            let layer = layers[index].layer
            id = layer.id
            entry.translucent = layer.text != nil || SceneDrawEntry.imageIsTranslucent(
                blending: layer.imageMaterial?.pass.blending, passthrough: layer.sceneInput, solidLayer: layer.solidFill != nil)
            entry.drawsLast = layer.fillsScene
        case .particles(let index):
            id = particleObjectID(batches[index])
            entry.translucent = true
        case .model(let index):
            let model = spatial.models[index]
            id = model.id
            entry.translucent = modelDrawing?.isTranslucent(model) ?? false
        }
        guard let id else { return entry }
        entry.sortOrder = spatial.sortOrder(of: id)
        // Only a perspective scene sorts by origin; its objects live in `spatial.transforms`.
        if spatial.drawOrder.splitsTranslucent {
            entry.origin = live3D(id, in: spatial.transforms)?.origin ?? spatial.transforms.nodes[id]?.local.origin ?? .zero
        }
        return entry
    }

    // MARK: - Transforms

    private func beginTransformFrame() {
        frameLocals.removeAll(keepingCapacity: true)
        frameLocals3D.removeAll(keepingCapacity: true)
        layerIndexByStateId.removeAll(keepingCapacity: true)
        for (index, entry) in layers.enumerated() { layerIndexByStateId[entry.layer.id] = index }
        frameZoom = orthographicZoom()
        // Nested tilts compose in depth from this frame's angles, scripts' and timelines' included
        // (docs/models-plan.md §5.16); a perspective scene draws through its 3D hierarchy anyway.
        if !isPerspective { transforms.updateComposition { [unowned self] id in self.liveLocal(id) } }
    }

    /// A layer's authored values moved by its user bindings: the base that animations and scripts
    /// start from. Kept per binding revision (`SceneBindingRevisions`) unless a bound property
    /// follows the music.
    private func baseValues(_ entry: PreparedLayer) -> SceneLayerBaseValues {
        let values = boundBaseValues(entry)
        return editorLive.isEmpty ? values : editorLive.base(values, id: entry.layer.id)
    }

    private func boundBaseValues(_ entry: PreparedLayer) -> SceneLayerBaseValues {
        let bindings = entry.layer.bindings
        guard !bindings.isEmpty else { return SceneLayerBaseValues(entry.layer) }
        let context = LiveSceneValueContext()
        if bindings.properties.contains(where: context.isMusicSynced) {
            return bindings.baseValues(for: entry.layer, in: context)
        }
        let id = entry.layer.id
        let revision = bindingRevisions.revision(of: id)
        var cache = baseValueCaches[id] ?? SceneBindingCache()
        let reused = cache.revision == revision
        let values = cache.value(at: revision) { bindings.baseValues(for: entry.layer, in: context) }
        if reused { bindingRevisions.noteReuse(of: id, cachedAt: cache.revision ?? revision) } else { baseValueCaches[id] = cache }
        return values
    }

    /// Hands every particle system its object's binding revision, which its kept overrides key on.
    private func refreshParticleRevisions() {
        for system in particleSystems {
            system.bindingRevision = particleObjectID(system).map(bindingRevisions.revision(of:)) ?? 0
        }
    }

    /// The value context of object `id`'s draw this frame: the timelines' values at its binding revision.
    private func values(of id: String) -> LiveSceneValueContext {
        var values = timelines.values
        values.bindingRevision = bindingRevisions.revision(of: id)
        return values
    }

    private func evaluatedLocal(_ entry: PreparedLayer) -> SceneLocalTransform {
        objectLocal(entry.motion, id: entry.layer.id)
    }

    /// An object's own transform this frame (`SceneObjectMotion.local`, scripts' values
    /// included), evaluated once per frame.
    private func objectLocal(_ motion: SceneObjectMotion, id: String) -> SceneLocalTransform {
        if let cached = frameLocals[id] { return cached }
        var local = motion.local(animation: timelines.object(id), script: scripts.object(id))
        if !editorLive.isEmpty { local = editorLive.local(local, id: id) }
        frameLocals[id] = local
        return local
    }

    /// This frame's own transform of any object: a drawn layer's, or another object's (groups,
    /// particle systems) from its motion. Nil for an object without either.
    private func liveLocal(_ id: String) -> SceneLocalTransform? {
        if let index = layerIndexByStateId[id] { return evaluatedLocal(layers[index]) }
        return objectMotions[id].map { objectLocal($0, id: id) }
    }

    /// A layer's world this frame: its own transform (`local`, else its evaluated one) in its
    /// parents' space, then its attachment on its parent's rig (the witcher's sword, 3803167460,
    /// hangs from the hand, not the parent's origin). Every ancestor uses its live (scripted,
    /// animated) transform, so moving a parent moves its children. WE's world, without the
    /// orthographic zoom (`frameZoom`), which only the draw applies.
    private func worldTransform(_ entry: PreparedLayer, local: SceneLocalTransform? = nil) -> SceneAffineTransform {
        transforms.world(of: entry.layer.id, local: local ?? evaluatedLocal(entry), live: { [self] id in liveLocal(id) },
                         attachments: puppetAttachments.affine)
    }

    /// This frame's orthographic zoom (`SceneOrthographicZoom`): `general.zoom` × the camera's
    /// zoom a script set, as the camera rig's projection has it. None in a perspective scene,
    /// where the zoom isn't read.
    private func orthographicZoom() -> SceneOrthographicZoom {
        guard !isPerspective else { return .none }
        let general = Float(spatial.camera.zoom)
        return SceneOrthographicZoom(factor: general * (scripts.state.scene.scriptCamera?.zoom ?? 1), sceneSize: sceneSize)
    }

    /// A particle system's emitter transform this frame: its object's, parents included, moved by
    /// camera parallax and shake as WE moves every object's model matrix (0x14018a0b3): the
    /// system's particles follow it unless it is `worldspace`; its children follow it through
    /// their links. The orthographic zoom (`frameZoom`) scales the plane they're drawn in.
    private func emitterWorld(_ configuration: SceneMetalParticleSystem,
                              motion: CameraMotion) -> SceneAffineTransform? {
        guard let id = configuration.objectID else { return nil }
        var world = transforms.world(of: id, live: { [self] id in liveLocal(id) }, attachments: puppetAttachments.affine)
        world.translation += particleParallaxOffset(id, motion: motion) - motion.shake
        return frameZoom.plane * world
    }

    /// A `layerimage` emitter's layer this frame (`ParticleFrameInputs.placeImages`), moved by
    /// camera parallax and shake as an emitter is (`emitterWorld`); nil when no such object exists.
    private func emitterImageLayerWorld(_ id: String, motion: CameraMotion) -> SceneAffineTransform? {
        guard transforms.nodes[id] != nil else { return nil }
        var world = transforms.world(of: id, live: { [self] id in liveLocal(id) }, attachments: puppetAttachments.affine)
        world.translation += particleParallaxOffset(id, motion: motion) - motion.shake
        return frameZoom.plane * world
    }

    /// The scene object a particle system belongs to: its own, or its family root's for a child.
    private func particleObjectID(_ system: ParticleSystemRuntime) -> String? {
        var current: ParticleSystemRuntime? = system.simulation ?? system
        var steps = 0
        while let candidate = current, steps < 64 {
            if let id = candidate.configuration.objectID { return id }
            current = candidate.parent
            steps += 1
        }
        return nil
    }

    /// Systems below this many live particles keep drawing at full resolution: the pass split of a
    /// reduced-resolution draw costs more than it saves on a few sprites.
    static let reducedResolutionParticleMinimum = 256

    /// Whether `system` draws at half resolution this frame (`SceneRenderSettings.reducedResolutionParticles`):
    /// a large additive material system of a scene without depth, not reading the scene.
    private func drawsReducedResolution(_ system: ParticleSystemRuntime) -> Bool {
        guard renderSettings.reducedResolutionParticles, frameDepth == nil,
              system.configuration.material?.blending.lowercased() == "additive",
              particleMaterials?.readsSceneSnapshot(system) == false else { return false }
        return (system.gpu?.completedCount ?? system.particles.count) >= Self.reducedResolutionParticleMinimum
    }

    /// Draws `systems` additively into a cleared half-resolution target, returned to be added onto
    /// the scene; `left` are the systems whose pipeline for it isn't ready (or all, without a target).
    private func drawReducedResolution(_ systems: [ParticleSystemRuntime], scene: MTLTexture, commandBuffer: MTLCommandBuffer,
                                       context: (ParticleSystemRuntime) -> ParticleMaterialRenderer.DrawContext)
        -> (target: MTLTexture?, left: [ParticleSystemRuntime]) {
        var avoiding = [scene]
        if let sceneCopy { avoiding.append(sceneCopy) }
        guard let particleMaterials,
              let target = renderTargetPool.texture(width: max(scene.width / 2, 1), height: max(scene.height / 2, 1),
                                                    pixelFormat: scene.pixelFormat, avoiding: avoiding) else { return (nil, systems) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return (nil, systems) }
        encoder.label = "Reduced-resolution particles"
        var left: [ParticleSystemRuntime] = []
        for system in systems where !particleMaterials.draw(system, alsoInto: target.pixelFormat, sampleCount: 1,
                                                            depthFormat: .invalid, encoder: encoder,
                                                            commandBuffer: commandBuffer, context: context(system)) {
            left.append(system)
        }
        encoder.endEncoding()
        return (left.count < systems.count ? target : nil, left)
    }

    /// Steps a system whose object is hidden (`ParticleFrameInputs.hidden`): the one step that
    /// clears it runs on whichever simulation holds it; nothing is drawn.
    private func stepHiddenParticles(_ system: ParticleSystemRuntime, deltaTime: Float, pixelFormat: MTLPixelFormat) {
        // The GPU's count is its last finished step's.
        let holdsParticles = system.gpu.map { $0.completedCount > 0 } ?? !system.particles.isEmpty
        guard let inputs = ParticleFrameInputs.hidden(system, deltaTime: deltaTime, holdsParticles: holdsParticles) else { return }
        guard particleSimulator != nil else {
            ParticleCPUSimulation.step(system, inputs: inputs)
            return
        }
        let rendererName = system.configuration.rendererName
        if let simulated = particleMaterials?.prepareSimulated(system, pixelFormat: pixelFormat, sampleCount: sceneSampleCount,
                                                               depthFormat: sceneDepthFormat) {
            particleRequests.append(.init(system: system, inputs: inputs,
                                          kind: .material(simulated.format, rendererName: rendererName),
                                          materialVertexCount: simulated.vertexCount))
        } else {
            particleRequests.append(.init(system: system, inputs: inputs, kind: .fallback(rendererName: rendererName)))
        }
    }

    /// A step as scripts' playback leaves it: paused emits nothing (its clock stands still),
    /// stopped clears the system; `emitParticles(count)` adds a burst of `count`.
    private static func applyScriptPlayback(_ playback: SceneScriptObjectCommand.Playback?, emitting count: Int?,
                                            to inputs: inout ParticleFrameInputs) {
        switch playback {
        case .pause?:
            for index in inputs.emitters.indices {
                inputs.emitters[index].rate = 0
                inputs.emitters[index].burst = 0
            }
        case .stop?:
            inputs.clears = true
        case .play?, nil:
            break
        }
        if let count, !inputs.emitters.isEmpty { inputs.emitters[0].burst += count }
    }

    /// The parallax offset of a particle object: its root object's live origin and `parallaxDepth`.
    private func particleParallaxOffset(_ id: String, motion: CameraMotion) -> SIMD2<Float> {
        guard let parallax = motion.parallax else { return .zero }
        let rootID = transforms.root(of: id)
        guard let node = transforms.nodes[rootID] else { return .zero }
        let rootLocal = liveLocal(rootID) ?? node.local
        return parallax.state.offset(rootOrigin: rootLocal.origin, rootDepth: parallaxDepth(of: rootID, node: node),
                                     amount: parallax.amount)
    }

    /// Hands the vertex stage the quad's full axes (parent rotation and non-uniform scale), in
    /// the same placement space `layerUniform` put its centre in.
    private func setQuadAxes(_ uniform: inout LayerUniform, quad: SceneQuadGeometry) {
        let extent = quad.extent
        let placementScale = SIMD2<Float>(extent.x > 0 ? uniform.size.x / extent.x : 1,
                                          extent.y > 0 ? uniform.size.y / extent.y : 1)
        uniform.quadAxisX = quad.axisX * placementScale
        uniform.quadAxisY = quad.axisY * placementScale
        uniform.rotation = 0
    }

    private func runEffects(_ entry: PreparedLayer, draw: LayerDraw, input: MTLTexture, snapshot: MTLTexture?,
                            frame: BuiltinFrameContext, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let effectGraph, !entry.layer.weEffects.isEmpty else { return nil }
        var context = effectContext(entry, draw: draw, input: input, snapshot: snapshot, frame: frame)
        let lit = prelit(entry, draw: draw, input: input, snapshot: snapshot, frame: frame, commandBuffer: commandBuffer)
        if lit != nil {
            // The prelit image is redrawn into the same texture every frame (its lights, the
            // reflection it samples): a new version, so no kept chain output outlives it.
            prelitVersion &+= 1
            context.inputVersion = prelitVersion
        }
        return effectGraph.apply(entry.layer.weEffects, to: lit ?? input,
                                 layerID: entry.layer.id, context: context, commandBuffer: commandBuffer)
    }

    /// Runs a layer's effects up to their last pass, which `encodeLayer` then draws into the scene
    /// through the layer's quad and material blending, as WE draws a layer's last effect pass
    /// (`EffectGraphRenderer.lastScenePass`): the shader runs once per pixel of the screen, not of
    /// the layer's buffer (docs/test-risks.md FX2). The chain starts from WE's base pass, the layer's
    /// material drawn into its buffer with the layer's colour, alpha and brightness
    /// (`ImageMaterialRenderer.base`), which the last pass then carries into the scene. nil where
    /// the effects composite through a buffer (`lastPassDrawsIntoScene`), or while a pipeline compiles.
    private func runEffectsDrawingLastPass(_ entry: PreparedLayer, draw: LayerDraw, input: MTLTexture, compositeSource: Bool,
                                           sceneFormat: MTLPixelFormat, frame: BuiltinFrameContext,
                                           commandBuffer: MTLCommandBuffer) -> EffectGraphRenderer.DrawnLastPass? {
        guard let effectGraph, let imageMaterials, let plan = lastPassDrawsIntoScene(entry, compositeSource: compositeSource)
        else { return nil }
        var context = effectContext(entry, draw: draw, input: input, snapshot: nil, frame: frame)
        let format = context.frameBufferFormat
        let target = lastPassPlacement(plan, draw: draw, image: nil, sceneFormat: sceneFormat)
        guard effectGraph.scenePassIsReady(entry.layer.weEffects, hidden: context.hiddenEffects, scene: target),
              imageMaterials.baseIsReady(plan, layerID: entry.layer.id, format: format),
              let base = imageMaterials.base(plan, materialDraw(entry, draw, texture: input, frame: frame),
                                             inputVersion: context.inputVersion, format: format,
                                             commandBuffer: commandBuffer) else { return nil }
        context.inputVersion = base.version
        return effectGraph.applyDrawingLastPass(entry.layer.weEffects, to: base.texture, layerID: entry.layer.id,
                                                context: context, commandBuffer: commandBuffer)
    }

    /// The layer's material when its effects' last pass draws into the scene (WE's rule for the
    /// last pass, below); nil when they composite through a buffer. WE sets an object's flag 0x10,
    /// which runs every pass into its buffers and draws them with a composite material
    /// (0x1401e9513, 0x1401ea06d…0x1401ea0c9), when:
    /// - its `colorBlendMode` is other than 0 and 31 (0x1401e6f74…0x1401e6fa2);
    /// - the scene has distance or height fog (scene flags 0x800000/0x1000000 from `general`'s
    ///   `fogdistance`/`fogheight`, 0x140186561…0x1401865ad; tested at 0x1401e6f96);
    /// - another object samples its image (`_rt_imageLayerComposite_<id>`: 0x1401881b0, 0x1401d3c1e);
    /// - it is lit with effects: its prelighting pass fills the buffer (0x140209b70…0x140209b79);
    /// - it is text (0x14020b1fa…0x14020b20d).
    /// Ours also composites through a buffer where it draws the layer another way: without the
    /// layer's material pass (text, scene regions, solid fills, a material that draws no image),
    /// with a `BLENDMODE` (31, which WE adds with), for effects that read the scene (WE copies the
    /// scene before the last pass, 0x1401ea0dd…0x1401ea114) and while a planar reflection draws
    /// the layers' images.
    private func lastPassDrawsIntoScene(_ entry: PreparedLayer, compositeSource: Bool) -> ImageMaterialPlan? {
        let layer = entry.layer
        // A puppet's last pass would draw its bind layout; its output is laid out by the posed mesh first.
        guard let plan = layer.imageMaterial, plan.prelighting == nil, layer.text == nil, !layer.sceneInput, layer.puppet == nil,
              layer.solidFill == nil, !layer.readsScene, !compositeSource,
              (plan.pass.variant?.combos["BLENDMODE"] ?? 0) == 0,
              !plan.pass.readsSceneSnapshot, !plan.pass.readsMipMappedFrameBuffer,
              plan.pass.blending.lowercased() != "alphatocoverage",
              !lighting.settings.fog.distance, !lighting.settings.fog.height,
              planarReflection?.isNeeded(spatial.models) != true else { return nil }
        return plan
    }

    /// Where a layer's last effect pass draws: its quad, as its material draws it (`encodeLayer`),
    /// sampling the chain's buffers where `image` shows its picture (its sprite frame, or the
    /// content of a padded texture); nil `image` gives the pass only its target (`scenePassIsReady`).
    private func lastPassPlacement(_ plan: ImageMaterialPlan, draw: LayerDraw, image: RenderTextureFrame?,
                                   sceneFormat: MTLPixelFormat) -> EffectGraphRenderer.ScenePlacement {
        let extent = draw.placement?.size ?? draw.quad.extent
        let positions = draw.placement?.quadPositions ?? ImageMaterialRenderer.quadPositions(extent: extent)
        let texCoords = ImageMaterialRenderer.corners.map { corner -> SIMD2<Float> in
            guard let image else { return corner }
            return image.uvOrigin + corner.x * image.uvAxisX + corner.y * image.uvAxisY
        }
        let viewProjection: simd_float4x4
        if let placement = draw.placement {
            viewProjection = placement.shaderViewProjection
        } else if frameDepth != nil, !isPerspective {
            viewProjection = PassMatrices.shaderViewProjection(SceneCamera.orthographic(size: sceneSize))
        } else {
            viewProjection = ImageMaterialRenderer.viewProjection(sceneSize: sceneSize)
        }
        return EffectGraphRenderer.ScenePlacement(
            positions: positions, texCoords: texCoords,
            model: draw.placement?.world ?? ImageMaterialRenderer.modelMatrix(draw.quad),
            view: draw.placement?.camera.view ?? matrix_identity_float4x4, viewProjection: viewProjection,
            blending: plan.pass.blending, pixelFormat: sceneFormat, sampleCount: sceneSampleCount,
            depthFormat: frameDepth == nil ? .invalid : SceneDepthStates.format)
    }

    /// What a layer's effects start from: its image, or for a sprite sheet its current frame cut out
    /// of the atlas, as WE's base pass draws it into the layer's buffer (`SceneSpriteFrameInputs`).
    private func effectInput(_ entry: PreparedLayer, image: RenderTextureFrame, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        guard entry.layer.puppet == nil, let cut = spriteFrameInputs.input(image, layerID: entry.layer.id, commandBuffer: commandBuffer)
        else { return image.texture }
        spriteFrameVersions[entry.layer.id] = cut.version
        return cut.texture
    }

    /// A layer's material draw of `texture` this frame (`ImageMaterialRenderer.Draw`), as `encodeLayer` makes it.
    private func materialDraw(_ entry: PreparedLayer, _ draw: LayerDraw, texture: MTLTexture,
                              frame: BuiltinFrameContext) -> ImageMaterialRenderer.Draw {
        ImageMaterialRenderer.Draw(
            layerID: entry.layer.id, quad: draw.quad, sceneSize: sceneSize,
            color: SIMD3(draw.color.x, draw.color.y, draw.color.z), alpha: draw.opacity, brightness: draw.brightness,
            texture: texture, contentSize: entry.layer.source.contentSize, uvOrigin: .zero,
            uvAxisX: SIMD2(1, 0), uvAxisY: SIMD2(0, 1), sceneSnapshot: nil, mipMappedFrameBuffer: mipMappedTarget,
            shadowAtlas: frameShadowAtlas, frame: frame, values: values(of: entry.layer.id),
            assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
            assetSprite: { [unowned self] key, source in self.effectAssetSprite(key: key, source: source) },
            placement: draw.placement)
    }

    /// What a layer's effect chain reads this frame besides its input.
    private func effectContext(_ entry: PreparedLayer, draw: LayerDraw, input: MTLTexture, snapshot: MTLTexture?,
                               frame: BuiltinFrameContext) -> EffectGraphRenderer.Context {
        var context = EffectGraphRenderer.Context(
            frame: frame,
            values: values(of: entry.layer.id),
            assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
            sceneSnapshot: snapshot,
            // The scripted/animated values the layer is drawn with this frame, not the authored ones
            // (in the raster already for text with font effects).
            layerColor: entry.layer.text?.effects == nil ? SIMD3(draw.color.x, draw.color.y, draw.color.z) : SIMD3(repeating: 1),
            layerAlpha: draw.opacity)
        context.mipMappedFrameBuffer = mipMappedTarget
        context.layerComposite = { [unowned self] id in self.layerComposites[id] }
        context.planarReflection = frameReflection
        context.systemTexture = { [unowned self] kind in self.systemTexture(kind) }
        context.effectTextureProjection = EffectGraphRenderer.effectTextureProjection(quad: draw.quad, sceneSize: sceneSize)
        // WE's layer buffers are frame-buffer class: RGBA16F in HDR.
        context.frameBufferFormat = postProcess.drawsHDR ? .rgba16Float : .rgba8Unorm
        context.assetContentSize = { _, source in source.contentSize }
        context.assetSprite = { [unowned self] key, source in self.effectAssetSprite(key: key, source: source) }
        if let probe = drawProbe { context.recordAnimated = { probe.record(constant: $0, value: $1) } }
        // Hidden effects (authored, user-bound or a script's `visible`) are built but skipped;
        // constants scripts set go over the material's.
        var scripted = scripts.effects(entry.layer.weEffects, of: entry.layer.id)
        if !editorLive.isEmpty { scripted = editorLive.effects(entry.layer.weEffects, of: entry.layer.id, scripted: scripted) }
        context.hiddenEffects = scripted.hidden
        context.constantWrites = scripted.writes
        context.scriptRevision = scripted.revision
        context.resolution = effectResolution(of: entry.layer.id)
        // A puppet's mesh redraws its image into the same texture as it moves: without the
        // drawing's version, the chain's kept output and base pass would hold the first pose.
        if entry.layer.puppet != nil { context.inputVersion = puppets?.albedoVersion(entry.layer.id) ?? 0 }
        // A sprite sheet's frames are cut into the same texture as it plays.
        if let version = spriteFrameVersions[entry.layer.id] { context.inputVersion = version }
        if renderSettings.sceneDetail == .matchDisplay {
            context.footprint = effectFootprint(entry, draw: draw, input: input)
            // Scene regions are drawn at the scene target's density, below full detail when the
            // target is matched to a smaller display; solid fills and text with effects are at
            // WE's own buffer size.
            if context.footprint == nil, fullDetailScale > 1, entry.layer.solidFill == nil, entry.layer.text == nil {
                let standIn = (SIMD2(Float(input.width), Float(input.height)) * fullDetailScale).rounded(.toNearestOrAwayFromZero)
                context.inputStandInSize = SIMD2(Int(standIn.x), Int(standIn.y))
            }
        }
        return context
    }

    /// The on-screen size, in scene-target pixels, of the whole image a layer's effects run on
    /// (`SceneEffectDetail`): its quad at the target's density, over the part of the image the quad
    /// shows (a padded `.tex` or a sprite frame shows part of it). Nil where the effects already run
    /// at the display's density or their input isn't the layer's image: scene-input layers (the
    /// scene under them, resampled at the target's density), text (rasterised at it), videos and
    /// perspective layers.
    private func effectFootprint(_ entry: PreparedLayer, draw: LayerDraw, input: MTLTexture) -> SIMD2<Float>? {
        let layer = entry.layer
        guard !layer.sceneInput, layer.text == nil, !layer.perspective, let frame = entry.frames.first,
              frame.texture.width == input.width, frame.texture.height == input.height else { return nil }
        if case .video = layer.source { return nil }
        let shown = SIMD2(simd_length(frame.uvAxisX), simd_length(frame.uvAxisY))
        guard shown.x > 0, shown.y > 0 else { return nil }
        // Through a camera, the quad is as large as its projection.
        if let placement = draw.placement {
            guard let density = placement.pixelsPerUnit(targetSize: SIMD2<Float>(sceneRenderTargetSize)) else { return nil }
            return placement.size * imageShareOfQuad(entry) * density / shown
        }
        return draw.quad.extent * imageShareOfQuad(entry) * renderPixelsPerUnit / shown
    }

    /// The share of a layer's quad its image covers: less than 1 where a puppet's quad grew to its
    /// posed bounds (`ScenePuppetCanvas`), so its effects keep running at the image's density.
    private func imageShareOfQuad(_ entry: PreparedLayer) -> SIMD2<Float> {
        guard let puppet = entry.layer.puppet, let canvas = puppetCanvases[entry.layer.id] else { return SIMD2(1, 1) }
        return ScenePuppetCanvas.imageShare(imageSize: puppet.imageSize, canvas: canvas)
    }

    /// Draws a puppet layer's mesh into its image (`puppetAlbedos`), posed by its animation layers
    /// this frame (docs/models-plan.md §4.3 M6, P2). Called only while the layer is visible, which
    /// is when WE evaluates its layers.
    private func drawPuppet(_ puppet: ScenePuppetPlan, _ entry: PreparedLayer, frame: BuiltinFrameContext,
                            compositeSource: Bool, commandBuffer: MTLCommandBuffer) {
        guard let puppets, let source = entry.frames.first?.texture else { return }
        // Posed this frame by `advanceRigs`, before the scripts ran.
        let animator = puppetAnimator(entry.layer.id, puppet)
        // WE draws the posed mesh in the scene (docs/models-plan.md §2.13), with effects or without:
        // nothing clips it at the image's rect, so what the posed mesh draws into covers its posed
        // bounds and the quad grows with it. Without effects that is the image itself; with them,
        // the posed layout of their output (`posedEffectOutput`). As the image another layer
        // samples, the mesh stays in the image.
        let direct = entry.layer.weEffects.isEmpty && !compositeSource
        let canvas = compositeSource ? nil : puppets.canvas(puppet, layerID: entry.layer.id, pose: animator.pose)
        puppetCanvases[entry.layer.id] = canvas
        // With effects the mesh draws its bind pose, the image as its texture lays it out: that is
        // where the effects' masks are painted, and the posed mesh then lays their output out
        // (`posedEffectOutput`), as WE draws the layer's geometry last.
        let pose = entry.layer.weEffects.isEmpty ? animator.pose : ScenePuppetPose.bind(boneCount: animator.pose.bones.count)
        // A rig that rearranges an atlas: the editor paints the effects' masks over its texture as
        // stored, where its parts don't overlap, so the effects read the texture itself and the
        // posed mesh lays their output out by its texture coordinates.
        if !entry.layer.weEffects.isEmpty, !puppet.bindPoseIsTextureLayout {
            puppets.prepareLayer(puppet, layerID: entry.layer.id)
            puppetAlbedos[entry.layer.id] = nil
            return
        }

        // The mesh drawn in the scene culls by its winding there, which a mirroring world flips
        // (§5.17); drawn into the image for effects or for another layer, it isn't in the scene yet.
        let mirrored = direct && puppetIsMirrored(entry, camera: frame.camera)
        puppetAlbedos[entry.layer.id] = puppets.albedo(puppet, ScenePuppetRenderer.Draw(
            layerID: entry.layer.id, source: source, pose: pose, frame: frame,
            values: timelines.values,
            assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
            canvas: direct ? canvas : nil, mirrored: mirrored),
            commandBuffer: commandBuffer)
        // Without effects WE draws the mesh in the scene through the layer's material, sampling
        // every texture at the mesh's coordinates: the quad draws with them laid out likewise.
        guard entry.layer.weEffects.isEmpty, let pass = entry.layer.imageMaterial?.pass else { return }
        var warped: [String: MTLTexture] = [:]
        for case let .asset(key, assetSource) in pass.textures.values {
            guard let texture = effectAssetTexture(key: key, source: assetSource) else { continue }
            warped[key] = puppets.warp(puppet, layerID: entry.layer.id, key: key, texture: texture,
                                       contentSize: assetSource.contentSize, pose: animator.pose, canvas: canvas,
                                       mirrored: mirrored, commandBuffer: commandBuffer)
        }
        puppetWarps[entry.layer.id] = warped
    }

    /// Whether a puppet layer shows its image mirrored on screen this frame: its world through the
    /// camera in a perspective scene, else its 2D world (`ScenePuppetRenderer.isMirrored`).
    private func puppetIsMirrored(_ entry: PreparedLayer, camera: SceneFrameCamera) -> Bool {
        if isPerspective {
            return ScenePuppetRenderer.isMirrored(world: world3D(entry.layer.id, in: spatial.transforms),
                                                  viewProjection: camera.viewProjection)
        }
        let linear = worldTransform(entry).linear
        return ScenePuppetRenderer.isMirrored(axisX: linear.columns.0, axisY: linear.columns.1)
    }

    /// A puppet's effect output (in its image's bind layout, `drawPuppet`) laid out by the posed
    /// mesh, which the layer then draws: WE draws a layer with effects through its geometry, the
    /// skinned mesh for a puppet, its triangles blended over each other by the layer's material,
    /// culled by their winding through `camera` (`puppetIsMirrored`). Anything else, or while the
    /// mesh can't be drawn, as it is.
    private func posedEffectOutput(_ output: MTLTexture?, of entry: PreparedLayer, camera: SceneFrameCamera,
                                   commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let output, let puppet = entry.layer.puppet, let puppets, let animator = puppetAnimators[entry.layer.id],
              let source = entry.frames.first?.texture, source.width > 0, source.height > 0 else { return output }
        // The output keeps the source's layout, the image in the same share of its texels.
        let share = SIMD2(Float(puppet.contentPixels.x) / Float(source.width), Float(puppet.contentPixels.y) / Float(source.height))
        let content = SIMD2(Float(output.width), Float(output.height)) * simd_min(share, SIMD2(repeating: 1))
        return puppets.warp(puppet, layerID: entry.layer.id, key: "_effects", texture: output, contentSize: content,
                            pose: animator.pose, canvas: puppetCanvases[entry.layer.id], redraw: true, blended: true,
                            mirrored: puppetIsMirrored(entry, camera: camera), commandBuffer: commandBuffer) ?? output
    }

    /// A script's call on a puppet's layers or bones. `setBoneTransform`'s matrix is in the scene;
    /// the rig keeps it in its model space (0x14020f350 multiplies by the object's inverse world).
    private func performRigCommand(_ command: SceneScriptRigCommand, on id: String) {
        guard let index = layers.firstIndex(where: { $0.layer.id == id }),
              let puppet = layers[index].layer.puppet else {
            models?.perform(command, on: id)
            return
        }
        let animator = puppetAnimator(id, puppet)
        if case let .setWorld(bone, matrix) = command {
            animator.perform(.setWorld(bone: bone, matrix: ScenePuppetAttachments.matrix(worldTransform(layers[index])).inverse * matrix))
        } else {
            animator.perform(command)
        }
    }

    /// Bone attachments on puppets, as their animators last posed them.
    private var puppetAttachments: ScenePuppetAttachments {
        ScenePuppetAttachments { [unowned self] id in
            guard let animator = self.puppetAnimators[id], let index = self.layerIndexByStateId[id],
                  let plan = self.layers[index].layer.puppet else { return nil }
            return (plan, animator)
        }
    }

    /// The layer's animator, made on first use.
    /// WE's object loop (0x1401891a0, at 0x14017fd26 in the frame): every object's update before
    /// the scripts' frame (0x1401802e5), so scripts read this frame's pose and get the layers'
    /// clip events (`animationEvent`) and ends (`addEndedCallback`) before their `update`, and
    /// their bone writes land on this frame's pose. A puppet updates hidden or not (0x1401fdf90
    /// tests only that it has a rig and layers, through 0x1402076e0); a model only while it and
    /// its parents are visible (0x14021c4d8), as its draw asks too. Without scripts nobody reads
    /// the events and ends, so they are dropped.
    private func advanceRigs() {
        let delta = Float(clock.delta)
        for entry in layers {
            guard let puppet = entry.layer.puppet else { continue }
            let animator = puppetAnimator(entry.layer.id, puppet)
            // Physics bones move in the scene: the image's world this frame, before the scripts'.
            animator.advance(delta: delta, values: timelines.values,
                             objectWorld: ScenePuppetAttachments.matrix(worldTransform(entry)))
            if !scripts.isRunning {
                _ = animator.takeEnded()
                _ = animator.takeEvents()
            }
        }
        guard let models else { return }
        var frame = BuiltinFrameContext()
        frame.time = clock.time
        frame.frameTime = clock.delta
        for model in spatial.models where scripts.isVisible(model.id) {
            guard let plan = model.plan,
                  models.advance(model, plan: plan, frame: frame, values: timelines.values) != nil,
                  !scripts.isRunning, let animator = models.animator(for: model.id) else { continue }
            _ = animator.takeEnded()
            _ = animator.takeEvents()
        }
    }

    private func puppetAnimator(_ id: String, _ puppet: ScenePuppetPlan) -> ScenePuppetAnimator {

        if let animator = puppetAnimators[id] { return animator }
        let animator = puppet.makeAnimator()
        puppetAnimators[id] = animator
        return animator
    }

    /// A lit or reflective layer's image as its effects start from it: lit by its material's
    /// prelighting pass (`ImageMaterialRenderer.prelight`); nil for any other layer.
    private func prelit(_ entry: PreparedLayer, draw: LayerDraw, input: MTLTexture, snapshot: MTLTexture?,
                        frame: BuiltinFrameContext, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let plan = entry.layer.imageMaterial, plan.prelighting != nil, let imageMaterials else { return nil }
        let lit = imageMaterials.prelight(plan, ImageMaterialRenderer.Draw(
            layerID: entry.layer.id, quad: draw.quad, sceneSize: sceneSize, color: SIMD3(repeating: 1), alpha: 1,
            brightness: 1, texture: input, contentSize: entry.layer.source.contentSize, uvOrigin: .zero,
            uvAxisX: SIMD2(1, 0), uvAxisY: SIMD2(0, 1), sceneSnapshot: snapshot, mipMappedFrameBuffer: mipMappedTarget,
            shadowAtlas: frameShadowAtlas, frame: frame, values: values(of: entry.layer.id),
            assetTexture: { [unowned self] key, source in self.effectAssetTexture(key: key, source: source) },
            assetSprite: { [unowned self] key, source in self.effectAssetSprite(key: key, source: source) }),
            // The layer's effect buffers' format: RGBA16F in HDR (docs/lighting-plan.md §2.3, §2.6).
            format: postProcess.drawsHDR ? .rgba16Float : .rgba8Unorm, commandBuffer: commandBuffer)
        prelitImages[entry.layer.id] = lit
        return lit
    }

    /// Ends an encoder of the scene pass, storing only what is read afterwards: the samples and
    /// depth when the pass `resumes` onto them; else the resolved colour, and the depth only when
    /// a frame stage reads it (`SceneFrameStage.readsSceneDepth`). Every scene-pass encoder ends
    /// here, as their attachments' store actions are left `.unknown` until then.
    private func endScenePass(_ encoder: MTLRenderCommandEncoder, resumes: Bool) {
        if sceneMultisampleTarget != nil {
            encoder.setColorStoreAction(resumes ? .storeAndMultisampleResolve : .multisampleResolve, index: 0)
        }
        if frameDepth != nil {
            let read = !resumes && frameStages.contains { $0.readsSceneDepth(settings: renderSettings) }
            encoder.setDepthStoreAction(depthBuffer.storeAction(resumes: resumes, read: read))
        }
        encoder.endEncoding()
    }

    /// Continues the scene pass after a pause (a snapshot of it, or effects run in between).
    private func resumeScenePass(on scene: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
        let resume = MTLRenderPassDescriptor()
        Self.attachScene(scene, multisampled: sceneMultisampleTarget, to: resume)
        resume.colorAttachments[0].loadAction = .load
        if frameDepth != nil { depthBuffer.attach(to: resume, clear: false) }
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: resume)
        encoder?.setRenderPipelineState(renderPipeline)
        return encoder
    }

    /// The scene drawn so far (`_rt_FullFrameBuffer`), current within `rect` (all of it when nil).
    /// Every scene-reading draw of a frame shares one full-size target, and only what changed is
    /// copied (`SceneSnapshotTracker`): the GPU runs the command buffer in order, so each draw
    /// reads its snapshot before the next copy overwrites any of it.
    private func sceneSnapshot(of scene: MTLTexture, commandBuffer: MTLCommandBuffer,
                               needing rect: SceneSnapshotTracker.Rect? = nil) -> MTLTexture? {
        if sceneCopy == nil {
            // The reflection copy's level 0 when this frame allows (`snapshotCanShare`): one
            // full-size target fewer.
            let shared = snapshotSharesMipMappedTarget ? mipMappedTarget.flatMap {
                $0.width == scene.width && $0.height == scene.height && $0.pixelFormat == scene.pixelFormat ? $0 : nil
            } : nil
            sceneCopy = shared ?? renderTargetPool.texture(width: scene.width, height: scene.height,
                                                           pixelFormat: scene.pixelFormat, avoiding: scene)
            snapshotTracker.reset()
        }
        guard let copy = sceneCopy else { return nil }
        let whole = SceneSnapshotTracker.Rect(x: 0, y: 0, width: scene.width, height: scene.height)
        guard let region = snapshotTracker.copy(for: rect ?? whole) else { return copy }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            snapshotTracker.reset()
            return nil
        }
        let origin = MTLOrigin(x: region.x, y: region.y, z: 0)
        blit.copy(from: scene, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin,
                  sourceSize: MTLSize(width: region.width, height: region.height, depth: 1),
                  to: copy, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        blit.endEncoding()
        return copy
    }

    /// The scene under a scene-input layer, as that layer's base image (`SceneRegionResample`).
    /// A quad that is exactly the scene (composition and fullscreen layers) uses the snapshot as is.
    /// Under WE's texture reduction a composition layer's buffers are its size over the reduction;
    /// a fullscreen layer's aren't (`TextureReduction`). Drawn through a 3D camera (`placement`), it
    /// is the scene under the projected quad (`SceneRegionProjection`).
    private func sceneRegion(of snapshot: MTLTexture, under quad: SceneQuadGeometry, placement: SceneLayerPlacement?,
                             reducedFor layer: SceneMetalLayer, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let reduction = layer.fillsScene ? 1 : Float(renderSettings.textureReduction)
        if let placement {
            guard let projection = regionProjection,
                  let size = SceneRegionResample.targetSize(extent: placement.size, layerSize: layer.size,
                                                            pixelsPerUnit: renderPixelsPerUnit / reduction),
                  let region = renderTargetPool.texture(width: size.x, height: size.y, pixelFormat: snapshot.pixelFormat,
                                                        avoiding: snapshot),
                  projection.draw(snapshot, under: placement, into: region, commandBuffer: commandBuffer) else { return nil }
            return region
        }
        if reduction == 1, !layer.clearsSceneAlpha, SceneRegionResample.coversWholeScene(quad, sceneSize: sceneSize) { return snapshot }
        guard let size = SceneRegionResample.targetSize(quad, layerSize: layer.size, pixelsPerUnit: renderPixelsPerUnit / reduction),
              let region = renderTargetPool.texture(width: size.x, height: size.y,
                                                    pixelFormat: snapshot.pixelFormat, avoiding: snapshot) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = region
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniform = SceneRegionResample.uniform(quad, sceneSize: sceneSize, targetSize: size)
        let pipelines = layerPipelines.pipelines(for: region.pixelFormat)
        // Copied over the cleared target without its alpha, the layer's base keeps alpha 0.
        encoder.setRenderPipelineState(layer.clearsSceneAlpha ? pipelines.colourCopy : pipelines.copy)
        encoder.setVertexBytes(&uniform, length: MemoryLayout<LayerUniform>.stride, index: 0)
        encoder.setFragmentBytes(&uniform, length: MemoryLayout<LayerUniform>.stride, index: 0)
        encoder.setFragmentTexture(snapshot, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return region
    }

    /// A textureless layer's image as its effects start from it: its fill at WE's buffer size, the
    /// layer's `size` rounded (`SceneMetalLayer.solidFill`), filled once per content; nil for a
    /// layer with a texture (or when the target can't be made, and the 1×1 source stands in).
    private func solidEffectInput(_ layer: SceneMetalLayer, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let fill = layer.solidFill else { return nil }
        let size = SolidEffectInput.size(layer.size)
        if let cached = solidEffectInputs[layer.id], cached.width == size.x, cached.height == size.y { return cached }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.x,
                                                                  height: size.y, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            OWELog.error(.scene, "Layer \(layer.id): could not allocate its \(size.x)×\(size.y) effect input")
            return nil
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(fill.x), green: Double(fill.y),
                                                            blue: Double(fill.z), alpha: Double(fill.w))
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.endEncoding()
        solidEffectInputs[layer.id] = texture
        return texture
    }

    private func effectAssetTexture(key: String, source: SceneMetalTextureSource) -> MTLTexture? {
        if case .animated = source { return animatedAssetFrame(key: key, source: source)?.texture }
        if let cached = effectAssetTextures[key] { return cached }
        guard let texture = makeTextureFrames(from: source)?.first?.texture else { return nil }
        effectAssetTextures[key] = texture
        return texture
    }

    /// An animated asset texture's sprite frame this frame, for `g_TextureNRotation/Translation`;
    /// nil for a still one.
    private func effectAssetSprite(key: String, source: SceneMetalTextureSource) -> BuiltinSpriteFrame? {
        guard case .animated = source, let frame = animatedAssetFrame(key: key, source: source) else { return nil }
        return BuiltinSpriteFrame(rotation: SIMD4(frame.uvAxisX.x, frame.uvAxisX.y, frame.uvAxisY.x, frame.uvAxisY.y),
                                  translation: frame.uvOrigin)
    }

    /// The frame an effect or material shows of an animated asset texture (T7): the texture's
    /// shared clock (§2.7), which every binding of the frame and every image layer of the texture
    /// share. The key is `materialPath|name`; the clock is the texture name's.
    private func animatedAssetFrame(key: String, source: SceneMetalTextureSource) -> RenderTextureFrame? {
        let frames: [RenderTextureFrame]
        if let cached = effectAssetFrames[key] {
            frames = cached
        } else {
            guard let made = makeTextureFrames(from: source), !made.isEmpty else { return nil }
            effectAssetFrames[key] = made
            frames = made
        }
        guard frames.count > 1 else { return frames[0] }
        let texture = key.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? key
        let frame = timelines.materialTextureFrame(texture: texture, frameTimes: { frames.map(\.duration) },
                                                   delta: Float(clock.delta))
        // `setFrame(n)` can't reach a material's clock; a frame outside the sheet can't happen, but draws the first.
        return frame >= 0 && Int(frame) < frames.count ? frames[Int(frame)] : frames[0]
    }







    /// The scene target, at `renderPixelsPerUnit` pixels per scene unit.
    /// Draws into `multisampled` when there is one, resolving into `scene` whenever the pass
    /// ends (so a pause for a scene-reading layer resolves what's drawn so far, as WE resolves its
    /// multisampled target before reading `_rt_FullFrameBuffer`, 0x1400d3310); else into `scene`.
    /// The samples are kept only while the pass resumes: `endScenePass` sets the store action.
    static func attachScene(_ scene: MTLTexture, multisampled: MTLTexture?, to pass: MTLRenderPassDescriptor) {
        let attachment = pass.colorAttachments[0]!
        if let multisampled {
            attachment.texture = multisampled
            attachment.resolveTexture = scene
            attachment.storeAction = .unknown
        } else {
            attachment.texture = scene
            attachment.storeAction = .store
        }
    }

    /// This frame's multisampled scene target for WE's MSAA setting, made or remade to match
    /// `scene`; nil without MSAA (or when it can't be made, logged, when the pass draws without).
    /// Sets `sceneSampleCount`.
    private func sceneMultisample(for scene: MTLTexture) -> MTLTexture? {
        var samples = renderSettings.sceneSampleCount(on: device)
        if samples > 1, layerPipelines.pipelines(for: scene.pixelFormat, sampleCount: samples) == nil { samples = 1 }
        guard samples > 1 else {
            sceneMultisampleTarget = nil
            sceneSampleCount = 1
            return nil
        }
        if let target = sceneMultisampleTarget, target.width == scene.width, target.height == scene.height,
           target.pixelFormat == scene.pixelFormat, target.sampleCount == samples {
            sceneSampleCount = samples
            return target
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: scene.pixelFormat, width: scene.width,
                                                                  height: scene.height, mipmapped: false)
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = samples
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor) else {
            OWELog.error(.scene, "Could not allocate the \(scene.width)×\(scene.height) \(samples)× MSAA scene target; drawing without MSAA")
            sceneMultisampleTarget = nil
            sceneSampleCount = 1
            return nil
        }
        sceneMultisampleTarget = target
        sceneSampleCount = samples
        return target
    }

    private func sceneRenderTarget(pixelFormat: MTLPixelFormat, size pixelSize: SIMD2<Int>) -> MTLTexture? {
        if let sceneRenderTarget, sceneRenderTargetSize == pixelSize, sceneRenderTarget.pixelFormat == pixelFormat {
            return sceneRenderTarget
        }

        // Owned outright, not pooled: the scene is drawn into for the whole frame, so a pooled
        // scratch request of the same size (a scene-input region) must never be handed it.
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: pixelSize.x,
                                                                         height: pixelSize.y, mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            OWELog.error(.scene, "Could not allocate the \(pixelSize.x)×\(pixelSize.y) scene target")
            return nil
        }
        sceneRenderTarget = texture
        sceneRenderTargetSize = pixelSize
        return texture
    }

    /// The user's colour for a text layer (`_owe_text_<id>_color`), white when unset.
    private func textTint(layerID: String) -> SIMD3<Float> {
        guard let value = WallpaperServices.shared.userPropertyString("_owe_text_\(layerID)_color") else {
            return SIMD3(repeating: 1)
        }
        let rgb = value.parseVector3()
        return SIMD3(Float(rgb.0), Float(rgb.1), Float(rgb.2))
    }

    /// `layerID` keys the user's text settings and the text cache. `pointSize` is a script's
    /// `pointsize`, which wins over the app's size setting. `fill` nil rasterises white coverage,
    /// coloured when drawn; a colour rasterises the text in it, as WE's `font` pass draws it into
    /// the buffer its effects run on and other layers sample (3378346807's cyan clock).
    private func makeTextFrame(_ text: SceneMetalText, value: String, pointSize: Float?, boxSize: SIMD2<Float>,
                               pixelsPerUnit: Float, layerID: String,
                               fill: SIMD3<Float>?) -> (frame: RenderTextureFrame, baseSize: SIMD2<Float>)? {
        let stateKey = layerID
        let fontName = WallpaperServices.shared.userPropertyString("_owe_text_\(layerID)_font") ?? ""
        let sizeValue = pointSize
            ?? WallpaperServices.shared.userPropertyValue("_owe_text_\(layerID)_size", fallback: Float(text.pointSize))
        let bold = WallpaperServices.shared.userPropertyString("_owe_text_\(layerID)_bold") == "true"
        let italic = WallpaperServices.shared.userPropertyString("_owe_text_\(layerID)_italic") == "true"
        let rasterScale = textRasterScales[stateKey, default: SceneTextRasterScale.Tracker()].scale(for: pixelsPerUnit)
        let cacheKey = "\(stateKey)|\(value)|\(boxSize.x)|\(boxSize.y)|\(fontName)|\(sizeValue)|\(bold)|\(italic)|\(rasterScale)"
            + "|\(text.horizontalAlignment ?? "")|\(text.verticalAlignment ?? "")"
            + (fill.map { "|\($0)" } ?? "")
        let slot = "\(stateKey)|\(fill != nil)|\(pixelsPerUnit == 1)"
        for done in textRaster.takeFinished() {
            if let result = done.result { textFrameCache.insert(result, for: done.key, cost: result.cost) }
        }
        if let cached = textFrameCache.value(for: cacheKey) {
            textRaster.show(cached, slot: slot)
            return (cached.frame, cached.baseSize)
        }
        // A changed string is rasterised on a pool job while the previous raster keeps drawing.
        let request = SceneTextRasterRequest(text: text, value: value,
                                             fontName: fontName.isEmpty ? (text.font ?? "System") : fontName,
                                             pointSize: sizeValue, bold: bold, italic: italic,
                                             rasterScale: rasterScale, fill: fill)
        guard let (result, isNew) = textRaster.raster(key: cacheKey, slot: slot, request: request) else {
            OWELog.error(.scene, "Text layer \(layerID): could not rasterise")
            return nil
        }
        if isNew { textFrameCache.insert(result, for: cacheKey, cost: result.cost) }
        return (result.frame, result.baseSize)
    }

    /// Maps a scene-unit position and size onto `drawableSize` pixels. Scene draws use
    /// `.stretch` (the target has the scene's aspect); the composite uses the user's placement, at
    /// `pixelsPerPoint` (the frame's display by default).
    private func layerUniform(position: SIMD2<Float>, size: SIMD2<Float>, opacity: Float,
                              drawableSize: SIMD2<Float>, placement: WallpaperPlacement,
                              pixelsPerPoint: Float? = nil) -> LayerUniform {
        let scale: Float
        switch placement {
        case .stretch:
            return LayerUniform(position: SIMD2<Float>(position.x * drawableSize.x / sceneSize.x,
                                                        position.y * drawableSize.y / sceneSize.y),
                                size: SIMD2<Float>(size.x * drawableSize.x / sceneSize.x,
                                                   size.y * drawableSize.y / sceneSize.y),
                                sceneSize: drawableSize, opacity: opacity, particleShape: 0, rotation: 0, color: SIMD4<Float>(repeating: 1),
                                uvOrigin: .zero, uvAxisX: SIMD2<Float>(1, 0), uvAxisY: SIMD2<Float>(0, 1),
                                effects: SIMD4<Float>(1, 1, 1, 0), blur: 0,
                                colorEffects: SIMD4<Float>(0, 1, 0, 0.7), transform: SIMD4<Float>(0, 0, 0, 1),
                                transformScaleY: 1)
        case .fill, .zoom, .fit, .center:
            scale = ScenePlacementScale.scale(for: placement, sceneSize: sceneSize, drawableSize: drawableSize,
                                              pixelsPerPoint: pixelsPerPoint ?? drawablePixelsPerPoint)
        }
        let offset = (drawableSize - sceneSize * scale) / 2
        return LayerUniform(position: SIMD2<Float>(position.x * scale + offset.x,
                                                   position.y * scale + (drawableSize.y - sceneSize.y * scale - offset.y)),
                            size: size * scale, sceneSize: drawableSize, opacity: opacity,
                            particleShape: 0, rotation: 0, color: SIMD4<Float>(repeating: 1),
                            uvOrigin: .zero, uvAxisX: SIMD2<Float>(1, 0), uvAxisY: SIMD2<Float>(0, 1),
                            effects: SIMD4<Float>(1, 1, 1, 0), blur: 0,
                            colorEffects: SIMD4<Float>(0, 1, 0, 0.7), transform: SIMD4<Float>(0, 0, 0, 1),
                            transformScaleY: 1)
    }

    /// Compiles landed so far in the layer, effect and particle renderers.
    private var pipelinesLanded: Int {
        (effectGraph?.pipelinesLanded ?? 0) &+ (imageMaterials?.pipelinesLanded ?? 0) &+ (particleMaterials?.pipelinesLanded ?? 0)
    }

    /// Whether any pipeline is still compiling off the render thread.
    var pipelinesCompiling: Bool {
        hasPendingEffectPipelines || imageMaterials?.hasPendingPipelines == true
            || particleMaterials?.hasPendingPipelines == true
    }

    /// The unquantised pixels per unit that sizes the scene target to `drawable` when the scene is
    /// a single effect-less video filling it at the same aspect; nil otherwise.
    private func videoOnlyPixelsPerUnit(_ drawable: SIMD2<Float>) -> Float? {
        guard layers.count == 1, case .video = layers[0].layer.source, layers[0].layer.weEffects.isEmpty,
              particleSystems.isEmpty, spatial.models.isEmpty, !scripts.isRunning,
              sceneSize.x > 0, sceneSize.y > 0, drawable.x > 0, drawable.y > 0 else { return nil }
        let exact = drawable.x / sceneSize.x
        guard abs(sceneSize.y * exact - drawable.y) < 0.5,
              max(drawable.x, drawable.y) <= SceneRenderResolution.maximumTextureDimension else { return nil }
        return exact
    }

    /// Hands this frame's inputs to the layer analysis, which marks the layers they change dirty.
    private func analyseLayers(effectFrame: BuiltinFrameContext, motion: CameraMotion, drawableSize: SIMD2<Float>) {
        guard let layerAnalysis else { return }
        var inputs = SceneLayerFrameInputs()
        inputs.time = effectFrame.time
        inputs.pointer = effectFrame.pointer
        inputs.parallax = effectFrame.parallax
        inputs.parallaxActive = motion.parallax != nil
        inputs.shake = motion.shake
        inputs.cameraShake = motion.cameraShake
        inputs.audio = effectFrame.audio
        inputs.audioLevel = motion.audioLevel
        // System textures (now-playing artwork) keep following the clock; a video only its frames.
        if mediaTextures != nil && effectFrame.time != analysedTime
            || layers.contains(where: { if case let .video(stream) = $0.layer.source { stream.hasNewFrame } else { false } }) {
            videoRevision &+= 1
        }
        analysedTime = effectFrame.time
        inputs.videoRevision = videoRevision
        inputs.userPropertiesRevision = WallpaperServices.shared.propertyService.revision
        inputs.scripts = scripts.state
        inputs.animatedSites = animations?.sites ?? []
        let shape = (layers: layers.count, target: drawableSize)
        // A layer, effect or post-process whose pipeline is still compiling draws another way until
        // it lands; nothing the analysis tracks says when.
        // A compile can also start and land between two frames, unseen by `warming`.
        let warming = pipelinesCompiling
        let landed = pipelinesLanded
        inputs.sceneChanged = shape.layers != analysedShape.layers || shape.target != analysedShape.target
            || warming || analysedWarmUp || landed != analysedLanded || textRaster.hasFinished
            || scripts.userVisibilityRevision != analysedUserVisibility
        analysedUserVisibility = scripts.userVisibilityRevision
        analysedLanded = landed
        analysedShape = shape
        analysedWarmUp = warming
        layerAnalysis.update(inputs)
    }

    /// Whether this frame is drawn (`FramePacing`); called once the analysis has seen its inputs.
    private func paceFrame(_ frame: BuiltinFrameContext, at now: CFTimeInterval) -> Bool {
        let parallaxMoved = frame.parallax != pacedParallax
        pacedParallax = frame.parallax
        guard let analysis = layerAnalysis else { return framePacing.record(.smooth, at: now) }
        // Models pose every frame (the analysis counts the scene's own as animated stages); one a
        // script created after the load counts the same.
        if !spatial.models.isEmpty { return framePacing.record(.smooth, at: now) || !skipsIdleFrames }
        var particlesLive = false, particlesFollowCursor = false
        for system in particleSystems where particleObjectID(system).map({ scripts.isVisible($0) }) ?? true {
            particlesLive = true
            if system.configuration.controlPoints.contains(where: \.followsCursor) { particlesFollowCursor = true; break }
        }
        let inputs = FrameDemandInputs(analysis: analysis, pointerMoved: frame.pointer != frame.pointerLast,
                                       parallaxMoved: parallaxMoved, particlesLive: particlesLive,
                                       particlesFollowCursor: particlesFollowCursor)
        return framePacing.record(framePacing.classify(inputs), at: now) || !skipsIdleFrames
    }

    /// The cursor in scene units, mapped through the placement of the display it is on, or nil
    /// while it is on none of this scene's displays.
    private func sceneCursor(_ viewports: [SceneViewport]) -> SIMD2<Float>? {
        for viewport in viewports {
            guard let drawablePoint = viewport.cursorPixels else { continue }
            return ScenePlacementScale.scenePoint(drawablePoint: drawablePoint, placement: placement, sceneSize: sceneSize,
                                                  drawableSize: viewport.drawableSize, pixelsPerPoint: viewport.pixelsPerPoint)
        }
        return nil
    }

    private func clearUploadedImages() {
        uploadedImagesLock.lock()
        uploadedImages.removeAllObjects()
        particleMipmaps.removeAll()
        uploadedImagesLock.unlock()
    }

    /// A particle system's texture 0 with its mip chain; systems that share a texture share it.
    /// A sprite sheet keeps the levels its file stores: a generated chain would bleed its cells
    /// into each other at the small levels.
    private func particleTexture(from source: SceneMetalTextureSource, spriteSheet: Bool) -> MTLTexture? {
        guard let texture = makeTextureFrames(from: source)?.first?.texture else { return nil }
        guard !spriteSheet, ParticleTextureMipmaps.needsChain(texture) else { return texture }
        let key = ObjectIdentifier(texture)
        uploadedImagesLock.lock()
        let cached = particleMipmaps[key]?.chained
        uploadedImagesLock.unlock()
        if let cached { return cached }
        let chained = ParticleTextureMipmaps.mipmapped(texture, device: device, queue: commandQueue)
        uploadedImagesLock.lock()
        defer { uploadedImagesLock.unlock() }
        if let raced = particleMipmaps[key]?.chained { return raced }
        particleMipmaps[key] = (texture, chained)
        return chained
    }

    private func makeTextureFrames(from source: SceneMetalTextureSource) -> [RenderTextureFrame]? {
        guard case let .image(image) = source else { return uploadTextureFrames(from: source) }
        uploadedImagesLock.lock()
        let cached = uploadedImages.object(forKey: image)?.frames
        uploadedImagesLock.unlock()
        if let cached { return cached }
        guard let frames = uploadTextureFrames(from: source) else { return nil }
        uploadedImagesLock.lock()
        defer { uploadedImagesLock.unlock() }
        if let raced = uploadedImages.object(forKey: image)?.frames { return raced }
        uploadedImages.setObject(UploadedFrames(frames), forKey: image)
        return frames
    }

    private func uploadTextureFrames(from source: SceneMetalTextureSource) -> [RenderTextureFrame]? {
        switch source {
        case let .image(image):
            if let raw = TEXRawImageRep.of(image) {
                // Its allocation, padding and all, as a block-compressed .tex (`contentUVExtent`).
                guard let texture = raw.makeAllocationTexture(device: device) else {
                    OWELog.error(.scene, "Could not upload a \(raw.pixelsWide)×\(raw.pixelsHigh) .tex image")
                    return nil
                }
                let crop = raw.isPadded ? raw.contentUVExtent : SIMD2<Float>(1, 1)
                return [RenderTextureFrame(texture: texture, duration: .greatestFiniteMagnitude,
                                           uvOrigin: .zero, uvAxisX: SIMD2<Float>(crop.x, 0), uvAxisY: SIMD2<Float>(0, crop.y))]
            }
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let texture: MTLTexture
            do {
                texture = try SceneTextureUpload.texture(from: cgImage, loader: textureLoader, device: device)
            } catch {
                OWELog.error(.scene, "Could not upload a \(cgImage.width)×\(cgImage.height) image: \(error)")
                return nil
            }
            return [RenderTextureFrame(texture: texture, duration: .greatestFiniteMagnitude,
                                       uvOrigin: .zero, uvAxisX: SIMD2<Float>(1, 0), uvAxisY: SIMD2<Float>(0, 1))]
        case let .dxt(source):
            guard let texture = makeDXTTexture(source) else { return nil }
            let crop = Self.contentUVExtent(source)
            return [RenderTextureFrame(texture: texture, duration: .greatestFiniteMagnitude,
                                       uvOrigin: .zero, uvAxisX: SIMD2<Float>(crop.x, 0), uvAxisY: SIMD2<Float>(0, crop.y))]
        case let .video(stream):
            // Stand-in until the first frame decodes; draw() swaps in the live texture.
            guard let texture = stream.currentTexture() ?? makePlaceholderTexture() else { return nil }
            return [RenderTextureFrame(texture: texture, duration: .greatestFiniteMagnitude,
                                       uvOrigin: .zero, uvAxisX: SIMD2<Float>(1, 0), uvAxisY: SIMD2<Float>(0, 1))]
        case let .animated(animation):
            let textures = animation.images.compactMap { image -> MTLTexture? in
                if let raw = TEXRawImageRep.of(image) { return raw.makeTexture(device: device) }
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                do {
                    return try SceneTextureUpload.texture(from: cgImage, loader: textureLoader, device: device)
                } catch {
                    OWELog.error(.scene, "Could not upload a \(cgImage.width)×\(cgImage.height) animation frame: \(error)")
                    return nil
                }
            }
            guard textures.count == animation.images.count else { return nil }
            return animation.frames.compactMap { frame in
                guard frame.imageIndex < textures.count else { return nil }
                // Frame rects are in the atlas's pixels; the texture was made from those pixels,
                // whatever size in points the image reports. WidthY/HeightX shear or turn the rect.
                let atlas = textures[frame.imageIndex]
                let atlasSize = SIMD2<Float>(Float(atlas.width), Float(atlas.height))
                guard atlasSize.x > 0, atlasSize.y > 0 else { return nil }
                return RenderTextureFrame(texture: textures[frame.imageIndex], duration: frame.duration,
                                          uvOrigin: SIMD2<Float>(frame.x, frame.y) / atlasSize,
                                          uvAxisX: SIMD2<Float>(frame.width, frame.widthY) / atlasSize,
                                          uvAxisY: SIMD2<Float>(frame.heightX, frame.height) / atlasSize)
            }
        case .uploaded:
            // Its pixels were dropped after its first upload; a new upload loads the file again.
            OWELog.error(.scene, "An uploaded image was handed back for upload without its pixels")
            return nil
        }
    }

    /// The part of a padded .tex allocation the image covers, in UV units: the quad samples only
    /// the image, never the padding around it.
    static func contentUVExtent(_ texture: TEXCompressedTexture) -> SIMD2<Float> {
        guard texture.width > 0, texture.height > 0, texture.contentWidth > 0, texture.contentHeight > 0 else {
            return SIMD2(1, 1)
        }
        return simd_min(SIMD2(Float(texture.contentWidth) / Float(texture.width),
                              Float(texture.contentHeight) / Float(texture.height)), SIMD2(1, 1))
    }

    private func makePlaceholderTexture() -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel: UInt32 = 0
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        return texture
    }

    /// The layer's texture this frame: a video's current picture, or the sprite frame of an
    /// animated texture from the instance's texture clocks (docs/timeline-plan.md §2.7, §3.2),
    /// taken once per frame (a script's override advances each time it is asked).
    private func textureFrame(for entry: PreparedLayer) -> RenderTextureFrame {
        // A puppet's image is its mesh's drawing, laid out like its source texture.
        if entry.layer.puppet != nil, let albedo = puppetAlbedos[entry.layer.id] {
            let source = entry.frames[0]
            return RenderTextureFrame(texture: albedo, duration: source.duration, uvOrigin: source.uvOrigin,
                                      uvAxisX: source.uvAxisX, uvAxisY: source.uvAxisY)
        }
        // A video layer's texture is replaced every frame, so the decoded frame list is only a seed.
        if case let .video(stream) = entry.layer.source, let texture = stream.currentTexture() {
            return RenderTextureFrame(texture: texture, duration: .greatestFiniteMagnitude,
                                      uvOrigin: .zero, uvAxisX: SIMD2<Float>(1, 0), uvAxisY: SIMD2<Float>(0, 1))
        }
        // A system texture (the now-playing artwork) replaces the image while there is one.
        if let kind = entry.layer.systemImage, let texture = systemTexture(kind) {
            return RenderTextureFrame(texture: texture, duration: .greatestFiniteMagnitude,
                                      uvOrigin: .zero, uvAxisX: SIMD2<Float>(1, 0), uvAxisY: SIMD2<Float>(0, 1))
        }
        guard entry.frames.count > 1, let id = Int(entry.layer.id) else { return entry.frames[0] }
        let frame = timelines.spriteFrame(object: id, delta: Float(clock.delta))
        drawProbe?.record(spriteFrame: frame, object: id)
        // `setFrame(n)` isn't range-checked; a frame outside the sheet draws the first.
        return frame >= 0 && Int(frame) < entry.frames.count ? entry.frames[Int(frame)] : entry.frames[0]
    }


    /// A system texture's image now; nil without one (or without script services).
    private func systemTexture(_ kind: SceneSystemTexture) -> MTLTexture? {
        mediaTextures?.texture(kind)
    }

    private func spriteSheetUV(for particle: Particle,
                               configuration: SceneMetalParticleSystem) -> (origin: SIMD2<Float>, size: SIMD2<Float>) {
        guard let sheet = configuration.spriteSheet, sheet.frames > 0 else {
            return (.zero, SIMD2<Float>(repeating: 1))
        }
        let frame: Int
        switch configuration.animationMode {
        case "randomframe":
            frame = particle.spriteFrame % sheet.frames
        case "once":
            frame = min(Int(saturating: (particle.age / particle.lifetime) * Float(sheet.frames) * configuration.sequenceMultiplier),
                        sheet.frames - 1)
        default:
            // Over the particle's life, times `sequencemultiplier` (`ParticleRecordWriter.spritePhase`).
            let cycle = particle.age / max(particle.lifetime, 0.0001) * configuration.sequenceMultiplier
            frame = Int(saturating: (cycle - cycle.rounded(.down)) * Float(sheet.frames), in: 0...(sheet.frames - 1))
        }
        let column = frame % sheet.columns
        let row = frame / sheet.columns
        let size = SIMD2<Float>(1 / Float(sheet.columns), 1 / Float(sheet.rows))
        return (SIMD2<Float>(Float(column) * size.x, Float(row) * size.y), size)
    }

    private func makeDXTTexture(_ source: TEXCompressedTexture) -> MTLTexture? {
        // DXT1/3/5 are BC1/BC2/BC3. Apple Silicon Macs consume those natively, so upload the
        // blocks as-is, with every stored mipmap, instead of expanding them to rgba8Unorm through
        // the decode kernel.
        if SceneTextureUpload.blockFormat(for: source.format) != nil, device.supportsBCTextureCompression {
            return SceneTextureUpload.blockCompressedTexture(source, device: device)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                    width: source.width, height: source.height,
                                                                    mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let input = device.makeBuffer(bytes: source.data, length: source.data.count, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        var uniform = DXTDecodeUniform(width: UInt32(source.width), height: UInt32(source.height),
                                       blockColumns: UInt32((source.width + 3) / 4), format: source.format)
        encoder.setComputePipelineState(dxtDecodePipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&uniform, length: MemoryLayout<DXTDecodeUniform>.stride, index: 1)
        let threads = MTLSize(width: 8, height: 8, depth: 1)
        encoder.dispatchThreads(MTLSize(width: source.width, height: source.height, depth: 1), threadsPerThreadgroup: threads)
        encoder.endEncoding()
        commandBuffer.commit()
        // Keep the decode asynchronous. Metal command buffers on the same queue
        // preserve ordering, so later scene draws wait on this texture on-GPU
        // without blocking the render/content thread here.
        return texture
    }

    private func appendParticleTrail(_ particle: Particle, system: ParticleSystemRuntime,
                                     drawableSize: SIMD2<Float>) {
        let speed = simd_length(particle.velocity)
        // `ComputeParticleTrailTangents` (common_particles.h): the size times the speed's stretch,
        // clamped to `minlength`…`maxlength`.
        let limits = system.configuration.trailLengthLimits
        let stretch = max(limits.y, min(speed * system.configuration.trailLength, limits.x))
        let size = particle.size * system.drawSizeScale
        let length = size * stretch
        let width = system.configuration.refractive ? max(2, size * 0.08) : size
        var uniform = layerUniform(position: particle.position,
                                   size: SIMD2<Float>(width, length),
                                   opacity: particleOpacity(particle, in: system), drawableSize: drawableSize, placement: .stretch)
        uniform.rotation = speed > 0.01 ? atan2(particle.velocity.y, particle.velocity.x) - .pi / 2 : particle.rotation
        uniform.color = particle.color
        let uv = spriteSheetUV(for: particle, configuration: system.configuration)
        uniform.uvOrigin = uv.origin
        uniform.uvAxisX = SIMD2<Float>(uv.size.x, 0)
        uniform.uvAxisY = SIMD2<Float>(0, uv.size.y)
        particleInstances.append(uniform)
    }

    /// Grows geometrically so a system that ramps up to its particle cap stops reallocating.
    private func particleInstanceBuffer(for count: Int) -> MTLBuffer? {
        guard count > 0 else { return nil }
        let needed = MemoryLayout<LayerUniform>.stride * count
        if let buffer = particleInstanceStorage, buffer.length >= needed { return buffer }
        particleInstanceStorage = device.makeBuffer(length: max(needed * 2, 64 * MemoryLayout<LayerUniform>.stride),
                                                    options: .storageModeShared)
        return particleInstanceStorage
    }

    /// Draws one rope per particle through its own position history, rather than one rope through
    /// the whole system as `rope` does.
    private func appendRopeTrail(_ particle: Particle, system: ParticleSystemRuntime,
                                 drawableSize: SIMD2<Float>) {
        let configuration = system.configuration
        var trail = particle.orderedHistory
        // The newest sample lags by up to one interval, so close the gap to the particle itself.
        trail.append(particle.position)
        guard trail.count > 1 else { return }

        let opacity = particleOpacity(particle, in: system)
        let subdivision = max(configuration.ropeSubdivision, 1)
        var spline: [SIMD2<Float>] = []
        for index in 0..<(trail.count - 1) {
            let previous = trail[index > 0 ? index - 1 : index]
            let start = trail[index]
            let end = trail[index + 1]
            let following = trail[index + 2 < trail.count ? index + 2 : index + 1]
            for step in 0..<subdivision {
                spline.append(catmullRom(previous, start, end, following, Float(step) / Float(subdivision)))
            }
        }
        spline.append(trail[trail.count - 1])

        let uv = spriteSheetUV(for: particle, configuration: configuration)
        for index in 0..<(spline.count - 1) {
            let start = spline[index]
            let end = spline[index + 1]
            let delta = end - start
            let length = simd_length(delta)
            guard length > 0.01 else { continue }
            // 0 at the oldest sample, 1 at the particle itself.
            let progress = Float(index + 1) / Float(spline.count - 1)
            // A rope ribbon is twice the particle's size wide.
            let size = 2 * particle.size * system.drawSizeScale
            let width = configuration.fadeTrailSize ? size * progress : size
            var uniform = layerUniform(position: (start + end) / 2,
                                       size: SIMD2<Float>(length, max(width, 0.01)),
                                       opacity: configuration.fadeTrailAlpha ? opacity * progress : opacity,
                                       drawableSize: drawableSize, placement: .stretch)
            uniform.rotation = atan2(delta.y, delta.x)
            uniform.color = particle.color
            uniform.uvOrigin = uv.origin
            uniform.uvAxisX = SIMD2<Float>(uv.size.x, 0)
            uniform.uvAxisY = SIMD2<Float>(0, uv.size.y)
            particleInstances.append(uniform)
        }
    }

    /// One rope through the system's particles; one per instance of an instanced system.
    private func appendRope(_ system: ParticleSystemRuntime, drawableSize: SIMD2<Float>) {
        for strand in ParticleRopeStrands.strands(system.particles) {
            appendRope(strand, system: system, drawableSize: drawableSize)
        }
    }

    private func appendRope(_ particles: [Particle], system: ParticleSystemRuntime, drawableSize: SIMD2<Float>) {
        guard particles.count > 1 else { return }
        var spline: [(position: SIMD2<Float>, size: Float, color: SIMD4<Float>, opacity: Float)] = []
        let subdivision = max(system.configuration.ropeSubdivision, 1)
        for index in 0..<(particles.count - 1) {
            let previous = particles[index > 0 ? index - 1 : index]
            let start = particles[index]
            let end = particles[index + 1]
            let following = particles[index + 2 < particles.count ? index + 2 : index + 1]
            for step in 0..<subdivision {
                let t = Float(step) / Float(subdivision)
                spline.append((catmullRom(previous.position, start.position, end.position, following.position, t),
                               start.size + (end.size - start.size) * t,
                               simd_mix(start.color, end.color, SIMD4<Float>(repeating: t)),
                               particleOpacity(start, in: system)
                                   + (particleOpacity(end, in: system) - particleOpacity(start, in: system)) * t))
            }
        }
        if let last = particles.last {
            spline.append((last.position, last.size, last.color, particleOpacity(last, in: system)))
        }
        for index in 0..<(spline.count - 1) {
            let start = spline[index]
            let end = spline[index + 1]
            let delta = end.position - start.position
            let length = simd_length(delta)
            guard length > 0.01 else { continue }
            // A rope ribbon is twice the particle's size wide.
            let averageSize = (start.size + end.size) * system.drawSizeScale
            var uniform = layerUniform(position: (start.position + end.position) / 2,
                                       size: SIMD2<Float>(length, averageSize),
                                       opacity: (start.opacity + end.opacity) / 2,
                                       drawableSize: drawableSize, placement: .stretch)
            uniform.rotation = atan2(delta.y, delta.x)
            uniform.color = (start.color + end.color) / 2
            particleInstances.append(uniform)
        }
    }

    private func catmullRom(_ previous: SIMD2<Float>, _ start: SIMD2<Float>, _ end: SIMD2<Float>,
                            _ following: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {        let t2 = t * t
        let t3 = t2 * t
        // Split into terms so older compilers type-check it in reasonable time.
        let a: SIMD2<Float> = 2 * start
        let b: SIMD2<Float> = (end - previous) * t
        let c1: SIMD2<Float> = 2 * previous - 5 * start
        let c: SIMD2<Float> = (c1 + 4 * end - following) * t2
        let d1: SIMD2<Float> = 3 * start - previous
        let d: SIMD2<Float> = (d1 - 3 * end + following) * t3
        return 0.5 * (a + b + c + d)
    }

    /// The particle's alpha (`alphafade` is one of its operators) with the material's multiplier.
    private func particleOpacity(_ particle: Particle, in system: ParticleSystemRuntime) -> Float {
        particle.alpha * system.configuration.opacityMultiplier
    }
}
/// WE keeps the pointer where it left a display rather than recentring it, and reports no
/// button pressed while it is elsewhere; a jump to the centre would kick pointer-driven effects.
struct SceneCursorTracker {
    private(set) var lastPosition: SIMD2<Float>?

    /// `live` is nil while the cursor is on another display.
    mutating func update(_ live: SIMD2<Float>?, sceneSize: SIMD2<Float>) -> (position: SIMD2<Float>, onDisplay: Bool) {
        if let live {
            lastPosition = live
            return (live, true)
        }
        return (lastPosition ?? sceneSize / 2, false)
    }
}
