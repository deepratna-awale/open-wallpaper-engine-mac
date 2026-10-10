# 501 results: WE 2.8.0.42

## How it was captured
- **Frames:** `captures/mo2_501_*.png` are WE's swapchain images, taken with RenderDoc (`../../../rd_grab/rd_timed.py`) from the running wallpaper.
- **Why not screenshots:** the second screen was covered by another application window, so screenshots weren't usable. They were deleted and not committed.
- **Timing:** trigger times are in `captures/rd_timed_report.txt`; each was within 5 ms of the requested time.
- **No clips:** the .mp4 clips aren't included, since RenderDoc gives single frames. Path playback is covered by stills at 0.5, 1, 1.5 and 3 s instead.

## Cube centres (px) and widths

| capture | red | green | blue | red width |
|---|---|---|---|---|
| layer_zoom1 t3 | (724,600) | (960,580) | (1053,563) | 140 |
| **layer_zoom2 t3** | (724,600) | (960,580) | (1053,563) | 140 |
| layer_fov26 t3 | (489,661) | (960,619) | (1146,586) | 279 |
| **path_zoom t0.5 / t1 / t1.5 / t3** | (724,600) | (960,580) | (1053,563) | 140 |
| path_fov t0.5 | (498,658) | (960,618) | (1142,586) | 273 |
| path_fov t1 | (585,636) | (960,603) | (1107,577) | 222 |
| path_fov t1.5 | (721,601) | (959,580) | (1054,563) | 142 |
| path_fov t3 | (591,634) | (960,602) | (1106,576) | 218 |

## Answers
1. **`_layer_zoom2` is identical to `_layer_zoom1`.** Same pixels for all three cubes, so a camera layer's `zoom` does nothing in a perspective scene. **OWE is right.**
2. **`_path_zoom` is constant** at all four times, identical to the zoom-1 control. Meanwhile `_path_fov` clearly animates: the red cube's width goes 273 → 222 → 142 → 218 px, i.e. fov 50 → 26 → 50, and the path re-runs (queue mode random). So a camera path's `zoom` channel is ignored in perspective too, while its `fov` channel plays.
3. **The layer wins over the scene camera block.** At zoom 1 the cubes are at the "layer's view" positions, (724,600)/(960,580)/(1053,563), against the predicted (728,598)/(960,579)/(1053,563). The block would put them at (795,581)/(960,570)/(1040,560).
4. **The editor (perspective scene) offers no Zoom anywhere.**
   - **Scene options → Camera:** FOV, Near Z, Far Z, Camera preview (`editor/scene_camera_settings.png`).
   - **Camera layer inspector:** Origin, Angles, Scale, Edit Camera POV, **FOV** and Paths (`editor/probe_cam_inspector.png`). In the ortho scene of 519b the same inspector shows **Zoom** instead of FOV.
   - **Path tracks offered:** Center x/y/z, Eye x/y/z, Up x/y/z and **FOV**. There's no Zoom track (`editor/path_tracks.png`).
   - **Path json:** the path the editor writes (`editor/editor_path_perspective.json`) has a `fov` key track and **`"zoom": null`**. The frame-0 FOV of 5 is my input slip; it was meant to be 50.
   - **Layer key:** the camera layer keeps its `"zoom": 2.0` key on save, though the UI doesn't show it.
   - **Viewport:** no zoom1/zoom2 viewport screenshots, since there's no zoom control to change, and the layer's zoom 2 renders the same as 1.

## Editor side effect
**`path` cleared on save.** When a perspective camera layer has a path and is saved through the editor, the layer's `path` becomes `""` if no path file existed yet. After pointing the layer at an empty `scripts/camera_paths_950.json`, the editor fills that file on save.
