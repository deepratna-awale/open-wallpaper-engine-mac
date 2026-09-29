import Cocoa
import MetalKit
import CryptoKit

enum SceneMetalTextureSource {
    case image(NSImage)
    case dxt(TEXCompressedTexture)
    case animated(TEXAnimatedImages)
    /// Frames arrive from AVFoundation each frame rather than being decoded up front.
    case video(VideoTextureStream)
    /// A decoded image already on the GPU: only its sizes are kept, so the renderer's copy of the
    /// content holds no pixels (`uploaded`). Anything that uploads again loads the file again.
    case uploaded(SceneUploadedTexture)

    /// The image's own size in texels when it is smaller than the texture it is uploaded into
    /// (`g_TextureNResolution.zw`). Decoded images are already cropped to their content, so
    /// only block-compressed uploads, which keep the .tex padding, report one.
    var contentSize: SIMD2<Float>? {
        switch self {
        case let .dxt(texture):
            return SIMD2(Float(texture.contentWidth), Float(texture.contentHeight))
        case let .uploaded(info):
            return info.contentSize
        case .image, .animated, .video:
            return nil
        }
    }

    /// The image's size in pixels, which WE sizes an unsized layer by. An `NSImage`'s `size` is in
    /// points and follows the file's DPI (a 144-dpi PNG reports half its pixels), so it isn't used.
    var pixelSize: SIMD2<Float> {
        switch self {
        case let .image(image): return Self.pixelSize(of: image)
        case let .dxt(texture): return SIMD2(Float(texture.contentWidth), Float(texture.contentHeight))
        case let .animated(animation): return animation.images.first.map(Self.pixelSize(of:)) ?? .zero
        case let .video(stream): return stream.frameSize
        case let .uploaded(info): return info.pixelSize
        }
    }

    /// The size WE gives an image object that names none (an `autosize` model placed without a
    /// `size`, e.g. by `thisScene.createLayer('models/x.json')`): a sprite sheet's frame, the
    /// first `TEXS` frame's edges, not the atlas it is packed in; any other image's own size.
    var unsizedLayerSize: SIMD2<Float> {
        if case let .uploaded(info) = self { return info.unsizedLayerSize }
        guard case let .animated(animation) = self, let frame = animation.frames.first else { return pixelSize }
        return SIMD2(simd_length(SIMD2(frame.width, frame.widthY)), simd_length(SIMD2(frame.heightX, frame.height)))
    }

    /// What is kept once the pixels are on the GPU: decoded images and block-compressed data give
    /// way to their sizes; a video stays, since its frames keep arriving.
    var uploaded: SceneMetalTextureSource {
        switch self {
        case .image, .dxt, .animated:
            return .uploaded(SceneUploadedTexture(pixelSize: pixelSize, contentSize: contentSize,
                                                  unsizedLayerSize: unsizedLayerSize,
                                                  sheetPixelSize: sheetPixelSize))
        case .video, .uploaded:
            return self
        }
    }

    /// The texture's pixels that a `.tex-json` sprite-sheet frame size is measured in: the whole
    /// allocated texture (TEXS frame rects include the .tex padding). An image's pixels come from
    /// its bitmap: an `NSImage` made from a `CGImage` reports its representation's `pixelsWide` at
    /// the screen's backing scale (twice the bitmap on a Retina display). Nil without an image.
    var sheetPixelSize: SIMD2<Double>? {
        let size: SIMD2<Float>
        switch self {
        case let .dxt(texture): size = SIMD2(Float(texture.width), Float(texture.height))
        case let .uploaded(info): return info.sheetPixelSize
        case .image, .animated, .video: size = pixelSize
        }
        return size.x > 0 && size.y > 0 ? SIMD2<Double>(size) : nil
    }

    static func pixelSize(of image: NSImage) -> SIMD2<Float> {
        if let raw = TEXRawImageRep.of(image) { return SIMD2(Float(raw.pixelsWide), Float(raw.pixelsHigh)) }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return SIMD2(Float(cgImage.width), Float(cgImage.height))
        }
        return SIMD2(Float(image.size.width), Float(image.size.height))
    }
}

/// The sizes of an image `SceneMetalTextureSource.uploaded` stands for.
struct SceneUploadedTexture: Equatable {
    let pixelSize: SIMD2<Float>
    let contentSize: SIMD2<Float>?
    let unsizedLayerSize: SIMD2<Float>
    let sheetPixelSize: SIMD2<Double>?
}

