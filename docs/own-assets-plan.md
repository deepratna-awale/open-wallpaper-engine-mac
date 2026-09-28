# Own shader and asset set: plan

**Update 2026-09-28:** `Vendor/we-assets` was removed; the app now takes the reference assets from the user's own Steam copy (Settings › Assets, `<storage>/.owe-assets`) or a chosen install, and tests from `OWE_ASSETS`. Mentions of the bundled copy below describe the state when this plan was written.

**Status: 2026-09-27, research and plan only.** Branch `deepratna/feature-work`. Nothing here is implemented yet.

**The decision.** The app stops shipping the reference product's asset tree (`Vendor/we-assets`) and ships its own set:
- Every shader is written natively in Metal from standard techniques.
- The reference files are a behavioural reference only: parameters, defaults, ranges, and what the captures show. No shader is ported line by line.
- The interface Workshop content relies on is kept exactly:
  - effect paths;
  - material and effect JSON structure;
  - pass layout, FBO names, bind names;
  - uniform names and material keys;
  - combo names and value meanings;
  - defaults and ranges;
  - the GLSL helper functions that Workshop shaders `#include`.
- Improvements are welcome, but anything that changes the default look is an option that defaults OFF. Out of the box the output matches the reference captures.
- No mention of the other product in the new assets: not in the folder names, type names, comments or UI. The exceptions are factual Steam/Workshop requirements, and existing compatibility code and docs, which are out of scope. No attribution is added.

**How to read this.**
- §0 lists the findings that shape everything else.
- §1 is the inventory.
- §2 covers each shader and effect.
- §3 is the architecture.
- §4 replaces the non-shader assets. §4.1 covers fonts, including the curated set and system fonts.
- §5 is the rename.
- §6 is the ordered work breakdown.
- §7 lists risks and open points.

The numbers come from scans of the checkout and of the user's library at `/Volumes/980Pro/OpenWallpaperStorage`:
- 61 scenes, 57 Asset (dependency) items, 1 video and 1 web.
- None of it is packed (no `.pkg`). Each scene's own files plus the Workshop items it references (`workshop/<id>/…`, transitively) count as "local".

## 0. Findings that shape the plan

1. **Wallpapers carry their own copy of every built-in effect they use, and that copy is what runs.**
   - WE's compiler copies `effects/<name>/effect.json`, `materials/effects/*.json` and `shaders/effects/*` into the project. WE, like us (audit §8, `SceneEffectPlanBuilder`), resolves the project root before the assets root.
   - All 705 built-in effect uses in the library ship local copies. That covers 37 distinct effects in 61 scenes. (This scan counts 705; audit §8 counted 716 with its own method.)
   - Of the 556 local effect shader files, **445 are byte-for-byte the current reference version** (ignoring whitespace) and **111 are older versions**. Those older versions have real behavioural differences: an older `shake` has no `TIMEOFFSET` combo and defaults its phase texture to white, and 8 `pulse` copies use a different audio path.
   - So the bundled effect shaders run only in:
     - the effect gallery and the extras;
     - projects without the copy (generated or hand-written);
     - effects added in the inspector.
   - **To benefit real wallpapers, native effects must be substituted for recognised local copies** (§3.3, fingerprints). Unrecognised copies keep going through the translator.
2. **The shared GLSL headers are the most used bundled asset, and they must stay GLSL.**
   - 54 of 61 scenes have local shaders that `#include` a bundled header:
     - `common.h` 50;
     - `common_blending.h` 47;
     - `common_perspective.h` 31;
     - `common_blur.h` 22;
     - `common_composite.h` 7;
     - `common_fragment.h` 7;
     - `common_vertex.h` 2;
     - `common_pbr_2.h` 2.
   - Those shaders are translated in-app, so our replacement headers are **our own GLSL**. They keep the same function names, signatures, macros and uniforms, and have matching numerics.
   - The native Metal library gets a separate MSL port of the same maths.
3. **Engine shaders are never shipped by wallpapers and are the main prize for native Metal.**
   - Wallpaper materials name them, and the engine's own chains load them.
   - Library usage by scene:
     - `genericimage4` 39 (172 materials), `genericimage2` 22 (114), `genericimage3` 6;
     - `genericparticle` 38 (171), `generic4` 8 (97), `generic2` 1;
     - `composelayer` 19, `passthrough` 15, `flat` 14;
     - `font` in every scene with text (29);
     - bloom/HDR chains: bloom is on in 17 scenes as authored and is on by default in WE (audit §9.1); HDR in 7;
     - volumetrics 9;
     - shadow casters in the lit 3D scenes.
4. **`Vendor/we-assets/ATTRIBUTION.txt` (a copy of `Scripts/we-assets-attribution.txt`) is wrong.** It says the shaders "have been translated … to Metal Shading Language". The tree holds only GLSL (124 `.frag`, 124 `.vert`, 3 `.geom`, 14 `.h`, no `.metal`). `README.md:280` and `CONTRIBUTING.md:65` are stale the same way. All of this goes away with the tree (package P17).
5. **Most of the tree's bytes are particle art.**
   - The tree is 49 MB, 1,022 files. 40 MB of it is `materials/particle` (164 `.tex` plus 52 editor `.gif`s).
   - The library uses 37 distinct particle textures, in 38 scenes.
   - These are artwork, not utility textures, and are the hardest part to replace without changing looks (§4.3, §7).
6. **There is no native bloom, text, composite or present shader today.**
   - Every engine pass goes through translated GLSL (`SceneShaders.metal` is only the legacy fallback draw).
   - There is no `SceneDynamicEffectCatalog`; the effect "catalog" is the file lookup itself.
   - There is no metallib cache. Every pipeline compiles MSL source at runtime (`device.makeLibrary(source:)`), and only the pipeline states go into `EffectPipelineArchive`.

## 1. Inventory

**Counting method.** "Scenes" = library scenes that reference the item and don't ship it themselves (the runtime resolves them to the bundled tree). "Closure" follows references: an effect's materials, their shaders, `#include`s, and default textures in sampler annotations. "Tests" names the suites that read the item (from the asset-loading survey).

Implicit engine use (not a file reference) is counted by scene features:

| Feature | Scenes |
|---|---|
| image layers | 60 |
| particles | 39 |
| text | 29 |
| scripts | 35 |
| sound | 14 |
| lights | 11 |
| 3D models | 9 |
| volumetrics | 9 |
| bloom authored on | 17 |
| HDR | 7 |

### 1.1 Shaders (`shaders/`, engine and utility)

| Item | What it is | Scenes | Loaded by | Tests |
|---|---|---|---|---|
| `genericimage2/3/4` (.vert/.frag) | Image layer material: texture, colour/alpha/brightness, blend-mode composite, PBR lighting, reflection, fog, prelighting, puppets (skinning/morph), sprite sheets, clipping, alpha-to-coverage | 4: 41 (39 by name + util materials), 2: 25, 3: 6; composite path for every blended layer | wallpaper materials; `materials/util/effectpassthrough(_4).json`, `solidlayer_instance*.json` | ImageMaterialRender/Lighting/Reflection/Prelighting, PrelitEffectChain, SceneDepthDraw, ScenePuppet*, SkinningReference, ImageMaterialSweep, WEImageBlendModes, LightingV1Require, GeometryShaderEmulation, ShaderVariantCache, InProcessShaderCompiler |
| `genericparticle` (.vert/.geom/.frag), `genericropeparticle` | Particle sprite/trail/rope rendering: sprite sheets, blend, refraction, lighting, cutout, fog, thick formats | 40 | particle materials (the literal is swapped for rope renderers) | ParticleMaterialRender, ParticleGPURender, ParticleMaterialPerformance, SceneRendererParticle, ParticleEditorTemplate, ParticleMaterialSweep, WEParticleGallery, GeometryShaderEmulation, LightingV1Require |
| `generic4`, `generic2`, `generic3`, `foliage4`, `fur4`, `chroma4`, `generic`, `flag` + `base/model_vertex_v1.h`, `base/model_fragment_v1.h` | 3D model materials: PBR, skinning, morphs, rim light, shading gradient, tint masks, foliage wind, fur shells | generic4 8, generic2 1 (the others 0) | model materials | ModelRender, ModelSkinning, SceneScriptModelData, ModelMaterialSweep, SceneShadow*, LightingV1Require |
| `shadowcaster`, `shadowcasterfoliage4`, `shadowcasterfur4` | Depth-only shadow map caster (skinning, morph, alpha test) | lit 3D scenes | `materials/util/shadowcaster.json` + `// [PASS] shadow` | SceneShadowTests, SceneShadowRenderTests |
| `font` | Text layer: glyph atlas sample, outline, blur, drop shadow, SDF/MSDF/colour-font modes | 29 | `materials/fonts/basefont.json` | RenderCheck, SceneTextEffects, ImageMaterialRender:463, WEExtras (text_*) |
| `flat` | Solid colour layer | 14 | `materials/util/solidlayer*.json`, `flat*.json` | SceneSolidLayerBlend, SceneLayerKind |
| `composelayer` | Composition layer: samples `_rt_FullFrameBuffer` | 19 | `models/util/composelayer.json`, `projectlayer.json`, `fullscreenlayer.json` | SceneLayerComposite, SceneLayerKind |
| `passthrough`, `passthroughsrgb`, `passthroughlinear` | Copies; the sRGB variant is the HDR→LDR combine | 15 / HDR 7 | util materials, volumetrics combine, HDR chain | SceneHDRChain, SceneVolumetrics |
| `downsample_quarter_bloom`, `downsample_eighth_blur_v`, `blur_h_bloom`, `combine` | LDR bloom chain (threshold, saturate, 1/4 → 1/8, separable 13-tap, add) | every scene with bloom (on by default) | `SceneBloomChain` | SceneBloomChainTests, WEEffectGallery (all), BloomLibrary |
| `hdr_downsample` (BLOOM/UPSAMPLE/BICUBIC), `combine_hdr` (LINEAR/DISPLAYHDR) | HDR bloom pyramid: downsample, bicubic upsample with scatter, combine | 7 | `SceneHDRChain` | SceneHDRChain, SceneHDRMaterial |
| `ccsimple` | Colour correction: 3D LUT plus params | app colour-filter setting | `SceneColorCorrection` | SceneColorCorrectionTests |
| `fade` | Camera fade | scenes using camera fade | `SceneCameraFade` | SceneCameraFadeTests |
| `volumetricsback`, `volumetricsfront` (FULLSCREEN, POINTLIGHT, COOKIE, SHADOW, QUALITY, FOG), `blur_k3` | Volumetric light: back-face depth, front ray-march, 3-tap blur, combine | 9 | `SceneVolumetricsPlan` | SceneVolumetricsTests, VolumetricsLibrary |
| `effectcomposebackground` | Effect composite background | 1 | `materials/util/effectcomposebackground.json` | — |
| `downsample_quarter`(`_linear`) | 4×4 box downsample (the emitter-image reduce duplicates it natively) | layer-image emitters | `ParticleEmitterImagePoints` (doc) | ParticleEmitterImage tests |
| `clippingmaskimage4`, `puppettexturechannels` | Clipping mask; puppet channel re-layout | 0 by file (puppet re-layout is native already) | — | — |
| Editor/debug: `brushinvert`, `brushpreview`, `compilerbackdrop`, `editorpaintbrush`, `editorsprite`, `orthogrid`, `wireframe`, `occlusiontest`, `error`, `minimal`, `minimalalpha`, `flatpoint`, `combine_hdr_editor`, `combine_video_hdr`, `passthroughblend`, `genericimage`, `generic`, `generic3`, `chroma4`, `flag` | Editor-only or unused | 0 | `error` is named in 3 code places | — (**drop**) |
| `declarations.json` | Editor metadata | 0 | nothing | — (**drop**) |

### 1.2 Shared GLSL headers (`shaders/*.h`)

"Direct" = local shaders that include the header. "Closure" = scenes that reach it through any resolved shader.

| Header | Interface (functions / macros / uniforms) | Direct | Closure |
|---|---|---|---|
| `common.h` | `hsv2rgb`, `rgb2hsv`, `rotateVec2`, `greyscale`; `M_PI`, `M_PI_HALF`, `M_PI_2`, `SQRT_2`, `SQRT_3` (the prelude inlines these constants too) | 50 | 61 |
| `common_blending.h` | `ApplyBlending(mode, A, B, opacity)` for image-blending modes 0…32ish; `Blend*` macros (Normal, Lighten, Darken, Multiply, Average, Add, Subtract, Difference, Negation, Exclusion, Screen, Overlay, SoftLight, HardLight, ColorDodge, ColorBurn, LinearDodge, LinearBurn, LinearLight, VividLight, PinLight, HardMix, Reflect, Glow, Phoenix, Hue, Saturation, Color, Luminosity, Tint, Opacity); `Desaturate`, `RGBToHSL`, `HSLToRGB`, `ContrastSaturationBrightness` | 47 | 60 |
| `common_perspective.h` | `squareToQuad` (4-point homography), `inverse(mat3)` | 31 | 31 |
| `common_blur.h` | `blur13/7/3`, `blur13a/7a/3a`, `blurRadial13a/7a/3a`, `blurRotateVec2` | 22 | 22 |
| `common_composite.h` | `ApplyCompositeOffset`, `ApplyComposite`; `g_CompositeAlpha`, `g_CompositeOffset`, `g_CompositeColor` | 7 | 7 |
| `common_fragment.h` | `DecompressNormal`, `DecompressNormalWithMask`, `ComputeMaterialSpecular*`, `ComputeLight`, `ComputeLightSpecular`, `ConvertSampleR8`, `ConvertTexture0Format`, `ConvertTextureFormat`; `FORMAT_*` constants | 7 | 46 |
| `common_vertex.h` | `BuildTangentSpace` (3 overloads) | 2 | 61 |
| `common_fog.h` | `CalculateFogPixelState`, `ApplyFog`, `ApplyFogAlpha`; `g_FogDistance*`, `g_FogHeight*` | 0 | 58 |
| `common_pbr.h`, `common_pbr_2.h` | `FresnelSchlick`, `Distribution_GGX`, `Schlick_GGX`, `GeoSmith`, `PointSegmentDelta`, `ComputePBRLight(Shadow)(Infinite)`, `PerformShadowMapping`, `PerformPointShadowMapping`, `CalculateProjectedCoords*`, `CombineLighting`, `random`; `SHADOW_ATLAS_ANTIALIAS` | 0 / 2 | 25 / 58 |
| `common_particles.h` | `ComputeParticleTangents`, `ComputeParticleTrailTangents`, `ComputeParticlePosition`, `ComputeSpriteFrame`, `ComputeScreenRefractionTangents/Coord`; particle uniforms | 0 | 40 |
| `common_foliage.h` | `CalcLeavesUVWeight`, `CalcFoliageAnimation` | 0 | 0 (foliage4) |
| `base/model_vertex_v1.h`, `base/model_fragment_v1.h` | `ApplySkinning*`, `ApplyMorph*`, `ApplyPosition*`, `ApplyTangentSpace`, `ApplyAmbientLighting`, `ClipSpaceToScreenSpace`; `ApplyReflection`, `ApplyAlphaToCoverage`; bone/morph uniforms | 0 | 8 |

`#require LightingV1` is not a file. It is expanded by `LightingV1Require.swift`, which ports the reference's generated source. See §7 R9.

