# Remaining editor items: generated projects and engine sources (WE 2.8.0.42)

All of these were generated with `build_extras.py` (no editor), captured on display 2 with `capture_gallery.ps1 -Prefix fxx_ -OutName extras -ClipSec 5`, and loaded with **zero WE log errors** (`extras.log`). Projects are in `projects/fxx_*`; their `.tex` files are omitted, so rebuild them with `build_gallery.py --restore-tex`. Captures are in `extras/<name>.png` and `.mp4`. The overview is `contact_extras.png`, with close-ups in `zoom_text.png` and `zoom_cutout_refr.png`.
They use the same layout as the gallery: checkerboard at (480,540) and gradient at (1440,540), 1024 px at scale 0.85, on a 0.15 grey background.

## Scene-format facts found along the way
- **An effect's `passes` in scene.json map by position to `effect.json` passes.** Blur has 4 passes (downsample4 → gaussian_x → gaussian_y → combine), and COMPOSITE lives in pass 4. `"passes":[{"combos":{"COMPOSITE":1}}]` is silently ignored (the capture is identical to Normal); `"passes":[{},{},{},{"combos":…}]` works.
- **Layer blend modes (`colorBlendMode` on the object) use the `BLENDMODE` numbering in `assets/shaders/common_blending.h`:**
  - 0 Normal, 1 Darken, 2 Multiply, 3 Color burn, 4 Linear burn, 5 Darker color (min), 6 Lighten, 7 Screen, 8 Color dodge, 9 Linear dodge
  - 10 Lighter color (max), 11 Overlay, 12 Soft light, 13 Hard light, 14 Vivid light, 15 Linear light, 16 Pin light, 17 Hard mix, 18 Difference, 19 Exclusion
  - 20 Subtract, 21 Reflect, 22 Glow, 23 Phoenix, 24 Average, 25 Negation, 26 Hue, 27 Saturation, 28 Color, 29 Luminosity
  - 30 Tint, 31 `A+B*opacity`, 32 `A+A*B`
  - Every mode except 5, 10 and 31 is `mix(A, Blend(A,B), opacity)`. Effects' `BLENDMODE` combos use the same numbers (vhs default 12 = Soft light, shine = 9 Linear dodge).

## Item 2: Composite modes (blur, the only effect with COMPOSITE, from `common_composite.h`)
- Uniforms: `compositealpha` (default 1, 0–2), `compositeoffset` (default "0 0", −10 to 10), `compositecolor` (default "1 1 1").
- Mean absolute difference, 0–255:

| Variant | vs Normal | vs no effect | What it looks like |
|---|---|---|---|
| Normal (0) | – | 10.75 | blurred |
| Blend (1), alpha 0.5 | 7.34 | 3.47 | halfway between original and blur |
| Blend (1), alpha 1.5 | 8.89 | 19.34 | overshoots: stronger than a full blur |
| Under (2) | 10.75 | **0.00** | identical to no effect: the blur goes behind an opaque layer |
| Cutout (3) | 81.8 | 82.1 | **both layers disappear**: the blurred shape cuts the layer out |

## Item 3: Solid layer with blend modes
A solid band (`models/util/solidlayer.json`, color 0.2 0.6 1.0, 1920×300) sits on top across both images, with `colorBlendMode` set to 0, 2, 7, 9, 11, 18 or 31.
- **Normal:** opaque band.
- **Multiply:** darkens (white checks turn blue, the gradient goes dark).
- **Screen and linear dodge:** brighten toward white and cyan.
- **Overlay:** hue-shifted; over the grey background the band barely shows.
- **Difference:** inverts (orange and cyan checks).
- **31 (native additive):** looks like linear dodge.
- The band renders more cyan than the specified 0.2 0.6 1.0.

## Item 4: Timeline
Real wallpapers store an animated property as `{"value": …, "animation": {"c0":[keys], "c1":[…], "c2":[…], "options": {"fps":30, "length":N, "mode":"loop"|"single", "wraploop":…, "startpaused":bool, "name":…}}}`.
- Each key is `{"frame", "value", "back":{"enabled","x","y"}, "front":{"enabled","x","y"}, "lockangle", "locklength"}`. The Bézier handles (back/front) are in frame and value units.
- Modes seen in the wild: **loop** and **single**.
- Generated test: the checkerboard's origin X moves +300 px over 60 frames at 30 fps, in the variants `loop`, `mirror`, `single` and `loop_bezier` (handles −20/+20 frames with a +250 value on the front, for an overshoot curve). See the 5 s clips.
- The red arrow was tracked at 6 fps over the 5 s clips (`x` values in the commit log):
  - **loop:** ramps up, then jumps back to the start every 2 s.
  - **mirror:** a real mode that ping-pongs (ramps up, then back down).
  - **single:** plays once and holds the last key (already finished when the capture started).
  - **loop_bezier:** the steep handles make it hold at each end and snap between them (a step-like curve), which confirms the handles shape the interpolation.