struct SceneMetalLayer {
    let id: String
    let name: String
    /// Replaced by its sizes (`SceneMetalTextureSource.uploaded`) once the renderer uploaded it.
    var source: SceneMetalTextureSource
    /// `origin`, relative to the parent object (see `SceneMetalContent.transforms`).
    let position: SIMD2<Float>
    let size: SIMD2<Float>
    let scale: SIMD2<Float>
    let opacity: Float
    let brightness: Float
    let color: SIMD4<Float>
    let text: SceneMetalText?
    let parallaxDepth: SIMD3<Float>
    let perspective: Bool
    let rotation: Float
    /// `angles.x` and `angles.y` (radians): the orthographic squash of a tilted object.
    var tilt: SIMD2<Float> = .zero
    let effects: SceneMaterialEffects
    /// Set for video layers so the picture can pulse with the music the way the AVKit path does.
    var musicSync: VideoMusicSyncVisuals? = nil
    /// Authored effects, run through Wallpaper Engine's own shaders.
    var weEffects: [SceneEffectPlan] = []
    /// Composition, fullscreen and project layers: the base image is the scene rendered so far
    /// under the layer (`_rt_FullFrameBuffer`), not a texture.
    var sceneInput = false
    /// A layer whose material has no texture (a solid layer's `flat`, a shape): its fill as
    /// straight RGBA. Its quad stretches a 1×1 source, but WE sizes its effect buffers to the
    /// layer's `size`, rounded (`wallpaper64.exe` 0x140209206…0x14020923c), so its effects start
    /// from the fill at that size (`SceneMetalRenderer.solidEffectInput`).
    var solidFill: SIMD4<Float>? = nil
    /// The layer's quad adds to the scene instead of blending over it. A `shape` object's blend
    /// state is WE's `additive` (the shape class's +0x108, `wallpaper64.exe` 0x140260790, writes
    /// blending 2, which `0x140157e0e` names `additive`), where an image's is its material's.
    var additive = false
    /// A texture WE supplies at run time in place of the layer's image (its `instance`'s
    /// `usertextures` slot 0, e.g. the now-playing artwork); the image stands in while there is none.
    var systemImage: SceneSystemTexture? = nil
    /// Index of the object in scene.json: layers and particle systems draw in that order.
    var order = 0
    /// `alignment` (images) or the text block's aligned edge: where the quad sits against `position`.
    var alignment: String? = nil
    /// `fullscreen` models cover the scene whatever their parent is.
    var fillsScene = false
    /// User-bound transform/colour values, re-resolved each frame.
    var bindings = SceneLayerBindings()
    /// The image object's own material, drawn through WE's shader; nil draws the layer natively.
    var imageMaterial: ImageMaterialPlan? = nil
    /// A Puppet Warp image's mesh: it draws the layer image each frame (`ScenePuppetRenderer`),
    /// which the layer's effects and its own draw then read in place of `source`.
    var puppet: ScenePuppetPlan? = nil
    /// An animated texture's name (`textures[0]` of the image's material): every layer drawing the
    /// same texture shares its clock (docs/timeline-plan.md §2.7). Nil for a still one.
    var textureKey: String? = nil

    /// The renderer must interrupt the scene pass for this layer to give it the scene so far.
    var readsScene: Bool {
        sceneInput || imageMaterial?.readsSceneSnapshot == true || effectsReadScene
    }

    /// An effect pass reads the scene: it may sample any of it, not just what is under the layer.
    var effectsReadScene: Bool {
        weEffects.contains { $0.passes.contains(where: \.readsSceneSnapshot) }
    }
}

/// Audio-reactive transforms applied to a video layer each frame.
struct VideoMusicSyncVisuals {
    let zoomAmount: Float
    let tiltAmount: Float
    let saturationAmount: Float
    /// Supplied by the video stream so sync can follow the wallpaper's own soundtrack rather than
    /// the system-wide capture, which cannot tell the two apart.
    var levelSource: (() -> Double)? = nil
}

struct SceneMetalText {
    let value: String
    let font: String?
    let pointSize: CGFloat
    let horizontalAlignment: String?
    let verticalAlignment: String?
    /// Inset from the layer's own bounds; every authored text object declares one.
    let padding: SIMD2<Float>
    let maxWidth: Float?
    let maxRows: Int?
    let useEllipsis: Bool
    /// WE's `anchor` (none, center, top, topright, …, 0x14025a22b). WE's text translates its model
    /// matrix by four render-context floats per anchor (0x1402585c0), but nothing in
    /// `wallpaper64.exe` writes the first two, and WE's text captures (all `center`) sit where
    /// the unanchored layout puts them, so it moves nothing here (docs/roadmap.md §8.13).
    let anchor: String?
    let blockAlign: Bool
    /// `outline`, `blur` and `dropshadow` (`SceneTextEffects`); nil for plain text.
    var effects: SceneTextEffects? = nil
}

