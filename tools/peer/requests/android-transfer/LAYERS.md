# What WE keeps when exporting a scene for mobile (Lonely Cat, 3299228616)

The test scene has 271 objects in 6 language groups. Each group contains:
- SceneScript-driven text: "Clock 12" and "Date", with a `text` script and font `systemfont_consolas`;
- an AM/PM image with a `visible` script;
- audio-reactive bar images;
- particles and image effects (lightshafts, waterripple and others);
- one `sound` object playing `sounds/sorrow - luskos.mp3`.

Exports were made from WE 2.8.42 via right-click → Send to Mobile Device → Export .mpkg.

## Export dialog
- **No per-layer options or warnings.** The only messages are:
  - **Generic:** a "High resolution wallpapers can be particularly demanding…" banner (shown for this 4K-ish scene).
  - **Pre-Rendered:** "Pre-rendering a scene wallpaper can drastically improve performance, but **dynamic elements like clocks or interactive touch events will not work**."
- **Mobile-related UI strings** (`locale/ui_en-us.json`), the only limitation messages that exist:
  - type not supported on Android (web, application);
  - a 4 GB size limit;
  - "app out of date / requires the latest mobile app version" (feature gating by app version);
  - texture-conversion failure;
  - texture reduction levels: original, ×2 ("Better Performance"), ×4 ("High Performance").
- **Missing:** there is no string about scripts, text, fonts or audio not being supported.

## Dynamic (Balanced): `lonelycat_dynamic.mpkg`, 2.37 MB (original scene.pkg is 11.4 MB)
- **Container magic `PKGM0019`.** This differs from the Knight export's `PKGM0014`, so the version tag varies per export, possibly with features used.
- **scene.json is unchanged apart from one added key:** all 271 objects are kept, with **no** objects removed, added or modified.
  - **SceneScript is kept verbatim:** the text and visible scripts.
  - **Audio-reactive bars are kept as-is.**
  - **The `sound` object is kept.**
  - The only change is **`general.texturereduction: 4`**.
- **Fonts:** none are bundled. The text uses `systemfont_consolas`, a system-font reference, so the app must map it to its own font.
- **Textures:** every .tex is re-encoded smaller, e.g. LonelyCAT.tex 6.59 MB → 218 KB.
- **Files dropped:** only **`sounds/sorrow - luskos.mp3`** is not in the package. The sound object still references it, so background music is stripped.
- **Added:** `preview.gif` and `project.json` (`mpkg/lonelycat_dynamic_project.json`).

## Pre-Rendered (High Performance): `lonelycat_prerendered.mpkg`, 32.0 MB, magic `PKGM0014`
- **Contents:** `wallpaper.mp4` (H.264, 1080x1920, 30 fps, 30.0 s), plus the full original `scene.json` (271 objects, for reference), `project.json` (`type:"Scene"`, `file:"wallpaper.mp4"`) and `preview.gif`.
- **The clock and date are baked into the video at render time:** frames show "03:16 PM" and then "03:17 PM", "Sunday, 4 October" (`lonelycat_prerendered_clock_frames.png`). On the device the video loops, so the shown time is frozen to the export moment and repeats every 30 s.
- **Audio:** the bars are rendered with whatever audio was playing on the PC during export (here, silent). No audio file is included.

## Device behaviour (Tab S9)
- **Not tested yet:** importing the Lonely Cat files, i.e. whether the Dynamic clock ticks live, the bars react to tablet audio, and the system font renders. Pending the user.
