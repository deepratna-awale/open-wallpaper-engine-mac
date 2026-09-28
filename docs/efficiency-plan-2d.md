# Scene 2D efficiency plan

Goal: **look fast while being fast.** The least CPU, GPU and memory wins. Output does not have to match pixel for pixel, but perceived quality must not drop. Behaviour (what moves, and how) stays faithful to Wallpaper Engine. Heavy work is paid once, in the background, and never on the main thread or the render thread.

Sources: `docs/roadmap.md` (item 10, measured costs), the optimisation audit `scene-2d-effects.md` (IDs T1…O1 below refer to it), `SceneMetalRenderer.swift`, `EffectGraphRenderer.swift`, `ScenePostProcess.swift`, `SceneWallpaperViewModel.swift`, `TEXParser.swift`.

## 0. Measured baseline

Re-measured by WP0-A on 2026-09-28 at `cbf5b894`: M4 (10-core GPU), AC power, optimised build (Debug config with `-O`; the Release test host lacks Sparkle), `SceneFrameBenchmarkTests` with `OWE_SCENE_BENCH_JSON`. Median of 3 runs, 60 measured frames each after 2.5 s warm-up. Machine-readable rows (every variant, both sizes): `docs/efficiency-baseline-2d.json`.

Full scene, 3840×2160 (1920×1080 in brackets where it differs by more than 20 %):

| Wallpaper | GPU ms median / p99 / min | GPU ms, effects off | Effect MPix/frame | Render-thread CPU ms (wall / thread) | Load s (content + first frame) | Peak GPU alloc MB | Footprint MB |
|---|---|---|---|---|---|---|---|
| Tsunade 3742916237 | 31.3 / 52.8 / 16.5 | 2.9 | 245 | 0.66 / 0.57 | 0.24 + 0.03 | 649 | 1019 |
| One piece girls 3270035750 | 29.5 / 51.9 / 21.2 (22.6 / 27.1 / 17.6) | 5.3 (2.6) | 501 | 0.67 / 0.67 | 0.25 + 0.04 (first compile 0.62) | 1218 (1086) | 1671 |
| Lofi Cafe 2370927443 | 27.5 / 39.8 / 14.7 | 8.9 | 120 | 1.69 / 1.50 | 0.74 + 0.04 | 625 | 1293 |
| Dance Club 2176097362 | 20.8 / 39.6 / 9.9 (11.6 / 23.5 / 4.4) | 5.7 | 147 | 1.01 / 0.85 (2.43 / 2.13) | 0.36 + 0.06 | 1412 (1175) | 2325 |
| 3803167460 (“witcher (beta)”) | 23.8 / 37.8 / 13.3 | 11.5 | 115 | 1.25 / 1.11 | 0.53 + 0.04 | 1010 | 2116 |
| Kamado 3245833232 | 27.3 / 52.1 / 14.4 | 13.8 | 110 | 0.94 / 0.83 | 0.33 + 0.02 | 681 | 1823 |

