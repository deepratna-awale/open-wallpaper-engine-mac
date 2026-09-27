# Models ground truth (audit request, commit 7ffdb4f): partial, WE 2.8.0.42

The scripts are `setup.ps1` (copies the generated projects into WE as `mg_*` and builds the variants), `capture_mg.ps1` (records from load and checks each switch) and `pkg_replace.py` (swaps `scene.json` inside a `scene.pkg`). Captures are in `captures/`. The detailed per-item numbers are in `captures/MG_results.json` and `captures/MG1_sequences.json`.

## Done
- **MG1: PaRappa's random camera paths** (3 × 70 s; run 3 after a WE restart).
  - The first ~4 s is a fixed intro, identical in all runs, and is not one of the 13 paths.
  - After that, the 13 paths are drawn **independently, with replacement (not a bag)**. Every run repeats a path before all 13 have played.
  - No path followed itself in about 44 transitions. Pure chance would give about 3.4 such repeats, so this suggests the last path is excluded.
  - The sequence and the first random path **differ in every run** (Center In / Right to Left / Overhead), including runs 1 and 2, which had no restart between them. So there is no fixed seed.
  - Files: `MG1_run*_segments.png` (one labelled keyframe per 4.4 s segment), `MG1_sequences.json`, and `camera_paths_203.json` (extracted).
  - Label confidence: Center In/Out, Twist, Still, Rotate 1 and Overhead are solid. Left↔Right and Sunny↔PJ Focus are uncertain, but the repeat and same-sequence conclusions come from clustering and do not depend on the labels.
- **MG2: transparentsorting on the Solar system** (shadows off).
  - The workshop item and a local copy (`scene.json` swapped inside `scene.pkg`) are equivalent.
  - `transparentsorting` false shows **no visible difference** at 10 s or 20 s.
  - Caveats: the camera does not move in this scene, and the orbit lines are only about +20/255 above the background, so an ordering difference may not be visible.
  - A **loose `scene.json` next to `scene.pkg` makes WE look for every asset loose** (hundreds of "Failed opening" errors), so it must be replaced inside the pkg.
- **MG3: additive layer order.**
  - With blend 1, WE's arm points at 168.8°, which is **−x**. WE composes `base · additive`. The prediction was 171.5° for −x and −157.5° for +z.
  - With blend 0.5, WE's arm points at −175.3° (predicted −176.4°), so the additive layer is weighted by blend.
  - "Ours" gives +z (about −151°) and ignores the blend.
  - The library check (3803167460, 3803042537) is **not done**: subscribing needs the user's Chrome, which was unavailable.
- **MG4: root motion, no-flag case only.** `0x00000` loops back every second with no drift. The centre and angle at 0.5/1/2/3/4 s are in `MG_results.json`, and it matches ours to within 2–3 frames.
- **MG7 stills** (3734636606 at 10 s).
  - The cloth is **not black at any shadow quality**: mean RGB is about (157, 45, 48) for disabled, low, medium and high alike.
  - But no shadow is visible at low, medium or high either; the floor is identical to the disabled capture. So the shadow setting may not affect this scene, and this doesn't yet prove the cloth survives *active* shadows. The RenderDoc part is not done.

## Done in the second session (user away; captured with playback rules temporarily set to "run", then restored)
**Capture pitfall:** the earlier black and stale captures were **not** a locked screen. There were two causes:
1. WE's "pause when an app is maximized" rule. Two maximized windows were open on the primary monitor, so WE showed the plain Windows desktop.
2. The MG4 flagged models leaving WE's renderer stuck (see below).

