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

## Pending
These were **not captured: the Windows session locked or blanked the displays while the user was away**, so every capture came back black or showed a stale frame. They will be re-run when the user is back.
- MG4 flag variants 0x00800 … 0x10000
- MG6 ortho depth near/far, and the collision-model depth test on/off
- MG8 hidden collision sphere
- MG3 library items (need Chrome to subscribe)
- MG5 (editor puppet with morphs), user
- MG7 RenderDoc capture, which needs RenderDoc installed and the user's go-ahead
