# WE "Export .mpkg" (mobile wallpaper package) format

The export is reached via right-click → Send to Mobile Device → **Export .mpkg** (save type "Mobile Wallpaper (*.mpkg)").
- **Encryption:** the file is **not encrypted or signed**. Only the live transfer channel is encrypted.

## Container
This is the same layout as scene.pkg, with a different magic:
```
u32 len + "PKGM0014"
u32 entry count
per entry: u32 len + name, u32 offset, u32 size   (offset relative to the end of the table)
file data
```
- `../owe-beta3/unpack_pkg.py` unpacks it unchanged.

## Contents by type

| Export | Size | Entries | Notes |
|---|---|---|---|
| Video, 2447928310 | 229.4 MB (not committed) | `<original>.mp4`, `preview.gif`, `project.json` | The mp4 is **byte-identical** to the Workshop file. `project.json` is minimal: `{file, preview, title, type:"video"}` (`mpkg/video_project.json`) |
| Scene, **Dynamic / Balanced**, 2515150033 | 7.4 MB (`mpkg/scene_dynamic_balanced_2515150033.mpkg`) | 36: scene.json, project.json, preview.jpg, models/*.mdl (puppet), materials/*.tex plus json, effects, particles, masks | The **real scene** is sent loose, not packed into a scene.pkg. Balanced = **textures at half resolution** |
| Scene, **Pre-Rendered / High Performance**, 2515150033 | 31.0 MB (not committed) | `wallpaper.mp4`, `scene.json`, `project.json`, `preview.jpg` | `project.json` keeps `type:"Scene"` but **`file:"wallpaper.mp4"`** (`mpkg/prerendered_project.json`). scene.json is included (6.7 KB) |

## Pre-rendered video
- **Codec:** H.264 Constrained Baseline, yuv420p.
- **Size and length:** **1080x1920 portrait**, 30 fps, **30.0 s** loop, about 8.1 Mbit/s.
- **Settings used:** the defaults, i.e. Video Cropping "Fit to phone screen", Video Preset "Full HD", FPS 30, and the alignment slider (horizontal crop position).

## Dynamic options ("Show advanced settings")
- **Pixel art optimization:** a checkbox.
- **Texture Reduction:** Balanced = "Better Performance – (Reduce textures to half their resolution)". High Quality presumably keeps full resolution.

## Android app side
The app has an import entry: "Choose a video, GIF, or an exported wallpaper stored on your mobile and use it as a live wallpaper".
- **Import test:** importing the .mpkg files is pending, waiting on the user to copy them to the tablet.

## Implication for OWE
- **Generating packages:** OWE can generate `.mpkg` files on the Mac with no protocol reversing.
  - **Video:** pack mp4 + preview + a minimal project.json.
  - **Scene:** either pack the loose scene files (Dynamic), or render a 1080x1920 30 fps H.264 loop with `file:"wallpaper.mp4"` (Pre-Rendered).
- **Delivery:** the user moves the file to the tablet and imports it.