Reading the numbers:
- Effects are 55–90 % of GPU time everywhere; Tsunade and One piece girls are almost all effect cost (effects off: 3–5 ms). Effect MPix does not depend on display size (effects run at texture size), so 1080p saves little.
- GPU time is noisy: medians sit well above the least frame (1.5–2.5×), and p99 is up to 2× the median. Diff the median of 3 runs, and treat < 10 % as noise.
- Render-thread CPU is 0.6–2.4 ms a frame. Lofi Cafe and 3803167460 spend more with effects off than on at 1080p (particles and scripts no longer wait behind the GPU), so the wall number includes waits; the thread-CPU column is the one to diff.
- Load: content preparation 0.24–0.74 s on the calling thread (the test's main thread; `SceneWallpaperViewModel.metalContent()`), first frame 0.02–0.06 s once pipelines are warm; a cold pipeline compile adds about 0.6 s (One piece girls, first variant).
- Footprint is the test process, cumulative across wallpapers in one run (it includes the previous wallpapers' caches), so only its growth per wallpaper and the GPU allocation column are comparable between packages. Peak GPU allocation is `MTLDevice.currentAllocatedSize`.

Older figures from the roadmap and audit, kept for reference: dino_run text raster 35 ms stall on the render thread; script-created layers 2–4 frames late (both not re-measured by this benchmark).

Memory: a 2760×4466 RGBA8 target is 49 MB. Each dynamic effect layer holds 2–4 of them. Each decoded texture also keeps a CPU copy in 3 places (C1). The composite pass costs about 118 MB of bandwidth per frame at 5K. The scene target is 5–18 % larger than the display (S1).

All later packages report against these numbers: run the benchmark with `OWE_SCENE_BENCH_JSON` and diff against `docs/efficiency-baseline-2d.json`.

## 1. Ideas not in the decided list (new)

Evidence is from the audit (A) or from reading the code (C).

- **N1 Dirty-rect scene pass (new).** When the only thing that changes is a small layer over a flattened background (a clock, a blinking eye, a small particle emitter), redraw only the union of the changed layers' spill bounds. Use a scissor, `.load` on the retained scene target, and present that. The foundation's coverage data gives the rects. Evidence (C): `SceneSnapshotTracker` already tracks changed regions for snapshots, so the maths exists. Expected: most of a frame's cost disappears on clock-style scenes.
- **N2 Native raw texture formats (A: T1, H1).** Upload R8, RG88 and RGBA8888 straight from the LZ4 output as `.r8Unorm`, `.rg8Unorm` and `.rgba8Unorm`, and half-float formats as `.r16Float`/`.rgba16Float`. Today they are expanded to RGBA8 in Swift loops and routed through `NSImage`. Saves load CPU and ¾ of mask memory.
- **N3 Upload dedup (A: T2).** One GPU texture per loader cache key. Particles and their materials currently upload the same image twice.
- **N4 Drop CPU copies after upload (A: C1).** `NSCache` has no cost limit, and `assetDataCache` keeps the raw `.tex` bytes.
- **N5 Per-pass CPU (A: E3).** Resolve pipeline states once into `LayerState`, precompute `repeatingFBOs`, and compare chains by plan identity instead of by a `[[String]]`.
- **N6 Pooled and aliased scratch targets (A: P1, E1).** Ping and FBO targets come from a per-frame pool backed by the scene heap, with `makeAliasable()` after their last read. A static chain's scratch is released once its output is cached.
- **N7 MSAA store actions (A: MS1).** Use `.multisampleResolve` on the final segment and do not store the samples.
- **N8 Private storage + `optimizeContentsForGPUAccess` (A: G1)** for uncompressed textures, so they get lossless compression.
- **N9 Text cache byte budget (A: M1).** 32 MB, LRU.
- **N10 Thermal and Low Power Mode response (new).** Read `ProcessInfo.thermalState` and `isLowPowerModeEnabled` and move the Quality↔Efficiency slider's effective position one step towards efficiency at `.serious`, and cap the rate at 30 fps at `.critical`. Evidence (C): nothing in `Core/Playback/PlaybackRules.swift` reacts to either today.
- **N11 Pipeline prewarm from the scene cache (new).** Store the pipeline descriptors that were actually used in the scene cache, and compile them into `EffectPipelineArchive` during preparation. This removes the first-frame pipeline stalls that remain when a variant was never seen before.

## 2. Dependency graph

```
WP0 baseline + guard-rails
   │
   ├── F: Layer analysis foundation (dependencies / coverage / dirty)   [Phase 1]
   │      ├── Flattening (1)  ── N1 dirty-rect
   │      ├── Culling (2)
   │      └── Adaptive rate / idle skipping (9) ── Multi-display rates (16)
   │
   ├── P: Preparation pipeline (bounded work pool, scene cache file)     [Phase 1]
   │      ├── Textures (10, N2, N3, N4, N8)
   │      ├── Parallel loading + preview crossfade (14)
   │      ├── Scene-level resources: heap, argument buffers, atlases (11, N6)
   │      ├── Pipeline prewarm (N11)
   │      └── Prepare on arrival + library indicator (15)
   │
   ├── Shader work (3 fusion, 6 half precision) – independent, owns Scene/Shaders
   ├── Pass work (4 memoryless, 5 reduced-res blur, 7 composite/target/drawable, N7, N5)
   ├── MetalFX (8) – needs 7 (exact target) and F (text/line-art layer classes)
   ├── Text (12) + script layers same frame (13)
   └── App: main-thread offenders (18), settings slider (17), N10
```

## 3. Hot shared files and staging rules

- **`Scene/Rendering/SceneMetalRenderer.swift` (3410 lines)** is touched by almost every package. Rules:
  - Each package adds its logic in **its own new file** (an `extension SceneMetalRenderer` in `SceneMetalRenderer+<Area>.swift`, or a new type). Its edits to `SceneMetalRenderer.swift` itself are limited to calls (hooks) of at most about 15 lines per hunk.
  - Only one package per phase is the **owner** of `SceneMetalRenderer.swift`. Other packages in the same phase send their hook hunks to the owner as a patch in their report (`git diff -U3 -- <file>` of the hunk), and the coordinator applies them at integration. Packages stage only their own hunks with `git add -p` and commit with `git commit -- <owned files>`.
- The same rule applies to `EffectGraphRenderer.swift`, `SceneWallpaperViewModel.swift`, `ScenePostProcess.swift` and `Settings/SettingsView.swift`: one owner per phase, and patches from everyone else.
- Moves and renames are their own commit, contain no logic, and must build (CLAUDE.md).
- Any change to translated shader output bumps `ShaderVariantTranslator.revision` (`Scene/Shaders/ShaderVariant.swift:54`, now 10) and re-records the `ShaderRevisionGuardTests` fixture. Only the shader package of a phase may bump it.

## 4. Correctness rules shared by all packages

- **Behaviour** (positions, timing, animation, scripts, audio response) must match the pre-change run exactly: the existing unit tests plus `SceneDetailEquivalenceTests`.
- **Pixels** may change when they pass perceptual thresholds against the pre-change render, measured at 1080p and 4K over frames 0, 30 and 120:
  - SSIM ≥ 0.995 for lossless-in-intent changes (culling, flattening, fusion, memoryless targets, exact target size). These should in fact be near byte-identical; anything below 0.999 needs an explanation in the report.
  - SSIM ≥ 0.98 **and** a per-pixel ΔE2000 99th percentile ≤ 2.0 for lossy changes (half-res blur, half precision, BC7, MetalFX).
  - Text and line-art regions (a mask from F's layer classes) must reach SSIM ≥ 0.995 in every mode.
- New shared helper: `OpenWallpaperEngineTests/Support/PerceptualCompare.swift` (`ssim(_:_:)`, `deltaE99(_:_:)`, with an optional region mask). It is written by WP0-B and used by all packages.
- Fixtures are 5 heavy wallpapers from `/Volumes/980Pro/OpenWallpaperStorage` (linked through `OWE_LIBRARY`) plus the CI assets in `TEST_RUNNER_OWE_ASSETS`. Tests skip when a wallpaper is missing.
- **Scene Inspector:** a layer being edited is always marked dirty and live. It is never flattened, culled or served from a cache. The cache key of every derived cache includes a hash of the saved edits. Caches rebuild in the background when the Inspector closes, or when edits are saved or reset.

## 5. Metrics every package reports

In `SceneFrameBenchmarkTests`, for Tsunade, One piece girls, Lofi Cafe, Dance Club and 3803167460 (Kamado when present), at 1920×1080 and 3840×2160, before and after:

- GPU ms/frame (mean and p99), effect MPix/frame, and render-thread CPU ms (`OWEFrameMetrics`);
- peak `MTLDevice.currentAllocatedSize` and process footprint;
- load time to first live frame, and to the first frame of any kind (the preview);
- energy where possible: `powermetrics --samplers gpu_power,cpu_power -i 1000 -n 30` while the wallpaper plays, run by the coordinator only (it needs sudo);
- the SSIM and ΔE numbers from §4.

Benchmarks run one xcodebuild at a time, with derived data at `/Volumes/980Pro/.claude/dd-<package>`, `DEVELOPER_DIR=/Volumes/980Pro/Applications/Xcode.app/Contents/Developer` and `-only-testing:` limited to the package's tests.

## 6. Guard-rails (built in Phase 0, enforced from then on)

- **Thread assertions** (`Core/Diagnostics/ThreadGuards.swift`, new):
  - `assertNotMainThread(_ what:)` and `assertNotRenderThread(_ what:)`, debug-only (`#if DEBUG`), which call `assertionFailure` and log through `OWELog`. The render thread is identified by a thread-local flag set in the render loop's entry.
  - They are placed at the entry of every heavy function: `TEXParser.extractContainerImage`, texture decode and compression, shader translation (`ShaderCompiler`), `makeRenderPipelineState` (sync), font raster, `project.json` parsing and scene-cache reads and writes.
  - Additionally `assertRenderThread()` goes into per-frame functions that must not run elsewhere.
- **Hang watchdog** (`OpenWallpaperEngineTests/Support/HangWatchdog.swift`, new): a test base class feature that pings the main run loop every 50 ms and fails the test when the main thread goes more than 250 ms without answering, or when the render thread goes more than 100 ms between frames after the first frame. It is on by default in the render and benchmark tests.
- **Work pool** (`Core/Concurrency/PreparationPool.swift`, new):
  - A bounded pool: `ProcessInfo.activeProcessorCount - 1` workers at `.utility`, and 2 at `.background` during library preparation.
  - A memory budget in bytes (default: min(1 GB, 10 % of physical RAM)). A job declares its estimated peak bytes, and waits when the budget would be exceeded. One job larger than the budget runs alone.
  - Jobs can be cancelled and prioritised: the wallpaper that is being set comes first, then the displays' current wallpapers, then the library.
- **Power policy** (`Core/Playback/PowerPolicy.swift`, new): on battery, library preparation waits for charging, or for 2 minutes of user idle with more than 50 % charge. Preparation for a wallpaper that is being set always runs. Low Power Mode and thermal state feed N10.

## 7. Phases and work packages

Three packages run in parallel in each phase. The files named are owned exclusively for that phase. "Hooks" are hunks given to the owner of the hot file.

### Phase 0: baseline and guard-rails

**WP0-A Baseline and benchmark extensions.** Owns `OpenWallpaperEngineTests/SceneFrameBenchmarkTests.swift` and `OpenWallpaperEngine/Scene/Rendering/EffectPassTimer.swift`.
- Add load-time, memory-peak and render-thread CPU columns, and a JSON output (`OWE_SCENE_BENCH_JSON=<path>`) that later packages diff against.
- Run the 6 wallpapers and write the numbers into §0 of this document.
- Risk: noise. Run 3 times and report the median, on AC power.

**WP0-B Perceptual comparison + hang watchdog.** Owns `OpenWallpaperEngineTests/Support/PerceptualCompare.swift` and `HangWatchdog.swift` (both new).
- Tests: SSIM of an image with itself is 1, and a 1-px shift of a text image falls below 0.995.

**WP0-C Thread guards, work pool, power policy.** Owns `Core/Diagnostics/ThreadGuards.swift`, `Core/Concurrency/PreparationPool.swift` and `Core/Playback/PowerPolicy.swift` (all new), with call-site hunks in `TEXParser.swift` and `ShaderCompiler.swift`.
- Tests: pool budget (jobs wait, and never exceed the budget), cancellation, priority order. Assertions fire in a debug test that calls a guarded function on the main thread (with the assertion handler swapped for a test hook).
- Risk: assertions firing on existing paths. This is the point: list every hit in the report, don't silence it; the hits become Phase 1 work for WP1-C.

### Phase 1: the two foundations + main-thread offenders

**WP1-A Layer analysis foundation (F).** Owns `Scene/Rendering/SceneLayerAnalysis.swift` (new) and `SceneMetalRenderer.swift` (owner for this phase, hooks only).
- Design: `SceneLayerAnalysis` is built from the prepared content (`SceneRenderContent`) at load, and updated per frame in O(layers). For each layer it holds:
  - `dependencies`: the set of time-varying inputs, as a bit set: time, cursor, parallax, shake, audio, script writes, timelines, user properties, video, particles, sampling the frame beneath (`_rt_FullFrameBuffer`, `_rt_MipMappedFrameBuffer`, a composite source), and the Inspector.
  - `coverage`: the screen-space bounds including effect spill (the effect plan's maximum UV offset × the layer size, conservatively the whole layer target for passes whose offset can't be bounded), and an `opaque` flag (normal blend, alpha 1 constant, a texture known opaque from its format or a preparation-time alpha scan, and no effect that can write alpha < 1).
  - `dirty(frame)`: whether any dependency changed this frame. Script-driven properties are dirty when the script wrote them, not every frame.
  - A `class` per layer: text, line art (a preparation-time edge-density heuristic on the texture, *or* a text layer), or photo/painting. MetalFX and half-res blur use it.
- Correctness: conservative. Unknown means dynamic, unbounded means full screen. A test mutates every dependency kind one by one on the CI scenes and asserts that the layer goes dirty. A fuzz test over all CI scenes asserts that a frame rendered with `dirty == false` layers taken from the previous frame matches the full render (SSIM ≥ 0.999).
- Metrics: analysis CPU per frame (target < 0.05 ms for 200 layers).

**WP1-B Preparation pipeline + scene cache (P).** Owns `Scene/Loading/ScenePreparation.swift`, `Scene/Loading/SceneCacheFile.swift` (new) and `SceneWallpaperViewModel.swift` (owner for this phase).
- Design:
  - One cache file per wallpaper and variant at `<Wallpaper Storage>/.owe-cache/<workshopID>/<key>.owescene`, where key = hash(project files' mtimes and sizes, the saved Inspector edits, user properties that change the content, display pixel size and scale, settings that affect preparation, app build, `ShaderVariantTranslator.revision`, the GPU family).
  - Contents (versioned, memory-mapped, little-endian, 16-byte aligned): the parsed scene plan, the per-layer analysis seeds, the texture blobs (§ WP2-A), shader variant names, pipeline descriptors (N11).
  - `ScenePreparation.prepare(wallpaper:displays:priority:)` runs stages as pool jobs: parse → textures → shader variants → pipelines → analysis → write the file atomically (write to a temp file, then `rename`).
  - Loading prefers the cache; a miss falls back to today's path and schedules a preparation.
- Risks: a stale cache. The key covers everything that feeds it; a corrupt or foreign-version file is deleted and rebuilt. Disk use is capped (default 4 GB, LRU by last use).
- Tests: key changes on each input; a truncated file is rejected; loading from the cache equals loading from source (SSIM ≥ 0.999 and equal plan dumps).

**WP1-C Main-thread offenders (18) + guard hits.** Owns `App/Playback/DisplayPlaybackMonitor.swift`, `AppDelegate+DisplayPlayback.swift`, `Library/WEProject.swift`, `Video/VideoMusicSync.swift`, `Core/Settings/GlobalSettingsService.swift`.
- Replace the 0.5 s window scan with `NSWorkspace` notifications (activation, space change, screen sleep) plus a debounced `CGWindowListCopyWindowInfo` scan on a background queue, only while a rule that needs it is enabled.
- Parse `project.json` once, and apply property changes to the in-memory model.
- Read settings once into a value snapshot that is refreshed by an observer, not inside the video sync loop.
- Fix every thread-assertion hit from WP0-C that lies in these files, and list the others.
- Tests: `DisplayPlaybackMonitorTests` extended with notification-driven cases; a test counting `project.json` reads on 10 property changes (must be 0).
- Metrics: main-thread CPU % over 60 s idle with 2 displays (Instruments Time Profiler or `OWEFrameMetrics`).

### Phase 2: consumers of the foundations, round 1

**WP2-A Textures (10, N2, N3, N4, N8).** Owns `Scene/Format/TEXParser.swift`, `Scene/Rendering/SceneTextureUpload.swift`, `Scene/Loading/TexturePreparation.swift` (new), `Scene/Loading/TextureCompressor.swift` (new).
- Design:
  - N2: native R8/RG8/RGBA8 and half-float uploads.
  - Upload every stored mip level (T3) for BC and raw `.tex`.
  - Exact on-screen size: at preparation, for a layer whose on-screen size is fixed (from F: no scale dependency), resample once from the full original with a Lanczos-3 filter in linear light to the display pixel size × 1.0 (or the maximum over connected displays). Then build mips, and compress to BC7 (the encoder is to be chosen at implementation: bc7enc-rdo or a Metal compute encoder; compare against ASTC 4×4 on Apple GPUs and keep whichever gives better SSIM per byte and GPU time).
  - Layers whose size changes use WE's stored mips and stream levels in as the scale needs them.
  - Masks, flow maps, normal maps and any texture an effect reads as data (from the effect plan's texture slots: `mask`, `flow`, `normal`, `noise`, lookup tables) are never compressed or resampled.
  - `g_Texture*Resolution` keeps reporting the original size and mip info, as WE would, whatever size is uploaded.
  - N3 (dedup by key), N4 (drop CPU copies, cost limit on `NSCache`), N8 (private storage).
  - The Settings toggle is "Optimise textures" (default on), owned by WP2-C's settings hunk.
- Risk: a wrong resample size on layers that zoom (camera zoom, parallax scale). F's scale dependency decides; unknown means keep the original.
- Tests: `TextureRG88Tests`, `TextureUploadTests`, `TextureReductionTests`; new: every resolution uniform stays unchanged; masks stay bit-exact; SSIM thresholds on the 5 wallpapers.
- Metrics: GPU ms (sampling cost), memory, load time cold and cached, disk size.

**WP2-B Flattening (1), culling (2) and N1 dirty-rect.** Owns `Scene/Rendering/SceneFlattening.swift`, `SceneCulling.swift` (new), and `SceneMetalRenderer.swift` (owner this phase, hooks only).
- Flattening: runs of consecutive layers whose `dependencies` are empty (or all unchanged since the run was drawn) draw once into a cached target the size of the scene target, and draw as one quad. A run is broken by any layer that samples the frame beneath, any composite source (`_rt_imageLayerComposite`), and any live Inspector layer. Invalidation is exact: the run's key is the set of its layers' dependency versions; a changed version redraws the run in the same frame.
- Culling: skip alpha-0 layers (any blend mode except those that write alpha on `normal` with an effect), layers whose spill bounds miss the scene target, and layers fully under one opaque layer. Occlusion culling is disabled when anything above samples the frame beneath. Composite sources are never culled.
- N1: when every flattened run is clean and the dirty layers' union covers < 40 % of the target, retain the scene target, draw the flattened background into the dirty rects only and redraw the dirty layers with a scissor.
- Risk: memory for flattened targets. Cap at 2 full-scene targets per scene; merge beyond that.
- Tests: for each CI scene, flattened on vs off over 120 frames with a moving cursor and audio: SSIM ≥ 0.999. Culling counters in `OWEFrameMetrics`.
- Metrics: GPU ms, draw calls, memory.

**WP2-C Adaptive rate and idle skipping (9), settings slider (17), N10.** Owns `Core/Playback/FramePacing.swift` (new), `Core/Playback/PlaybackRules.swift`, `Core/Settings/GlobalSettings.swift`, `Settings/SettingsView.swift` (owner this phase).
- Design: each frame, F reports the fastest-changing dependency among the visible dirty layers. The rate is chosen from {max, 60, 30, 15, 0 (idle)}:
  - cursor, parallax and particles under the cursor → max;
  - smooth motion (timelines, scripts moving layers, particles) → 60 or 30 per the slider;
  - slow content (clock seconds, slow scroll) → 15;
  - nothing dirty → don't encode or present (A1), and wake on any dependency event.
  - The slider (Quality ↔ Efficiency, 5 stops, default stop 4) maps to the rate cap for smooth motion, the MetalFX scale and the half-res blur switch; WE's presets keep working and set the slider's position.
  - N10: thermal and Low Power Mode move the effective stop.
- Risk: a visible stutter when the rate changes. Ramp up at once, and ramp down only after 1 s of lower demand. Present at the display's `CADisplayLink` cadence divisor.
- Tests: rate decision table unit tests; the hang watchdog on a scene that goes idle and wakes on a cursor move (the first moved frame within 1 display refresh).
- Metrics: energy on an idle static scene (target near zero GPU), and average rate on the 5 wallpapers.

### Phase 3: pass work and shaders

**WP3-A Final-stage work (7, N7, N5).** Owns `Scene/Rendering/ScenePostProcess.swift`, `SceneRenderResolution.swift`, `EffectGraphRenderer.swift` (owner this phase), and `SceneMetalRenderer.swift` hooks (owner this phase).
- Skip the composite when post-processing is identity (S2), size the scene target exactly once the size is stable (S1), take the drawable just before `postProcess.encode` (F1), MSAA store actions (N7), and per-pass CPU (N5).
- Tests: `ScenePostProcessTests`; the composite-skip output equals the composite output byte for byte.
- Metrics: GPU ms at 5K and on a 14" MacBook Pro size, drawable hold time, render-thread CPU.

**WP3-B Shaders: fusion (3) and half precision (6).** Owns `Scene/Shaders/*` and `OpenWallpaperEngineTests/ShaderRevisionGuardTests.swift`.
- Fusion: fuse consecutive passes when the later pass reads the earlier pass's output **only at its own varying UV** (proved by the translator: every `texture(g_Texture0, v_TexCoord)` with no offset, no LOD, no gather), both have the same target size and format, and no other pass or FBO reads the intermediate. The audit found most WE passes sample neighbours, so fusion applies only where the proof holds; the translator emits a combined fragment function.
- Half precision: use `half` for colour math in fragment functions whose target is 8-bit, and keep `float` for UV, positions, time and anything feeding a texture coordinate.
- Bump `revision` once for the package, and re-record the fixture.
- Risk: banding from half precision in gradients. The ΔE threshold catches it; a shader can opt out by pattern.
- Tests: fused vs unfused SSIM ≥ 0.999; half vs float ΔE99 ≤ 2.0 on the 5 wallpapers plus all CI scenes.

**WP3-C Reduced resolution + memoryless (4, 5) + scene resources (11, N6).** Owns `Scene/Rendering/SceneRenderTargetPool.swift`, `Scene/Rendering/SceneHeap.swift` (new), `Scene/Rendering/EffectResolutionPolicy.swift` (new), with hooks to `EffectGraphRenderer.swift` (via WP3-A).
- Blur, bloom, glow and god-ray passes (from the effect's file name and the pass shader's pattern, not per wallpaper) render at ½, or ¼ at the efficiency end of the slider, and are upsampled bilinearly in the next pass that reads them. A pass whose result feeds a sharp edge (the layer class is text or line art) stays full size.
- Memoryless intermediates: only for a fused pair from WP3-B that still needs two render passes in one encoder (a tile shader or programmable blending, where the next pass reads the same pixel), and for depth and MSAA attachments that are never read.
- Scene resources: one `MTLHeap` per scene for targets and textures sized from the analysis, aliasing for scratch (N6); argument buffers for material textures; atlases only for particle sprites ≤ 256 px.
- Tests: `SceneRenderTargetPoolTests`; the ΔE and SSIM thresholds per wallpaper at ½ and ¼.
- Metrics: GPU ms, effect MPix, memory.

### Phase 4: loading, text and scripts

**WP4-A Parallel loading, preview crossfade and N11 (14).** Owns `Scene/Loading/SceneWallpaperPresenter.swift`, `SceneWallpaperView.swift`, `Scene/Shaders/EffectPipelineArchive.swift`, and `SceneWallpaperViewModel.swift` (owner this phase).
- Decode, compress, translate and create pipelines as pool jobs. Show the preview image at once and crossfade (250 ms) to the live scene. Draw layers that are ready, and upgrade the rest as they arrive (a missing layer draws nothing, as WE does before its textures load, and never a wrong texture).
- Tests: load order independence (the final frame equals a serial load); the hang watchdog during load.
- Metrics: time to first frame and to the live scene, cold and cached.

**WP4-B Text (12) and N9.** Owns `Scene/Rendering/TextLayout.swift`, `Scene/Rendering/SceneTextRaster.swift` (new), `SceneLRUCache.swift`.
- Raster on a pool job with double buffering: the render thread keeps drawing the previous raster until the new one is ready (at most 1 frame late, instead of a 35 ms stall). A glyph cache (glyph id, font, size, scale) so a clock redraws only changed glyphs into its layer texture. Byte-budgeted LRU (N9).
- Tests: `SceneRetinaTextTests`, `SceneTextLayoutTests`; dino_run score stall < 1 ms on the render thread.

**WP4-C Script layers in the same frame (13).** Owns `Scene/Scripting/Host/SceneScriptWallpaper.swift` and the script layer creation path, with a hook to `SceneMetalRenderer.swift` (via WP4-A's coordinator patch).
- Create the layer's GPU state synchronously from already-prepared resources when the script creates it, and fall back to the next frame only when a texture is not yet loaded (then load with high priority).
- Tests: a script creating a layer at frame N draws it in frame N (`SceneScriptWallpaperTests`).

### Phase 5: MetalFX, prepare on arrival, multi-display

**WP5-A MetalFX spatial upscaling (8).** Owns `Scene/Rendering/SceneUpscaler.swift` (new) and `SceneMetalRenderer.swift` hooks (owner).
- For heavy scenes (the benchmark's measured GPU time over the rate's budget), render the scene below native (0.67–0.8 by the slider) and upscale with `MTLFXSpatialScaler`. Text and line-art layers (from F's class) draw after the upscale, at native size, into the output. A layer that sits under a sampled-frame effect stays in the scaled pass.
- Tests: text regions SSIM ≥ 0.995; the whole frame ΔE99 ≤ 2.0.

**WP5-B Prepare on arrival (15).** Owns `Library/InstalledLibrary.swift`, `Library/Import/*`, `Library/LibraryPreparationScheduler.swift` (new), the library item views, and `Settings/SettingsView.swift` (owner: cache size and Clear Cache in Settings › Performance).
- After a Workshop download or import, and once over the existing library ordered by use count, schedule `ScenePreparation.prepare` for each connected display size, under the power policy. A "preparing" or "ready" badge on library items.
- Tests: the scheduler's order and power deferral; Clear Cache removes the files and the badges return to "not ready".

**WP5-C Multi-display (16).** Owns `Core/Playback/DisplayPlayback.swift`, `Library/DisplayPlaybackRouting.swift`, and `Core/Playback/FramePacing.swift` (from WP2-C).
- A rate per display, with a focus-aware budget (the display with the cursor or the focused app gets the high rate). The same wallpaper on displays of different sizes renders once at the larger size and is scaled (extends `renderShared`). A sleeping or fully covered display releases its targets and resumes with a crossfade from the preview.
- Tests: rate assignment; the release and resume path under the hang watchdog.

## 8. Integration order and full test runs

1. Each package commits only its owned files and reports patches for hot files it does not own.
2. At the end of each phase the coordinator applies the patches in the order the phase lists, builds, runs the **full test suite** (only the coordinator runs it, one xcodebuild at a time), runs the benchmark on the 6 wallpapers, and updates §0 with the new numbers.
3. A package whose numbers regress or whose thresholds fail is reverted from the phase and redone; the others stay.
4. Phases run in order 0 → 5. Within a phase the listed packages run in parallel (3 at a time).
5. After Phase 5: update `docs/roadmap.md` and `docs/progress-snapshot.md` with the final numbers.
