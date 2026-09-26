# WE effect gallery: every built-in effect at its defaults

WE 2.8.0.42, captured on display 2 at 1920×1080 (100% scaling). WE's own settings were FPS 25, MSAA x2, post-processing enabled, shadows and volumetrics high.

## Layout
- One project per effect, in `projects/fxgal_<effect>/`. The control is `fxgal_none`.
- Scene: 1920×1080, orthographic, clear colour 0.15 grey.
- Two image layers, each 1024×1024 at scale 0.85: `assets/checkerboard_1024.png` (64 px checks, red border, blue centre lines, red up-arrow) centred at (480, 540), and `assets/gradient_1024.png` (hue across, darker downward, white up-arrow) centred at (1440, 540).
- Each layer carries only the effect, as `{"file": "effects/<name>/effect.json"}`, with **no `passes`, no values and no combos**. What renders is therefore WE's fallback to the shader-annotation defaults.
- The effect's files (`effect.json`, `materials/`, `shaders/`) are copied from `wallpaper_engine/assets/effects/<name>/`. WE's runtime does **not** resolve effects from `assets/` by itself: without the copies it logs `Failed opening: materials/effects/<x>.json`.
- The `.tex` files are omitted to save space (4 MB each). Regenerate them with `python build_gallery.py --restore-tex projects assets`. The format is uncompressed RGBA8888: `TEXV0005\0TEXI0001\0`, then int32 values format=0, flags=2, w, h, w, h, 0, then `TEXB0001\0`, int32 imageCount=1, mipCount=1, w, h, byteCount, then raw RGBA bytes.
- `projects/user_effecttest-*` are the user's editor-made projects, included in full:
  - `blank`: black solid background, images at scale 1
  - `cloud1`: cloud motion
  - `irism`: iris movement
  - `pulse`
  - `scrol`: scroll
- Captures in `captures/<name>.png` (still at about 5 s after load) and `<name>.mp4` (3 s clip). `contact_1.png` and `contact_2.png` are labelled overviews.
- `metrics.tsv` has the mean absolute difference from the control (0–255) and the mean frame-to-frame motion. `capture.log` shows that all 50 projects loaded with no WE errors.
- Scripts: `build_gallery.py`, `capture_gallery.ps1`, `summarize.py`.

## Findings
**Defaults come from the shader annotations.** For example, in `tint.frag`, `uniform vec3 g_TintColor; // {"material":"color","default":"1 0 0"}` gives solid red. Every uniform and `[COMBO]` in `assets/effects/*/shaders/effects/*.{frag,vert}` declares its `default`, its `range` and its dropdown `options`. That is the full reference for defaults and limits.

| Effect | At defaults with no values (diff / motion) | Notes |
|---|---|---|
| blend | no change (0 / 0) | needs a second texture |
| blendgradient | both layers solid white (99 / 0) | |
| blur | soft blur (10.8 / 0) | 13×13 kernel |
| blurprecise | slight blur (2.8 / 0) | |
| blurradial | concentric radial blur rings on the checker (14.6 / 0) | |
| chromaticaberration | RGB fringes (5.3 / 0) | |
| cloudmotion | wavy horizontal displacement, animated (36 / 0.9) | |
| clouds | grey clouds overlaid, animated (39.7 / 0.9) | |
| colorkey | checker's white keyed to black; gradient's white arrow turned dark (51 / 0) | |
| cursorripple | no change (0 / 0) | needs cursor movement |
| depthparallax | whole layer shifted (33 / 0) | no depth map |
| edgedetection | white edges on white, near-white overall (99 / 0) | |
| filmgrain | animated grain (3.3 / 0.7) | |
| fire | no change (0 / 0) | needs a mask |
| fisheye | strong barrel bulge (36 / 0) | |
| fluidsimulation | fire-like plume rising from the centre-left (3.2 / 0.7) | |
| foliagesway | subtle sway (7.1 / 2.5) | |
| glitter | sparkles, strongest on dark areas (2.8 / 1.5) | |
| godrays | bright radial rays from the centre (24.9 / 0.15) | |
| iris | subtle animated movement (1.8 / 1.2) | |
| lightshafts | faint shaft top-centre (1.8 / 0.06) | |
| localcontrast | barely visible (0.4 / 0) | |
| motionblur | no change (0 / 0) | needs motion |
| nitro | electric arcs, animated (2.9 / 5.0) | |
| opacity | no change (0 / 0) | default alpha 1 |
| perspective | no change (0 / 0) | identity defaults |
| pulse | brightening pulses (19.1 / 4.2) | |
| reflection | checker mirrored to white; gradient flipped with the arrow pointing down (57 / 0) | |
| refraction | mild ripple displacement (17.7 / 0) | |
| scroll | image scrolls fast (58 / 18.8) | |
| shake | no change (0 / 0) | needs a mask |
| shimmer | subtle animated shimmer (0 / 1.5) | |
| shine | washed-out white rays (38 / 0.2) | |
| skew | no change (0 / 0) | identity defaults |
| spin | small spinning disc at the centre (2.2 / 0.6) | |
| swing | subtle swing (1.5 / 0.9) | |
| tint | solid red over both layers (80 / 0) | alpha 1 |
| transform | no change (0 / 0) | identity defaults |
| twirl | large twirl disc, animated (48.7 / 24.8) | |
| vhs | noise and tearing (2.5 / 0.8) | |
| watercaustics | caustic network on the gradient (2.6 / 0.7) | |
| waterflow | no change (0 / 0) | needs a flow map |
| waterripple | ripples (10.5 / 3.5) | |
| waterwaves | horizontal wave displacement (8.0 / 7.4) | |
| xray | no change (0 / 0) | needs a mask |

"No change" means the effect loads without errors but its defaults are neutral, or it depends on a mask, flow map, second texture or cursor that a bare effect doesn't have. The Mac renderer should show no change for these too.
