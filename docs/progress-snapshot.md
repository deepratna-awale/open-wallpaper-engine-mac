# Open Wallpaper Engine for macOS: progress snapshot

**Date: 2026-10-02**, `main`. Goal: run every Wallpaper Engine wallpaper except `application` ([`architecture.md`](architecture.md)). Order of work: [`roadmap.md`](roadmap.md). Tests are under `OpenWallpaperEngineTests/`; those that need WE's files read them from `OWE_ASSETS`.

Legend: ✅ working · 🟡 partial (what's left is named) · ❌ missing. "Unverified" means nobody has checked it against the code or WE.

## TL;DR

- Scenes draw through WE's own shaders, translated in process (glslang and SPIRV-Cross, `Vendor/ShaderToolchain`) and cached. All 45 shipped effects (plus `_empty`) match WE's captures in the effect gallery (`WEEffectGalleryTests`, 55 scenes).
- Composition, fullscreen and solid layers, masks, blend modes, parenting, text, timelines, user-property bindings, SceneScript, sound, audio reactivity, particles, lighting, 3D models and puppet warp are done (roadmap areas 1–7).
- Still open: roadmap area 8 items 19, 20, 21, 23, 24 (some partly done, see below), Workshop `preset`-type items, and the points in the plans that need WE ground truth (`lighting-plan.md` §5, `models-plan.md` §5, `test-risks.md`).

## 1. Coverage by wallpaper type and scene feature

### Wallpaper types

| Type | Status | Note |
|---|---|---|
| Video | ✅ | AVPlayer, hev1/avc3 MP4 remux (#65), WebM through WebKit with music sync (#26); sync effects: `VideoMusicSyncEffectTests`, `VideoWallpaperPlaybackTests`. |
| Web | ✅ | Properties and audio/media listeners delivered (`WebWallpaperPropertyBridgeTests`, `WebWallpaperMediaBridgeTests`); one WebContent process per wallpaper (#12). Open: late listeners get properties faithfully (#109, open). |
| Scene | ✅ | See the feature table. |
| Application | n/a | Out of scope. |
| Preset (Workshop `preset` type) | 🟡 | Local presets: save, apply, export, import WE's share JSON (#34, `WallpaperPresetTests`, `WallpaperPresetCompatibilityTests`). Workshop preset items (no `type`/`file`, a flat `preset` object, the base in `dependency`) are listed as their base's type, as WE does, and play the base with the preset's values as the item's defaults and their own property store (`WorkshopPresetItem`, `WorkshopPresetItemTests` on WE's install of 3332091404). |

### Scene features

| Feature | Status | Note |
|---|---|---|
| Image layers, sprite sheets, alignment | ✅ | Base image through WE's `genericimage*` materials (`ImageMaterialRenderTests`); sprite frames `TEXSpriteFramesTests`; effects on the current frame (#94). |
| Keyframe animation | ✅ | WE's timeline format, bit for bit (`SceneTimelineReferenceTests`, `timeline-plan.md`). |
| Composition / fullscreen / project layers | ✅ | `_rt_FullFrameBuffer` and `_rt_imageLayerComposite_*` (`SceneLayerCompositeTests`, `SceneRegionResampleTests`). |
| Solid layers | ✅ | `SceneSolidLayerBlendTests`. |
| Text layers | ✅ | WE's layout, anchor, `blockalign`, effects on text (`SceneTextLayoutTests`, `SceneTextAnchorTests`, `SceneTextEffectsTests`). |
| Parenting | ✅ | Full parent transforms, live (`SceneTransformTests`, `SceneTransform3DTests`; roadmap area 8 item 12). Objects without `id`: see open item 23. |
| Particles | ✅ | GPU operator program, children, control points, collisions, instance overrides, budget (`ParticleSimulationParityTests`, `ParticleOverrideTests`, `WEParticleGalleryTests`; roadmap area 2). |
| Built-in effects (46) | ✅ | §3. |
| Workshop / custom effects | ✅ | Same translator path as built-ins; `LibrarySweepTests`, `SceneShaderCompatTests`. |
| Multi-pass effects, FBOs, `previous`, `swap`, `_rt_*` | ✅ | Effect graph (`EffectGraphTests`, `EffectLastPassTests`); fluidsimulation's 20 passes verified in #113 (tests in that open PR). |
| Masks | ✅ | Masks bind through WE's materials; RG88 flow maps load both channels (`TextureRG88Tests`). |
| User-property bindings | ✅ | One generic binding layer on every field (#67, `UserPropertyBindingTableTests`, `SceneBindingResolutionTests`); sweep of every property in #68 (open). Particle overrides change only newly spawned particles, as in WE (#112, open). |
| SceneScript | ✅ | §5. |
| Audio-reactive (effects, scripts, bars) | ✅ | Core Audio process tap (#30), `g_AudioSpectrum*` fed (`AudioSpectrumTests`, `SceneScriptAudioBufferTests`), restart on device change (#96). |
| Sound objects | ✅ | WE's modes, gain, timers, script control, spatialization (`SceneSoundLayersTests`, `SceneSoundSpatializationTests`). Edge pan unverified against WE. |
| Bloom / HDR | ✅ | WE's LDR and HDR chains, display HDR (`SceneBloomChainTests`, `SceneHDRChainTests`, `lighting-plan.md` B1–B3). |
| Camera parallax / shake | ✅ | WE's formulas from the binary (`CameraParallaxLibraryTests`, `SceneCameraMotionTests`). Toggling parallax still rebuilds the content (item 24, #106 open). |
| Lights, 3D models, puppet warp | ✅ | `lighting-plan.md`, `models-plan.md` (`ModelRenderTests`, `ModelSkinningTests`, `ScenePuppetTests`). Texture channels (mesh flag 0x2): `ScenePuppetTextureChannelsTests` on WE 2.8.42's files. |
| Perspective scenes | ✅ | `SceneCameraTests`, `SceneCameraPathsTests` (models-plan M2–M4). |
| Cursor interaction | ✅ | Scene-space cursor, `solid` hit tests, clicks only on the wallpaper (`SceneScriptCursorHitTestTests`, `WECursorCaptureTests`). Pointer details without a WE capture: `test-risks.md` FX1. |
| Tests | ✅ | 375 test classes, sharded CI (#9, #63, #66). |

## 2. Effect coverage (the 46 effects in WE's install)

Every effect runs WE's own shaders through the translator. The effect gallery (`WEEffectGalleryTests`, fixtures in `Tests/Fixtures/WEEffectGallery/expected.json`) draws each one at its defaults and compares difference and motion with WE's capture; all 55 scenes pass, none is a known gap.

| Effects | Status | Note |
|---|---|---|
| `_empty` | ✅ | No-op, as in WE. |
| blend, blendgradient, blur, blurprecise, blurradial, chromaticaberration, cloudmotion, clouds, colorkey, depthparallax, edgedetection, fire, fisheye, foliagesway, glitter, godrays, iris, lightshafts, localcontrast, motionblur, nitro, opacity, perspective, pulse, reflection, refraction, scroll, shake, shimmer, shine, skew, spin, swing, tint, transform, twirl, vhs, watercaustics, waterflow, waterripple, waterwaves | ✅ | Gallery. |
| filmgrain | ✅ | Last pass drawn into the scene as WE does (`EffectLastPassTests`, `test-risks.md` FX2). |
| cursorripple, xray | ✅ | Gallery; cursor placement `WECursorCaptureTests`. WE capture with the cursor on screen still missing (FX1). |
| fluidsimulation | ✅ | Gallery; pass graph, swaps and FBOs checked in #113 (`FluidSimulationEffectTests`, in that open PR). Its cursor force has no WE capture (FX1). |

## 3. SceneScript

All of WE's API runs on `SceneScriptRuntime`, one per wallpaper instance (`scenescript-plan.md`); the last stub, `getVideoTexture`, landed in #85. The library's scripts are replayed in `SceneScriptCorpusReplayTests`.

| API | Status | Note |
|---|---|---|
| `update(value)`, `init`, `destroy`, `resizeScreen` | ✅ | `SceneScriptRuntimeTests`. |
| `applyUserProperties` (changed keys only) | ✅ | `SceneScriptBindingTests`. |
| Cursor callbacks, `input.*` | ✅ | `SceneScriptInputTests`, `SceneScriptCursorHitTestTests`. |
| `media*` callbacks | ✅ | `SceneScriptMediaTests`. |
| `createScriptProperties`, `shared` | ✅ | `SceneScriptBindingTests`, `SceneScriptRuntimeTests`. |
| `thisScene.getLayer`, `createLayer`, `destroyLayer`, `sortLayer`, `getLayerIndex` | ✅ | `SceneScriptObjectModelTests`. |
| `thisLayer` reads and writes, `Vec*`, degrees | ✅ | `SceneScriptLayerTransformTests`. |
| `setParent`, `lookAt`, attachments (#29) | ✅ | `SceneScriptLayerTransformTests`, `ScenePuppetAttachmentTests`. |
| `getAnimation`, `getTextureAnimation`, `animationEvent` | ✅ | `SceneScriptAnimationObjectTests`, `SceneRigAnimationEventTests`. |
| `getEffect`, `getMaterial`, `setMaterialProperty` | ✅ | `SceneScriptBindingTests`, `UniformScriptWriteTests`. |
| `engine.registerAudioBuffers` | ✅ | `SceneScriptAudioBufferTests`. |
| `engine.setTimeout`/`setInterval` | ✅ | `SceneScriptTimerTests`. |
| `localStorage` | ✅ | `SceneScriptLocalStorageTests`. |
| `camerashake`, camera transforms | ✅ | `SceneScriptCameraTests`. `getCameraTransforms` semantics under camera layers: models-plan §5.5. |
| `renderContext`, `console`, `applyGeneralSettings` (#32) | ✅ | `SceneScriptParityTests`. |
| `getVideoTexture` (#85) | ✅ | `SceneScriptVideoTextureTests`. |

## 4. Open

- **Roadmap area 8:**
  - 19. Scene audio cache: names are stable (SHA-256, 04aea06, `Scene/Loading/SceneSoundContentBuilder.swift`). Left: sweep old per-launch names and cap the folder (#105, open).
  - 20. Pipeline compiles unbounded, no retry, variant key without the Metal compiler's build; with the shader-compiler helper process (#107, open). `TEMPDUMP` is already gone.
  - 21. Text cache: already an LRU under 32 MB (`SceneMetalRenderer.textFrameCache`). Left: exact raster once an animated scale settles (#105, open).
  - 23. Objects without `id`: layers, visibility and binding keys use the index (04aea06); `?? -1` remains in `Scene/Loading/SceneSpatialContentBuilder.swift` and `SceneWallpaperViewModel.swift` (text keys, visibility map).
  - 24. Toggling parallax rebuilds the content (#106, open). The `_owe_effect_*` keys left are the live parallax settings, not dead code.
- **Workshop `preset`-type items** (§1).
- **WE ground truth:** `lighting-plan.md` §5, `models-plan.md` §5 (zoom in perspective, root motion with yaw alone, MDLV unknowns, …), `test-risks.md` "needs WE ground truth".
- **Other open PRs:** #102, #103 (screen saver loops), #104 (menu Next/Previous), #108 (playlist shortcuts), #110, #111 (live and stored user properties).

## History

The 2026-09-25 snapshot (root-cause verification, fix plan P0–P7, code-health review) is in the git history of this file; its fixes are traced in `roadmap.md` "Done" and area 8, and in `optimizations.md`.
