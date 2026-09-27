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

- **MG4: root-motion flags.** With **any** of the six clip-flag bits set (0x00800 � 0x10000), WE 2.8.0.42 **silently refuses to load the model**. `config.json` switches to the project, but the screen keeps the previous wallpaper even after 20 s, and nothing is logged. Each project differs from the working `0x00000` by exactly one byte of `gt_rootmotion.mdl` (offset 0x710, 00?10 for 0x01000). Loading several flagged models in a row left the renderer black until WE was restarted (`rootmotion_isolation.log` tests each variant after a clean restart). So there is no axis mapping to observe: WE does not accept these flags.
- **MG6: ortho depth.** The pixel at (960,540), 2 s after load, is **(253,0,0), red, in both `near-first` and `far-first`**. WE's orthographic 2D frame **depth-tests models**, and draw order doesn't matter. Ours (last-drawn) is wrong. Stills: `MG6_ortho_*_t2.png`.
- **MG6: collisionmodel particles and depth test.** Orange particle density inside the sphere's screen area relative to outside it, over 1.5�5 s:

| Variant | Ratio |
|---|---|
| depthtest disabled | 1.55 (particles drawn over the sphere) |
| enabled | 0.13 (particles behind the sphere are hidden) |
| shipped preview | 0.28 |

  Grid: `MG6_MG8_colmodel_grid.png`, with shipped, depth on / depth off, and hidden.
- **MG8: hidden collision model.** With the sphere's `visible` false, the sphere isn't drawn, and the particle density inside its area is **0.00%** (0.04% outside). Particles **still collide with the hidden model**.

## Pending (need the user)
- MG3 library items 3803167460 / 3803042537: subscribing needs Chrome, which was not connected.
- MG5: editor puppet with morphs.
- MG7: RenderDoc capture (needs RenderDoc installed).