**Tests for the headers:**
- `ShaderVariantCacheTests.testTranslatedOutputMatchesItsRevision` (golden hash of every bundled effect pair's MSL);
- `ShaderVariantTests` (every effect pair, ≥ 68);
- `GLSLReservedWordsTests`;
- `WEImageBlendModesTests` (reads `common_blending.h`);
- `ShaderVariantCacheTests`;
- the library sweeps.

### 1.3 Effects (`effects/<name>/`: `effect.json`, `materials/effects/*.json`, `shaders/effects/*`, normal-map PNGs)

- There are 46 effect folders, including `_empty`. Per-effect detail is in §2.3.
- Library use, as wallpapers / instances, all shipping local copies:

  | Effect | Wallpapers | Instances |
  |---|---|---|
  | shake | 31 | 263 |
  | waterwaves | 24 | 106 |
  | pulse | 17 | 27 |
  | foliagesway | 14 | 27 |
  | blend | 8 | 20 |
  | nitro | 8 | 28 |
  | blur | 7 | 9 |
  | opacity | 6 | 28 |
  | godrays | 6 | 8 |
  | waterripple | 6 | 8 |
  | waterflow | 6 | 7 |
  | iris | 6 | 36 |
  | blurprecise | 5 | 7 |
  | shine | 5 | 20 |
  | vhs | 5 | 16 |
  | localcontrast | 5 | 6 |
  | tint | 4 | 11 |
  | lightshafts | 4 | 4 |
  | transform | 3 | 11 |
  | perspective | 3 | 12 |
  | chromaticaberration | 3 | 3 |
  | scroll | 3 | 3 |
  | swing | 2 | 18 |
  | xray, depthparallax, fluidsimulation, clouds, filmgrain, cloudmotion, watercaustics | 2 each | — |
  | fire, reflection, refraction, cursorripple, fisheye, shimmer, glitter | 1 each | — |
  | _empty, blendgradient, blurradial, colorkey, edgedetection, motionblur, skew, spin, twirl | 0 | — |

- **Workshop copies of built-ins.** Workshop Asset items also ship copies of built-ins under `effects/workshop/<id>/…`: blurprecise ×4 items, spin, scroll, opacity, blend, blendgradient, pulse, tint, blur, blurradial, fisheye, colorkey, edgedetection, nitro, vhs, perspective. These are translated and can be fingerprinted like project copies.
- **Tests:**
  - `EffectGraphTests` (blur, glitter, lightshafts, motionblur, refraction, shake, shine, tint, xray, and every effect);
  - `EffectGraphReuse`/`Swap`/`Composite`, `EffectDocumentTests` (decodes every effect);
  - `WEAuthoredValuesTests` (every effect.json);
  - `ShaderStageUniformTests` (foliagesway);
  - `ShaderVariantTests`/`Cache`, `GLSLReservedWords` (blend);
  - `SceneEffectAssetScope`, `SceneEffectDetail`, `SceneLayerComposite` (blend);
  - `WEEffectGalleryTests` (all 46 + 5 composites + 4 user projects).

### 1.4 Materials and models (definitions)

| Item | What | Scenes | Tests |
|---|---|---|---|
| `models/util/{composelayer, composelayer_depthtest, fullscreenlayer, projectlayer, solidlayer, solidlayer_depthtest}.json` | Built-in layer models (`passthrough`, `fullscreen`, `autosize`, `projectlayer`, `solidlayer` flags) | 16, 2, 15, 3, 9, 5 | SceneLayerKind, SceneLayerComposite, SceneSolidLayerBlend |
| `materials/util/*.json` (62) | Used: `composelayer*` (18), `fullscreenlayer` (15), `solidlayer*` (9 + 5 + instance variants 2/2/1), `effectpassthrough(_4)` (every blended layer), `effectcomposebackground` (1), `shadowcaster`, `ccsimple`, `fade`, `downsample_quarter_bloom`, `downsample_eighth_blur_v`, `blur_h_bloom`, `combine_ldr`, `hdr_*`, `combine_hdr_upsample`, `combine_srgb`, `volumetrics_*` (6), `downsample_quarter`, `passthrough`, `flat*`. Unused: `debugrt*`, `gizmo*`, `wireframe`, `occlusiontest`, `compiler_backdrop`, `combine_hdr_editor`, `combine_video_hdr`, `combine_dhdr_upsample`, `combine_hdr_upsample_dbg`, `backbufferpassthrough`, `error` | as listed | SceneBloomChain, SceneHDRChain/Material, SceneVolumetrics (`volumetrics_combine` :118), SceneCameraFade, SceneColorCorrection, SceneShadow |
| `materials/fonts/*.json` (10) | `basefont`, `basefontrgba`, `_depth`, `_msdf` variants, `fontbackground(_depth)`. Code loads `basefont.json` | 29 | RenderCheck, ImageMaterialRender:463 |
| `materials/particle/{halo, halo_translucent}.json` | Particle default materials | via presets | ParticleMaterialRender, ParticleEditorTemplate |
| `particles/example*.json` (6) | Editor particle templates | 0 at runtime | ParticleEditorTemplateTests (pins max count 500, sphere emitter 32…512) |
| `materials/editor/*`, `materials/models/editor/*`, `models/editor/camera/camera.mdl` | Editor gizmos, camera model | 0 (`camera.mdl` feeds `Scripts/mdl-reference.py`'s fixture oracle) | MDL oracle fixtures |

### 1.5 Textures

| Item | Count | Scenes (closure; direct) | Tests |
|---|---|---|---|
| `util/white`, `black`, `flatnormal` | 3 | white 46 (16); black 1 | many (defaults for masks) |
| `util/noise` (white noise), `perlin_256`, `clouds_256` (tiling fBm), `uniform_256`, `noflow` (neutral flow), `fur` | 6 | noise 6, clouds 4, and every effect that defaults to them | SceneColorCorrection (`noise.tex`), gallery |
| `pattern/voronoi`, `voronoi_local` | 2 | watercaustics (2) | gallery |
| `gradient/*` (16 ramps) | 16 | toon_smooth 8 (closure), blend_gradient_reverse 1, swipe_wide 1; defaults of lightshafts (iridescent), fluidsimulation (fire), shimmer (ferro fluid) | gallery |
| `lut/*` (28 3D LUTs incl. `neutral`) | 28 | 0 by scenes; the app's colour filter setting | SceneColorCorrectionTests (every filter + neutral) |
| `cookie/flashlight1…4` | 4 | 1 (flashlight1 is the default cookie) | SceneVolumetrics, lighting tests |
| effect normal maps `refractnormal.png`, `waterripplenormal.png`, `waterflowphase.png` | 3 | via local copies (the wallpapers ship them too) | gallery |
| `materials/particle/**` | 164 `.tex` (+ 52 `.gif`, 1 `.tga`, unused) | 38 scenes use 37 of them. Top: halo 14, chromaticdot 9, drop 8, halo_6 8 (also xray's default), fog1 5, rosepetals 4, halo_4 4, halo_2 4, beam_1 3, debris1 3, fog3 3, sharp_halo 3, light_shafts_0/6 3, drop_normal 3, normal_ring_smooth 3 | ParticleMaterialRender (`beam/hose_1`), WEParticleGallery |

### 1.6 Fonts (`fonts/`)

15 font files with 4 licence texts. Library references that don't ship the file:
- Monofur 6 scenes (17 layers);
- Atami 2 (8 layers);
- Alcubierre 2–3;
- 8-bit Operator+ 1;
- Blackout 2 AM 1.

`systemfont_*` references are resolved from the OS: arial 4, cambria 2, calibri 1. Wallpapers ship their other fonts themselves (Quicksand, Anurati, Rajdhani, Oxanium …).

Tests:
- `SceneTextLayoutTests` (`fonts/NotoSans-Regular.ttf`, metrics 286/−79/363 at 64 pt);
- `WorkshopAssetResolverTests` (synthetic);
- WEExtras text captures.

### 1.7 Scripts

| Item | What | Scenes | Tests |
|---|---|---|---|
| `scripts/jsclasses/baseclasses.js` (1,456 lines) | Global runtime: `Vec2`, `Vec3`, `Vec4`, `Mat3`, `Mat4`, `MediaPlaybackEvent`, `IModelData`, `deg2rad`/`rad2deg`, `_Epsilon`, `stringifyAdapter` | 35 | every SceneScript suite through `SceneScriptPrelude.load()`; `WEAuthoredValuesTests:253`; the replay corpus |
| `scripts/jsmodules/{wemath, wecolor, wevector}.js` | Modules `WEMath` (`deg2rad`, `rad2deg`, `smoothStep`, `mix`), `WEColor` (`rgb2hsv`, `hsv2rgb`, `normalizeColor`, `expandColor`), `WEVector` (`angleVector2`, `vectorAngle2`) | 7 / 4 / 3 (11 total) | SceneScriptModuleCompiler |

### 1.8 zcompat

| Item | What | Scenes | Tests |
|---|---|---|---|
| `zcompat/scene/shaders/2078835426` (pixelate), `2084198056` (Simple_Audio_Bars) | Replacement GLSL for two Workshop shaders up to a project id | Simple_Audio_Bars is used by 5 scenes (through 2084198056 and 3021673417's copy) | SceneShaderCompatTests (reads the vendored folder) |
| `zcompat/web/{780658164, 780662613, 780675904, 784979889, 854685299}.json` | Web wallpaper patch actions | web items with those ids | WebCompatPatchesTests (reads the vendored folder) |

### 1.9 Code that resolves the tree

These are the touch points for §5 and P0/P1:
- **`Core/WallpaperEngineAssets.swift`:** `bundled` (resource `we-assets`, valid if it has `effects/`), `testInstall` (`OWE_WE_ASSETS`, under XCTest only), `searchDirectories` = [testInstall, bundled], `locate`. The user-configured folder (`configured`, defaults `WallpaperEngineAssetsDirectory`) was removed on 2026-09-27 at the user's request.
- **`SceneWallpaperViewModel.assetData`:** zcompat, then the wallpaper's pkg, folder and Workshop items, then `sharedAssetData`. `sharedAssetData` adds the `.tex` suffix, remaps `materials/presets/…`, and prefixes `materials/`.
- **`ShaderSourceLoader`:** stages are `<name>.<stage>`, then `shaders/<name>.<stage>`; includes are `shaders/<inc>`, then `<inc>`. `GeometryShaderEmulation.sources` does the same for `.geom`.
- **Engine chains:**
  - `SceneBloomChain:28-31`, `SceneHDRChain:62-77`, `SceneVolumetricsPlan:54-59`;
  - `SceneColorCorrection:16/20/86`, `SceneCameraFade:15`;
  - `ImageMaterialPlan:156` (`effectpassthrough_4`), `ModelMaterialPlan:253` (`shadowcaster`);
  - `SceneWallpaperViewModel:1117` (`basefont`).
- **Other resolvers:**
  - `SceneFontResolver` (`systemfont_`, then wallpaper, then asset roots, then Workshop);
  - `SceneSoundContentBuilder:62`;
  - `SceneScriptPrelude:19-51`;
  - `SceneShaderCompat` and `WebCompatPatches`, whose root is `directory ?? bundled`;
  - `SceneInspectorView:248` (effect parameters);
  - `WorkshopAssetResolver.defaultRoots`, which derives the Steam Workshop folder from the configured install.
- **Build:** `project.pbxproj` folder reference `Vendor/we-assets`; `release.yml:134` checks `we-assets/shaders/common.h`.
- **Scripts:** `Scripts/vendor-we-assets.sh`, `Scripts/we-assets-attribution.txt`, `Scripts/mdl-reference.py:10,49`.

## 2. Shaders and effects

### 2.1 Conventions for every native program

- **Interface first.** Each program has a manifest (§3.2) in our own JSON. It lists:
  - uniforms by their GLSL names (`g_Strength`) with material keys, defaults and ranges exactly as the reference declares them, including stage-divergent declarations (§2.4);
  - combos with defaults and option values;
  - textures with slot, default and sampler combo;
  - varyings/attributes by fixed location;
  - pass render state.
- **Default look = reference.** Every improvement is either:
  - **invisible:** it passes the parity gate of §3.6 (LDR max ≤ 2/255, mean ≤ 0.3/255), so it is always on; or
  - **visible:** an OFF option (§6.6).
- **Apple-GPU baseline, applied everywhere unless noted:**
  - `half` for colour arithmetic in LDR paths;
  - `float` for UVs, time, homographies and depth;
  - function constants instead of `#if`;
  - no dynamic indexing of varyings (use fixed arrays with constant bounds);
  - `[[early_fragment_tests]]` where there is no discard;
  - memoryless render targets for intermediates consumed in the same pass;
  - `.dontCare` load actions on fully overwritten FBOs.

Effort key: **S** ≤ 1 day, **M** 2–4 days, **L** 1–2 weeks. Every item includes parity tests and capture checks.

### 2.2 Engine programs

| Program | Technique | Interface to keep | Improvements (OFF unless invisible) | Reference quirks and bugs | Apple-GPU | Effort | Verify |
|---|---|---|---|---|---|---|---|
| **passthrough / passthroughsrgb / passthroughlinear / composelayer / effectcomposebackground / fade / flat** | Copy, linear↔sRGB encode, full-frame sample, solid colour, fade mix | Names, `g_Texture0`, `_rt_FullFrameBuffer` binding, `g_Color4`/`g_UserAlpha`/`g_Brightness` | none | a solid layer's `colorBlendMode` goes through `effectpassthrough_4` (audit §9.3) | Fold `composelayer`'s full-frame copy into programmable blending (read `[[color(0)]]`) where the layer composites into the same target (invisible) | S | ImageMaterialRender, SceneLayerComposite, SceneSolidLayerBlend; extras `solidblend_*` (0.20–0.27 mean abs, no regression) |
| **genericimage2 / 3 / 4** | Textured quad/mesh with colour × alpha × brightness; `BLENDMODE` composite over `_rt_FullFrameBuffer`; PBR lights (LightingV1), reflection (`_rt_MipMappedFrameBuffer`), emissive, PBR masks and their `.tex`-flag component combos, fog (dist/height/computed), prelighting (+dual vertex), skinning (`SKINNING`, `SKINNING_ALPHA`), morphs, sprite sheets, clipping (`CLIPPING*`), alpha-to-coverage, `VERTEXCOLOR`, `HDR`, `SCENE_ORTHO` | Material keys (Alpha, Brightness, roughness 0.7, metallic 0, reflectivity, reflectivitydistance 4, emissive*, speculartint, ambientlowpass), combos LIGHTING/REFLECTION/FOG plus the engine combos above, `g_Texture0…N` slots, attribute locations | (a) **Programmable-blending composite:** read the destination in-tile instead of copying the frame for every blended layer. Invisible if parity holds; it is the biggest bandwidth win. (b) Anisotropic filtering in perspective scenes: **OFF**. (c) Mip bias fixes: **OFF** | `g_Color4`/`g_UserAlpha` double application (test-risks I1/I20); FX3: stage uniforms not split in `ImageMaterialPlan` (fix while porting) | Function constants for ~30 switches (the variant count stays bounded by the effective-combo filter), half colour | L | ImageMaterial* suites, WEReference stills (15 scenes, score no worse), puppet5s captures, extras solid/composite |
| **genericparticle / genericropeparticle** | Instanced camera-facing sprites (geometry stage expands points to quads, trails and ropes), sprite-sheet frame blend, overbright, cutout, refraction (screen-space tangent offset), lighting, fog, `THICKFORMAT` | Combos CUTOUT, DOUBLESIDEDLIGHTING, FOG, LIGHTING, REFRACT and engine TRAILRENDERER, SPRITESHEET(BLEND), THICKFORMAT, TRAILSUBDIVISION, GS_ENABLED; material keys `ui_editor_properties_overbright`, `_cutout_*`; particle record layout | (a) **Mesh-shader expansion** (Metal 3 object/mesh stages) instead of the emulated geometry stage (invisible; removes the `3×(N−2)` vertex waste in `GeometryShaderEmulation`). (b) Soft particles (depth fade): **OFF** | PG2 (lightshafts_6), PG5 (snowstorm fog coverage): ours vs reference, investigate during the port; rope ordering I14 | Mesh shaders or vertex-pulling from the GPU simulation's record buffer (no CPU copy) | L | Particle* suites, WEParticleGallery (122 items; coverage ±50 %, motion ±50 %, plus no regression beyond ±5 % of the translated baseline), extras `refraction_bigdrops` |
| **font** | Samples the CoreText-rasterised glyph texture; outline, blur, drop shadow as offset/dilated samples; SDF/MSDF/colour-font modes | Combos BLUR_ENABLED, OUTLINE_ENABLED, DROP_SHADOW_ENABLED, SDF, MSDF, COLORFONT; material names of the 10 `materials/fonts/*.json` | (a) SDF glyphs from CoreText outlines (crisp at any scale): **OFF**. (b) Separable blur for large blur radii (invisible) | EX2: the effect buffer is centred on the origin rather than the ink (layout, not shader) | Half, one pass for all three effects | M | SceneTextEffects, SceneTextLayout, extras `text_*` (0.5–1.7 mean abs, no regression) |
| **LDR bloom** (`downsample_quarter_bloom`, `downsample_eighth_blur_v`, `blur_h_bloom`, `combine`) | Bright-pass (max(r,g,b) − threshold, saturation push 2c − luma, × strength), 1/4 then 1/8 downsample, separable 13-tap Gaussian, additive combine | Material keys `bloomstrength`, `bloomthreshold`, `bloomtint`; FBO scales; the arithmetic of audit §9.2 exactly | **"Enhanced bloom" OFF:** energy-conserving dual-filter pyramid with soft-knee threshold and Karis average, resolution-independent radius (fixes LR6) | LR6: the radius is fixed in target pixels, so it changes with render size (a reference quirk; the fix is in the OFF option) | One compute dispatch for the downsample chain (single-pass downsampler, threadgroup memory); separable blur in compute | M | SceneBloomChainTests, every gallery scene (bloom on by default: control SSIM ≥ current), BloomLibrary |
| **HDR bloom** (`hdr_downsample` BLOOM/UPSAMPLE/BICUBIC, `combine_hdr`, `passthroughsrgb`) | Downsample pyramid (up to `levels` from min(w, h)), bicubic upsample with `scatter`, strength/(1 + scatter^(n−2)), combine and encode | Keys `bloomhdrstrength`, `scatter`, `blend`, `bloomtint`; level rule; RGBA16F everywhere (LR8) | Tile-based upsample+combine fusion (invisible if parity holds); "Enhanced bloom" as above | LR5 (prelit RGBA8, fixed), LR7 (`bloomhdr*` not live) | Compute pyramid, half storage | M | SceneHDRChain/Material, 3606529469 and 3352730400 captures |
| **ccsimple** | 3D LUT lookup (32³ strip) plus brightness/contrast/saturation params | `lutparams`, `params`, `lut/<name>` names | Tetrahedral LUT interpolation: **OFF** | — | 3D texture instead of strip (invisible) | S | SceneColorCorrectionTests |
| **volumetricsback / volumetricsfront / blur_k3 / combine** | Back-face depth of light volumes, front-face ray march (point/spot, cookie, shadow-map test, `QUALITY` steps, fog), 3-tap blur, additive combine | Combos FULLSCREEN, POINTLIGHT, COOKIE, SHADOW, QUALITY, FOG, REVERSEDEPTH; light fields | Blue-noise jittered march + temporal accumulation: **OFF** | LR20/21 (draw order, script cameras) | Compute ray-march at reduced size into a memoryless target | M | SceneVolumetricsTests, 3352730400 `vol_*`, 3159348391/3378346807/3455121165 `*_volHigh`/`volOff` |
| **generic4 (+ generic2, foliage4, fur4) with model_*_v1** | PBR mesh shading: GGX, Fresnel-Schlick, Smith; shadow atlas (PCF), point shadows, cookies; rim light, shading gradient, tint mask, morphs, skinning; foliage wind; fur shells (`INSTANCECOUNT`) | Material keys listed in §1.1; combos FOG, LIGHTING, REFLECTION, RIMLIGHTING, SHADINGGRADIENT, TINTMASKALPHA, ADDITIVE, MORPHING(_NORMALS), SKINNING, foliage/fur keys; `g_Bones` (mat4x3), `g_MorphOffsets/Weights` | (a) Multi-scattering GGX energy compensation: **OFF**. (b) PCSS soft shadows: **OFF**. (c) Specular anti-aliasing (Toksvig): **OFF** | GP1 (3734636606 cloth darker; investigate while porting), GP5 (ADDITIVE not set) | Half for BRDF terms where parity holds; argument-buffer bone palette | L | ModelRender, ModelSkinning, SceneShadow*, 3D captures `shadowsHigh_t10`/`shadowsOff_t10` (2350874185, 3159348391, 3378346807, 3455121165, 3657770939, 3734636606) |
| **shadowcaster (+ foliage4, fur4 variants)** | Depth-only pass with skinning, morph and alpha test | Combos BONECOUNT, MORPHING, MORPHING_NORMALS, SKINNING; `// [PASS] shadow` redirection | — | LR22 (casters show only with shadows off) | Depth-only pipeline, no fragment function where there is no alpha test (invisible) | S | SceneShadowTests |

### 2.3 Effects

**Reading the table.**
- "Uses" = wallpapers / instances in the library.
- "Gallery" = the reference capture's mean abs diff from the control / mean motion. Captures are under `/Volumes/980Pro/dd-agentREF/peer/tools/peer/effect_gallery/captures/<effect>.png|.mp4`.
- **Tolerance.** Tolerance is `WEEffectGallery` (diff within max(2, 0.25·diff), motion within max(0.35, 0.4·motion)) **plus** no regression against the translated baseline: SSIM ≥ baseline − 0.01, mean abs ≤ baseline + 0.5.
- **Interface.** Every effect keeps:
  - its `effect.json` passes, FBOs (`name`, `scale`, `format`, fixed `width`/`height`, `uvs`) and binds;
  - its material files' names and render state;
  - every uniform name, material key, default and range, and every combo, as listed in §2.4.

| Effect | Uses | Technique | Passes / FBOs | Improvements | Quirks and bugs | Apple-GPU | Effort | Gallery |
|---|---|---|---|---|---|---|---|---|
| **shake** | 31 / 263 | Flow-map (`util/noflow`) driven UV oscillation with friction, bounds, speed; audio drive (AUDIOPROCESSING, frequency band min/max, power, bounds); NOISE; DIRECTION; TIMEOFFSET phase mask | 1 / 0 | — | Older local versions (no TIMEOFFSET, white phase default, `flowPhase` term): **profile** (§3.3) | Fuse with neighbours (§3.7) | S | 0.00 / 0.01 |
| **waterwaves** | 24 / 106 | Sine UV displacement along direction, `pow` sharpness (exponent), DUALWAVES second wave, PERSPECTIVE homography, TIMEOFFSET | 1 / 0 | — | 3 older local copies | fuse | S | 8.02 / 7.44 |
| **pulse** | 17 / 27 | Brightness/tint pulse from sin(time·speed + phase) or the audio spectrum band, thresholds (bounds), noise modulation; PULSECOLOR/PULSEALPHA; blend 9 | 1 / 0 | — | `g_PulsePhase` declared [0,1] and [0,6.282] in different stages (§2.4); 8 older copies with a different audio path; FX4 motion lower | fuse | S | 19.10 / 4.18 |
| **foliagesway** | 14 / 27 | Noise-driven sway weighted by corner weights and bounds (MODE UV/Vertex) | 1 / 0 | — | Stage-divergent `g_Speed` (`speed` 1 vs `speeduv` 5) and `g_Phase` (0 vs 0.5): keep both (audit §8) | fuse | S | 7.07 / 2.46 |
| **blend** | 8 / 20 | Up to 6 extra textures blended by `ApplyBlending` (NUMBLENDTEXTURES, BLENDMODE default 2), UV transform (TRANSFORMUV/REPEAT), WRITEALPHA, OPACITYMASK | 1 / 0 | — | 7 older copies (no `require` in combos) | — | S | 0.00 / 0.01 |
| **nitro** | 8 / 28 | Two scrolling `clouds_256` layers (speeds, scales, LOD) thresholded into a colour ramp within bounds; blend 22 | 1 / 0 | Mipmapped noise: **OFF** (see filtering) | — | — | S | 2.90 / 5.01 |
| **blur** | 7 / 9 | 4×4 box downsample to 1/4, separable Gaussian 13/7/3 taps (KERNEL), combine with COMPOSITE (normal/blend/under/cutout), COMPOSITEMONO, BLENDMODE, BLURALPHA, MASK | 4 / 2 (¼, `rgba_backbuffer`) | **Precise blur OFF:** full-resolution or dual-filter with correct σ, bicubic upsample; radius independent of layer size | 2–3 older copies | One compute pass: threadgroup-memory separable blur, downsample fused | M | 10.75 / 0.00; composites normal 10.73, blend α0.5 3.47, α1.5 19.27, under 0.00, cutout 82.18 |
| **opacity** | 6 / 28 | alpha × `g_UserAlpha` × mask | 1 / 0 | — | 1 older copy | fuse | S | 0.00 / 0.01 |
| **godrays** | 6 / 8 | Bright/threshold cast (CASTER) → ½ downsample → radial blur towards `center`/`direction` (SAMPLES) → Gaussian (KERNEL) → combine with noise (NOISE, `clouds_256`) and blend 9 | 5 / 2 | Precise blur (as blur) | 2 older copies | Compute radial blur | M | 24.91 / 0.15 |
| **waterripple** | 6 / 8 | Scrolling normal map (`waterripplenormal.png`) → refraction offset; SPECULAR (a `COMBO_OFF`); PERSPECTIVE | 1 / 0 | — | 1 older copy; `g_Direction` range declared differently per stage | fuse | S | 10.50 / 3.50 |
| **waterflow** | 6 / 7 | Flow-map advection with two phases cross-faded (phase texture, feather) | 1 / 0 | — | 4 older copies | fuse | S | 0.00 / 0.01 |
| **iris** | 6 / 36 | Radial UV scale inside a masked circle with noise wobble (rough), BACKGROUND | 1 / 0 | — | — | fuse | S | 1.84 / 1.17 |
| **blurprecise** | 5 / 7 | Full-res separable Gaussian (`blur13a/7a/3a`) × scale | 2 / 1 | Precise blur | 3 older copies | Compute separable | S | 2.82 / 0.00 |
| **shine** | 5 / 20 | Edge/threshold cast (EDGES) → ½ → directional streak blur (SAMPLES) → Gaussian → combine with noise; blend 9 | 5 / 2 | Precise blur | 2 older copies | compute | M | 38.00 / 0.19 |
| **vhs** | 5 / 16 | Scanline jitter, tracking band, chromatic shift, noise bands (`util/noise`), GREYSCALE, INVERTARTIFACTS; blend 12 | 1 / 0 | — | 5 older copies | — | S | 2.52 / 0.78 |
| **localcontrast** | 5 / 6 | Unsharp mask at a large radius: ¼ downsample, Gaussian, combine by `strength`, GREYSCALE | 4 / 2 | Precise blur | — | compute | S | 0.39 / 0.01 |
| **tint** | 4 / 11 | `ApplyBlending(30, color)` × alpha × mask | 1 / 0 | — | — | fuse | S | 79.91 / 0.00 |
| **lightshafts** | 4 / 4 | Procedural rays inside a 4-point perspective quad: angular noise, feather, radius, colour start/end or the `gradient_iridescent` map (RENDERING), RAYMODE/RAYCORNER | 1 / 0 | — | PG3 fixed (a shape object's `DIRECTDRAW` and square size) | — | M | 1.75 / 0.06 |
| **transform** | 3 / 11 | Affine UV (offset, scale, angle), CLAMP, MODE | 1 / 0 | — | 2 older copies | fuse | S | 0.00 / 0.01 |
| **perspective** | 3 / 12 | `squareToQuad` homography of 4 points, REPEAT | 1 / 0 | — | — | fuse | S | 0.00 / 0.01 |
| **chromaticaberration** | 3 / 3 | Per-channel radial (MODE) or directional offsets with centre falloff, VARIATION | 1 / 0 | — | — | — | S | 5.33 / 0.00 |
| **scroll** | 3 / 3 | UV scroll × repeat | 1 / 0 | — | — | fuse | S | 58.32 / 18.76 |
| **swing** | 2 / 18 | Pendulum rotation of a region between two points about a centre, feather, noise, DOUBLESIDED | 1 / 0 | — | — | fuse | S | 1.45 / 0.89 |
| **xray** | 2 / 3 | Pointer-centred reveal of texture 1 through a halo sprite (`particle/halo_6`), size, multiply | 1 / 0 | — | FX1 (pointer y, projection: no capture) | — | S | 0.00 / 0.01 |
| **depthparallax** | 2 / 3 | Parallax-occlusion ray march in a depth map (`g_Texture1`, default black) driven by the pointer, QUALITY steps | 1 / 0 | Relief-mapping binary refinement: **OFF** | — | — | M | 33.32 / 0.00 |
| **fluidsimulation** | 2 / 2 | Stable fluids: advection, curl, vorticity confinement, divergence, pressure Jacobi, gradient subtract; point/line dye emitters, cursor force, collision mask, PBR shading of the dye (`common_pbr_2`) | 20 / 9 | Higher pressure-iteration count / red-black Gauss-Seidel: **OFF** | 2 older copies of `vorticity`; stage-divergent `lineEmitterSize*` ranges | Compute with threadgroup Jacobi; half velocity | L | 3.22 / 0.70 |
| **clouds** | 2 / 2 | Two scrolling `clouds_256` octaves (scales, speeds), threshold/feather, LOD bias, directional shading, colour ramp, PERSPECTIVE, WRITEALPHA | 1 / 0 | Mipmapped noise: **OFF** | `g_CloudSpeeds` is vec2 in one stage and vec4 in the other | — | S | 39.66 / 0.91 |
| **filmgrain** | 2 / 2 | Per-frame offset `util/noise` sample, power, scale, blend 12 (soft light), GREYSCALE | 1 / 0 | — | FX2 (ours: spread 0.66 of the reference; check against the new noise texture) | — | S | 3.31 / 0.69 |
| **cloudmotion** | 2 / 2 | UV displacement by scrolling `perlin_256` along direction, granularity | 1 / 0 | — | 1 older copy | fuse | S | 35.98 / 0.92 |
| **watercaustics** | 2 / 3 | Animated voronoi caustics (`pattern/voronoi_local`, `voronoi`, `uniform_256`, `perlin_256`), chromatic split, blur, glow, PERSPECTIVE, MODE; blend 32 | 1 / 0 | Analytic caustics (no textures): **OFF** | 1 older copy | — | M | 2.64 / 0.66 |
| **fire** | 1 / 1 | Flow-mapped cloud distortion into a two-colour ramp, REFRACT | 1 / 0 | — | 1 older copy | — | S | 0.00 / 0.01 |
| **reflection** | 1 / 2 | Mirrored copy about a direction line with offset/alpha, PERSPECTIVE | 1 / 0 | — | — | — | S | 57.05 / 0.00 |
| **refraction** | 1 / 2 | Normal-map (`refractnormal.png`) screen refraction × strength/scale | 2 / 0 | — | Normal map beside the material (audit §8, fixed) | — | S | 17.66 / 0.01 |
| **cursorripple** | 1 / 1 | Pointer force injection → wave-equation simulation in ping-pong FBOs (persist across frames) → refraction, shading, REFLECTION, PERSPECTIVE | 3 / 2 | Frame-rate-independent step: **OFF** | FX1 (no pointer capture) | Compute simulation | M | 0.00 / 0.01 |
| **fisheye** | 1 / 1 | Barrel distortion around centre within size, BACKGROUND | 1 / 0 | — | — | fuse | S | 35.92 / 0.01 |
| **shimmer** | 1 / 2 | Moving highlight band through the `gradient_ferro_fluid` map, delay/width/angle/offset, OFFSET mask; blend 32 | 1 / 0 | — | FX4 motion lower | — | S | 0.00 / 1.48 |
| **glitter** | 1 / 1 | Fixed 256² sparkle tile (`_rt_GlitterTiles`, `uvs: repeat`) from `perlin_256`, then view/time-dependent sparkle | 2 / 1 | — | — | — | S | 2.76 / 1.47 (statistics) |
| **motionblur** | 0 | Temporal accumulation: mix(previous, current, rate) in a persistent FBO; combine | 3 / 2 | **Frame-rate-independent rate OFF** (the per-frame mix makes trails depend on fps; verify during the port) | `carriesFrames` (audit §8) | — | S | 0.00 / 0.01 |
| **blurradial** | 0 | Single-pass zoom blur towards the centre, 13/7/3 samples | 1 / 0 | Precise blur | — | — | S | 14.64 / 0.00 |
| **colorkey** | 0 | Chroma key: RGB distance to the key colour with tolerance/fuzziness, INVERT, FLATTEN | 1 / 0 | — | — | fuse | S | 50.98 / 0.00 |
| **edgedetection** | 0 | Sobel on luminance, threshold × multiply, two outline colours, blend | 1 / 0 | — | — | — | S | 99.16 / 0.01 |
| **blendgradient** | 0 | Gradient-map blend from `clouds_256` luminance with edge glow, UV transform | 1 / 0 | — | — | — | S | 99.37 / 0.00 |
| **skew** | 0 | Per-edge skew offsets, MODE, REPEAT | 1 / 0 | — | — | fuse | S | 0.00 / 0.01 |
| **spin** | 0 | Rotation of a circular/elliptical region with feather, noise, friction | 1 / 0 | — | — | fuse | S | 2.20 / 0.64 |
| **twirl** | 0 | Swirl distortion with angular falloff, INNER, ELLIPTICAL, noise | 1 / 0 | — | — | fuse | S | 48.73 / 24.76 |
| **_empty** | 0 | Identity | 1 / 0 | — | — | — | S | — (parity only) |

The four `user_*` gallery projects (cloud1, irism, pulse, scrol) are editor-authored scenes over these effects and stay in the gallery run.

### 2.4 Interface details the ports must reproduce

These come straight from the reference's declarations and are easy to lose:

- **Stage-divergent declarations.** When the two stages declare a uniform differently, the fragment copy is `<name>_weFragment` (translator revision 8). Native manifests list both, so `ShaderConstantResolver` keeps resolving each from its own annotation. Cases:
  - foliagesway: `g_Speed` is `speed` 1 vs `speeduv` 5; `g_Phase` is 0 [0, 6.28] vs 0.5 [0, 2];
  - pulse: `g_PulsePhase` ranges;
  - clouds: `g_CloudSpeeds` is vec2 vs vec4;
  - waterripple: `g_Direction` range;
  - fluidsimulation: `lineEmitterSize*` ranges.
- **Material keys that are localisation-looking strings are still keys.** chromaticaberration uses `ui_editor_properties_center`, `…_strength`. cloudmotion, shimmer and watercaustics use `ui_editor_properties_*`. Scenes store values under those exact keys, so they stay verbatim. Only *labels* may become ours.
- **`COMBO_OFF`** (waterripple SPECULAR) and `require` blocks (newer blend copies) keep their semantics.
- **Default textures by name:**
  - `util/white`, `util/black`, `util/noise`, `util/noflow`, `util/perlin_256`, `util/clouds_256`, `util/uniform_256`;
  - `pattern/voronoi(_local)`;
  - `gradient/gradient_fire`, `gradient_iridescent`, `gradient_ferro_fluid`;
  - `particle/halo_6`;
  - `_rt_FullFrameBuffer`, `_rt_shadowAtlas`, `_alias_lightCookie`.
- **Fixed attribute locations and varyings.** The same locations as `ShaderPairRewriter`: `a_Position` 0, `a_TexCoord` 1, `a_Normal` 2, `a_Tangent4` 3, `a_Color` 4, `a_BlendIndices` 5, `a_BlendWeights` 6, …, `a_PositionC1` 11. `g_TextureN` is at texture/sampler N.
- **Pointer and projection.** `g_PointerPosition` is y-down. `g_EffectTextureProjectionMatrix` is as `EffectGraphRenderer.effectTextureProjection` (audit §8).

### 2.5 Shared GLSL headers (our GLSL, for the translator)

| Header | Technique | Must match | Effort |
|---|---|---|---|
| `common.h` | HSV/RGB, 2D rotation, luma | constants and luma weights | S |
| `common_blending.h` | Photoshop-style separable and non-separable blend modes; HSL helpers | The **mode numbering** of `ApplyBlending` and each formula's clamp behaviour. It is pinned by `WEImageBlendModesTests` and the extras' `solidblend_*` (0.20–0.27) | M |
| `common_perspective.h` | Unit square → quad projective map; 3×3 inverse | results to 1e-5 | S |
| `common_blur.h` | Fixed-weight 13/7/3-tap Gaussians (linear and radial) | the weights as effective behaviour (the σ the taps realise); verified by pixel parity | S |
| `common_composite.h` | Composite modes normal/blend/under/cutout with offset/colour | the composite captures | S |
| `common_fragment.h` | Normal decompression (incl. RG88/DXT5nm), Blinn-Phong helpers, texture-format conversions per `FORMAT_*` | the format constants' values | S |
| `common_vertex.h` | Tangent frames | — | S |
| `common_fog.h` | Distance and height fog | fog params layout | S |
| `common_pbr.h`, `common_pbr_2.h` | GGX/Smith/Schlick, point/spot/tube lights, shadow atlas and cascades, point shadows, cookie projection, `CombineLighting` overloads | LightingV1 behaviour; 3D captures | M |
| `common_particles.h` | Billboard tangents, trails, sprite frames, screen refraction | particle gallery | S |
| `common_foliage.h`, `base/model_vertex_v1.h`, `base/model_fragment_v1.h` | Wind animation, skinning/morph/position helpers, reflection, alpha-to-coverage | model captures | M |

**Verification for all headers:**
1. **While working:** the targeted set in §6.4 (P3). That is the per-header wallpaper list and the header test classes, with old-header versus new-header render parity on those wallpapers and a gallery `_ONLY` subset. Thresholds are as in §3.6.
2. **When all headers are done** (a whole system, §6.5): every local shader in the library (54 scenes plus the Asset items) and every `Tests/Fixtures` shader translates with zero new failures in `LibrarySweepTests` and `ImageMaterialSweepTests`/`Particle`/`Model` sweeps. The full WEReference run follows.
3. Bump `ShaderVariantTranslator.revision`: the inlined text changes, and `ShaderVariantCacheTests` enforces the bump.

## 3. Architecture

### 3.1 Two backends, one interface

`TranslatedShaderVariant` today is the unit every renderer consumes: MSL text, `UniformLayout`, texture slots, attributes and combos. It generalises to a **`ShaderProgramVariant`** with a backend:
- **`.translated(vertexMSL, fragmentMSL)`:** today's path. Workshop custom shaders and unrecognised local copies always use it. It stays as it is, with its cache, `revision`, the in-process glslang/SPIRV-Cross toolchain and the process fallback.
- **`.native(program, profile, functionConstants)`:** functions come from the app's precompiled `default.metallib`. Specialisation happens through `MTLFunctionConstantValues`.

Both carry the same `UniformLayout`, texture slots and attribute map. So these stay unchanged:
- `EffectGraphRenderer`'s `UniformProgram`, `UniformWriter` and `BuiltinUniforms`;
- `ShaderConstantResolver`;
- the inspector;
- the plan builders.

The only branch is in each renderer's `makePipeline`: `makeLibrary(source:)` versus `defaultLibrary.makeFunction(name:constantValues:)`. The renderers that branch are Effect, Image, Particle, Model, Shadow, Puppet, Volumetrics and CameraFade. `ParticleMaterialRenderer` also joins the pipeline archive at this point; it doesn't use it today.

**New code**, owned by P0:
- `Scene/Shaders/Native/` (Swift):
  - `NativeShaderCatalog`;
  - `NativeProgramManifest`;
  - `ShaderInterface`, a common protocol over the GLSL-annotation parser and the manifest;
  - `NativeVariantResolver`;
  - `ShaderBackendPolicy`.
- `Scene/Shaders/Native/Metal/` (`.metal` + `.h`): compiled into the app target. This folder is inside the synced app folder on purpose, unlike the folder reference that keeps shipped data from compiling.

### 3.2 Manifests: the interface as data

- Each native program has `Scene/Shaders/Native/Manifests/<program>.json`, bundled as a resource.
- The manifest uses the annotation schema the loader already understands: `material`, `label`, `default`, `range`, `type`, `options`, `combo`, `mode`, `components`, `formatcombo`, `hidden`, `require`.
- The manifest's fields:
  - `uniforms`: per stage, so stage divergence is representable;
  - `combos`: name, default, options, and the function-constant index;
  - `textures`: slot, default, combo, mode;
  - `attributes` and `varyings`;
  - `stages`: MSL function names per stage and optional geometry/mesh stage;
  - `profiles`: §3.3.
- `ShaderInterface` returns the same `ShaderUniformDeclaration`/combo records whether they come from GLSL comments or a manifest. `SceneEffectParameters.sources` (the inspector) and every plan builder then read either source.
- **Uniform layout.** A generator (`Scripts/native-shaders/gen-uniforms.swift`, run by hand; output checked in) turns each manifest into:
  - an MSL header `Native<Program>Uniforms.h` with an explicit `struct` in std140-compatible offsets;
  - the Swift `UniformLayout` table.

  `UniformWriter` then fills native buffers by name, exactly as it does now. A test fails when the generated files are stale.
- **Argument buffers.**
  - Uniforms stay a constant buffer at index 0 (bound through `SceneUniformArena`, as now).
  - Textures and samplers move to one Tier-2 argument buffer per pass. It is a `struct { texture2d<half> t[N]; sampler s[N]; }` written with `gpuResourceID`s, with `useResource` for residency.
  - This is a later step inside P0 (P0b). It changes no pixels and removes per-slot `setFragmentTexture` calls in long effect chains.

### 3.3 Recognising local copies: fingerprints and profiles

A wallpaper's local `shaders/effects/shake.frag` is authoritative (WE-faithful). To run it natively:

1. **Normalise:** strip comments and whitespace from the vertex and fragment text, after including headers by name (not by content).
2. **Hash:** SHA-256 of `stage\0normalised` per stage, then the pair.
3. **Look up** `Scene/Shaders/Native/Fingerprints.json`: `{ pairHash: { program, profile } }`. It contains hashes only, never source.
4. **Hit:** use the native program with that profile. The *interface* is still parsed from the local file's own annotations (older copies declare different defaults, e.g. shake's white phase texture). This works because the native program accepts the superset of uniforms and combos.
5. **Miss:** translate as today. `LibrarySweepTests` gains a coverage line: native / translated counts per effect, so the drift is visible.

**Profiles** cover behavioural differences between versions (e.g. `shake@v1` has no `TIMEOFFSET` and adds `flowPhase`). They are function constants too. So one native shader serves several versions, and each profile needs its own parity test against that version's GLSL.

**Building the table:** `Scripts/native-shaders/fingerprint.py` is dev-only.
- It reads the current reference files and every local copy in a library folder, and prints hash → (effect, file set) groups. A person assigns each group a profile.
- It is not run at build time and ships nothing but hashes.
- Starting point: the current version (445 files), plus the ~20 distinct older versions behind the 111 differing files. Those are shake, pulse, blend, vhs, waterwaves, waterflow, godrays, shine, blur, blurprecise, transform, xray, fire, waterripple, cloudmotion, caustics and fluid vorticity.

**Engine shaders** don't need fingerprints. Wallpapers never ship them, so a material naming `genericimage4` resolves to the native program unless the wallpaper itself ships `shaders/genericimage4.*`. In that case the wallpaper wins and is fingerprinted like effects.

**Resolution order** for a shader name:
1. zcompat replacement;
2. the wallpaper's own files (→ fingerprint → native or translated);
3. the native catalog;
4. the external assets folder (§5; translated);
5. nothing: logged, the plan fails as today.

### 3.4 Combos as function constants

- Each combo gets `constant int NAME [[function_constant(k)]]`. `k` comes from the manifest (stable per program; never reuse an index).
- Absent combos take the manifest default through `is_function_constant_defined`.
- Boolean-style combos become `bool` constants derived in the shader (`constant bool HAS_MASK = MASK != 0;`), so dead code is eliminated.
- **Effective-combo filtering stays.** Only combos the program declares, or that its profile needs, enter the key. The key is `native|<program>|<profile>|NAME=v…` (sorted), which keeps the variant count bounded like today's.
- **Arrays sized by combos** (blur's `v_TexCoord[13|7|3]` for KERNEL) become a fixed max-size array with a loop bound on a function constant. The compiler specialises and unrolls it.
- **Engine combos** (`LIGHTS_*`, `HDR`, `SCENE_ORTHO`, `REVERSEDEPTH`, `GS_ENABLED`, `TEX<n>FORMAT`, `SPRITESHEET*`) are just more constants, filled by the existing `SceneEngineCombos` and the builders' override layers.
- **`#require LightingV1`** becomes a native include of our lighting functions, selected by the same `LIGHTS_*` constants.

### 3.5 Caching and pipeline archives

- **Native functions** are compiled at build time into `default.metallib`. Runtime compile of native programs is specialisation only: fast, and cached by the OS shader cache.
- **`EffectPipelineArchive`** takes native pipeline descriptors as well (bump its `revision` to 3). The archive key already includes GPU, OS and app build, so a new metallib invalidates it.
- **Optional (P0c):** harvest the pipeline set of the gallery, the extras and a library sweep with `metal-tt`/offline binary archives for the Apple GPU families, and ship them. This removes first-load stalls. It is a performance-only step with no visual change.
- **The translation cache** (`shader-variants/r<rev>-…`) is untouched for Workshop shaders. The header rewrite bumps `ShaderVariantTranslator.revision` once (P3).
- **Warm-up:** the plan builders already know every variant at load. The native pipelines are requested asynchronously there (`compileQueue`), as now.

### 3.6 Migration: both backends side by side, gated

- **`ShaderBackendPolicy`** is per wallpaper instance and injected, never global. Its modes:
  - `.translated`;
  - `.native`;
  - `.preferNative`: native where the catalog has a *shipped* program, else translated. This is the default.
  - `.compare`: debug only. It renders both backends and logs per-pass mean/max difference once per variant.
- **Developer switch:** the launch argument `-OWEShaderBackend translated|native|compare`, read through `UserDefaults.app` so isolated test runs honour it. There is no user-facing setting.
- **Shipping a program:** each program is added to `NativeShaderCatalog.shipped` in the same commit that lands its parity tests. So a half-ported effect never reaches users.
- **Regression gate:** `NativeParityTests` (new, per program), run in CI:
  - **Inputs:** fixture textures (checkerboard, HSV gradient, a grey ramp, an HDR ramp to 8.0, alpha edges), fixed `g_Time` ∈ {0, 1.37, 5, 100.5}, and fixed pointer positions.
  - **Combo matrix:** defaults; each combo value one at a time; pairwise for LIGHTING × REFLECTION × FOG on image and model programs; every profile.
  - **Comparison:** the translated variant of the *reference GLSL* against the native variant, rendered by the same renderer into the same format.
  - **Thresholds:** LDR RGBA8 max ≤ 2/255 and mean ≤ 0.3/255; RGBA16F relative ≤ 1e-3 (absolute 1e-3 below 1.0); depth ≤ 1e-5.
- **Goldens.**
  - While the reference tree is still in the repository (until P17), the gate compares live.
  - At P17 the translated outputs become `Tests/Fixtures/NativeParity/<program>/<case>.png|.exr` goldens: 256², about 5–10 MB total. They are our renders of test patterns, not reference files.
  - The optional live compare remains against a local install via `OWE_WE_INSTALL`.
- **Capture harnesses** are the acceptance test. They compare against captures, so they are independent of the reference files.
  - Each package runs them **only for its own subset**, through the harness's `_ONLY` variable (§6.4), with `translated` and `native`. Both reports are kept in the package's PR.
  - The full harness runs happen only at a whole-system milestone (§6.5).
  - The no-regression rule applies (per harness):

  | Harness | Rule |
  |---|---|
  | `OWE_EFFECT_GALLERY` | gallery tolerances, SSIM ≥ baseline − 0.01, mean abs ≤ baseline + 0.5 |
  | `OWE_WE_EXTRAS` | mean abs ≤ baseline + 0.3 |
  | `OWE_PARTICLE_GALLERY` | coverage and motion within the harness tolerances and within ±5 % of baseline |
  | `OWE_WE_REFERENCE` | score (meanAbs + 50·(1 − SSIM)) ≤ baseline + 0.5 per cell |

  Captures live under `/Volumes/980Pro/dd-agentREF/peer/tools/peer/`: `effect_gallery/{captures,extras}`, `particle_gallery/{captures,elements}`, `light_test/captures`, and the per-scene folders (default, puppet5s, `shadows*`, `vol_*`, `texres_*`).
- **Build and test runs** go on a `git archive` in `/Volumes/980Pro/dd-agentOA-src` with derived data in `/Volumes/980Pro/dd-agentOA`, one at a time.

### 3.7 Architecture-level performance that is invisible by construction

- **Effect-chain fusion.** A run of single-pass, FBO-free effects on one layer compiles into one native pass that composes the per-effect functions. Each effect is a `sample → UV remap / colour op` function over the previous result. This applies to shake → waterwaves → pulse → opacity, where shake alone has 263 instances.
  - Fusion removes the 8-bit quantisation between passes, so it can differ by ≤ 1–2/255.
  - It ships ON only if the parity gate holds on the library's actual chains (`LibrarySweepTests` renders them both ways). Otherwise it becomes the OFF option "Fused effect chains". Either way it lands last (P16).
  - It needs the UV-remap effects expressed as "sample the previous result at a remapped UV", which is exactly their structure.
- **In-tile blend-mode compositing** for image layers (§2.2).
- **Compute downsample pyramids** for bloom/HDR/blur; memoryless intermediates.

## 4. Replacing the non-shader assets

### 4.1 Fonts

#### 4.1.1 Fonts that the bundled set and wallpapers reference

- **What "matches" means.** Our layout follows the reference's FreeType size metrics (`TextLayout.swift`): ascender rounded up, descender rounded down, line height `asc − desc + lineGap` rounded to nearest, all from the font's `hhea` table.
- **The metrics that must match** are therefore `unitsPerEm`, `hhea.ascender`, `hhea.descender`, `hhea.lineGap`, and the advance widths.
- **The check:**
  - `FontMetricsParityTests` reads each bundled font and asserts our `ascent`/`descent`/`lineHeight` at 64 pt and 17 pt against a table.
  - The table is the reference file's hhea values, recorded by the dev-only `Scripts/fonts/measure.py` before the swap. NotoSans at 64 pt: 286 / −79 / 363.
  - Then the extras `text_*` captures (mean abs ≤ baseline + 0.3) and `SceneTextLayoutTests`.

| File (name kept) | Family | Upstream | Licence | Bundle? | Version / metrics |
|---|---|---|---|---|---|
| `NotoSans-Regular.ttf` | Noto Sans | github.com/notofonts/latin-greek-cyrillic | OFL 1.1 | **Yes** | Ours 2.000 (2017); upstream 2.015 (2024). Upstream documents asc 1069 / desc −293, the same as ours. **Measure the static Regular from the release** (not the Google Fonts variable file, whose default instance may differ); the glyph set grew. The fallback is to pin 2.000 from the notofonts history (also OFL). |
| `RobotoMono-Regular.ttf` | Roboto Mono | github.com/googlefonts/RobotoMono | OFL 1.1 (was Apache 2.0; our 3.000 file was Apache) | **Yes** | 3.001 upstream is variable only. Take the static 3.000 Regular from the upstream release tag, or instance the variable file at wght 400 and verify hhea 2048/2146/−555/0. |
| `8bitOperatorPlus8-Regular.ttf` | 8-bit Operator+ 8 | Grand Chaos Productions (Jayvee D. Enaguas) | OFL 1.1 (RFN "8-bit Operator+") + CC-BY-SA 4.0 | **Yes** (unmodified; ship OFL text) | 1.2.0 (2014), the latest; unchanged |
| `Blackout 2 AM.ttf` | Blackout 2AM | The League of Moveable Type, github.com/theleagueof/blackout | OFL 1.1 | **Yes** | 2.003; the same file upstream |
| `Segment7Standard.otf` | Segment7 | fontlibrary.org/en/font/segment7 (Cedric Knight) | OFL 1.1 | **Yes** | single 2014 release |
| `Monofur-PK7og.ttf` | monofur | Tobias B. Köhler (original site gone; licence mirrored in github.com/chrissimpkins/codeface) | Freeware, "distributed as long as they are together with this text file" | **Yes, with its readme next to it** | 1.0 (2000); unchanged. Rename the file to `monofur.ttf` and keep an alias for the referenced name `fonts/Monofur-PK7og.ttf` (6 scenes) in the resolver's name table. |
| `TwemojiMozilla.ttf` | Twemoji Mozilla | github.com/mozilla/twemoji-colr | Artwork CC-BY 4.0; build Apache 2.0 | **Yes** (CC-BY credit in the licence file only, not in the UI) | 0.4.0 → 0.7.0 (Emoji 14). Keep 0.4.0 metrics (upm 512, 475/−91/46) or verify 0.7.0's. |
| `Alcubierre.otf` | Alcubierre | Matt Ellis / Ellis Design | Freeware; sources conflict on commercial use | **Needs written permission** | 2–3 scenes reference it |
| `Atami-Regular.otf` | Atami | Andrew Herndon (Behance/Gumroad) | Conflicting; one text forbids redistribution without permission | **Needs written permission** | 2 scenes (8 layers) |
| `CursedTimerUlil-Aznm.ttf` | Cursed Timer ULiL | Heaven Castro (FontSpace) | "Freeware"; fan-work origin | **Needs permission** | 0 scenes |
| `Lazer84.ttf`, `summer85.ttf` | Lazer 84, Summer 85 | Lazer Visuals (Juan Hodgson), lazervisuals.com. The old sunrise-digital.net domain now redirects to an unrelated site; don't use it. | Labelled OFL but "free for personal use" with pay-what-you-want for commercial use | **Needs permission** (or purchase) | 0 scenes |
| `kust.ttf` | Kust | WildType, wildtype.design | Free for personal and commercial use per summaries; app bundling not addressed | **Needs permission** | 0 scenes |
| `opensticks.ttf` | OpenSticks | Apocalypse Laboratories (FontSpace) | "Free for commercial use"; redistribution not granted | **Needs permission** | 0 scenes |
| `spincycle_3d_ot.otf` | Spin Cycle 3D OT | BV Fonts (Jess Latham), bvfonts.com/tou.php | Free for personal/commercial *use*; forbids including in compilations | **Needs permission** (leaning no) | 0 scenes |

**Fonts we can't bundle.** When a wallpaper references a font we have no permission for:
1. **Try the resolution order of §4.1.3 first:** the wallpaper, then an installed copy by family/PostScript name. Users who own the font get it.
2. **Otherwise fall back** to a bundled font of the same *class*, chosen per file in a small table. For Atami and Alcubierre that is a geometric display sans (Orbitron / Space Grotesk). This is logged once per wallpaper.
3. **Permission requests** are the coordinator's decision (§7 D1). Only Alcubierre (2–3 scenes) and Atami (2) matter for the current library.

**Windows `systemfont_*` names** (arial 4 scenes, cambria 2, calibri 1). Arial ships with macOS. For the two that don't, bundle metric-compatible OFL/Apache faces:
- **Carlito** (OFL; metric-compatible with Calibri);
- **Caladea** (Apache 2.0; metric-compatible with Cambria).

This replaces today's Georgia/Helvetica Neue aliases, fixes the "fallback font" half of GP2, and moves the default output *towards* the captures, so it is ON. Sizes: Carlito Regular about 600 KB, Caladea about 100 KB (estimates; measure).

#### 4.1.2 The curated set shipped with the app

All are OFL 1.1 from Google Fonts / upstream repos. Sizes are the Google Fonts files. We ship the upstream variable file where one exists, so every weight costs one file.

| Look | Family | Why | Source | Size |
|---|---|---|---|---|
| Clean sans | **Inter** | Screen-optimised UI sans; huge weight range; excellent at clock/date sizes | github.com/rsms/inter | 877 KB (opsz, wght) |
| Geometric | **Montserrat** | The most-requested geometric sans for titles; wide Latin/Cyrillic | github.com/JulietaUla/Montserrat | 745 KB (wght) |
| Display / condensed | **Oswald** | Condensed display with weights (Bebas Neue is caps-only at one weight) | github.com/googlefonts/OswaldFont | 172 KB |
| Display caps | **Bebas Neue** | The standard poster/clock face; tiny | github.com/dharmatype/Bebas-Neue | 61 KB |
| Serif | **Playfair Display** | High-contrast editorial serif for quotes and titles | github.com/clauseggers/Playfair | 301 KB |
| Text serif | **Lora** | Calm text serif for longer lines | github.com/cyrealtype/Lora-Cyrillic | 212 KB |
| Mono | **JetBrains Mono** | Clear monospace for terminal/system-monitor wallpapers | github.com/JetBrains/JetBrainsMono | 187 KB |
| Sci-fi / tech | **Orbitron** | Geometric futuristic caps; the go-to HUD face | github.com/theleagueof/orbitron | 39 KB |
| Tech grotesque | **Space Grotesk** | Modern tech grotesque, less extreme than Orbitron | github.com/floriankarsten/space-grotesk | 137 KB |
| Handwriting | **Caveat** | Natural handwriting, legible at size | github.com/googlefonts/caveat | 404 KB |
| Library-driven | **Rajdhani**, **Quicksand**, **Oxanium** | Library wallpapers use them (they ship them too); bundling makes them pickable | itfoundry/rajdhani, andrew-paglinawan/QuicksandFamily, sevmeyer/oxanium | 378 KB (Regular only) + 125 KB + 44 KB |

- **Total:** about 3.7 MB for the curated set. The retained reference-named fonts are about 2.0 MB, most of it Twemoji 1.16 MB and Noto Sans 0.46 MB. Carlito and Caladea add about 0.7 MB.
- **Overall:** about 6.3 MB, which is 3.8 MB more than today's 2.5 MB of fonts.
- **CJK:** rely on the system. macOS ships PingFang SC/TC/HK, Hiragino Sans and Apple SD Gothic Neo, all reachable through CoreText cascade. Noto Sans SC alone would add 17.8 MB (JP 9.6 MB) for no gain on macOS. The picker lists the system CJK families.
- **Excluded:** Poppins (static-only: 18 files, 160 KB each; Montserrat covers the look), Source Serif 4 and IBM Plex Sans (good, but duplicative). All are easy to add later.

#### 4.1.3 Any installed font, and the resolution order

**Resolution order for a text layer.** `SceneFontResolver` is reorganised; the source cases get neutral names (`.wallpaper`, `.bundled`, `.system`, `.fallback`, `.userChoice`):

0. **The user's choice for this layer**, if set (§4.1.4).
1. **The wallpaper's own font file:** its folder, package, or a Workshop item it references. This is unchanged and also covers `fonts/workshop/<id>/…`.
2. **A bundled font by path or name:**
   - The path `fonts/<file>` maps to the file table (§4.1.1), including aliases such as `Monofur-PK7og.ttf` → `monofur.ttf`.
   - Otherwise the file's stem or family name is matched against the bundled catalog.
3. **An installed system font** by family name, PostScript name, or full name, through `CTFontDescriptorCreateMatchingFontDescriptors` with `kCTFontFamilyNameAttribute` / `kCTFontNameAttribute`. For `systemfont_<name>`:
   - an installed family whose squeezed key matches (arial → Arial);
   - then the bundled metric-compatible face (calibri → Carlito, cambria → Caladea);
   - then the alias table (segoeui → Helvetica Neue …).
4. **The fallback:**
   - the class fallback table for known-but-unbundled reference fonts;
   - else bundled Noto Sans, the reference's own default text face;
   - CoreText cascade for missing glyphs: system CJK; Twemoji for emoji, to match the captures, with Apple Color Emoji behind an OFF option "System emoji".
   - Each fallback is logged once with the wallpaper and layer.

**Metrics for system fonts.**
- System fonts go through the same `TextLayout` rules: FreeType-style rounding of `hhea` ascender/descender/lineGap.
- `NSFont.ascender`/`descender`/`leading` report `hhea` values for most fonts. Some system fonts, including SF Pro, apply CoreText's own line-spacing adjustments.
- `TextLayout` therefore reads the `hhea` table directly (`CTFontCopyTable(font, kCTFontTableHhea)`) for every font, bundled or system, so all fonts follow one rule.
- **Test:** for SF Pro, New York, Helvetica Neue and the curated set, the computed metrics equal the `hhea`-derived values. A layout snapshot of a two-line string in each alignment is stable.

**Registration.**
- Bundled fonts are registered once per process with `CTFontManagerRegisterFontURLs(.process)`, lazily on first use, not at launch.
- Wallpaper fonts stay registered from data, as today (`SceneFontRegistry`).
- System fonts need no registration.

#### 4.1.4 The font picker (UI) and how the choice is stored

- **Where.**
  - The Scene Inspector's layer section for text layers gets a **Font** row. It shows the current family and style and where it comes from ("Wallpaper", "Bundled", "System", "Fallback").
  - The sidebar user-properties panel gets the same row under a "Text" group when the wallpaper has text layers. It is off by default: shown only after the user overrides once, to keep the panel WE-like.
- **The picker** is a SwiftUI popover:
  - a search field (family, style, PostScript name);
  - sections **Recent**, **Wallpaper**, **Bundled** and **Installed**;
  - each row previews the layer's own text (first 24 characters) in that family, rendered lazily;
  - a style menu per family from `NSFontManager.availableMembers(ofFontFamily:)`;
  - "Reset to wallpaper font".
  - Families come from the bundled catalog plus `NSFontManager.shared.availableFontFamilies` (or `CTFontManagerCopyAvailableFontFamilyNames`), refreshed on `kCTFontManagerRegisteredFontsChangedNotification`.
- **Recent fonts** are an app-wide list (the last 8) in `UserDefaults.app` under a typed settings key (`GlobalSettings.recentTextFonts`). They are not per wallpaper.
- **Storage.**
  - The override is a user property of the wallpaper, so it follows `WallpaperPropertyScope`: per display, or shared with "Sync properties across displays".
  - The key is a **typed identifier** (CONTRIBUTING rule 4), e.g. `SceneLayerPropertyKey.textFont(objectID:)`. It serialises to the property store's string key in one place.
  - The value is `FontReference`: `{source: bundled|system|wallpaper, family, style, postScriptName}`, encoded as a string.
  - Changing it is a **re-rasterise** (the text texture), not a scene rebuild. `SceneDocument`'s "how much work a key change needs" gains that case.
- **Rendering.**
  - The chosen font feeds the same CoreText rasterisation into `g_Texture0`, the `font` program's outline/blur/drop-shadow (§2.2), and `TextLayout`'s placement.
  - The effect buffer grows with the new ink (EX2 handling applies).
  - Scripts that set `thisLayer.font` keep priority over the stored choice for that frame, as a script write does for other properties.
- **Tests:**
  - `SceneFontResolverTests`: the order 0–4, aliases, `systemfont_` mapping, fallback logging;
  - `FontMetricsParityTests`;
  - `TextFontOverrideTests`: stored per display, sync on and off, re-rasterise without rebuild, and a script write wins;
  - a UI unit test of the picker's filtering and recents.

### 4.2 Utility textures (generated)

- **The generator** is `Scripts/assets/generate-textures.swift`, our own. It is deterministic (fixed seeds), run by hand, and its output is checked in.
- **Output format:**
  - It writes our `.tex` interop format through a small `TEXWriter`, the counterpart of `TEXParser`. A round-trip test covers it.
  - The generated `.tex-json` sidecars carry the flags the sampler setup reads: `clampuvs`, `nointerpolation`, and mips on or off.
  - PNG is an alternative only where the loader already takes PNG at a `.tex` path, as for the effect normal maps.

| Texture | Generation | Target behaviour (measured from the reference by `Scripts/assets/measure.py`, dev-only) |
|---|---|---|
| `util/white`, `util/black` | constant 1×1 (or 4×4) | exact |
| `util/flatnormal` | constant (0.5, 0.5, 1) | exact |
| `util/noflow` | constant neutral flow (0.5, 0.5) | exact |
| `util/noise` | white noise, RGBA independent, uniform histogram | same size, per-channel mean/σ, no mips (FX2: then check film grain's spread) |
| `util/uniform_256` | uniform random 256² | histogram |
| `util/perlin_256` | tiling gradient noise, period 256 | power spectrum and tiling |
| `util/clouds_256` | tiling fBm (octaves and persistence fitted to the reference spectrum) | spectrum, histogram; clouds/nitro/fire/godrays/shine gallery values |
| `util/fur` | fur strand density noise | histogram |
| `pattern/voronoi`, `voronoi_local` | tiling Worley F1 (global and local-cell variants) | cell count, distance histogram; watercaustics gallery |
| `gradient/*` (16) | our own ramps, one per name, as piecewise-linear stops in the generator | same size and orientation; a similar hue path per name (fire, ice, neon, rainbow, toon, toon_smooth, iridescent, swamp, ghost flame, ferro fluid, swipe, blend_gradient(_reverse)). The three that are effect defaults (fire, iridescent, ferro fluid) are verified in the gallery. |
| `lut/neutral` | identity 32³ | exact |
| `lut/*` (27 creative) | our own grades (lift/gamma/gain, curves, split toning), one per filter name | These back the app's colour-filter setting, not wallpapers. Looks will differ (decision D4). |
| `cookie/flashlight1…4` | radial falloff with rings and noise, 4 variants | energy and radius similar; `flashlight1` is the default cookie |
| effect normal maps (`refractnormal`, `waterripplenormal`, `waterflowphase`) | normals from generated height fields; phase from noise | refraction 17.66, waterripple 10.5/3.5 in the gallery |

### 4.3 Particle art (`materials/particle/**`)

The particle textures are artwork, and their shapes set coverage in the particle gallery.

**Plan by category:**
1. **Procedural in the generator (S–M):** halo*, sharp_halo, chromaticdot, drop and normals, normal_ring_smooth, beams, light_shafts, bubbles, rain, snow, spark/star/misc shapes, lightning bolts (a recursive midpoint bolt generator), fog/smoke (fBm puffs, sprite-sheet flipbooks with the same grid and frame counts).
2. **Drawn (M–L):** leaves*, rosepetals, animals, debris, explosion/fire flipbooks. Authored as our own SVG/vector sources in `SharedAssets/source/particle/`, rasterised by the generator. Sprite-sheet grids stay identical because frame counts are part of the interface.
3. **Per texture:** keep the name, size, format class (RGBA/RG88/R8), sprite-sheet layout, alpha coverage and mean luminance within ±10 % of the reference. These are measured dev-only and stored as numbers in `Scripts/assets/particle-targets.json`.

**Order:** the 37 textures the library uses first, then the rest (the particle gallery covers every preset). Until a texture exists, the external-assets-folder fallback (§5) or `generateProceduralTexture` covers it. The 52 `.gif`s and the `.tga` are dropped (unused).

### 4.4 Definitions (JSON), written by us

- **`effects/<name>/effect.json` + `materials/effects/*.json` (46 effects):**
  - Identical keys, pass order, FBO specs, binds, `dependencies`, `replacementkey`, `group`, `performance`.
  - `name`/`description` become plain English with our own localisation.
  - The `preview` field is dropped (unused at runtime).
  - Test: `EffectDocumentTests` against a checked-in interface snapshot (§6, P4).
- **`materials/util/*.json`:** only the ~35 the runtime or Workshop materials use (§1.4), same fields.
- **`materials/fonts/*.json`:** all 10 names.
- **`models/util/*.json`:** all 6.
- **`materials/particle/halo(_translucent).json`.**
- **`particles/example*.json`:** our own editor templates with the same fields and the defaults `ParticleEditorTemplateTests` pins (max count 500, sphere emitter 32…512, …).
- **Dropped:** `materials/editor/*`, `materials/models/editor/*`, `models/editor/camera/camera.mdl` (replace `mdl-reference.py`'s `VENDORED` oracle input with a generated MDL fixture), `shaders/declarations.json`.

### 4.5 Scripting helpers

- **`baseclasses.js`** is rewritten from the documented SceneScript API (the published docs and `lib.sceneScript.d.ts` signatures):
  - `Vec2`, `Vec3`, `Vec4`, `Mat3`, `Mat4` with their documented methods and operators-by-method, `MediaPlaybackEvent`, `IModelData`;
  - `deg2rad`/`rad2deg`;
  - float32 semantics where scripts observe them (test-risks SF13).
- **The modules `WEMath`, `WEColor` and `WEVector`** are rewritten from their documented signatures.
- **Import specifiers are interface.** Scripts `import … from 'WEMath'`, so the names stay. Our files are `math.js`, `color.js` and `vector.js` under `OpenWallpaperEngine/Resources/SceneScript/modules/`. `SceneScriptPrelude` maps specifier to file in one table. The helpers load as bundled resources, not from the asset tree, like `objects-scene.js` today.
- **Verification:**
  - every SceneScript suite;
  - `SceneScriptCorpusReplayTests`: the P5 subset while working (§6.4), and the whole corpus once the helpers are complete (§6.5);
  - `WEAuthoredValuesTests` baseclasses part;
  - a new `ScriptHelperAPITests` that exercises every documented member against expected values.

### 4.6 zcompat

- **Scene shader patches (2):** first check whether the translator now compiles `pixelate` (2078835426) and `Simple_Audio_Bars` (2084198056; 5 scenes) unpatched. If it does, delete the patches. If not, fix the cause generically in the translator (preferred, CONTRIBUTING rule 1), or write our own minimal replacement GLSL under `zcompat/scene/shaders/<id>/` with our own `config.json`.
- **Web patches (5):** reproduce each item's failure in `WKWebView` and write our own patch actions for `zcompat/web/<id>.json` (the schema is ours: `WebCompatPatches`).
- **Tests:** `SceneShaderCompatTests` and `WebCompatPatchesTests` move to `Tests/Fixtures/ZCompat` plus the new tree.

## 5. The rename

**Neutral names:**

| Now | New |
|---|---|
| `Vendor/we-assets/` (folder reference) | `SharedAssets/` at the repo root (folder reference, bundled as `Contents/Resources/shared-assets`). It is not under `Vendor/` because it isn't vendored. |
| `WallpaperEngineAssets` | `SharedAssets` (`bundled`, `external`, `searchDirectories`, `locate`) |
| `WallpaperEngineAssets.configured` / defaults key `WallpaperEngineAssetsDirectory` | Removed (2026-09-27, at the user's request; see D2). Nothing to rename or migrate; tests use `testInstall` (`OWE_WE_ASSETS`). |
| `.wallpaperEngineAssetsDirectoryDidChange`, `setWallpaperEngineAssetsDirectory`, `chooseWallpaperEngineAssetsDirectory`, `GlobalSettings.wallpaperEngineAssetsDirectory` / settings case `wallpaperEngineAssetsDirectory` | Removed (2026-09-27, see D2). |
| `SceneFontResolver.Source.weAssets` | `.bundled` (plus `.system`, `.fallback`, `.userChoice`) |
| `WallpaperEngineLabels` | Out of scope: it reads an installed product's locale file (compatibility). Rename to `InstalledEditorLabels` only if the coordinator wants it (D6). |
| `Scripts/vendor-we-assets.sh`, `Scripts/we-assets-attribution.txt` | Deleted (P17). Replaced by `Scripts/assets/*` generators and `Scripts/fonts/fetch.sh`, which downloads the upstream releases and verifies SHA-256. |
| `ShaderVariantTests.weAssets`, `Fixtures.hasWEShaderSources` | `sharedAssets`, `hasSharedShaderSources` |

**UI strings.** `OpenWallpaperEngine/Localizable.xcstrings` plus code literals; many aren't in the catalog yet and should be added.

| Where | Now | New |
|---|---|---|
| `Settings/PerformancePage.swift:113` (Scene Detail picker) | "Full (Wallpaper Engine)" | "Full" |
| `PerformancePage.swift:110` (texture resolution help) | "Wallpaper Engine's setting: High Performance loads textures at half…" | "High Performance loads textures at half…" |
| `PerformancePage.swift:115` | "…Full draws every effect at its texture's full size, as Wallpaper Engine does." | "…Full draws every effect at its texture's full size." |
| `Settings/GeneralPage.swift:98` (section) | "Wallpaper Engine Assets" | "Shared Assets" |
| `GeneralPage.swift:100` (footer) | "Shared textures, effects and presets ship with the app… Point it at the assets folder of a Wallpaper Engine installation…" | "Effects, textures and presets ship with the app. Optionally choose an extra assets folder; files missing from the app are looked up there." |
| `GeneralPage.swift:84`, `:88`, `:93` | "Using built-in assets", "Choose...", "Use Built-in Assets" | unchanged (already neutral) |
| `GeneralPage.swift:270` (open panel) | "Choose Wallpaper Engine assets folder" | "Choose an assets folder" |
| `GeneralPage.swift:162-163` | "…keeps each display's properties, as Wallpaper Engine does…" | drop the clause |
| `GeneralPage.swift:185-186` | "Metal draws video … the way Wallpaper Engine does. Experimental." | "Metal draws video … with effects and scene features. Experimental." |
| `Settings/DiagnosticsPage.swift:18` | "Built-in" / "Wallpaper Engine install" | Removed with the setting (2026-09-27). |
| `DiagnosticsPage.swift:56` | "WE shaders are translated per combination…" | "Wallpaper shaders are translated per combination…" (and a line for native programs) |
| `UI/FirstLaunchView.swift:124` | "…with a familiar layout if you already know Wallpaper Engine." | "…with a familiar layout." |
| Catalog-only keys, unused in code | "Clear Wallpaper Engine Assets Location", "Select the assets folder from a Wallpaper Engine installation…", "Similar UI Layout to Wallpaper Engine on Steam", "You can easily import video type wallpapers from steam workshop of Wallpaper Engine…" | Delete the stale keys |
| **Kept (factual Steam/Workshop requirement)** | `Workshop/WorkshopView.swift:124` "…You must own Wallpaper Engine on Steam." and the Steam login/API strings | Keep |
| **Product name (not in scope)** | "Open Wallpaper Engine" (window, menus, About, folder names, bundle display name), `AboutUsView.swift:30` "Wallpaper Engine for Mac" | Unchanged unless the user decides otherwise (D7) |

**Also neutralised** (developer-facing, low priority, same package):
- log messages in `sharedAssetData` ("no Wallpaper Engine assets available");
- `SceneFontResolver`'s "not found in the wallpaper, WE assets or workshop items";
- `SceneSoundContentBuilder`'s "WE's assets";
- `SceneScriptRuntime`'s source URLs `owe://we/scripts/…` → `owe://runtime/…`.

**Build and CI:**
- `project.pbxproj` folder reference path;
- `release.yml:134` checks `shared-assets/effects/blur/effect.json` and the native metallib instead of `we-assets/shaders/common.h`;
- `README.md:280`, `CONTRIBUTING.md` ("WE assets" section, `.metal` note), `docs/architecture.md` (`Resources/`) updated in P17.

**Commit rules.** Per CONTRIBUTING.md:
- **P1a** is a pure move/rename commit: folder, type, keys, identifiers. It has no logic and must build.
- **P1b** holds the string edits and the migration.
- Asset drops never share a commit with code.

## 6. Work breakdown

### 6.1 Packages

- **Ordering:** infrastructure, then smallest and most used first.
- **Parallel lanes** are marked; a lane owns its files exclusively.
- **Every package** lands:
  - its parity tests (`NativeParityTests/<program>`);
  - its entry in `NativeShaderCatalog.shipped` or the asset swap;
  - capture-harness reports for `translated` and `native`, on its subset only;
  - a line in `docs/progress-snapshot.md`.
- **The test column is a summary.** The exact `-only-testing` classes and wallpaper list per package are in §6.4. Nobody runs the full suite or a library-wide sweep inside a package; those runs are listed in §6.5.

| # | Package | Owns (files) | Depends | Effort | Tests / captures (summary; exact set in §6.4) |
|---|---|---|---|---|---|
| **P1a** | Rename, move only | `Vendor/we-assets` → `SharedAssets/`, `Core/WallpaperEngineAssets.swift` → `Core/SharedAssets.swift`, identifiers in settings/notifications, pbxproj, `release.yml` path | — | S | Build; full test suite unchanged |
| **P1b** | Strings and defaults migration | `Settings/{General,Performance,Diagnostics}Page.swift`, `UI/FirstLaunchView.swift`, `Localizable.xcstrings`, `Core/Settings/GlobalSettings*.swift` (migration), log strings | P1a | S | `ExternalAssetsMigrationTests`, `AppStorageIsolationTests` |
| **P0** | Native backend infrastructure | `Scene/Shaders/Native/**` (new); a `makePipeline` branch in Effect/Image/Particle/Model/Shadow/Puppet/Volumetrics/CameraFade renderers; `ShaderVariant.swift` (`ShaderProgramVariant`); `EffectPipelineArchive` (r3); `SceneEffectParameters.sources` (manifest-aware); `ShaderBackendPolicy`; `Scripts/native-shaders/{gen-uniforms.swift, fingerprint.py}`; `Fingerprints.json` | P1a | L | `NativeParityHarness` (shared), `NativeManifestTests` (generated-layout freshness, annotation equivalence), `FingerprintTests` (normalisation stability, library coverage report), `ShaderBackendPolicyTests`, `EffectPipelineArchiveTests` |
| **P0b** | Argument buffers for textures | same renderers' bind code | P0 | M | Parity (bit-identical), `SceneFrameBenchmark` |
| **P2** | Utility textures and generator | `Scripts/assets/generate-textures.swift`, `TEXWriter`, `SharedAssets/materials/{util/*.tex, pattern, gradient, lut, cookie}`, effect normal maps | P1a | M | `TEXWriterRoundTripTests`, `GeneratedTextureStatsTests` (targets JSON), SceneColorCorrectionTests; gallery for noise-using effects |
| **P3** | Shared GLSL headers (ours) | `SharedAssets/shaders/*.h`, `SharedAssets/shaders/base/*.h`; translator revision bump | P1a (parallel with P0, P2) | M | Header subset parity, WEImageBlendModes, InProcessShaderCompiler, ShaderVariantCache. The library-wide sweeps (0 new failures) run once, when the header system is complete (§6.5). |
| **P4** | Definitions JSON (ours) | `SharedAssets/effects/*/effect.json`, `…/materials/effects/*.json`, `materials/{util,fonts,particle}/*.json`, `models/util/*.json`, `particles/example*.json` | P1a (parallel) | S | `EffectDocumentTests` + `EffectInterfaceSnapshotTests` (keys, passes, FBOs, binds identical to a recorded snapshot of the reference interface), ParticleEditorTemplate, SceneLayerKind |
| **P5** | Script helpers | `Resources/SceneScript/modules/*.js`, `baseclasses` replacement, `SceneScriptPrelude.swift` | P1a (parallel) | M | All SceneScript suites, CorpusReplay, `ScriptHelperAPITests` |
| **P6** | Fonts: sourcing, bundling, licences | `SharedAssets/fonts/**` (fonts + licence files), `Scripts/fonts/{fetch.sh, measure.py}`, curated set | P1a (parallel); D1 | S | `FontMetricsParityTests`, SceneTextLayout, extras `text_*` |
| **P7** | Font resolution, system fonts, picker | `SceneFontResolver.swift`, `SceneFontRegistry.swift`, `TextLayout.swift` (hhea read), `Scene/UI/TextFontPicker*.swift` (new), inspector text row, typed key in `SceneDocument`, `GlobalSettings.recentTextFonts` | P6 | L | `SceneFontResolverTests`, `TextFontOverrideTests`, `FontMetricsParityTests` (system), picker unit test, extras `text_*` |
| **P8** | Native utility passes | Native: passthrough(+srgb, linear), composelayer, flat, fade, effectcomposebackground, blur_k3, downsample_quarter(_linear) (and have `ParticleEmitterImage.metal` reuse it) | P0 | M | Parity; SceneLayerComposite, SceneSolidLayerBlend, SceneCameraFade; extras `solidblend_*` |
| **P9** | Native single-pass effects, batch A (most used) | shake (+ profiles), waterwaves, pulse (+ profiles), foliagesway, opacity, tint, transform, perspective, scroll, iris, waterflow, waterripple | P0, P2, P4 | M | Parity per effect and profile; gallery; library coverage |
| **P10** | Native LDR + HDR bloom, colour correction | `SceneBloomChain`/`SceneHDRChain` program switch, native bloom/HDR/ccsimple | P0, P2 | M | SceneBloomChain/HDRChain/HDRMaterial/ColorCorrection; every gallery scene; 3606529469 |
| **P11** | Native text (`font`) | native `font` | P0, P6 | M | SceneTextEffects, RenderCheck, extras `text_*` |
| **P12** | Native image materials | genericimage2/3/4 (+ `effectpassthrough(_4)`, `solidlayer_instance*`), in-tile composite | P0, P3 (MSL port of blending/PBR shares code), P8 | L | ImageMaterial* suites, Puppet*, WEReference (15 scenes), extras composite/solid |
| **P13** | Native single-pass effects, batch B | nitro, blend, vhs, chromaticaberration, xray, filmgrain, cloudmotion, swing, clouds, fire, reflection, fisheye, shimmer, skew, spin, twirl, colorkey, edgedetection, blendgradient, _empty | P0, P2, P4 | M | Parity; gallery |
| **P14** | Native multi-pass effects | blur (+ composites), blurprecise, blurradial, localcontrast, motionblur, godrays, shine, glitter, refraction, lightshafts, depthparallax, watercaustics | P0, P2, P4 | L | Parity; gallery (incl. composites), EffectGraphTests |
| **P15** | Native particles | genericparticle, genericropeparticle, mesh-shader expansion | P0, P3 | L | Particle* suites, WEParticleGallery, extras `refraction_bigdrops` |
| **P16** | Native models, shadows, volumetrics; simulation effects; chain fusion | generic4/2/foliage4/fur4, shadowcaster*, volumetrics*, cursorripple, fluidsimulation; effect-chain fusion | P0, P3, P12 | L | Model*, SceneShadow*, SceneVolumetrics, 3D captures (`shadows*`, `vol*`), gallery, LibrarySweep chain parity |
| **P18** | Particle art | `Scripts/assets/particle/**`, `SharedAssets/source/particle/**`, `SharedAssets/materials/particle/**` | P2 | L | `ParticleTextureTargetsTests`, WEParticleGallery, ParticleMaterialRender |
| **P19** | zcompat own fixes | `SharedAssets/zcompat/**` or translator fixes | P3 | S | SceneShaderCompat, WebCompatPatches, the 5 Simple_Audio_Bars scenes |
| **P20** | Enhancement options (OFF) | `Core/Settings/GlobalSettings.swift` (typed keys), `Settings/PerformancePage.swift` (section "Enhancements"), the native programs' option constants | P9–P16 per option | M | Each option: ON renders differently, OFF is parity-identical |
| **P17** | Remove the reference tree | delete the remaining reference files, `vendor-we-assets.sh`, attribution; freeze parity goldens; update README/CONTRIBUTING/architecture/release.yml | all of the above | S | Full suite with goldens; all four capture harnesses; `release.yml` bundle check |

**Parallel lanes:**
1. After P1a, in parallel: **P0 | P2 | P3 | P4 | P5 | P6**. They share no files.
2. After P0: **P8 | P9 | P10**, then **P11 | P12 | P13 | P14**, then **P15 | P16**.
3. **P7** follows P6 and runs alongside the shader lanes.
4. **P18** follows P2.
5. P17 is last.

A tester agent runs the whole-system runs of §6.5 when a system closes.

**Critical path:** P1a → P0 → P12 → P16 → P17. That is roughly 6–8 weeks of lane time with 3–4 agents; the L items dominate.

### 6.2 Package definition of done

1. `NativeParityTests` green for every combo case and profile of the package's programs.
2. The package's targeted set (§6.4) green: its `-only-testing` classes, run with `OWE_LIBRARY` pointed at its subset folder.
3. The `_ONLY` capture reports attached, with the no-regression rule met.
4. `LibrarySweepTests` coverage printed (native/translated counts) **for the subset only**.
5. No new `try?`, globals, or `_owe_` keys.
6. The translator revision is bumped if translated output changed (P3 only).
7. Moves in their own commits.
8. No full-suite or library-wide run. If the package completes a system, the §6.5 run for that system follows as its own step, owned by the tester agent.

### 6.4 Targeted test sets per package (the only tests a package runs)

**The rule (from the user).** Nobody runs the full suite or a library-wide wallpaper sweep while working on part of a system. Each package runs:
- only its test classes, through `xcodebuild test -only-testing:OpenWallpaperEngineTests/<Class>` (repeated per class);
- only its wallpapers, with `TEST_RUNNER_OWE_LIBRARY` pointed at a scratch folder of symlinks.

**Building the subset folder.** `Scripts/test-subset.sh <package> <ids…>` (new, part of P0) creates `/Volumes/980Pro/dd-agentOA/lib-<package>/`:
- It adds a symlink per wallpaper id.
- It adds a symlink for every Asset item those wallpapers reference through `workshop/<id>/…`, transitively. For example, 2084198056 goes with the Simple_Audio_Bars users.
- It writes a matching `.owe-workshop-dependencies.json`.

P0 also checks that the Workshop resolver sees the subset folder under test. `WorkshopAssetResolver.defaultRoots` uses `wallpapersDirectory`, which is the isolated test folder. If it doesn't see it, make `OWE_LIBRARY` a resolver root in tests.

**Other constraints:**
- Capture harnesses run with their `_ONLY` variables: `OWE_EFFECT_GALLERY_ONLY`, `OWE_WE_EXTRAS_ONLY`, `OWE_PARTICLE_GALLERY_ONLY`, `OWE_WE_REFERENCE_ONLY`.
- Builds and tests run on a `git archive` in `/Volumes/980Pro/dd-agentOA-src` with derived data in `/Volumes/980Pro/dd-agentOA`, one at a time.
- Every native package also runs `NativeParityTests/<its programs>` and `NativeManifestTests`, which are not repeated in the table.

**Wallpaper lists** were chosen from the library scan:
- every wallpaper that ships an **older** copy of the package's effects, since those exercise the fingerprint profiles;
- plus one or two current-version users per effect or feature.

| Pkg | `-only-testing` classes | Wallpapers (`OWE_LIBRARY` subset) | Capture `_ONLY` subset |
|---|---|---|---|
| **P1a** | `WallpaperEngineAssetsTests` (renamed `SharedAssetsTests`), `ShaderVariantTests`, `EffectDocumentTests`, `SceneEffectAssetScopeTests`, `SceneShaderCompatTests`, `WebCompatPatchesTests`, `WorkshopAssetResolverTests`, `SceneTextLayoutTests`, `SceneColorCorrectionTests` | none | none |
| **P1b** | `ExternalAssetsMigrationTests` (new), `AppStorageIsolationTests`, `SharedAssetsTests` | none | none |
| **P0** | `NativeManifestTests`, `FingerprintTests`, `ShaderBackendPolicyTests`, `EffectPipelineArchiveTests`, `ShaderVariantCacheTests`, `EffectGraphTests`, `ImageMaterialRenderTests` (smoke: the branch compiles both backends), `NativeParityTests/_empty` | Fingerprint coverage: 2176097362 (old shake, pulse, blur, vhs, transform, opacity), 1394503570 (old blur, shine, blurprecise), 2370927443 (many current, old blend/godrays/waterripple), 3244466773 (old fluid vorticity, current clouds/nitro) | gallery: `none` |
| **P0b** | `EffectGraphTests`, `ImageMaterialRenderTests`, `SceneFrameBenchmarkTests` (bench env) | 3245833232, 3639372043 | none |
| **P2** | `TEXWriterRoundTripTests`, `GeneratedTextureStatsTests`, `SceneColorCorrectionTests`, `SceneVolumetricsTests`, `EffectGraphTests` | noise and pattern users: 3352730400, 3803167460 (filmgrain), 3244466773 (clouds, nitro), 3455121165 (watercaustics, cloudmotion), 1805766573 (fire), 3233200129 (cookie `flashlight1`), 2370927443 (`blend_gradient_reverse`), 3657770939 (`gradient_swipe_wide`) | gallery: filmgrain, clouds, cloudmotion, nitro, fire, godrays, shine, glitter, blendgradient, watercaustics, lightshafts, fluidsimulation, shimmer, refraction, waterripple, waterflow, depthparallax, xray |
| **P3** | `InProcessShaderCompilerTests`, `ShaderVariantTests`, `ShaderVariantCacheTests`, `GLSLReservedWordsTests`, `WEImageBlendModesTests`, `LightingV1RequireTests`, `GeometryShaderEmulationTests`, `HeaderParityTests` (new: old vs new headers on the subset's local shaders) | one or two per header: 2176097362, 2370927443 (`common_blending`), 3455121165, 3606529469 (`common_perspective`), 3802767544, 3803042537 (`common_blur`), 3384390033, 3639372043 (`common_composite`), 3074485715, 3443078996 (`common_fragment`), 3803044683 (`common_vertex`), 3245833232 (`common_pbr_2`) | gallery: blend, blur, blurprecise, pulse, perspective, godrays, composite_normal, composite_cutout; extras: solidblend_02, solidblend_11 |
| **P4** | `EffectDocumentTests`, `EffectInterfaceSnapshotTests` (new), `WEAuthoredValuesTests` (non-library cases), `ParticleEditorTemplateTests`, `SceneLayerKindTests`, `SceneLayerCompositeTests`, `SceneSolidLayerBlendTests`, `SceneEffectAssetScopeTests` | util models: 3074485715 (`projectlayer`, `composelayer`), 3352730400 (`projectlayer`, `solidlayer`), 2350874185 (`composelayer_depthtest`, `solidlayer_depthtest`), 3453730450 (`fullscreenlayer`), 2963872291 (`solidlayer`), 3384390033 (`effectcomposebackground`) | gallery (effects without local copies, so the new JSON is what runs): blur, composite_under, godrays, glitter, fluidsimulation, cursorripple, motionblur, refraction, localcontrast, shine |
| **P5** | `ScriptHelperAPITests` (new), `SceneScriptModuleCompilerTests`, `SceneScriptObjectModelTests`, `SceneScriptWallpaperTests`, `SceneScriptCameraTests`, `SceneSharedInstanceTests`, `SceneScriptReplayFixtureTests`, `WEAuthoredValuesTests`, `SceneScriptCorpusReplayTests` (subset library only) | module and vector users: 2963872291 (WEColor, WEMath), 3378346807 (all three), 3677897732, 3803728810 (WEVector), 2406282996 (WEMath), 2176097362 (WEColor), 3734636606 (Vec/Mat-heavy physics) | none |
| **P6** | `FontMetricsParityTests` (new), `SceneTextLayoutTests`, `SceneTextEffectsTests`, `WorkshopAssetResolverTests` | reference-named fonts: 2176097362, 3352730400, 3546971487 (Monofur), 2963872291 (Alcubierre, Atami), 3074485715 (Atami), 2370927443 (8-bit Operator+, Blackout, Alcubierre, Monofur) | extras: text_plain_msdf, text_plain_nomsdf, text_outline, text_blur, text_dropshadow, text_defaults_only |
| **P7** | `SceneFontResolverTests` (new), `TextFontOverrideTests` (new), `TextFontPickerTests` (new), `FontMetricsParityTests`, `SceneTextLayoutTests`, `SceneTextEffectsTests`, `RenderCheckTests` | `systemfont_*`: 3109042108, 3159348391 (arial), 3443078996 (calibri), 3378346807, 3453730450 (cambria; GP2); Workshop fonts: 3802509485 (Oxanium), 3244466773 (Quicksand/Anurati from 2981960200) | extras: text_* (as P6) |
| **P8** | `SceneLayerCompositeTests`, `SceneSolidLayerBlendTests`, `SceneCameraFadeTests`, `SceneLayerKindTests`, `SceneVolumetricsTests`, `ParticleEmitterImageTests` | 2276071817, 3270035750 (`composelayer`), 3378346807 (`fullscreenlayer`), 2963872291, 3384308105 (`solidlayer`), 3639372043 (`projectlayer`), 2350874185 (depth-test variants) | extras: solidblend_* (7), none |
| **P9** | `EffectGraphTests`, `ShaderStageUniformTests`, `FingerprintTests` | old-version users: 2176097362 (shake, pulse, opacity, transform), 1805766573, 1839434069 (shake), 2276071817 (shake, pulse, waterwaves), 2515150033 (waterwaves, pulse, waterflow), 2321732083 (pulse, transform), 2370927443 (waterripple). Current users: 3245833232 (shake, waterwaves, waterflow, iris), 3803167460 (foliagesway, iris, opacity), 3384390033 (tint, scroll, opacity), 3736761065 (perspective) | gallery: shake, waterwaves, pulse, foliagesway, opacity, tint, transform, perspective, scroll, iris, waterflow, waterripple, user_pulse, user_irism, user_scrol |
| **P10** | `SceneBloomChainTests`, `SceneHDRChainTests`, `SceneHDRMaterialTests`, `SceneColorCorrectionTests`, `LightingMemoryTests` | bloom: 3639372043, 3270035750, 2321732083; HDR: 3606529469, 3352730400, 2350874185 | gallery: none, tint, scroll; WE reference: 3606529469, 3270035750, 3352730400 |
| **P11** | `SceneTextEffectsTests`, `SceneTextLayoutTests`, `RenderCheckTests`, `ImageMaterialRenderTests` (text case) | 2176097362, 3378346807, 3802509485, 3109042108 | extras: text_* |
| **P12** | `ImageMaterialRenderTests`, `ImageMaterialLightingTests`, `ImageMaterialReflectionTests`, `ImageMaterialPrelightingTests`, `PrelitEffectChainTests`, `SceneDepthDrawTests`, `ScenePuppetTests`, `ScenePuppetAnimationTests`, `SkinningReferenceTests`, `WEImageBlendModesTests`, `LightingV1RequireTests`, `SceneLayerCompositeTests` | 2515150033 (puppet, legacy lights, reflection), 2321732083 (puppet), 3803167460 (prelit, reflective), 2370927443 (reflection, 11 effects), 3270035750 (tube lights), 3352730400 (cookie spot, HDR), 3121284565, 3546971487 (genericimage3), 2048761036 (genericimage2) | extras: solidblend_*, composite_*; WE reference: 2515150033, 2321732083 (incl. puppet5s), 3270035750, 3352730400 |
| **P13** | `EffectGraphTests`, `GLSLReservedWordsTests` | 3182591332, 3189211857 (nitro, old vhs), 2321732083, 3074485715, 2963872291 (old blend), 3109042108 (chromaticaberration, old vhs), 2048761036, 2567642368 (old xray), 3352730400 (filmgrain), 3455121165 (old cloudmotion), 3672756984 (swing, shimmer), 3244466773 (clouds), 1805766573 (old fire), 3453730450 (fisheye), 2370927443 (reflection) | gallery: nitro, blend, vhs, chromaticaberration, xray, filmgrain, cloudmotion, swing, clouds, fire, reflection, fisheye, shimmer, skew, spin, twirl, colorkey, edgedetection, blendgradient, user_cloud1 |
| **P14** | `EffectGraphTests`, `EffectCompositeTests`, `EffectGraphReuseTests`, `EffectGraphSwapTests` | old-version users: 1394503570 (blur, shine, blurprecise), 2176097362 (blur), 2406282996 (blurprecise), 2350874185, 2370927443 (godrays), 1805766573 (shine). Current users: 3639372043 (blur, shine, localcontrast), 3802767544 (godrays, lightshafts), 3803042537 (glitter, lightshafts, godrays), 3384390033 (refraction), 3109042108 (depthparallax), 3606529469 (watercaustics) | gallery: blur, composite_* (5), blurprecise, blurradial, localcontrast, motionblur, godrays, shine, glitter, refraction, lightshafts, depthparallax, watercaustics |
| **P15** | `ParticleMaterialRenderTests`, `ParticleGPURenderTests`, `ParticleMaterialPerformanceTests`, `SceneRendererParticleTests`, `ParticleEditorTemplateTests`, `GeometryShaderEmulationTests` | 3378346807, 2963872291, 3606529469 (sharp_halo, water), 3803042537 (fire, beams), 2048761036, 1394503570, 3443092605, 2370927443 (drops, ropes), 3802525393 (light, nature) | particle gallery: a 30-item subset (every renderer kind; lightshafts_4…6, snow_2, rain, beams, rope and trail presets, collisionbounds, the refraction drops); extras: refraction_bigdrops |
| **P16** | `ModelRenderTests`, `ModelSkinningTests`, `SceneScriptModelDataTests`, `SceneShadowTests`, `SceneShadowRenderTests`, `SceneVolumetricsTests`, `LightingV1RequireTests`, `EffectGraphTests` | generic4: 3159348391, 3233200129, 3378346807, 3384390033, 3453730450, 3455121165, 3657770939, 3734636606; generic2: 2350874185; fluid: 3244466773, 3245833232; cursor ripple: 3384390033. Chain fusion: 3245833232, 3244466773, 3742916237, 3803167460 (shake-heavy) | WE reference: 3455121165, 3657770939, 3734636606, 3159348391, 3378346807, 2350874185 (`shadows*`, `*_vol*`), 3352730400 (`vol_*`); gallery: cursorripple, fluidsimulation |
| **P18** | `ParticleTextureTargetsTests` (new), `ParticleMaterialRenderTests` | per texture batch (all users of the batch): halo* (1805766573, 2321732083, 2370927443, 2515150033, 3109042108, 3245833232, 3443092605, 3453730450); chromaticdot/drop (2406282996, 2764281221, 3639372043, 1839434069, 2048761036); fog/smoke (2567642368, 3384308105, 3806006894, 2515150033); nature/leaves/petals (1394503570, 3602219506, 3802525393, 3803167460); light/beam (3802767544, 3802900973, 3803042537); water/sharp_halo (3606529469, 3736761065) | particle gallery: the presets that use the batch |
| **P19** | `SceneShaderCompatTests`, `WebCompatPatchesTests`, `ShaderVariantTests` | Simple_Audio_Bars users: 2176097362, 3074485715, 3109042108, 3455121165, 3803167460 (with Asset items 2084198056, 3021673417); the web items with zcompat ids if present | none |
| **P20** | the option tests of each program (ON differs, OFF identical), `AppStorageIsolationTests`, `QualitySettingsTests`, `EnhancementSettingsTests` (new) | one wallpaper per option: 3639372043 (blur, bloom), 3606529469 (HDR bloom), 3455121165 (filtering, perspective), 3352730400 (volumetrics), 3734636606 (model shading) | gallery: blur, none |
| **P17** | see §6.5 (it is itself a whole-system run) | — | — |

### 6.5 Whole-system full runs (the only full-suite and library-wide runs)

A system is complete when every package in it has landed. At that point the tester agent runs, once:
- the full suite (`xcodebuild test`, no `-only-testing`);
- the library-wide sweeps named per system, with `OWE_LIBRARY` at `/Volumes/980Pro/OpenWallpaperStorage`;
- the full capture harnesses named per system.

Failures go back to the owning package, which fixes them with its targeted set.

| System | Complete after | Full runs |
|---|---|---|
| **Rename** | P1a + P1b | full suite (no sweeps; nothing renders differently) |
| **Shared GLSL headers** | P3 | full suite; `LibrarySweepTests`, `ImageMaterialSweepTests`, `ParticleMaterialSweepTests`, `ModelMaterialSweepTests` (0 new translation failures); `OWE_WE_REFERENCE` full |
| **Script helpers** | P5 | full suite; `SceneScriptCorpusReplayTests` and `SceneScriptLibraryCostTests` over the whole library |
| **Fonts** | P6 + P7 (+ P11 if it lands first) | full suite; a library text sweep (every scene with text: 29); `OWE_WE_EXTRAS` full |
| **Textures, definitions, zcompat** | P2 + P4 + P19 | full suite; `LibrarySweepTests`; `OWE_EFFECT_GALLERY` full; `OWE_WE_EXTRAS` full |
| **Own shaders** (every native program) | P0 + P0b + P8 … P16 + P20 | full suite; every library sweep (`LibrarySweepTests`, Image/Particle/Model/`MDLLibrary` sweeps, `VolumetricsLibraryTests`, `LitLayerLibraryTests`, bloom/HDR/timeline/puppet library suites); all four harnesses full (`OWE_EFFECT_GALLERY` 55, `OWE_PARTICLE_GALLERY` 122, `OWE_WE_EXTRAS`, `OWE_WE_REFERENCE` 15 scenes); fingerprint coverage over the whole library; chain-fusion parity over the library's actual chains (this decides §3.7) |
| **Particle art** | P18 | full suite; `ParticleMaterialSweepTests`; `OWE_PARTICLE_GALLERY` full |
| **Final (tree removed)** | P17 | everything above once more, with goldens instead of the live reference; `release.yml`'s bundle check on a Release build |

### 6.6 Settings the OFF options add

All are global, typed `GlobalSettings` keys through `UserDefaults.app`. They appear in Settings → Performance → **Enhancements**. Each changes the look, so each defaults OFF.

| Key | Label | Affects |
|---|---|---|
| `enhancedBlur` | Precise blur | blur, blurprecise, blurradial, localcontrast, godrays/shine blur: correct σ, full-res or dual-filter, bicubic upsample, radius independent of layer size |
| `enhancedBloom` | HDR-aware bloom | LDR and HDR bloom: soft-knee threshold, energy-conserving pyramid, resolution-independent radius (LR6) |
| `highQualityFiltering` | High-quality texture filtering | mipmapped noise and pattern textures, anisotropic filtering on layer textures in perspective scenes, bicubic upsampling of reduced-size effect buffers |
| `highPrecisionBuffers` | 16-bit effect buffers | `rgba_backbuffer` FBOs and effect ping-pong targets in LDR scenes become RGBA16F (removes banding between passes) |
| `outputDithering` | Dither output | blue-noise dither before 8-bit quantisation of the final frame |
| `effectCorrections` | Corrected effect behaviour | frame-rate-independent motion blur and cursor ripple; other per-effect fixes listed in §2.3 as they're confirmed |
| `systemEmoji` | System emoji in text | Apple Color Emoji instead of Twemoji in the fallback cascade |
| `fusedEffectChains` | Fused effect chains | only if chain fusion fails the parity gate (§3.7); otherwise always on and not a setting |
| `volumetricsJitter`, `modelShadingExtras` | Smoother volumetric light; Advanced material shading | blue-noise march + accumulation; multi-scatter GGX, PCSS, specular AA |

Per-layer, not a setting: the **text font override** (§4.1.4).

## 7. Risks and open points

### 7.1 Decisions needed

| # | Decision | Recommendation |
|---|---|---|
| **D1** | Fonts without redistribution rights: Alcubierre, Atami, Cursed Timer, Lazer 84, Summer 85, Kust, OpenSticks, Spin Cycle 3D | Ask the authors of Alcubierre and Atami (the only two the library uses); ship the others only with permission; class fallback meanwhile |
| **D2** | Keep the external assets folder setting (renamed) as a fallback for files we lack, e.g. particle art not yet redrawn and the particle gallery's `presets`? | Yes. Native programs always win over it for engine shaders. It is also what `WorkshopAssetResolver` uses to find a Steam Workshop folder. **Superseded 2026-09-27:** the user had the setting removed; the app uses only its bundled assets, so what isn't bundled has no fallback, the Steam Workshop folder root went with it, and the particle gallery reads `presets` through the test-only `OWE_WE_ASSETS`. The steps that assume an external folder (§5 item 4, P1b's migration, R1's fallback) no longer apply. |
| **D3** | Native substitution for local effect copies, by fingerprint (§3.3) | Yes. Without it, native effects only help the gallery and new projects. |
| **D4** | Creative LUT looks will change (app colour-filter feature, not wallpaper content) | Accept; our grades keep the names |
| **D5** | Parity goldens from translated reference renders, kept after P17 | Keep: they are our renders of test patterns |
| **D6** | Rename `WallpaperEngineLabels` (reads an installed product's locale) | Leave: compatibility code |
| **D7** | The product name "Open Wallpaper Engine" and "Wallpaper Engine for Mac" in About | Out of scope for this plan; flag to the user |
| **D8** | Emoji face: Twemoji (matches captures) vs system | Twemoji default, system as the OFF option |

### 7.2 Risks

| # | Risk | Mitigation |
|---|---|---|
| **R1** | **Noise and particle art can't be pixel-identical.** Captures are compared by statistics for random effects already, but coverage-sensitive presets may drift. | Measure targets per texture (§4.3); gallery tolerances plus ±5 % no-regression; keep the external-folder fallback until each texture passes |
| **R2** | **Older local shader versions** (111 files) need profiles; a missed behavioural difference changes a wallpaper silently. | Fingerprint misses fall back to the translator (safe by default); every profile gets its own parity test against that version's GLSL |
| **R3** | **Parity after P17** depends on frozen goldens: a renderer change that legitimately alters output needs a regeneration path. | Keep the live-compare option against `OWE_WE_INSTALL`; goldens are regenerated only through that path |
| **R4** | **Variant explosion** with function constants on genericimage4 (~30 switches) and first-load pipeline stalls. | The effective-combo filter; async compile as today; the pipeline archive (r3); optional offline harvest (P0c) |
| **R5** | **Interface drift:** a key, default or range typed wrong in a manifest breaks Workshop scenes quietly. | `EffectInterfaceSnapshotTests` and `NativeManifestTests` compare manifests with a recorded snapshot of the reference annotations: names, keys, defaults, ranges, combo options. The snapshot is data about the interface, not source. |
| **R6** | **Header rewrite regressions** in Workshop GLSL that relies on side effects: macro names, implicit `#define`s, uniform declarations inside headers. | Keep every macro and uniform the headers declare (§1.2); the library sweep must show 0 new compile failures; old/new parity on local shaders |
| **R7** | **The mesh-shader path** for particles needs Metal 3 (Apple silicon and recent AMD); older Macs keep the emulated path. | Choose by device capability; parity on both paths |
| **R8** | **Font metrics of updated upstream versions** (Noto 2.015, Roboto Mono 3.001) differ from the reference's copies. | `FontMetricsParityTests`; pin older upstream releases where they differ |
| **R9** | **`LightingV1Require.swift`** is a port of the reference's generated GLSL, in code. It is out of this plan's asset scope but has the same provenance. | Rewrite it from the lighting technique during P12/P16, when the MSL lighting library exists, and keep its output parity. Coordinator to confirm it is in scope. |
| **R10** | **`SceneShaders.metal`'s legacy native draw** duplicates material behaviour (CONTRIBUTING rule 8). | Once P12/P15 ship, delete the fallback draw with the "draws natively" branches, or reduce it to an error texture. Tracked, not part of these packages. |
| **R11** | **Licensing of Twemoji (CC-BY)** requires credit. | The licence file ships beside the font. The user said "no attribution" for the other product; this credit is the font licence's own requirement and is not shown in the UI. Confirm (part of D1). |
| **R12** | **Test runtime:** the gallery takes 25 min and the particle gallery 45 min, run twice (translated/native). | Packages run only their `_ONLY` subsets and `-only-testing` classes (§6.4); full runs happen only at the system milestones (§6.5) |
| **R13** | **A subset hides a cross-package regression** until the system run. For example, P3's headers could break a shader that no P3 wallpaper uses. | The subsets include every old-version user per effect. The system runs (§6.5) are scheduled as soon as a system closes, not batched to the end. A regression found there is fixed in the owning package with its targeted set. |

### 7.3 Open questions for ground truth

- Which bloom size the reference uses per scene-detail setting (LR6): this decides whether the resolution-independent radius could be the default.
- Motion blur's frame-rate dependence: confirm with a capture at two frame rates before calling it a bug (currently an OFF correction).
- PG2 (lightshafts_6)/GP1 root causes: likely found while porting the programs involved.
