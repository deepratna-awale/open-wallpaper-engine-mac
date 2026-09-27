# WE particle gallery: every built-in preset variant and every particle component preview

WE 2.8.0.42, display 2 at 1920×1080. All projects were generated without the editor.

## Presets: `captures/<preset>_<variant>.png` and `.mp4` (5 s)
- `build_particles.py` reads every `assets/presets/*/preset.json` (20 presets, 74 variants) and builds one project per variant.
- **Object placement:** the variant's objects are placed exactly as defined, with origin offset to screen centre (960, 540), matching where the editor drops presets.
- **Asset bundling:** the preset's `materials/` and `particles/` folders are copied in. The lightshafts variants also need `assets/effects/lightshafts` bundled; without it WE logs `Failed opening: materials/effects/lightshafts.json`.
- **Background, 1920×1080, in `assets/`:**
  - `bg_black`: near-black with a faint 100 px numbered grid and a red crosshair at the emitter/centre;
  - `bg_grey`: the same at 50% grey, used for smoke and fog;
  - `bg_pattern`: a 32 px high-contrast checker, used for refractive variants.
- `index.json` maps each project to its background. `captures_metrics.tsv` has the % of pixels differing from the background, plus frame motion. Overviews are in `contact_captures_*.png`.

## Components: `elements/ptce_<component>.png` and `.mp4`
- WE ships one preview scene per particle component in `assets/scenes/particleelementpreviews/<component>/`. These are the clips the editor's add dialogs play: 48 emitters, initializers, operators and renderers.
- Each preview was loaded as-is (`projects/ptce_*` are straight copies) and captured.
- **The values in these scenes are the preview's values.** They are probably close to the editor's add-defaults, but that isn't guaranteed.
- `assets/particles/example.json` is the editor's **Basic** template. It matches the editor recording: rate 20, distance 32–512, lifetime 3–5, max 500, alpha fade in 0.5. `example3d`, `examplecursorfollow`, `examplecursoravoid` and `exampleturbolence(3d)` are the other templates.

## Capture reliability
- **WE sometimes drops an `openWallpaper` command.** The first pass captured the previous wallpaper for about 36 presets and 24 components, visible as identical metrics.
- `capture_particles.ps1` now confirms each switch in `config.json` and re-issues the command if needed. The affected items were recaptured and checked.
- The earlier effect gallery and extras are not affected: none of their captures match the reset wallpaper.

## Rebuild
- Projects are omitted from git because the backgrounds are 8 MB `.tex` files per project.
- To rebuild: run `python build_particles.py`, which regenerates everything from the WE install. The component previews come straight from `assets/scenes/particleelementpreviews`.
