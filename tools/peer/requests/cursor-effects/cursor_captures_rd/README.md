# Cursor effects: WE 2.8.0.42 stills via RenderDoc (item 9)

## Method
- **Why RenderDoc:** the Windows session was locked, so desktop capture is black. WE kept rendering behind the lock screen, and it kept reading the cursor.
  - WE was started under `renderdoccmd capture`.
  - `../../rd_grab/rd_cursor.py`, running inside qrenderdoc, sets the cursor with `SetCursorPos` (per-monitor DPI aware; monitor 2 at 1920,0, 1920x1080), waits 1 s, triggers a one-frame capture, and saves the swapchain image.
- **Cursor check:** `GetCursorPos` matched every target (`rd_cursor_report*.txt`).
- **WE settings:** FPS 25, MSAA x2, post-processing on, playback rules "run".
- **Frames:** `<project>_park.png` (cursor parked at 40,40) and `<project>_<x>_<y>.png`, full 1920x1080 frames of monitor 2. They are the swapchain image, not a screenshot, and contain no cursor sprite.
- **Sweeps not captured:** the `curs_ripple_sweep` and `curs_fluid_sweep` clips are missing. RenderDoc grabs one frame per trigger, about 0.4–1.4 s apart, so it can't make a continuous clip. They need an unlocked desktop.

## Halo centres (`halo_centres.tsv`)
- **How measured:** each centre is the brightness-weighted centroid of (still − reference), keeping only differences above 8.
- **Reference:** the parked frame, or, for `curs_xray_parallax`, `curs_parallax_none` at the same point.

| project | cursor | halo centre | Δ |
|---|---|---|---|
| xray_plain | 960,540 | 961.9,540.4 | +1.9,+0.4 |
| xray_plain | 700,350 | 702.5,351.5 | +2.5,+1.5 |
| xray_plain | 1250,760 | 1249.1,760.0 | −0.9,0 |
| xray_plain | 560,540 | 567.3,540.1 | +7.3,0 (clipped by the layer edge) |
| xray_plain | 960,180 | 964.7,180.0 | +4.7,0 |
| xray_moved | 1250,460 | 1251.5,459.5 | +1.5,−0.5 |
| xray_moved | 1100,340 | 1099.2,340.9 | −0.8,+0.9 |
| xray_moved | 1400,600 | 1401.8,598.7 | +1.8,−1.3 |
| xray_moved | 1000,520 | 995.8,522.9 | −4.2,+2.9 |
| xray_zoom | 960,540 | 963.1,540.9 | +3.1,+0.9 |
| xray_zoom | 1200,700 | 1199.4,699.8 | −0.6,−0.2 |
| xray_zoom | 700,380 | 703.8,381.1 | +3.8,+1.1 |
| xray_crop | 960,540 | 961.9,540.4 | +1.9,+0.4 |
| xray_crop | 1200,800 | 1198.1,799.9 | −1.9,−0.1 |
| xray_crop | 700,250 | 703.4,251.8 | +3.4,+1.8 |
| **xray_parallax** | 960,540 | 961.9,540.4 | +1.9,+0.4 |
| **xray_parallax** | **1100,620** | **1098.7,619.9** | **−1.3,−0.1** |
| **xray_parallax** | 840,460 | 844.3,461.2 | +4.3,+1.2 |

## Findings
- **Every case:** the halo sits under the cursor in all cases, within about 5 px. The one bigger offset (560,540) is caused by clipping at the layer edge.
- **Parallax:**
  - With camera parallax on, WE's halo **follows the cursor**: it is at 1098.7,619.9 with the cursor at 1100,620.
  - Your current render keeps it at the pre-parallax position (960,540 while the cursor is at 1100,620). So the effect matrix **does** account for the parallax shift, and the FX1 case is decided in favour of "the matrix includes the camera/parallax".
  - Caveat: the centroid is measured against `curs_parallax_none` at the same cursor point, so the layer shift cancels out. The halo is placed relative to the shifted layer, and it lands on the cursor.
- **Crop 1920x1440 scene at 960,540:** the result is identical to plain. The halo lands at the cursor in display pixels, so the pointer is normalised to the window, and the mapping goes through the cropped scene correctly.
