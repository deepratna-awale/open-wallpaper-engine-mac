# Cursor capture request (OpenWallpaperEngine, test-risks FX1)

WE's effect gallery was captured with the cursor on the primary monitor, so x-ray, cursor ripple and the fluid simulation's pointer force show nothing in it. The Mac port maps the cursor as follows. None of it has been checked against a capture yet:

- `g_PointerPosition` is y-down (0 at the top). The binary agrees: `GetCursorPos`, then `ScreenToClient`, then `(x, y) / client size` (0x1401115a8 to 0x14011164b, stored at +0x9c).
- `g_PointerPositionLast` is the previous frame's value (0x140181615).
- `g_EffectTextureProjectionMatrix` maps the effect's texture space to the layer's quad on screen.

This request asks for stills with the cursor at known points, and two clips of a scripted cursor sweep.

## What to run (Windows, WE 2.8, the effect gallery's setup)

The setup is the same as the effect gallery: display 2 at 1920×1080, 100 % scaling, WE's FPS 25, MSAA x2, post-processing on. WE's mouse interaction must be on. Keep the PowerShell window on the primary monitor, and don't touch the mouse while the script runs.

1. `python build_cursor_request.py --we "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"` writes the `curs_*` projects into `projects\myprojects` and writes `shots.json` next to the script. It needs Pillow and `gradient_1024.png`, which is in this folder.
2. Run `powershell -ExecutionPolicy Bypass -File capture_cursor.ps1`. It needs ffmpeg on the PATH. For each project it:
   - opens the project on monitor 2, with the cursor parked at that monitor's top-left corner, and after 4 s saves `<project>_park.png`;
   - for each still, moves the cursor with `SetCursorPos` to the point on monitor 2 (display pixels from its top-left, as listed in `shots.json`), waits 1 s, and saves `<project>_<x>_<y>.png`. The screenshot doesn't include the cursor;
   - for a sweep, records a 4 s clip (`<project>.mp4`, gdigrab without the mouse, CRF 18). The cursor goes from (560, 540) to (1360, 540) in 1 s. Each position is logged with its millisecond in `<project>_path.csv`, and the script saves `<project>_after.png` 0.3 s after the sweep.
3. Send back the `cursor_captures` folder, including `capture.log`. The log has the monitor's bounds, the cursor position `GetCursorPos` reported at each still, and any WE errors.

## The projects

Every project is one 1024 px layer showing the gallery's hue gradient, over a 0.15 grey clear colour, with bloom off. Each effect runs at its defaults. At its defaults, x-ray draws a white halo (`particle/halo_6`, 0.2 of the layer) wherever the pointer maps into the layer, so the halo's centre shows WE's whole cursor mapping.

| Project | Layer and scene | Stills (display px) | Question |
|---|---|---|---|
| `curs_none` | no effect | 960,540 | control |
| `curs_xray_plain` | centred, scale 0.85 | 960,540; 700,350; 1250,760; 560,540; 960,180 | pointer y and the layer mapping |
| `curs_xray_moved` | at (1250, 620), scale 0.6 × 0.9, turned 30° | 1250,460; 1100,340; 1400,600; 1000,520 | the matrix follows move, non-uniform scale and rotation |
| `curs_xray_zoom` | `general.zoom` 1.5 | 960,540; 1200,700; 700,380 | the matrix includes the orthographic zoom |
| `curs_xray_crop` | a 1920×1440 scene covering the 16:9 display (180 px cropped top and bottom) | 960,540; 1200,800; 700,250 | pointer normalised to the window or to the scene |
| `curs_xray_parallax` (+ `curs_parallax_none`, same stills, no effect) | camera parallax on (amount 1, delay 0.1, mouse influence 1), layer depth 1 | 960,540; 1100,620; 840,460 | the matrix includes the parallax shift |
| `curs_ripple_sweep` | cursor ripple | sweep | ripple position and size along the path |
| `curs_fluid_sweep` | fluid simulation (its default emitter plus the pointer force) | sweep | force direction and strength |

## Ours

`OpenWallpaperEngineTests/WECursorCaptureTests` renders the same projects with the cursor at the same points and times. It takes `OWE_CURSOR_REQUEST=<this folder>`, and the projects must be generated into `projects/` with `--out <this folder>/projects`. It finds each halo's centre as the brightness-weighted centre against the parked frame (or against the parallax control at the same point). Our renders and `report.tsv` go to `ours/`. Once WE's captures are in `cursor_captures/`, the test also requires each centre to be within 4 px of WE's.

Our current halo centres: in every orthographic case the halo sits under the cursor, within about 3 px. At 560,540 it is 9 px off, but that is because the halo is clipped by the layer's edge, which will be the same in WE. With parallax on, the halo stays where the cursor would be on the layer before the parallax shift: at 960,540 while the cursor is at 1100,620. That is the unverified case from test-risks FX1, "the matrix ignores the camera (… parallax …)", and these captures decide it.
