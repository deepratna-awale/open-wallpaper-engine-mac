# Capture request 501: a camera layer's `zoom` and a camera path's `zoom` in a perspective scene

`docs/models-plan.md` §2.1 says `zoom` "does nothing in perspective [I]". For `general.zoom` that is settled: owe-beta3's `owe_zoombox1/2` were pixel-identical, so it isn't asked again. Two other zooms are still read only from the binary:
- a **camera layer's** own `zoom` key;
- a **camera path's** `zoom` channel.

OWE ignores both in a perspective scene (`ScenePerspectiveCameraRig`). This request checks that against WE 2.8, and asks what WE's editor offers for zoom in a perspective scene.

## Setup

The setup is the same as owe-beta3/models-open: WE 2.8.0.42, the wallpaper running on monitor 2 at 1920×1080 and 100 % scaling. Bloom is off in the scene. Any FPS setting works (30 as before).

1. `python build_501.py` writes the five projects into `projects/`. They are already committed, so this step is only needed if a file changes. Copy each `projects/p501_*` folder into `wallpaper_engine\projects\myprojects`.
2. Every project has the same content. Every material is unlit generic4 on `util/white`, so each colour is flat.
   - A floor grid on y = 0: grey lines every unit, black ones every 5, x −10…10, z −30…5.
   - Three unit cubes standing on it: **red** at (−2, 0.5, 0), **green** at (0, 0.5, −5), **blue** at (2, 0.5, −15).
   - A camera layer, "Probe Cam" (id 950), at (0, 1, 10) with angles 0, so it looks straight down −Z. It has `"visible": {"value": true}` (519b found that a layer without `visible` plays no path).
   - The scene's own `camera` block is at (0, 1, **14**), 4 units further back. If a frame shows the layer being ignored, the cubes are visibly smaller and closer together; see the table below.
   - `camerafade` is off.

| Project | Camera layer | Path (`scripts/camera_paths_950.json`) |
|---|---|---|
| `p501_layer_zoom1` | fov 50, zoom 1 | none (control) |
| `p501_layer_zoom2` | fov 50, **zoom 2** | none |
| `p501_layer_fov26` | **fov 26.2505**, zoom 1 | none. It is the reference for what an FOV-like 2× zoom would look like: tan(fov/2) halved |
| `p501_path_zoom` | fov 50, zoom 1 | eye and centre held; **zoom 1 → 2 → 1** at frames 0/30/60, 30 fps, `mode` single |
| `p501_path_fov` | fov 50, zoom 1 | eye and centre held; **fov 50 → 26.25 → 50**. It is the control that shows a path plays in this scene |

The path files copy the layout of 519b's editor-made path: `magic` handles, `mode` single, `wraploop` false, length 60, `cameramode` fly.

## Captures

The names follow the `mo2_*` convention, each with its project folder copied next to it as before.

| File | Project | When |
|---|---|---|
| `mo2_501_layer_zoom1_t3.png` | `p501_layer_zoom1` | 3 s after load |
| `mo2_501_layer_zoom2_t3.png` | `p501_layer_zoom2` | 3 s |
| `mo2_501_layer_fov26_t3.png` | `p501_layer_fov26` | 3 s |
| `mo2_501_path_zoom_t{0.5,1,1.5}.png` and `mo2_501_path_zoom.mp4` | `p501_path_zoom` | stills at 0.5/1/1.5 s, and a 4 s clip at 30 fps from load |
| `mo2_501_path_fov_t{0.5,1,1.5}.png` and `mo2_501_path_fov.mp4` | `p501_path_fov` | the same |

`shots.json` lists the same captures.

**If neither path plays**, `p501_path_fov` included, make the path in the editor instead and capture it under the same names:
1. Select "Probe Cam", then **Paths → + Add**. Key frame 0 and frame 60 with the layer as it is.
2. At frame 30, set FOV (for `_path_fov`) or Zoom (for `_path_zoom`) as in the table, with Auto Keyframe on.
3. The editor drops `visible` from the camera object on save (519b), so add `"visible": {"value": true}` back.

## The editor (screenshots)

Open `p501_layer_zoom2` in WE's editor:
1. **Scene settings → Camera:** is a Zoom field shown for this perspective scene? Screenshot it.
2. **"Probe Cam" selected:** is Zoom shown and editable? Screenshot the inspector. Does the editor viewport change between zoom 1 and 2? Take one viewport screenshot at each, with the camera preview on.
3. **Paths → + Add on "Probe Cam":** which tracks can be keyed (Eye, Center, Up, FOV, Zoom)? Key every track it offers at frame 0 and frame 30 with a changed value, save, and send the written `scripts/camera_paths_*.json` as `editor_path_perspective.json`. For a perspective scene, does it write `zoom` keys, `"zoom": null`, or no key at all? And `fov`?

## What we need to know

OWE's prediction is that both zoom variants look **identical to their control**: `_layer_zoom2` the same as `_layer_zoom1`, and `_path_zoom` constant over time. `_path_fov` and `_layer_fov26` should show the narrower view.

Cube centres on the 1920×1080 frame, from `build_501.py`:

| Cube | Layer's view, zoom 1 | FOV-like 2× (`_layer_fov26`) | Scene camera block (layer ignored) |
|---|---|---|---|
| red | (728, 598) | (497, 656) | (795, 581) |
| green | (960, 579) | (960, 617) | (960, 570) |
| blue | (1053, 563) | (1145, 586) | (1040, 560) |

1. **Does `_layer_zoom2` differ from `_layer_zoom1`?**
   - If it doesn't, OWE is right and §2.1's [I] for camera layers becomes settled.
   - If it does, how does it differ?
     - **(a)** It matches `_layer_fov26`. OWE would then divide tan(fov/2) by the layer's zoom.
     - **(b)** The near red cube grows more than the far blue one (a dolly).
     - **(c)** Something else.
   - Give the three cube centres and the red cube's width in px.
2. **Does `_path_zoom` change over time?** The same three cases apply, at 1 s against `_path_fov` at 1 s.
3. **Does the layer win over the scene's camera block?** At zoom 1, are the cubes at the "layer's view" positions, or at the "scene camera block" ones? (Expected: the layer's.)
4. **What does the editor offer and write** for zoom in a perspective scene (the three screenshots and `editor_path_perspective.json`)?