- **MG4: root-motion flags.** With **any** of the six clip-flag bits set (0x00800 ... 0x10000), WE 2.8.0.42 **silently refuses to load the model**. `config.json` switches to the project, but the screen keeps the previous wallpaper even after 20 s, and nothing is logged. Each project differs from the working `0x00000` by exactly one byte of `gt_rootmotion.mdl` (offset 0x710, 00->10 for 0x01000). Loading several flagged models in a row left the renderer black until WE was restarted (`rootmotion_isolation.log` tests each variant after a clean restart). So there is no axis mapping to observe: WE does not accept these flags.
- **MG6: ortho depth.** The pixel at (960,540), 2 s after load, is **(253,0,0), red, in both `near-first` and `far-first`**. WE's orthographic 2D frame **depth-tests models**, and draw order doesn't matter. Ours (last-drawn) is wrong. Stills: `MG6_ortho_*_t2.png`.
- **MG6: collisionmodel particles and depth test.** Orange particle density inside the sphere's screen area relative to outside it, over 1.5-5 s:

| Variant | Ratio |
|---|---|
| depthtest disabled | 1.55 (particles drawn over the sphere) |
| enabled | 0.13 (particles behind the sphere are hidden) |
| shipped preview | 0.28 |

  Grid: `MG6_MG8_colmodel_grid.png`, with shipped, depth on / depth off, and hidden.
- **MG8: hidden collision model.** With the sphere's `visible` false, the sphere isn't drawn, and the particle density inside its area is **0.00%** (0.04% outside). Particles **still collide with the hidden model**.

## Done in the third session
- **MG3: library items** (subscribed via the user's Chrome; 10 s from load with playback rules temporarily set to "run", then restored).
  - `MG3_library_3803167460.mp4` (the witcher; loaded at 3.3 s) with stills at 2/4/6 s after load. The 8 s point fell past the end of the clip.
  - `MG3_library_3803042537.mp4` (loaded at 1.5 s) with stills at 2/4/6/8 s.
  - Overviews: `MG3_library_*_grid.png`.
- **MG7: RenderDoc 1.46** (portable zip from renderdoc.org, signed by Baldur Karlsson; analytics opted out). WE was launched under `renderdoccmd capture` with shadows **high**, and the capture was triggered and analysed through qrenderdoc's Python API (`mg7/rd_mg7.py`).
  - Files: `mg7/cloth_frame22470.rdc` (the capture, 29 MB), `mg7/mg7_report.txt` (the report) and `mg7/ps_event*.txt` (pixel-shader disassembly).
  - **Shadows ARE drawn.** The shadow atlas is `2D Depth Target 236`: 1536×512 R32, three 512² cascades, 483 draws (events 22–5817) before the main pass. The main depth buffer is 1920×1080 D32.
  - **The cloth draw is event 15469** (DrawIndexed, alpha 0.6):
    - PS cb0: TintColor 0.784 0.196 0.196, TintAlpha 0.6, Roughness 0.7, Metallic 0.1, Brightness ~0, EmissiveBrightness 0.
    - VS cb0: LightAmbientColor = LightSkylightColor = 0.1255 0.2588 0.3804; EyePosition 7 7 −7.
    - cb2: LDirectional_Color 6.0 5.2941 4.8941; LDirectional_Direction 0.5068 0.7514 −0.4226; `g_LFeature_ShadowProjection[0..2]` (cascade matrices, in the report); `g_LFeature_ShadowProjectionTransform[i]` = (i/3, 0, 1/3, 1), i.e. the atlas cascades side by side; `g_Texture6Texel` = 1/1536, 1/512, 1536, 512.
    - SRVs: slot 0 is a 32×32 RGBA8 texture; **slot 1 is the shadow atlas.**
  - **Cloth pixel output:** pixel history at (1070,410) and (1020,330) gives shaderOut ≈ **(0.621, 0.177, 0.192, a 0.6)**, and the final pixel is (0.620, 0.176, 0.192) after FXAA (event 15548). **The cloth is not black under active high-quality shadows.**
  - The combos are compiled into the variant; see `ps_event15469.txt` for the shadow-sampling code.

## Pending
- MG4 retry: root-motion flags written by WE's own model importer (editor).
- MG5: puppet with morphs (editor).