struct SceneMaterialEffects {
    let brightness: Float
    let contrast: Float
    let saturation: Float
    let bloom: Float
    let blur: Float
    let exposure: Float
    let gamma: Float
    let hue: Float
    let bloomThreshold: Float
    let transformAngle: Float
    let transformOffset: SIMD2<Float>
    let transformScale: SIMD2<Float>

    /// No adjustment. A layer's material constants reach WE's own shader (`ImageMaterialPlan`);
    /// they are never guessed into these native adjustments by name.
    static let identity = SceneMaterialEffects(brightness: 1, contrast: 1, saturation: 1, bloom: 0, blur: 0,
                                               exposure: 0, gamma: 1, hue: 0, bloomThreshold: 0.7,
                                               transformAngle: 0, transformOffset: .zero,
                                               transformScale: SIMD2<Float>(repeating: 1))
}

struct SceneBloomSettings {
    let enabled: Bool
    let strength: Float
    let threshold: Float
    let tint: SIMD3<Float>
    /// `hdr` and `bloomhdr*`; HDR also needs `enabled` and the user's post-processing setting.
    var hdr = SceneHDRBloomSettings()
}

struct SceneMetalContent {
    let size: SIMD2<Float>
    let layers: [SceneMetalLayer]
    let particleSystems: [SceneMetalParticleSystem]
    let bloom: SceneBloomSettings
    /// Every object's parent and authored transform; layer positions are relative to their parent.
    var transforms: SceneTransformHierarchy = .empty
    /// Objects that aren't drawn layers (groups, particle systems), by id: how their own
    /// transform moves, so what hangs below them follows.
    var motions: [String: SceneObjectMotion] = [:]
    var camera = SceneCameraEffects()
    /// The projection, camera settings, camera layers and paths, model objects and draw-order mode
    /// of WE's 3D runtime (`SceneSpatialContentBuilder`; docs/models-plan.md § Seams).
    var spatial = SceneSpatialContent()
    /// `general.clearcolor`, resolved against the user properties: the scene target's clear colour.
    var clearColor = SceneGeneralDefaults.clearColor
    /// The wallpaper instance's key in the user-property store (its directory path).
    var wallpaperKey = ""
    /// Every object's own `visible` before scripts (authored, user-bound or the app's toggle), by
    /// id. Hidden objects are built anyway: scripts can show them (plan §4.3).
    var visibility: [String: Bool] = [:]
    /// The id of each object of scene.json, in scene order.
    var objectIDs: [Int] = []
    /// The scene's SceneScripts; nil when it has none.
    var scripts: SceneScriptSceneContent?
    /// The document the instance's timelines come from; nil for a preview or a video.
    var timelines: SceneTimelineSource?
    /// The scene's sound layers.
    var sounds: [SceneSoundContent] = []
    /// `general`'s lighting settings and the scene's light objects.
    var lighting = SceneLightingContent()
    /// WE's volumetric lights, planned for the user's volumetrics setting; nil when it is
    /// disabled or no light casts volumetrics (`SceneVolumetricsPlan`).
    var volumetrics: SceneVolumetricsPlan?
    /// The combos WE's engine sets on every material of this content (`SceneEngineCombos`).
    var engineCombos = SceneEngineCombos()
    /// WE's LDR bloom passes, planned with the content's engine combos; nil without a shader
    /// toolchain. Planned for every scene: a script or user property can turn `bloom` on.
    var bloomChain: SceneBloomChain?
    /// WE's HDR bloom and combines, planned when the content draws in HDR (`engineCombos.hdr`),
    /// in place of `bloomChain`; nil otherwise or without a shader toolchain.
    var hdrChain: SceneHDRChain?
    /// WE's colour correction (`ccsimple`) for the user's image filter and colour options; nil
    /// without a shader toolchain.
    var colorCorrection: SceneColorCorrection?
    /// WE's camera fade, made for a scene with camera paths; nil otherwise or without a shader
    /// toolchain.
    var cameraFade: SceneCameraFade?
}

/// `scene.json` as the content was built from it, for the wallpaper instance's `SceneAnimationSet`
/// (docs/timeline-plan.md §2.1). A renderer keeps its set, clocks and all, across content rebuilt
/// from the same document (a user property changed a layer), as it keeps the scripts.
struct SceneTimelineSource {
    var wallpaperID: String
    var document: SceneJSON
    var signature: String
}