## Item 5: Image layer material (Lighting & Reflections), from `assets/shaders/genericimage4.frag`
- **Combos:** LIGHTING (default 0), REFLECTION (default 0), FOG (default 1).
- **Textures:**
  - Albedo (required).
  - Normal map: combo NORMALMAP, rg88 format. It needs LIGHTING or REFLECTION on.
  - PBR mask: combo PBRMASKS, paint default "0 0 0 1", with components metallic (METALLIC_MAP), roughness (ROUGHNESS_MAP), reflection (REFLECTION_MAP) and emissive (EMISSIVE_MAP). It needs LIGHTING or REFLECTION on.
- **Material values:**

| Value | Default | Range |
|---|---|---|
| roughness | 0.7 | 0–1 |
| metallic | 0 | 0–1 |
| speculartint | 1 1 1 | colour |
| emissivecolor | 1 1 1 | colour |
| emissivebrightness | 1 | 0–10 |
| reflectivity | 1 | 0–1 |
| reflectivitydistance (hidden) | 4 | 0.01–10 |

- **Light object fields** (from wallpaper64.exe and real scenes):
  - `light`: lpoint, lspot, ltube or ldirectional
  - color, intensity, radius, exponent, innercone, outercone, lightsourcesize, castshadow, castvolumetrics, density, volumetricsexponent, usecookie/cookie, cascadedistance0/1/2
- The editor's per-type light count limits are not in the assets. They still need the editor dialog.

## Item 6: Particle components (registry strings in wallpaper64.exe)
Names only; defaults need the editor or the preset JSONs in `assets/presets/*/particles`.
- **Emitters:** sphererandom, boxrandom, layerimage.
- **Initializers:** colorrandom, hsvcolorrandom, colorlist, sizerandom, alpharandom, velocityrandom, lifetimerandom, rotationrandom, angularvelocityrandom, positionoffsetrandom, turbulentvelocityrandom, inheritcontrolpointvelocity, mapsequencearoundcontrolpoint, mapsequencebetweencontrolpoints, remapinitialvalue, inheritinitialvaluefromevent.
- **Operators:** movement, angularmovement, alphafade, alphachange, sizechange, colorchange, oscillateposition, oscillatealpha, oscillatesize, turbulence, vortex, vortex_v, boids, controlpointattract, maintaindistancetocontrolpoint, maintaindistancebetweencontrolpoints, reducemovementnearcontrolpoint, capvelocity, remapvalue, inheritvaluefromevent, collisionsphere, collisionbox, collisionbounds, collisionquad, collisionplane, collisionmodel.
- **Renderers:** sprite (orientation screen, upright or fixed), spritetrail, rope, ropetrail.
- **Children events:** eventfollow, eventspawn, eventdeath.

## Item 8: Text font effects
Field names come from wallpaper64.exe: `msdf`, `outline`, `outlinethickness`, `outlinecolor`, `blur`, `blursize`, `dropshadow`, `dropshadowsize`, `dropshadowopacity`, `dropshadowoffset`, `dropshadowcolor`, `padding`, `spacing`. All other text fields are listed in the gallery README.

| Variant | vs plain MSDF |
|---|---|
| plain, msdf false | 0.62 (edge antialiasing differs) |
| outline 4, black | 1.64 (thin dark outline) |
| blur 1 | 0.54 (softened glyphs) |
| drop shadow 6, opacity 1, offset 4 4 | 0.81 (dark shadow down-right) |
| outline + blur + drop shadow on, no values | 3.08 (WE fills defaults: outline, shadow and blur all visible) |

The font is the bundled `NotoSans-Regular.ttf`, copied into the project.

## Item 10a: Refraction
- The `rainrefractive` preset (material REFRACT=1, refract_amount 0.05, textures particle/drop and particle/drop_normal) was changed to 8 slow sprite drops of size 220 over both images.
- **Result:** on the gradient, each drop shows colours from slightly to its **right** (+x); the red area shows yellow inside the drops, and the green area shows cyan. So the refraction samples the background shifted toward +x at the default amount.
- On the checkerboard, the drops show thin black-and-white stripes, which isn't conclusive.

