# Optimisations

The project's record of what was tried to make wallpapers cheaper, what shipped, what was rejected, and why. Every number names its source: a PR, a commit, or a measurement file in the repo. A change whose numbers are not written down yet is listed without them.

The detailed 2D plan, its baseline and its audit are in [`efficiency-plan-2d.md`](efficiency-plan-2d.md) and [`efficiency-baseline-2d.json`](efficiency-baseline-2d.json).

## Rules

- The least CPU, GPU and memory wins.
- Pixel changes are fine if perceived quality holds. Checks are perceptual (SSIM, ΔE), not byte equality.
- Keep an optimisation only if it measurably wins. The 2D audit's bar: roughly ≥ 5 % GPU ms or ≥ 50 MB on at least two wallpapers, a large load-time cut, or idle GPU going to zero.
- Never cap effects, passes, shaders or particles to save cost.
- Behaviour stays faithful to Wallpaper Engine. No per-wallpaper hacks.
- Heavy work runs once, in the background, never on the main or render thread.

## How it is measured

- Scenes: `SceneFrameBenchmarkTests` on an -O build, 3840×2160 (and a second size), alternating off/on runs, medians. GPU time is noisy: medians sit 1.5–2.5× above the fastest frame, so under 10 % is treated as noise (efficiency-plan-2d.md §0).
- Load: content load of the same wallpaper with the change off and on, 3 runs (PR #76).
- Baseline wallpapers and numbers: efficiency-plan-2d.md §0.

## Shipped

### Scene rendering

| Change | Measured | Source |
|---|---|---|
| Idle skipping and adaptive frame rate | One piece girls encodes 0 of 120 frames when idle (GPU 0); animated scenes unchanged | efficiency-plan-2d.md §9 |
| Identity-composite skip and late drawable | Dance Club and Tsunade −5 to −7 %, Kamado −4 to −5 %, witcher −3 to −5 % GPU | efficiency-plan-2d.md §9 |
| Blur, bloom, glow and god-ray buffers at ½ (slider stop 4) | Lofi Cafe 11.8 → 10.8 ms, Tsunade 14.2 → 13.5 ms; others ±1 % | efficiency-plan-2d.md §9 |
| Optimise textures (BC7 and full mips, on by default) | GPU texture memory −5 to −30 MB on five wallpapers; One piece girls 339 → 144 MB, load 1.30 → 0.35 s | efficiency-plan-2d.md §9 |
| Per-layer analysis | Needed by idle skipping; render-thread CPU 0.4–3.6 ms per frame against 0.4–1.7 ms at the baseline | efficiency-plan-2d.md §9 |
| Decoded images dropped after upload; two drawables at ≤ 60 fps | One 5K BGRA drawable is about 59 MB | PR #21 |
| Scene drawing on a dedicated render thread | Frames keep coming during a 0.5 s main-thread stall | PR #22 |
| Text rasterised on a pool job | Removes the 35 ms render-thread stall measured on dino_run | commit 79f23b31, efficiency-plan-2d.md §0 |
| BC7 encoding on one pool thread instead of every core | Background compression no longer uses every CPU core | commit bbc95b91, PR #24 |

### Video, web and audio

| Change | Measured | Source |
|---|---|---|
| Redraw a video layer only on a new frame; effect-less video straight into the drawable | 4K test video: 180 → 24 frames drawn, GPU 550 → 49 ms over 3 s | PR #23 |
| Lossless hev1/avc3 → hvc1/avc1 remux | Only `moov` is rewritten; `mdat` is streamed in 4 MB chunks, never loaded | PR #65 |
| Covered, muted web wallpapers suspended; one web process per page shared by displays; audio delivery stops while paused | Not measured as numbers | PRs #8, #12, commit 127aff1a |
| System audio capture only while a wallpaper needs it; spectrum DFT padded to 4096 points for the 640 bins it keeps | Not measured as numbers | PRs #7, #20 |

### Particles, 3D and puppets

| Change | Measured | Source |
|---|---|---|
| Particle definition cache: copies of one definition share its built parts | Load: rain (1444077782) 1.33–1.51 → 0.47 s; Katana (3238423642) 6.9–7.1 → 1.6 s. Material plan step on rain 1399 → 395 ms | PR #76 |
| Material-plan shader memo: parsed stages and folded geometry reused across plans | Particle material-plan time per load, first / reload: Katana 754 → 313 / 674 → 171 ms, Sylvanas (1464416607) 163 → 44 / 160 → 39 ms, rain 320 → 76 / 319 → 70 ms, Lonely Cat (3299228616) 172 → 44 / 173 → 39 ms (helped by the memo already holding rain's shaders). Katana's content build about 1.8 → 1.0 s on first load. Shader variant keys byte-identical | PR #87 body and comment |
| Shadow CPU cost (3D models plan, optimisation O) | 3657770939 45–63 → 13.5–17 ms, 3734636606 65–72 → 28.5–32 ms (Debug); output byte-identical | dd-decisions log, 3D models plan |
| Cheaper shadows: maps at half size, depth-only casters | Not measured as numbers | PR #54 |
| Empty systems skip GPU steps, O(n) rope neighbours, refraction copies only its rect, particle mip chains, instanced systems sized from spawn bound | Not measured as numbers | PRs #15, #17, #23 |
| Per-mesh culling, split vertex streams, meshes uploaded at load with no CPU copy | Not measured as numbers | PRs #13, #19, #23 |
| Unchanged puppets skip re-posing | Not measured as numbers | PR #6 |

## Rejected or dropped

| Change | Measured | Why | Source |
|---|---|---|---|
| Particle batching (one draw per group of same-material systems) | Rain: about 0.8–0.9 ms render CPU per frame (524 → about 170 dispatches); Katana ≤ 0.1–0.5 ms, within noise. Both are GPU-bound (rain GPU 64–66 ms) | Too small; GPU time dominates | `batching-measure` probe, 2026-10-01 |
| Particle JSON parse cache alone | ≤ 5 ms per load | Not worth it; the cost is in building systems (see the definition cache) | same probe |
| Culling (2D) | ±2 % on all six baseline wallpapers | No win | efficiency-plan-2d.md §9 |
| Bottom-run flattening | One piece girls −5 to −8 %, others ±2 % | Wins on one wallpaper only | efficiency-plan-2d.md §9 |
| Pass fusion | Dance Club −7 to −10 %, others −3 to +3 %; many fused variants failed to translate | One wallpaper, and fragile | efficiency-plan-2d.md §9 |
| Half colour outputs in shaders | −0 to −2 % | Noise; reverted, translator revision 12 | efficiency-plan-2d.md §9 |
| Per-scene heap, exact scene-target size, chain-key caching | −3 to +2 % GPU, memory within 30 MB, CPU unchanged | No win | efficiency-plan-2d.md §9 |
| On-disk scene cache file | Load 29–58 ms either way (within 1 ms) | No win | efficiency-plan-2d.md §9, commit 29cbf018 |
| project.json, music-sync values and a settings snapshot in memory | Cached lookup 29 µs vs 13–32 µs read and parse; a UserDefaults read is 0.3 µs | No win | efficiency-plan-2d.md §9 |
| Native Y'CbCr video decode with GPU conversion | Memory BGRA +70 MB vs YUV +128 MB on a 4K video | Three RGBA targets outweigh the smaller NV12 pool | PR #18 (closed) |
| Distance-fog model skip | — | Reverted | commit b396cc38 |
| Bundled video decoder | — | The lossless remux (PR #65) plays the same files with the system decoder | PR #65 |
| Live lock-screen wallpaper | — | Not possible on macOS; a lock-screen picture and a screen saver are offered instead | PR #72 |
| Film grain at its noise's scale | — | Not equivalent: WE's `filmgrain` samples `util/noise` (256²) at the layer's UV × `scale` × aspect, about 1.45 noise texels per pixel on rain at 4K, and the same pass carries the full-resolution image; a smaller pass would blur both | `effects/filmgrain` shaders, perf/fullscreen-effect-layers |

## Settings and storage decisions

- **Render resolution.** Display renders at the display's point size; Retina (native pixels) is opt-in; Full is the authored size. On an M4 at 3840×2160 (2×), Retina → Display: rain 45.3 → 26.2 ms GPU median (−42 %), GPU memory 713 → 473 MB. Scenes authored above 1080p save little unless scene detail is Match Display (2b 4K 18.2 → 17.6 ms, Fantasy Woman 9.0 → 8.9 ms). PR #73 comment.
- **Screen saver loops.** One video per unique display point size (not backing pixels), rendered one at a time in a background job. Loop length is the exact LCM of the timeline and sprite-sheet periods, capped at 60 s; otherwise the best perceptual match to frame 0 after 5 s, with a 0.25 s crossfade if the seam still shows. PR #72, commit e7e2ee5e.
- **Package storage.** Extracted files and the `.pkg` hold the same bytes, so keeping both would double the size. On a 69-wallpaper library: .pkg 1,045.9 MB vs loose files 1,045.7 MB of data; loose files cost 12 MB (+1.1 %) more on disk from 4 KB blocks (PR #88 comment). Originals are deleted after conversion when that setting is on.
- **Re-download on a converter bump.** Only bundles that a bump affects are re-downloaded (a per-version rule), one at a time at background priority. On a real library, 21 of 68 stale bundles were queued instead of all 68 (about 1 GB). PR #84 comment.
- **Thread guards in release builds.** Kept: on an M4 (-O), a passing check costs 2.61 ns and the renderFrame wrapper 6.71 ns, about 10 ns per frame, so no change is needed. PR #86 comment; PR #75.

## Pending

| Change | State | Source |
|---|---|---|
| Fullscreen layers drawn where a display shows them (`SceneVisibleRegion`, a scissor on every effect pass plus a 64 px margin and the farthest parallax and shake), copies between an effect's buffers handed over as textures (`EffectGraphRenderer.copyCanAlias`), motion blur's history at half size (`EffectResolutionPolicy.temporalDivisor`, slider stop 5 until measured) | Implemented, each switchable (`OWE_FX_CLAMP`, `OWE_FX_COPY_ALIAS`, `OWE_FX_HALF_ACCUM`); to be measured with `FullscreenEffectMeasureTests` (GPU ms and SSIM on rain, Tsunade, witcher) and kept only where it wins | perf/fullscreen-effect-layers |
| MetalFX upscaling (Off or MetalFX at 50/67/75 %) | Small, noisy gain: Katana fastest frame 25.9 → 21.9 ms, median about 53 ms both; Cyberpunk Samurai 2.1 → 3.2 ms (a cheap scene gains nothing). To be re-measured after point-size rendering | PR #73 |
