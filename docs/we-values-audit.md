# WE-authored values audit

**Status: 2026-09-26.** Work queue item 2 in [`roadmap.md`](roadmap.md).

The rule: every default, threshold, range, step, option list, label and unit that Wallpaper Engine authors comes from WE's own data. We never invent them. The sources are:
- effect and material json
- shader annotations (`// {"material":…}` and `// [COMBO] {…}`)
- project.json `general.properties`
- the scene.json `general` block
- particle json
- SceneScript `createScriptProperties`

Where WE authors nothing, we use WE's own default and cite where it comes from.

**Verdicts:**
- **fix:** the value must come from WE.
- **fixed:** done in this pass. The test is `WEAuthoredValuesTests`.
- **keep:** an app-only feature that WE doesn't have.
- **unknown:** needs WE ground truth (a capture, or more reverse engineering).
- **handoff:** another agent owns the file.

**Ground-truth sources used:**
- **`wallpaper64.exe`** (the local install, disassembled to `we64.asm` in the session scratchpad):
  - the scene-settings constructor at 0x140186f84…0x1401870e3
  - the property table that maps `general` field names to offsets, at 0x14019a…0x14019b2a0
  - the camera-parallax update at 0x140189b0f…0x140189cc6, the per-object displacement at 0x14018b062…0x14018b14e, and the load-time reset of an orthographic camera at 0x14018866b
  - the camera-shake routine at 0x140199580…0x14019977c
- **`bin/wallpaperui.exe`**: the editor's shader-annotation parser at 0x14046cdc9…0x14046d0bf (`range`, `linked`, `position`, `int`, `direction`, `nobindings`, `conversion`).
- **`ui/dist/scripts/scripts.js`**: WE's browse sidebar and the property editor.
  - The slider row uses `step:property.step||1, precision:property.precision||1`.
  - `EditorUserPropertyDetailsModalCtrl` creates sliders as `min 0, max 1` and saves `precision` as the decimals plus 1, with `step = 0.1^(precision-1)`.
  - The material slider uses `step 0.01, precision 2`; an `int` material slider uses step 1.
  - The linked slider links while x == y.
- **`assets/scripts/jsclasses/baseclasses.js`**: WE's `createScriptProperties` and `_Internal.updateScriptProperties`.
- **`locale/ui_en-us.json`**: WE's English text for the `ui_…` label keys.
- **WE 2.8.0.42's editor on Windows** (the user's screenshots, 2026-09-26): §7.

## 1. Effect parameters (inspector) — fixed

| Location | Was | WE's source | Verdict |
|---|---|---|---|
| `SceneEffectParameters.parameter` — range with no `range` annotation | `min(0, default)` … `max(1, 2 × default)` | `wallpaperui.exe` 0x14046cef9: `min = 0`, `max = 1.0f` | fixed (`SceneEffectParameters.defaultRange`) |
| `SceneEffectParameters.parameter` — default | components padded with the last value | the renderer's parse (`ShaderConstantResolver`): missing components are 0 | fixed; the test compares against the resolved constant |
| `SceneInspectorView.makeEffects` — slider range | widened to include the current value | the annotation range as is; the number field accepts values outside it | fixed (`clampsTypedValue: false`) |
| `SceneInspectorView` — colour control | any key containing "color" | annotation `"type":"color"`; values are 0…1 (the 255 guess is gone) | fixed |
| `SceneInspectorView.isPercentage` | "(%)" appended by key name | WE shows no unit | fixed (removed) |
| `SceneInspectorView` — slider step and decimals | continuous, 3 decimals | step 0.01 and 2 decimals; `int` uses step 1 and 0 decimals | fixed |
| `SceneInspectorView` — `linked` vec2 | two independent sliders | a link toggle that starts linked while x == y and moves both together | fixed |
| `SceneInspectorView` — `[COMBO]` with a `material` key | not shown | a checkbox, or a picker with the authored options in authored order; the choice is stored under `combo_<NAME>` and applied by `SceneEffectPlanBuilder.comboOverrides` | fixed |
| `SceneInspectorView` — combos with `"type":"imageblending"` (`BLENDMODE`) and no `options` | not shown | WE's editor list (`wallpaperui.exe` 0x140160040): 33 modes in its order and groups, §7.2 | fixed (`WEImageBlendModes`); an image layer's own `colorBlendMode` gets the same picker |
| `SceneInspectorView` — a combo's `require` (for example `RIMLIGHTING` needs `LIGHTING=1`) | — | WE hides a combo whose requirements don't hold | fixed |
| Labels | `ui_editor_properties_x` turned into words | WE's `locale/ui_*.json`, bundled in `we-assets/locale` (`WallpaperEngineLabels`: the user's language over English); the words are the fallback | fixed |

## 2. project.json properties (sidebar) — fixed

| Location | Was | WE's source | Verdict |
|---|---|---|---|
| `SceneUserPropertiesView.load` — `min`/`max` when absent | 0 / 1 | WE's editor creates sliders as 0 / 1 | kept; now cited (`UserPropertyDefinition.defaultSliderRange`) |
| `UserPropertySliderFormat.effectiveStep` | continuous when there is no step | `step || 1` | fixed |
| `UserPropertySliderFormat.fractionDigits` | `precision`, or 3 | `precision − 1` (WE saves the decimals + 1), or 1 → 0 decimals | fixed |
| sidebar slider | the step wasn't passed to the slider | the slider snaps to WE's step | fixed |
| `usesDegrees` for ids ending `_direction` | shown in degrees ×180/π | WE shows the raw value | fixed (the name heuristic is gone) |
| property `text` and combo option labels | turned into words | WE's translation, then words | fixed |
| `_owe_*` sliders (hue, saturation, bloom, blur, speed, parallax, text size and opacity) | app ranges, continuous | not in WE | keep: app extras, 0.01 step; identity at their defaults, so they never change WE's values untouched |
| `undeclaredVisibilityToggles` | invents bool properties for undeclared `visible` bindings | WE shows only declared properties | keep (app affordance); shown under Wallpaper Settings, which is **unknown** whether acceptable |

Parsing moved to `UserPropertyDefinition`, which has unit tests. It is also checked against every library project.json.

## 3. scene.json `general` — fixed defaults and runtime

| Field | Was | WE's default (`wallpaper64.exe` constructor) | Verdict |
|---|---|---|---|
| `bloomstrength` | 1 | 2.0 (offset 0x3bc) | fixed (`SceneGeneralDefaults`) |
| `bloomthreshold` | 0.7 | 0.65 (0x3c0) | fixed |
| `bloomtint` | 1 1 1 | 1 1 1 (0x3d8…0x3e0) | kept |
| `bloomhdrstrength` / `threshold` / `feather` / `scatter` / `iterations` | not read | 2.0 / 1.0 / 0.1 / 1.619 / 8 (0x3c4…0x3d4) | unknown: the HDR chain isn't implemented (roadmap 5.4) |
| `camerashakespeed` / `amplitude` / `roughness` | 0 | 3.0 / 0.5 / 1.0 (0x328 / 0x32c / 0x330) | fixed default; the renderer now uses them (`SceneCameraShake`, below) |
| `cameraparallaxamount` / `delay` / `mouseinfluence` | 0 | 0.5 / 0.1 / 0.5 (0x334 / 0x338 / 0x33c) | fixed default; the renderer now uses them (`SceneCameraParallax`, below) |
| `gravitydirection`, `winddirection`, `windstrength` | not read | (0, −1, 0); (0.707, 0.707, 0); 1.0 | unknown: no consumer yet |
| fog fields | not read | distance 1…5, height 1…−3, densities 1 | unknown: no consumer yet |
| `SceneMetalRenderer` composite bloom threshold without WE bloom | 0.55 | WE's default 0.65 | fixed |
| `SceneMetalRenderer` `userBloom × 1.2`, `userBlur × 4` | app constants | `_owe_bloom` / `_owe_blur` are app extras | keep |

**Camera parallax — fixed** (`SceneCameraParallax`, roadmap 8.16). The invented `0.18 × depth × cursorDelta × sceneSize × amount × influence` model and its `perspective` zoom are gone. WE's model, from `wallpaper64.exe`:
1. The scene update (0x140189b0f…0x140189cc6) runs it while flag 0x100 (`cameraparallax`) is set. The influence is `cameraparallaxmouseinfluence`; WE uses 0 while its input flags 0x200200 are set, which we don't model.
2. `cursor = clamp((x, 1 − y), 0, 1)`; our cursor is already y-up.
3. `target = eye.xy + size · (cursor · influence + 0.5 · (1 − influence))`. An orthographic scene without camera paths has its authored eye reset to 0 at load (0x14018866b), so `eye` is only the camera shake, applied just before.
4. With `delay > 0`: `pos += (target − pos) · min(1, (1 − delay / 3) · 10 · dt)`. Otherwise `pos = target`. At load `pos` is the scene centre (0x140188715).
5. `g_ParallaxPosition = clamp(pos / size, 0, 1)`, and (0.5, 0.5) until parallax runs (0x1401886ea). A flag at 0x800 mirrors x; we don't model it.
6. When flags 0x108 are both set (parallax on, orthographic scene), the render loop (0x14018b062…0x14018b14e) translates every object by `amount · (root.origin.xy − pos) · root.parallaxDepth.xy`. `root` is the object's topmost ancestor (the parent chain at +0x180), so a child moves with its root. The mouse hit test at 0x14018a0b3 uses the same offset. A perspective scene isn't displaced.

**Units — measured.** `pos`, `eye` and `size` (+0x340, +0xf0, +0x354) are all scene units, so the displacement is scene units too, and with depth 1 a full cursor sweep moves an object by `−amount · influence · size`. WE 2.8.0.42 on Windows at 1920×1080, on 3802047741 (orthographic 1920×1080, amount 0.5, influence 0.17, no `parallaxDepth`): left edge → centre −82 px, left → right −164 px, opposite to the cursor and linear, about 2 px vertical drift. The model gives −81.6 and −163.2. The headless render of that wallpaper through `SceneMetalRenderer` gives −82 and −163 at 1920×1080 (−163 and −327 at 3840×2160 with the cursor in points), with or without its 0.1 delay once settled, and 0 px vertically. The shake reads the same projection height (+0x358), so its orthographic offset is scene units too: `amplitude · 0.1 · 0.1 · height`, 5.4 units for amplitude 0.5 at 1080. Tests: `SceneCameraMotionTests.testParallaxSweepMatchesWEsMeasurement`, and `CameraParallaxLibraryTests` on the wallpaper itself (skipped without the library).

The app's `_owe_effect_enabled_parallax` toggle and `_owe_effect_parallax_amount` (default 1, a multiplier on WE's amount) are kept as app extras. Tests: `SceneCameraMotionTests` checks the formulas against hand-derived values and a rendered frame.

**Camera shake — fixed** (`SceneCameraShake`). The invented `47.3 / 71.9 / 53.1 / 83.7` Hz sines are gone. WE's routine is 0x140199580, called by the scene update while flag 0x80 (`camerashake`) is set:
1. `t = speed² · g_Time`. The time is the scene clock at +0x130 of the render context, which the particle oscillate operators also read.
2. `v = (cos t, sin(1.333 t), sin t)`. An orthographic scene zeroes z.
3. With `r = roughness³` above 0.001 and not 1: `v = v / |v| · |v|^r`.
4. `v` is scaled by `amplitude · 0.1`, and in an orthographic scene also by `0.1 · projection height`.
5. The eye and centre both move by `v`, so the scene moves by `−v`. The parallax target includes the shaken eye.

**Text and shape layers — fixed.** Both now read their object's `parallaxDepth`, with WE's default 1 1 (`SceneWallpaperViewModel.parallaxDepth(of:)`). Previously both were built with `.zero`. The preview and video layers stay at 0: they aren't WE objects, and their content has no camera.

**Still open:**
- Particle systems aren't moved by parallax or shake. They should be, since WE's render loop displaces every object, and the shake moves the camera. This belongs to the particle agent's files.
- Camera paths (`camera.paths`) aren't implemented, so the eye is always 0 in an orthographic scene.
- A perspective scene's `g_ParallaxPosition` uses our 1920×1080 stand-in size. **unknown**
- A layer's `perspective` flag is carried but unused now that the invented zoom is gone. WE uses it for its perspective draw, not for parallax.

## 4. SceneScript `createScriptProperties` — fixed

| Location | Was | WE's source | Verdict |
|---|---|---|---|
| `AudioReactiveScriptEngine` shim | replaced WE's builder: combo default = `o.value` (undefined), no `_config`, every authored key copied | WE's builder: combo = `options[0].value`, `_config` with label/min/max/int/options; `_Internal.updateScriptProperties` applies declared keys only and turns a colour string into a `Vec3` when the default is one | fixed (`SceneScriptPropertiesShim`) |
| `scriptproperties` bound to a user property (`{"user":…,"value":…}`) | unresolved | WE resolves them through the user property | handoff: SceneScript agent (docs/scenescript-plan.md, WP for script instances) |

## 5. Name heuristics and native approximations

| Location | Value | Verdict |
|---|---|---|
| `SceneWallpaperViewModel.materialEffects` | read material constants by name (`brightness`/`intensity`/`gain`, `strength`/`glow`, `radius`/`sigma`, `threshold` → 0.7…) into the native image draw; bloom and blur defaulted to 1 when the shader *name* contained "bloom"/"blur" | **fixed**: removed. Every layer gets `SceneMaterialEffects.identity`, and material constants reach WE's own shader through `ImageMaterialPlan`. No library image layer matched a guessed name, so nothing regresses: the image material sweep is unchanged. Test: `SceneLayerKindTests.testMaterialConstantsAreNotGuessedIntoNativeAdjustments`. Follow-up: `SceneMaterialEffects` is now constant and can be deleted, along with the native shader's adjustment uniforms |
| `SceneWallpaperViewModel.buildMetalTextLayer` | `pointsize ?? 24`, `padding ?? 0` | unknown: every corpus text object authors both. WE's text defaults weren't located (the text property table is at 0x14025…, and the pointsize offset isn't mapped yet) |
| `SceneUserPropertiesView` text extras | size 1…256, colour `1 1 1` tint, opacity 1 | keep: app extras, multiplicative identity at their defaults |
| `SceneInspectorView` move / scale | 0.05…5×, 1/10/50 px steps | keep: app editing tools, not a WE value |
| video music sync (`VideoMusicSyncSettings`) | zoom 0…0.5, pace ±1, tilt ±15°, saturation −1…2 | keep: app-only feature |
| inspector and sidebar "Music Amount" | ± the slider span | keep: app-only feature |
| `AudioSpectrum` (was LWE's `maxStep 0.3`, `0.35·log10`, tilt) | LWE's FFT shaping | fixed: WE's pipeline from `wallpaper64.exe` (block DFT and bands `0x1400d02b0`, gain and smoothing `0x140111654`; `Audio/AudioSpectrum*.swift`) |
| `SceneMetalRenderer` `_owe_speed` | scales the scene clock, 0 stops it; the audio smoothing ignored it | WE's playback `rate`: value ÷ 100, at least 0.1 (0x140114d58…0x140114d98), times the frame clamped to 0.0001…0.25 s, clamped again (0x1401114c3…0x14011150f); the scene time is a double with a float copy that goes back to 0 past 432 000 s (0x14017fcca…0x14017fcf6); the audio smoothing steps by the same frame time | fixed (`SceneClock`, roadmap 8.4): the slider starts at 0.1 |

## 6. Particles — fixed

Particle systems now compile their initializers and operators into records the way `wallpaper64.exe`'s particle parser (0x1401c1c70) does, and the CPU (`ParticleProgramCPU`) and GPU (`ParticleProgram.h`) run them in authored order. Every default below is WE's own: it fills each element's json before parsing, with one filler per element (cited in `ParticleSystemBuilder`, `ParticleInitializerBuilder`, `ParticleOperatorBuilder`). Where two values are given, the first is for an orthographic (2D) scene and the second for a perspective one; the parser's flag comes from `orthogonalprojection` (0x14010daa0, 0x14018768a). The reverse-engineering notes are `re/initializers-spec.md` and `re/operators-spec.md` under the session's derived data.

**Emitters** (`ParticleSystemBuilder.emitterShape`):

| Field | Was | WE's value | Verdict |
|---|---|---|---|
| `rate` | ?? 100 | 10 (0x1401b8e59) | fixed |
| `distancemax` | ?? 0 | sphere 256 / 1 (a scalar); box "256 256 0" / "1 1 1" (0x1401b9100, 0x1401b9520) | fixed |
| `distancemin` | ⚠ x only, as a ratio | sphere: a radius (scalar), 0; box: a per-axis shell, "0 0 0" | fixed |
| `directions` | ?? (1, 1, 0) | sphere "1 1 0"; box "1 1 0" / "1 1 1" | fixed |
| emitter `name` | ?? "sphererandom" | sphererandom unless `boxrandom` | kept |
| `instantaneous` | ?? 0 | 0; the burst also comes out of the rate's carry (0x140237a06) | fixed |
| `speedmin` / `speedmax` | ?? 0; swapped if reversed | 0 / 0, as authored; radial from the centre, set (0x140237c14) | fixed |
| `sign` | ?? 0 | "0 0 0"; applied by flag 1, which a non-zero sign sets (0x1401c61e7) | fixed |
| `cone` | not read | 0: `u` from −cos(cone·π) (0x1401c61ba) | fixed |
| sphere spawn | uniform in a ring | radius `dmin + cbrt(r)·|v·directions|·(dmax − dmin)` (0x140237c14) | fixed |
| system `maxcount` | ?? 1000 | no default: 0 | fixed |
| `starttime` | not read | pre-simulated in 0.05 s steps (0.2 s from 500 particles; 0x14022f2e0) | fixed |
| system `flags` 8…0x80 | not read | switch off the colour, speed, count, lifetime and size overrides | fixed |
| a second emitter | ignored (logged) | WE runs every emitter record in order, each with its own rate, carry, burst, clock and per-period count, counting what the earlier ones spawned (0x1402378a0) | fixed (CPU, GPU, instances) |
| `layerimage` | logged, emitted as a sphere | points from the layer's image reduced to a quarter, a random one per spawn, through the layer's transform; flags 0x10000 (the texel's colour), `offsetmin`/`offsetmax` "−5 −5 0"/"5 5 0" (2D) with flag 0x80000 (§11.2) | fixed |
| depth (z) | dropped | `directions` z spreads the spawn in depth and the launch follows it; every operator and initializer works in 3D, control points carry z and their `controlpointangle<n>` orientation (§11.4, §11.6) | fixed |

**Initializers:** lifetime is set; size, colour and alpha multiply WE's base values (lifetime 1, size 0.5, the instance colour and alpha; 0x14023b340); velocity, rotation and spin add. Two of a kind both apply.

| Initializer | Was | WE's value | Verdict |
|---|---|---|---|
| `lifetimerandom` | 1…1 | 0…1, `exponent` 1, at least 0.001 | fixed |
| `sizerandom` | 20…20 | 5…50 / 0.001…1, times the base 0.5 | fixed |
| `alpharandom` | 1…1 | 0.05…1 | fixed |
| `colorrandom` | ?? (1, 1, 1) | "0 0 0"…"255 255 255" ÷ 255, one random for the three channels | fixed |
| `hsvcolorrandom` | ⚠ treated as RGB | hue 0…1 in `huesteps` 6 steps, saturation 0.5…1, value 0.5…1, HSV→RGB (0x1401b8c70) | fixed |
| `colorlist` | not read | a random colour of the list, jittered in HSV by the noises | fixed (up to 4 colours, more logged) |
| `normalizedParticleColor` | ⚠ ÷255 when > 1 | removed: `colorrandom` always ÷ 255, `colorchange` never | fixed |
| `velocityrandom` | 0 | "−32 −32 0"…"32 32 0" / "−1 −1 −1"…"1 1 1", one random per axis | fixed |
| `turbulentvelocityrandom` | 0; added to the range | 1D simplex noise turns `forward` about `right`; speed 100…250 / 0.5…1, phase 0…0.1 | fixed |
| `rotationrandom`, `angularvelocityrandom` | ⚠ z only | z is the 2D axis; a bare number is (0, 0, n); 0…2π and −5…5 | fixed |
| `positionoffsetrandom` | a random box | fBm of 2D simplex noise of the position and time; scale 0.001 / 1, distance 100 / 0.1, octaves 6 | fixed |
| `inheritcontrolpointvelocity` | not read | the control point's velocity × 0.1…0.2 | fixed |
| `mapsequencebetweencontrolpoints` | count ≥ 2; ⚠ arc × 0.5 | count 32 (step 1/(count − 1)), arcamount 0.3, sizereductionamount 0.9, flags 1/2/4/8, 16 (count override), 32 (restart each period) | fixed |
| `mapsequencearoundcontrolpoint` | a helix from the span | radius and height kept from the emitter, angle from the sequence; count 32, flags 1 (count override), 2 (restart each period) | fixed |
| `remapinitialvalue` | output ?? size; input range 0…1 | WE's full remap: multiply, `maxlifetime` → `size` by default, every input, output, component and transform | fixed |
| `inheritinitialvaluefromevent` | setcolor | setcolor | kept |

**Operators:** size, alpha and colour start from their base values every frame and the operators multiply them (0x14023fc08…0x14023fc99). Only `movement` moves particles by their velocity. Blend windows (`blendinstart` … `blendoutend`, 0x1401c2a40) switch an operator to its blended form.

| Operator | Was | WE's value | Verdict |
|---|---|---|---|
| `movement` `gravity` | ⚠ z if non-zero, else y | "0 0 0", in the system's space; flag 1 gives it in the scene | fixed |
| `drag` | linear `1 − drag·dt` | `v·(1 − min(drag·dt', 1))`, after the position step; dt' = dt·`pow(min(0.025 / frame time, 1), 0.7)`, the engine's frame time [engine+0x14c] (SceneScript's `engine.frametime`). `angularmovement` damps, and `controlpointattract`, `turbulence`, `vortex`, `vortex_v2`'s spin and `boids` push, by dt' too. At an fps limit ([engine+0x148], the settings' `fps`, 0x1401114f1) of 1…20 the VM runs twice with dt/2 (0x140237724…0x140237793) | fixed |
| `alphafade` | fadeout ?? 1 (none) | 0.5 / 0.5, fractions of the life | fixed |
| `sizechange` / `alphachange` / `colorchange` | 0 → 1, values 1 | start 1 (colour "1 1 1"), end 0 ("0 0 0"), times 0 → 1 | fixed |
| `angularmovement` | integrated always | force 0, drag 0; only this operator spins | fixed |
| `oscillate*` | ⚠ range middles | one random per particle for frequency, phase and scale; frequency 1…5 / 1…10, scale 0…10 (0.5) / 0…1 / 0.8…1.2 | fixed |
| `remapvalue` | ⚠ drives alpha unless velocity | multiply, `lifetimefraction` → `size`; every input, output and transform (FastNoise2 simplex and fBm) | fixed |
| remap control points | outputs 7, 8, 16…18 not written; inputs 17/18 particle → point | outputs move the particle (distance, fraction between the output points, delta, direction) or write the point into the shared array, once per group of four particles in the operator (0x140246781); inputs run particle → point; the initializer's point inputs zero the point first (0x14023d31d); written points persist as the next step's previous points; reductions leave vector outputs alone | fixed (CPU; GPU in one thread for such programs) |
| `vortex` | distanceouter 1000 | 500 / 1 … 650 / 2, speed 2500 / 1 … 0, axis "0 0 1" | fixed |
| `vortex_v2` | = vortex | adds centre force (flag 2) and a ring (flag 4): radius 300, width 50, pull 50 / 10 | fixed |
| `boids` | threshold 150; ~256 neighbours | separation 20, neighbours 50, maxspeed 500, factors 15 / 1 / 2; WE's time slicing | fixed |
| `reducemovementnearcontrolpoint` | outer 100 | inner 100 / 0.5, outer 350 / 1, reduction 100 … 0 | fixed |
| `maintaindistancetocontrolpoint` | pulls velocity | moves with the point and keeps `distance` 200 / 1 | fixed |
| `maintaindistancebetweencontrolpoints` | stiffness 10 | carries each particle with the moving segment | fixed |
| `turbulence` | scale 0.005, speed 500…1000, timescale 0.01; ⚠ `phasemax` ignored | scale 0.01 / 0.5, speed 500…1000 / 1…5, timescale 20 / 1, 3D simplex noise; `phasemax` × the particle's random (`phasemin` WE never reads) | fixed |
| `controlpointattract` | scale 100, threshold 1000 | 512 / 20, 512 / 5, flag 2 (no overshoot), delete within 15 / 0.5 (flag 1) | fixed |
| `capvelocity` | cap | 100 / 1 | fixed |
| `inheritvaluefromevent` | set/multiply only | setcoloropacity; every verb, each step | fixed |

**Renderer:**

| Field | Was | WE's value | Verdict |
|---|---|---|---|
| trail length | ⚠ 1 in the simulation, 0.05 / 10 for the shader | one value: `spritetrail` `length` 0.05, `maxlength` 10, `minlength` 0 (the shader's stretch); `ropetrail` `length` 1 s of history | fixed |
| `subdivision` | ⚠ 4 in the simulation, 0 for `TRAILSUBDIVISION` | `rope` 4, `ropetrail` 1, clamped 0…32, for both | fixed |
| `segments` | ?? 4 | 4 | kept |
| built-in trail | `speed · 0.08` | WE's stretch, as the shader | fixed |
| particle size | the shaders read half | WE's size (the base 0.5 × the random) is the quad's width everywhere | fixed |
| refract-amount opacity 0.04…1 | heuristic | built-in draw only | keep (it only affects the fallback draw) |
| `orientation`, `axis`, `flags` | not read | screen / upright / fixed axes for `g_Orientation*` (0x1402298b0; flag 1: the axis in the scene), the rope's ORIENTATION combo | fixed |
| rope `uvscale` / `uvsmoothing` / `uvscrolling` | not read | the rope builder's layout (0x14023099e): expected points rate × lifetime (capped at the fps limit while filling), smoothing (default on) slides the texture as the oldest point dies, scrolling shifts it by the dead, the count ÷ uvscale; a scrolling `ropetrail` takes TRAILSCROLLALPHA and WE's `g_RenderVar0` | fixed |

**Control points** (0x14022e3e0): read by index (WE ignores `id` and `locktopointer`); flag 1 follows the cursor, flag 2 is a scene position (not for control point 0), flag 4 copies the parent system's `parentcontrolpoint`. Flag 16 is set by 10 WE assets (the dripping-water presets, on the points their instance override drives), but the runtime never reads it: the point's flags are tested only for 1, 2, 4, 8 and the parser's 0x10000 (0x14022e461, 0x14022a08c, 0x14022e66e, 0x14022a765, 0x14022bf26). It is a plain point here too.

**Units:** the particles simulate in their system's space (WE's model matrix, 0x14023761b…0x14023767a): velocities, gravity, forces and every distance scale and turn with the object. A `worldspace` system simulates in the scene; its spawn offsets and velocity initializers turn with the emitter (the control point matrix).

**Children, audio, collision:** children `maxcount` 10, `probability` 1, type static (kept); link `flags` 1 makes the child's control points the parent's particles, 2 restarts the child each time a periodic emitter of the parent starts a period (0x14022f790 → 0x14022f6c0; §11.3); audio `audioprocessingbounds` "0.8 1.0", `exponent` 2, frequency 0…1 (kept); collision defaults 2D / 3D: plane at −150 / 0, sphere at "0 −200 0" / origin with radius 50 / 1, quad "0 −150 0" / origin of 200 × 200 / 1 × 1, bounce 0.5, push-out × 1.05 (kept, now cited).

**Instance overrides:** 1 by default, no clamps (WE has none either); the system's flags switch parts off. `count` scales every emitter's rate and `maxtoemitperperiod` as well as the maximum, and `rate` scales only the turbulence operators' `timescale` (the parser's bindings; §11.3).

**Camera:** particle systems now move with camera parallax and shake as every WE object does (their emitter's transform takes the layer's offset).

## 7. WE 2.8.0.42's editor (ground truth)

Checked against the editor itself (screenshots of WE 2.8.0.42 on Windows).

**7.1 Rotation — fixed.**

| Field | Editor | Ours | Verdict |
|---|---|---|---|
| `angles.z` = +30° | turns the object counter-clockwise | counter-clockwise since dc179e3 (WE's `Rz(z)·Ry(y)·Rx(x)`, 0x1401dd630) | confirmed |
| `angles.x` = 30° (orthographic scene) | squashes the object vertically by cos 30°, no perspective | was ignored | fixed: `SceneAffineTransform` takes the x and y rows of WE's rotation without their z (+x → (cy·cz, cy·sz), +y → (sx·sy·cz − cx·sz, sx·sy·sz + cx·cz)) |
| `angles.y` = 30° | squashes it horizontally by cos 30° | was ignored | fixed, as above |

The tilt comes from the authored angles, user bindings, timelines and scripts (`SceneLocalTransform.tilt`). Tests: `SceneTransformTests` (the squashes, the counter-clockwise turn, and all three angles against WE's 3D rotation projected). Still open: a parent's tilt composes with its children as projected 2×2 matrices, not as WE's 3D matrices, so a child tilted back against a tilted parent doesn't straighten; a perspective scene is drawn with the same orthographic squash (no perspective camera yet). A particle system's own `angles.x`/`.y` aren't applied to its emitter (WE simulates it in its 3D space); its parents' are.

**7.2 Blend modes — fixed.** The editor lists 33, Normal the default: under "Native (fast)" Normal, Add; under "Emulated (slow)" Tint, Darken, Multiply, Color burn, Linear burn, Darker color, Lighten, Screen, Color dodge, Linear dodge, Lighter color, Overlay, Soft light, Hard light, Vivid light, Linear light, Pin light, Diffuse light, Hard mix, Difference, Exclusion, Subtract, Reflect, Glow, Phoenix, Average, Negation, Hue, Saturation, Color, Luminosity. `wallpaperui.exe` 0x140160040 fills that menu, pairing each `ui_editor_blending_*` key with its `BLENDMODE` value, and the values select the branches of `ApplyBlending` in `common_blending.h`:

| Mode | Value | Mode | Value | Mode | Value |
|---|---|---|---|---|---|
| Normal | 0 | Screen | 7 | Hard mix | 17 |
| Add | 31 (`A + B·opacity`) | Color dodge | 8 | Difference | 18 |
| Tint | 30 | Linear dodge | 9 (`BlendAdd`) | Exclusion | 19 |
| Darken | 1 | Lighter color | 10 (`max`) | Subtract | 20 |
| Multiply | 2 | Overlay | 11 | Reflect | 21 |
| Color burn | 3 | Soft light | 12 | Glow | 22 |
| Linear burn | 4 (`BlendSubstract`) | Hard light | 13 | Phoenix | 23 |
| Darker color | 5 (`min`) | Vivid light | 14 | Average | 24 |
| Lighten | 6 | Linear light | 15 | Negation | 25 |
| | | Pin light | 16 | Hue, Saturation, Color, Luminosity | 26…29 |
| | | Diffuse light | 32 (`A + A·B`) | | |

The inspector shows `imageblending` combos and an image layer's `colorBlendMode` as that list, with WE's labels (`locale/ui_en-us.json`, English text as the fallback) and groups; the layer's choice is saved with its edited object. Tests: `WEImageBlendModesTests`, `WEAuthoredValuesTests`.

**7.3 User properties per display — fixed.** In WE the same wallpaper on two displays has independent user properties: its UI keeps them per monitor (`currentSelection.properties[selectedMonitor.location]`, `ui/dist/scripts/scripts.js`). WE's UI scripts have no setting named "sync properties": the closest is the layout, "Wallpaper per display" (0, independent properties) or "Clone single wallpaper" (2, one wallpaper and one set of properties on every display). Ours: each display has its own store, and Settings → General → "Sync properties across displays" (default **off**, WE's per-display behaviour) makes them share one. Displays whose properties are equal still share one running instance; different properties run separate instances, and a wallpaper still plays its sound once (from the instance on its audible display). Details in `architecture.md` ("Wallpaper instances"). Tests: `WallpaperPropertyScopeTests`.

**7.4 A new particle system — no change.** The editor creates a system from WE's own template, `particles/example.json`. Those are template values the editor writes into the new system's json, not what `wallpaper64.exe` assumes for an absent field, so our parse defaults (§6) stay:

| Field | Editor template | WE's parse default for an absent field (ours) |
|---|---|---|
| `maxcount` | 500 | none: 0 |
| emitter | `sphererandom` | `sphererandom` |
| `distancemin` … `distancemax` | 32 … 512 | 0 … 256 (2D) / 1 (3D) |
| `directions` | 1 1 0 | 1 1 0 |
| `rate` | 20 | 10 |
| `speedmin` / `speedmax` | 0 | 0 |
| `lifetimerandom` | 3 … 5 | 0 … 1 |
| `colorrandom` | 255 255 255 … 255 255 255 (white) | 0 0 0 … 255 255 255 |
| `sizerandom` (template, not in the screenshots) | 50 … 200 | 5 … 50 / 0.001 … 1 |
| `velocityrandom` (template) | ±50 ±50 0 | ±32 ±32 0 / ±1 |
| operators | `movement`, `alphafade` | — |
| `alphafade` | fade in 0.5 (fade out absent: 0.5) | 0.5 / 0.5 |
| material | `particle/halo.json`: additive | a material without `blending`: translucent |
| overbright | 1 | `g_Overbright`'s annotation default, 1 |

Test: `ParticleEditorTemplateTests` runs the template and gets the editor's values; `ParticleProgramTests` keeps the parse defaults.

**7.5 Clamp UVs on import — no change needed.** WE's importer turns Clamp UVs on by default and writes it into the `.tex` (TEXI flags bit 2). The renderer reads that flag alone: a flagged `.tex` clamps, an unflagged one repeats, an image that isn't a `.tex` clamps, and the object's `clampuvs` can only add clamping (`ImageMaterialPlanBuilder.textureClamps`). Nothing assumes the opposite default. Test: `TexClampUVsDefaultTests`.

**7.6 Light sliders — noted.** The editor's ranges: intensity 0…25, radius 0…30, falloff 0…4, cone 0…180 (degrees). Our inspector doesn't expose light properties (lights are read from scene.json only), so there is nothing to range yet; an inspector for lights should use these.

**7.7 An effect's Composite option — confirmed, no engine change.** The editor offers Normal, Blend, Under and Cutout, and Blend an Alpha slider (0…2, default 1). `wallpaper64.exe` and `wallpaperui.exe` have no compositing of their own for it (no `COMPOSITE` or `compositealpha` string in either): it is the `COMPOSITE` combo of the effect's own shader, `shaders/common_composite.h`:

| Mode | `COMPOSITE` | `ApplyComposite(original, effect)` (effect.rgb × `compositecolor` first, greyed by `COMPOSITEMONO`) |
|---|---|---|
| Normal | 0 | the effect |
| Blend | 1 | rgb `ApplyBlending(BLENDMODE, original, effect, effect.a × compositealpha)`; a max(effect.a × saturate(compositealpha), original.a) |
| Under | 2 | effect.a × saturate(compositealpha), then mix(effect, original, original.a) |
| Cutout | 3 | effect.a × saturate(compositealpha) × (1 − original.a) |

scene.json stores it in the pass: `"combos": {"COMPOSITE": 1}` and `compositealpha`, `compositecolor`, `compositeoffset` (UV offset in texels, only when `COMPOSITE` ≠ 0). In WE 2.8.42's assets only `effects/blur`'s combine includes it; the library uses Blend in 3546971487 (alpha 0.78) and 2963872291 (1.2, offset −2.28). The effect graph already runs it as any combo; the inspector lists the combo with WE's labels. Test: `EffectCompositeTests` (WE's blur in each mode against `ApplyComposite`, colour and monochrome). Open: WE's editor shows Alpha (and Offset) only while the compiled variant uses them; our inspector lists every annotated uniform.

**7.8 Image filter and colour options — fixed** (they were absent). WE adds seven properties to every wallpaper (`wallpaper64.exe` 0x140107160…0x140108bba) and reads them back when it applies properties (0x140182336…0x14018262f):

| Key | Label | Type, range, default | Shown |
|---|---|---|---|
| `wcc_v` | Image filter | `combolutfilters`: "" (None) or a LUT | always |
| `wcc_amt` | Filter strength | slider 0…100, 100 | `wcc_v.value` |
| `wec_e` | Show color options | bool, false | always |
| `wec_brs`, `wec_con`, `wec_sa`, `wec_hue` | Brightness, Contrast, Saturation, Hue shift | slider 0…100, 50 | `wec_e.value` |

The filters are WE's `lutFilterOptionFiles` (`scripts.js`), listed as "1 Vibrant Contrast" … "25 Retro Handheld" after None: `k23_b`, `lutx32_adventure`, `lutx32_coloration`, `simple_film`, `lutx32_bluenavy`, `80s_post-apocalyptic_action`, `desert_4`, `desperado`, `lutx32_dusk`, `lutx32_honeyb`, `lutx32_sandyskyd`, `lutx32_slate`, `lutx32_westernf`, `setting_sun`, `tower`, `lutx32_amber`, `aliens_2`, `lutx32_daisy`, `lutx32_emeraldd`, `lutx32_ferne`, `lutx32_backsea`, `lutx32_beach`, `lutx32_studio`, `sharp_wasteland`, `gamebob_2`: 32³ volume `.tex` files in `materials/lut` (TEXI flag 0x40; one PNG, blue slices stacked). WE keeps con, brs and sa / 50, hue / 100 − 0.5 and strength / 100. It makes `materials/util/ccsimple.json` only when they aren't identity: `COL` when the options are shown and any is away from (1, 1, 1, 0), `LUT` when a filter is chosen with strength > 0; then `params` = ((brs/50)², √(con/50), √(sa/50), hue/100 − 0.5), texture 1 = `lut/<filter>`, `lutparams` = strength/100. The pass runs after the bloom and its combine (lighting-plan §2.6 step 6).

Ours: the wallpaper properties sidebar shows the seven for scenes, with WE's keys, labels (WE's locale when installed), ranges, defaults and conditions; `ScenePostProcess` runs WE's `ccsimple` through the effect graph as WE does, the chosen filter's volume bound each frame. A HDR frame is corrected as the composite shows it [?: WE's HDR input to `ccsimple`]. Tests: `SceneColorCorrectionTests` (the derivations, the gates, the 25 LUTs, the pass against a CPU model of `ccsimple.frag`: within 2/255). WE's UI also offers these for video wallpapers [?: whether the engine applies them there]; ours shows them for scenes.

**7.9 Anti-aliasing — fixed** (the setting was stored but unused, defaulting to x2). WE's `msaa` (none, x2, x4, x8; none is WE's default and its low/medium presets', x2 its high/ultra presets'). With it, WE draws the scene objects into `_rt_FullFrameBufferMultiSampled` (render-target flags 0x20, 0x140181dcc) and resolves it into the frame buffer (`ResolveSubresource`, vtable +0x1c8 at 0x1400d3310, which copies instead when the target isn't multisampled) after the objects (0x140183550). Effects, bloom and the other passes stay single-sampled. Ours: the scene pass draws into a multisampled target resolved at the end of every stretch of the pass (a pause for a scene-reading layer resolves what's drawn so far), with its layer, image-material and particle pipelines made for the sample count; a count the GPU lacks falls to the next lower. The setting is stored under WE's key `msaa`, so the old unused value is left behind. Test: `SceneMSAATests` (WE's default, the stored key, supported counts, hard edges without MSAA and coverage-smoothed ones with it).

**7.10 Text layers.** The editor's new text layer ("Text Layer", white, opacity 1, Arial 32, padding 32, Smooth Font Scaling on, centred) is a template it writes into the object. `wallpaper64.exe`'s text constructor (0x140256ae0), matched to the fields by the property table (0x140259190…), is what an absent field means:

| Field | WE's parse default | Ours before | Verdict |
|---|---|---|---|
| `pointsize` | 32 | 24 | fixed |
| `padding` | 32 | 0 | fixed (every library text object authors it) |
| `spacing` | 0 0 | not read | open: the layout doesn't apply `spacing` yet (3802509485 authors 10.48) |
| `maxwidth`, `maxrows` (when limited) | 500, 1 | unlimited | fixed |
| `horizontalalign`, `verticalalign` | centre | centre | confirmed |
| `font` | empty (the system's) | the system's | confirmed |
| `msdf`, `outline`, `blur`, `dropshadow` | off | — | confirmed |
| `outlinethickness`, `outlinecolor` | 4, black | — | new |
| `blursize` | 6 (the editor's new layer writes 1) | — | new |
| `dropshadowsize`, `dropshadowopacity`, `dropshadowoffset`, `dropshadowcolor` | 6, 1, 4 4, black | — | new |

Scripts see the same values (`SceneScriptSceneDescriber`). Tests: `WETextDefaultsTests`.

*Font effects — fixed* (they were ignored). WE draws them in `shaders/font.frag` from an MSDF atlas of 32 px per em with a 24 px range (`MSDF_RANGE`). The engine sets the shader from the object (0x1401b3b60…0x1401b3f5f): sizes in scene units × 32 / pointsize × 0.24 (atlas pixels per unit; the em is pointsize × 300/72 units), clamped to outline ≤ 5.1, blur, shadow size and offsets ≤ 6, outline + blur ≤ 5.1; `OUTLINE_ENABLED` from a thickness of 1, `BLUR_ENABLED` above 0, `DROP_SHADOW_ENABLED` for a size above 0 or any offset. The MSDF atlas is used whenever `msdf` or any effect is on (0x1401b0600…0x1401b0640); otherwise glyphs are rasterised at their size. Ours: the glyphs' signed distance from their coverage raster (an exact Euclidean transform) stands in for the MSDF atlas, and `SceneTextEffects` evaluates the shader's math on it into a coloured raster; such text draws natively (the `font` material reads coverage). The library's users: 3803044683's five clocks and titles (outline 4 or 1.33, drop shadow 6, offset 4 4, black). Smooth Font Scaling (`msdf`) alone looks the same as our raster at display resolution. Tests: `SceneTextEffectsTests` (fields, WE's shader values and clamps, the distance field, outline, drop shadow and blur on a square). Not compared with a WE capture: none of the captures has text effects.

**7.11 Solid layers — confirmed.** A solid layer is an image object on `models/util/solidlayer.json`; the editor's Resolution is its `size` (1920 × 1080 for a new one), and "Enable click events" is `solid`, on unless authored false: WE's object constructor sets flag 0x2000 (0x1401ddc72), and the scripts' object table starts every object solid (`SceneScriptObjectField.defaultValue`), overridden only by an authored `solid`. The loader sizes the layer from `size` (the scene's only when it has none). No change.

**7.12 Effect defaults seen in the editor — our values.** The inspector's defaults and ranges are the shaders' annotations (materials set no constants for these), checked for every effect by `testEveryEffectParameterIsItsAnnotation`:
- **Shine:** ray threshold 0.5 (0…1), noise on, noise amount 0.4 (0.01…1), noise scale 3 (0.01…10), noise speed 0.15 (0.01…1), direction 0, speed 0 (−1…1), edges 4, quality 8 samples, ray length 0.1 (0.01…1), ray intensity 1 (0.01…2), colour white, blur scale 1 1 (0.01…2, 13×13), blend mode Linear dodge (9).
- **Depth parallax:** quality Occlusion (performance), depth 1 1 (0.01…2), perspective 1 (−5…5), center 0.3 (0…1).
- **Pulse:** blend mode Linear dodge (9), pulse colour on, pulse alpha off, amount 1 (0…2), speed 3 (0…10), phase 0 (0…6.282; the vertex shader's time offset 0…1), bounds 0 1, power 1 (0…4), noise amount 0 (0…2), noise speed 0.5 (0…1), tint low and high white, audio response off, frequency 0…1 (0…15), audio amount 1 (0…2), exponent 1 (0…4), audio bounds 0.5 1.
- **Blur:** scale 1 1 (0.01…2), kernel 13×13, Composite Normal (Alpha 1, 0…2), blend mode Normal, monochrome off, blur alpha on.

The recordings' numbers weren't in the brief, so these are listed for comparison: any that differs is a mismatch to fix.

**7.13 Texture resolution, and `quarter` — WE has no quarter; `auto` fixed for sized scenes.** Captures of 3270035750 at `resolution` full, half and quarter (tools/peer README, batch 3, item 7: shared GPU memory full 707 MB, half 327 MB; quarter's reading failed).
- **The settings offer three values.** `ui/dist/scripts/scripts.js` `textureResolutionOptions`: High Quality (`full`), High Performance (`half`) and Automatic (`auto`). Ours has the same labels. WE's presets (`getQualityPreset`) all use `full`, and so do ours.
- **`quarter` is `auto`.** `wallpaper64.exe` has no `quarter` string. It reads `general.resolution` with `""` as the default (0x1401155b3), then compares the value with `full` (0x1401155f6) and `half` (0x14011560e) only. Any other value sets engine flag 0x10, which is `auto` (0x140115629). That covers `auto`, a missing key and a hand-written `quarter`; WE keeps `quarter` in `config.json` because the UI only stores the string. The reduction is 1 + a bool (0x140187e37…0x140187e3c), so it can't be 4, and the `.tex` loader skips at most one mipmap.
  - The stills agree. The Laplacian variance of the lace crops (Nami's bodice, her stocking, Robin's lace and Boa's stocking) is:
    - full: 2370, 976, 2646 and 965
    - quarter: 2253, 1006, 2628 and 810
    - half: 1100, 533, 1267 and 415
  - So quarter is as sharp as full. Its `auto` doesn't reduce this 1920 × 1080 scene on a 1920 × 1080 display (see the next point). `half` also passes `-halfresolution` to `webwallpaper64.exe` (0x14011a681…0x14011a729; only `half`, not `auto`).
- **`auto` depends on the scene — fixed.** 0x14017e6f0 first checks engine flag 0x400, which is set at load when `general.orthogonalprojection` has a nonzero width and height (0x1401875b5…0x14018768a).
  - With the flag, `auto` reduces when the scene's width × height is more than 3.9 × the window's pixels (0x140492848; the window is `g_Screen`'s size, 0x1400d84eb). A 3840 × 2160 scene on a 1080p display reduces. A 1920 × 1080 scene never reduces, even on a small display.
  - Without the flag (a perspective scene), `auto` reduces below 0.95 × 1080p, as before.
  - Ours only applied the window rule. `TextureReduction.factor(_:outputPixels:sceneSize:)` now applies both, with the scene's size from `TextureReduction.orthographicSize(of:)`.
  - An `orthogonalprojection` with `auto: true` also sets the flag (0x140187565), but its size stays 0, so `auto` never reduces that scene; ours does the same (`WESceneProjection.orthographicAuto`).
- **Our half against WE's (headless, `WEReferenceComparisonTests`, `texres_*` captures).** Colours match; mean luma is 142.6 for WE and 142.3 for ours.
  - Our half has lower lace variance than our full, as WE's does: 920/2085, 474/975, 889/2297 and 523/973. WE's are 1100/2370, 533/976, 1267/2646 and 415/965.
  - SSIM is 0.69 for half and 0.91 for full; the lower half score comes mostly from the figures' bob phase. `texres_half/still2` is a frame without the side figures, so it isn't ranked.
- Tests: `TextureReductionTests` (both `auto` rules, the flag's both-sides rule, and WE's config values including `quarter`).

**7.14 Light count and lit images — confirmed, no change** (lighting-plan §2.2, "Light count"). What the user saw in the editor: a 2D scene "allows 15 lights"; 256 point lights "all work" in a 3D scene; an image was lit only after Cast shadow. What the binaries say:

| Question | WE | Ours |
|---|---|---|
| Lights per scene | No limit. Adding a 16th light shows "Total light limit of 15 has been reached. The wallpaper will only display the closest lights" and adds it anyway (`wallpaperui.exe` 0x1400a37c6). 2D and 3D are the same. | no limit |
| Lights that light a surface | At most 15 per type (point, spot, tube, directional). This is the `lightconfig` word, which the editor writes as min(count, 15) (0x14041cd30), with at most 3 shadow maps and 1 cookie. Each frame the first ones in sort order are used: shadowed and cookie lights first, then the closest along the view (`wallpaper64.exe` 0x140190c80). | same (`WELightConfig`, `SceneLightPacker`) |
| Does `castshadow` choose lights? | No. It only sorts the light first and, with shadows on, gives it a shadow slot. | same |
| What lights an image | Its material's `LIGHTING` combo, the layer's Lighting option ("Only affects images with lighting enabled or 3D models"). | same (`SceneEngineCombos.lightingCombos`) |

So the 256-light test can't have lit more than 15 points at once, and the Cast shadow observation is an editor artefact or the test setup (lighting-plan §5 item 8 lists what to capture). Tests: `SceneLightPackerTests.testTwoHundredFiftySixPointLightsKeepTheFifteenClosest`, `testCastShadowSortsButDoesNotSelect`.

## 8. Effects at their defaults (WE's effect gallery)

**Ground truth.** WE 2.8.0.42 on Windows drew one generated scene per built-in effect (the peer's `tools/peer/effect_gallery`, README and EXTRAS.md): orthographic 1920 × 1080, clear colour 0.15, a checkerboard and an HSV gradient (1024², scale 0.85) each carrying only `{"file": "effects/<name>/effect.json"}`, so every value is the shader annotation's default. The captures are a still about 5 s after load and a 3 s clip; `metrics.tsv` holds each effect's mean absolute difference from the no-effect scene and its mean frame-to-frame motion (480 × 270 luma at 5 fps). EXTRAS.md item 2 adds blur's five `COMPOSITE` modes.

**Ours.** `WEEffectGalleryTests` builds the same scenes from the fixture pictures (`Tests/Fixtures/WEEffectGallery`) and the WE assets' effects, draws them through the real loader and renderer (`WEReferenceRenderer`, the still at 5 s and 16 frames at 5 fps), and measures them as summarize.py does. In the first run (50 scenes, before the composites were added) 11 were off by the test's tolerances and every one lacked WE's bloom; now all 55 match WE's difference and motion within tolerance, with SSIM against WE's stills of 0.87–1.00 (the random effects, film grain and glitter, are matched by their statistics, not their pixels).

| Effect | Was | Cause | Fix |
|---|---|---|---|
| every scene (the control too) | SSIM 0.84 against WE's control, a glow missing around bright areas | a scene without `general.bloom` blooms in WE; ours didn't | §9.1 |
| refraction, water ripple | refraction 27 against 17.7; water ripple static (motion 0 against 3.5) | their normal maps ship as `materials/effects/<name>.png` with a `.tex-json`; a PNG was looked for only beside the material, not where the `.tex` is | a PNG (or JPEG, GIF) is looked for at every `.tex` candidate path (`SceneWallpaperViewModel.loadTexture`) |
| motion blur | the layers at 0.8 opacity (diff 42 against 0) | its accumulation reads `_rt_FullCompoBuffer1`, which only the previous frame wrote; the chain has no time input, so its first output was kept for good | `SceneEffectPlan.carriesFrames`: an effect that samples or copies an FBO before the frame writes it, or swaps buffers, is never kept |
| foliage sway | motion 0.44 against 2.46 | `g_Speed` is `speed` (1) in the vertex stage and `speeduv` (5) in the fragment stage, and `g_Phase` 0 and 0.5; both stages shared the vertex stage's value | a uniform both stages declare differently (type, material key or default) gets a fragment-stage copy, `<name>_weFragment`, with its own annotation (`ShaderUniformDeclaration.stageLocalNames`, `ShaderPairRewriter`; translator revision 8) |
| glitter | dense 1 px speckles, motion 0.57 against 1.47 | its `_rt_GlitterTiles` FBO is a fixed 256² tile (`width`, `height`) sampled with `"uvs": "repeat"`; both were ignored, so the tile was layer-sized | `EffectGraphRenderer.fboSize` honours a fixed size; an FBO with `uvs: repeat` is sampled with a repeating sampler |
| x-ray | a halo at the centre (then a corner) of every layer | `g_EffectTextureProjectionMatrix` was identity, so the pointer mapped into every layer's image as if the layer filled the screen; and WE's pointer is y-down (its shaders flip it "to match texture space Y") while ours was handed y-up | the matrix maps the effect's texture space to the layer's quad on screen (`EffectGraphRenderer.effectTextureProjection`); `g_PointerPosition`/`Last` are y-down in the shaders (`BuiltinUniforms`). Cursor ripple and the fluid simulation's force use both too |
| filmgrain | — | matches (2.2 against 3.3 difference, motion 0.70 against 0.69), but our grain's spread is about 0.66 of WE's | open (docs/test-risks.md FX2) |

The 11 effects WE shows no change for at their defaults (blend, cursor ripple, fire, motion blur, opacity, perspective, shake, skew, transform, water flow, x-ray) show none in ours either (0.00, SSIM 1.000). The composite modes match: normal 10.73 (WE 10.75), blend α 0.5 3.47 (3.47), blend α 1.5 19.27 (19.34), under 0.00 (0.00), cutout 82.18 (82.10). scene.json's `passes` map to effect.json's passes by position (blur's `COMPOSITE` is in pass 4, as in WE).

**Effects missing from the project — fixed.** WE resolves an effect's `materials/…` and `shaders/…` at the project root, then the assets root, and never inside `assets/effects/<name>/`: without its copy of `materials/effects/<x>.json` a project logs "Failed opening" and WE drops the effect. Ours looked in the effect's own folder first, through the same reader that falls back to the WE assets, so it found `assets/effects/<x>/materials/…` and drew the effect. Now the effect's folder is searched only when the wallpaper itself has the effect (its folder, package or a Workshop item it references: `SceneEffectPlanBuilder.readWallpaperFile`), and only in the wallpaper's files; otherwise the plan fails with `missing materials/effects/<x>.json`, which is logged once with the object, and the effect is dropped. A Workshop effect keeps its files in the effect's folder of its item (`effects/workshop/2084198056/Simple_Audio_Bars/`, used by 2176097362, 2370927443 and 3074485715), and that still resolves. Every library scene was checked: all 716 built-in effect uses ship their materials, shaders and textures at the project root (or find them at the assets root, as 3384390033's `materials/util/effectcomposebackground.json`), so no library wallpaper loses an effect. The engine's own chains (bloom, HDR, colour correction) read WE's assets directly and keep the folder lookup. Tests: `SceneEffectAssetScopeTests`.

Tests: `WEEffectGalleryTests` (gated by `OWE_EFFECT_GALLERY`; expectations and tolerances in `Tests/Fixtures/WEEffectGallery/expected.json`), `EffectGraphTests.testMotionBlurAccumulatesAcrossFrames`, `testFixedSizeFBOsDontFollowTheLayer`, `testXRaySpriteFollowsThePointerOverTheLayer`, `ShaderStageUniformTests`, `SceneEffectAssetScopeTests`, `BuiltinUniformTests.testPointerParallaxAndScreen`.

## 9. WE 2.8.0.42's generated extras (effect gallery EXTRAS.md, ground truth)

The peer generated these projects without the editor (`build_extras.py`) and captured them in WE 2.8.0.42 on Windows: the gallery's layout (checkerboard and gradient, 1024 px at scale 0.85, over 0.15 grey), a still at about 5 s and a 5 s clip. `WEExtrasComparisonTests` draws each through our loader and renderer at the gallery's settings (post-processing on, MSAA x2) and writes WE | ours | difference pictures and `report.tsv` (run with `OWE_WE_EXTRAS` pointing at a folder with `projects/fxx_*`, their `.tex` restored, and `we/<name>.png`). Mean absolute difference from WE's still (0–255), after the fixes below:

| Project | Before | After |
|---|---|---|
| No object (the layout alone) | not drawn; the blur composite projects on the same layout were 14.5–18 | 0.26 (the composites 0.25–0.44) |
| Solid band, blend modes 0, 2, 7, 9, 11, 18, 31 | 22–40 | 0.20–0.27 |
| Text, plain / outline / blur / drop shadow / defaults only | 7.2–9.4 | 0.5–1.7; 0.27–1.50 with WE's advances (9.5) |
| Refraction drops | 20.8 | 4.4 (random drop positions) |
| Timeline single / mirror | 14.6 / 16.9 | 0.19 / 0.36 |

**9.1 Bloom is on when the scene leaves `bloom` out — fixed.** Every capture glows: a halo around the checkerboard's red border, bright colours bleeding into the grey. The scene settings constructor starts the flags at 0x26 (0x140186d1f), and `bloom`'s accessor sets and clears bit 2 of that word (property table entry 0x140199825, accessor 0x14019b4e0), so bloom is on unless the scene turns it off. `hdr` is bit 0x400 (0x14019b6f0), which starts clear. Ours read an absent `bloom` as off. The editor writes `bloom` into every scene it saves (all 61 unpacked library scenes author it), so only generated or hand-written scenes change. Test: `WEAuthoredValuesTests.testBloomIsOnWhenTheSceneLeavesItOut`. Three render fixtures that test other things now author `"bloom": false`, as the editor would.
- Not fixed (SceneScript area): `thisScene.bloom` reads `SceneScriptSceneField.defaultValue`, which is 0 for `bloom`, `bloomstrength` and `bloomthreshold`. For a scene without them, WE's values are on, 2 and 0.65.

**9.2 The solid band is "more cyan" because of bloom, not colour space — fixed with 9.1.** The band's colour 0.2 0.6 1.0 is stored and drawn as authored. WE's LDR bloom (`downsample_quarter_bloom.frag`) takes max(r,g,b) − threshold (1 − 0.65 = 0.35), scales the colour by it, pushes saturation (2·c − luma), and adds 2× that (strength 2): (0, 0.47, 1.03). Added to (0.2, 0.6, 1.0) and clamped, that gives (51, 255, 255), which is WE's pixel exactly. The same arithmetic gives WE's Difference band over grey, (14, 170, 255). The darker results (Multiply 8, 23, 38 and Overlay 15, 46, 76 over grey) stay under the threshold and show the colour unchanged.

**9.3 A solid layer's `colorBlendMode` — fixed** (test-risks E-5). Its `flat` shader has no `BLENDMODE`, so ours logged it and drew the band opaque. WE composites a layer through `materials/util/effectpassthrough_4.json` (genericimage4) with `BLENDMODE` set to the object's mode and `FOG_COMPUTED` 1 (0x1401ebcba…0x1401ebe55; `effectpassthrough.json`, genericimage3, when the renderer reports a level below 3). It maps mode 31 to 0 and adds with the pass's blending. Ours: a solid layer with a blend mode draws its fill through that material (`ImageMaterialPlanBuilder.buildBlendComposite`); for 31, `ApplyBlending`'s A + B·opacity is the same sum. All seven modes now match WE's still within 0.3. Tests: `ImageMaterialRenderTests.testSolidFillCompositesWithItsBlendMode` (Multiply against WE's arithmetic), `SceneSolidLayerBlendTests`.

**9.4 Timelines — match, no change.** The tracked arrow over the 5 s clips (6 fps) against our evaluator (`SceneTimelineChannel`, Bézier x handles scaled by half the segment, bisection, integer frames) with the clip's start fitted: loop 1.8 px mean error, mirror 1.9 px, `loop_bezier` 0.7 px. `loop_bezier` holds near 481…492 for a second, then snaps to 779, in both. `single` holds 780 in both. Our headless frames step exactly as the model does. The loop stills differ from WE's (9 and 43) only because WE's capture started at an unknown time after load (the fit puts it about 1.2 s into a cycle).

**9.5 Text — placement fixed; font effects match.** With the placement fixed, outline 4, blur 1, drop shadow 6 / 1 / "4 4" and the defaults-only case (outline 4, blur 6, shadow 6, "4 4", black) compare at 0.9–1.7 mean abs. Before the fix, aligned by hand, they already looked the same (`/Volumes/980Pro/agentEX-out/text_effects_aligned.png`). The glyph cores sit within 0.6 px of WE's. The placement was about 38 px too high and 5 px too far left. WE's layout (0x1401b0410, placed by 0x140257690…0x1402577c4) is:
- **Metrics.** The line height, ascender and descender are FreeType's size metrics in whole pixels: ascender rounded up, descender rounded down, height rounded to nearest. For NotoSans at 64 pt these are 286, −79 and 363.
- **Vertical.** `verticalalign` (bottom 0, center 1, top 2) places the first baseline at:
  - center: −(asc − (n−1)·L)/2. The block from the first ascender to the last baseline is centred, and the descender is ignored.
  - top: −asc.
  - bottom: −desc + (n−1)·L.
- **Horizontal.** A line's width is its glyphs' ink, joined with the pen's start. Lines align within the widest. The block's span is centred on the origin, or starts (`left`) or ends (`right`) on it.
- **What doesn't place the text.** scene.json's `size` plays no part, and `padding` is only room around the glyphs.

Ours followed a box: the authored size, grown to fit, with the edge named by the alignment on the origin, and the lines inside the padding centred as ascender to descender. `SceneTextLayout` now places the lines as WE does, around the origin, in a box centred on it. Tests: `SceneTextLayoutTests` (the capture's baseline at −143, each vertical and horizontal alignment, the box holding the lines). This supersedes "match WE's in size and place" in we-reference-report R1 for vertical placement.
- **Advances, the buffer and `blockalign` — fixed (2026-09-27, test-risks EX1–EX3, GP2).**
  - **Advances.** Each glyph advances by HarfBuzz's advance floored to a whole unit (0x1401b1166: `x_advance >> 6`; offsets likewise). A glyph's box for the line width is FreeType's pixel box (`FT_Glyph_Get_CBox(…, FT_GLYPH_BBOX_PIXELS)`, 0x1401addb0). Measured on "WE Text 123", the glyph centres are within 1.1 units of WE's, against 2.5 with CoreText's fractional advances. The text extras improved: plain 0.54 → 0.27, msdf 0.94 → 0.85, blur 0.94 → 0.84, drop shadow 1.16 → 1.05, outline 1.67 → 1.50, defaults only 1.45 → 1.29.
  - **The buffer.** It is the lines' bounds (the ink across; the first ascender to the last line's bottom) plus `padding` (at most 512), centred on those bounds (0x140258900, 0x140257d70, 0x140258050). A left-aligned text's buffer starts at its ink less the padding, so a layer sampling it 1:1 (3378346807's `TRANSFORMUV` overlay) sees the glyphs at x = `padding`, as in WE's capture.
  - **`blockalign`.** A line the wrap broke (flag at 0x1401b1cc6) spreads `maxwidth` less its width over its spaces, tabs and carriage returns, and takes `maxwidth` as its width (0x1401b21ee…0x1401b22d1).
  - **`systemfont_*`.** WE's table at 0x140484cc0 maps eight names to Windows font files (arial, calibri, cambria.ttc, comic, consola, micross, segoeui, verdana). A name outside it, or a face that fails to load, falls back to `arial.ttf` (0x1401ad549). `SceneFontResolver.weSystemFonts` maps each to its family, or to a macOS stand-in: Cambria → Times New Roman, the closest match to the metrics measured on 3378346807's clock.
- **Still different:** WE's glyphs are hinted FreeType outlines, ours CoreText's unhinted ones. WE adds the padding only to text with effects or text that is sampled (0x140258954).

**9.6 Particle refraction — match, no change.** Eight static 220 px `rainrefractive` drops. Measured on the gradient against the no-object capture, each drop's left half shows the background from 27–56 px to its right and its right half from 6–55 px to its left, like a lens. The peer's "colour from the right" is the left half. Ours (WE's `genericparticle` with `REFRACT`) does the same: +30…+52 on the left half and −35…−50 on the right. The drops' positions are random in both.

**9.7 Image layer material and light fields — no gap.** genericimage4's combos (LIGHTING 0, REFLECTION 0, FOG 1), textures and material values (roughness 0.7, metallic 0, … reflectivitydistance 4) reach the renderer from the shader's own annotations. Every light field EXTRAS.md lists (`light` lpoint/lspot/ltube/ldirectional, color, intensity, radius, exponent, innercone, outercone, lightsourcesize, castshadow, castvolumetrics, density, volumetricsexponent, usecookie/cookie, cascadedistance0/1/2) is decoded.

**9.8 Particle registry — checked.** The strings in `wallpaper64.exe` list 3 emitters, 16 initializers, 26 operators, 4 renderers and 3 child events. The operator EXTRAS.md calls `vortex_v` is `vortex_v2`.
- All initializers and operators build, except `collisionbox`, whose VM entry does nothing in WE (0x140240279). `collisionmodel` collides with its linked model since M10 (models-plan §2.12).
- The renderers `sprite`, `spritetrail`, `rope` and `ropetrail` and the events `eventfollow`, `eventspawn` and `eventdeath` are handled.
- The `layerimage` emitter (particles emitted from a layer's image; only WE's element preview uses it) is built (§11.2).
- Test: `ParticleProgramTests.testEveryRegisteredInitializerAndOperatorBuilds`.

## 10. WE 2.8.0.42's particle editor schema (ground truth, data only)

`docs/we-particle-editor-schema.json` holds the particle editor's property panels. For every renderer, emitter, initializer and operator, the `children[]` and `controlpoint[]` entries, and the system panel, and the particle layer's instance sliders (53 panels, 435 fields), it gives:
- label (WE's `ui_editor_properties_*` key and its English text)
- type, slider range, step, whether typed values are clamped
- the value the editor writes when the component is added (2D, and 3D when it differs: 45 fields)
- combo options with their JSON values
- the visibility condition
- the VA it came from

How it was read:
- **Panels.** `wallpaperui.exe`'s panel builder (0x1401bba44) has one branch per component id. Each field is one call: number box 0x1401f39d0 / 0x1401f36f0, float slider 0x14015f0f0 (min and max as float arguments), int slider 0x14015f470, vector 0x14015d310, flag checkbox 0x140161620 (bit as an immediate), checkbox 0x140160f60, combo 0x14015fd90, and condition 0x1401641c0.
- **Shared groups.** Renderer orientation, axis and worldspace are at 0x1401b7e80. The operator blend window is 0x1401b76a0, audio response 0x1401b78c0, collision behaviour 0x1401b8ca0 and limit behaviour 0x1401b8630. The system panel is 0x1401b68e0.
- **Add-defaults.** When a component is added, a filler for it (0x140150070…0x140159b70) writes every absent key. Like the runtime, the filler takes the scene's orthographic flag, so 2D and 3D values can differ.
- **Option values.** They come from the editor's value tables (0x140abac30: remap values, operations, event verbs, transforms, components). Labels come from `locale/ui_en-us.json`.
- **Steps and clamping.** These come from the property templates in `ui/dist/scripts/scripts.js`:
  - `number` is `<input type=number step=any>` with no min or max (arrow keys ±1).
  - `slider` steps 0.01 (`sliderHighPrecision` 0.001); `sliderint` steps 1.
  - The typed box next to a slider has no range, and rzslider's `enforceRange` is off. **The editor clamps nothing**, except the colour list's count, which is a 1–10 slider with no box.
- **Cross-check.** The Windows session's UI Automation read of the editor (`particle_fields.json`) matches every one of its 327 values: order, value and option list. That settles which JSON key each unlabeled X/Y/Z box edits.

**Ranges.** Only these fields have one; every other number is an unranged box:

| Field | Range |
|---|---|
| rope / ropetrail `subdivision` | 0–16 |
| ropetrail `segments` | 2–16 |
| rope / ropetrail `uvscale` | 0.1–3 |
| hsvcolorrandom `huesteps` | 1–30 |
| colorlist count | 1–10 |
| mapsequencebetweencontrolpoints `sizereductionamount` | 0–1 |
| mapsequencebetweencontrolpoints `arcamount` | −1–1 |
| audio response `audioprocessingfrequencystart` / `…end` | 0–15 (int) |

The material panel's overbright is 0–5 (UIA).

**Flag bits** (checkboxes on `flags`):

**The particle layer's instance sliders** (UIA; `instanceoverride`), all 1 by default, each with a free number box: Opacity (`alpha`) 0.01–1, Playback rate (`rate`) 0.01–5, Speed 0–5, Size 0.01–5, Count 0.01–2, Lifetime 0.01–2; a Color picker (`colorn`) follows. The runtime clamps none of them (§6).

**Editor spot checks** (UIA on the Windows session, `particle_schema/README.md` and `editor_observed_v3/legacy_panels.json`), now in the schema:
- **Remap components.** "Input component" (All/X/Y/Z/Sum/Average/Max/Min) shows only when Input is a vector; "Output component" (All/X/Y/Z) only when Output is a vector. Input = Position with Output = Size shows neither, so the list without All that the panel code builds for a scalar output (0x1401b93d0 mode 0) never appeared. Both remaps.
- **`remapinitialvalue`'s Input list** has no "Lifetime fraction" (the operator's starts with it), as the schema had.
- **A child's Max count (10) and Probability (1)** stay visible with Type = Static; the panel's condition (`pList[1].value!=='static'`) doesn't hide them.
- **`collisionbox`** has no display name in the editor (it shows the raw key `ui_editor_particle_element_operator_collisionbox`), so it is deprecated: marked `deprecated` in the schema. Its VM entry does nothing (§9.8).

| Where | Bits |
|---|---|
| System | 1 worldspace, 2 no frame blending, 4 perspective, 8 / 0x10 / 0x20 / 0x40 / 0x80 disable colour / speed / count / lifetime / size overrides. The five override bits match `SceneParticleOverrides`. |
| Renderers, movement | 1 worldspace |
| Emitters | 2 limit to one per frame, 4 random periodic emission (shows min/max periodic duration and delay, and max to emit per period) |
| layerimage | 0x10000 copy layer colour (**on** when added), 0x20000 update the emission bitmap periodically, 0x40000 inherit layer motion, 0x80000 random offset |
| mapsequencearoundcontrolpoint | 1 modify count with layer settings, 2 restart with periodic emission |
| mapsequencebetweencontrolpoints | 0x10 modify count, 0x20 restart, 1 / 2 / 4 reduce outer positions / velocities / sizes, 8 arc |
| remap | 1 clamp input, 2 clamp output |
| controlpointattract | 1 delete in centre, 2 reduce velocity near centre (**on**) |
| vortex / vortex_v2 | 1 infinite axis; v2: 2 maintain distance to centre, 4 ring shape |
| boids | 1 clamp speed (**on**) |
| collision plane / sphere / quad | 1 lock to control point, 2 stop rotation on collision |
| Child | 1 set control points to particle positions, 2 restart with periodic emission |
| Control point | 1 lock to pointer, 2 worldspace, 4 copy from parent (shows raw value 8 and the parent index), 0x10 hide gizmo in editor |

The control point's 0x10 is editor-only, which confirms §6: the runtime never tests it.

**Against our runtime defaults — no change.** Every add-default the fillers write equals the parse default we use for an absent field (§6), in 2D and 3D. This covers:
- emitter rate 10, periodic 2/3/1/2
- `distancemax` 256 / 1
- `sizerandom` 5…50 / 0.001…1
- `rotationrandom` max 0 0 2π (shown as 360°)
- `turbulentvelocityrandom` 100…250 / 0.5…1
- turbulence, vortex, vortex_v2 ring values, boids, capvelocity, collision, children (maxcount 10, probability 1, static)
- the flags defaults: controlpointattract 2, boids 1
- remap: multiply, `maxlifetime` / `lifetimefraction` → `size`, components `all`, transform scale 2, octaves 3
- inherit verbs: `setcolor` / `setcoloropacity`
- rope smoothing on; ropetrail fade alpha / size off

So the fillers are the engine's defaults written out, and our runtime values stay. The only editor values that differ are these:
- **The new-system template.** `particles/example.json` (§7.4) is what the editor writes into a new system, e.g. `maxcount` 500 and `rate` 20.
- **layerimage `flags` 0x10000 (copy layer colour).** The runtime's filler writes it too (0x1401b9930), so it is also our default (§11.2).
- **`uvscale` is written as the int 1.**
- **controlpointattract offset.** The panel edits `origin`, while the filler writes `offset` "0 0 0". The VM reads neither (0x140241554).

**WE quirks kept in the data:**
- The limit-behaviour combo of both map-sequence initializers is labelled "Orientation" (it passes `ui_editor_properties_orientation`).
- `rotationrandom` shows degrees and stores radians (vector mode `angle`).
- The system panel shows the parsed system's values (e.g. `sequencemultiplier` at object +0x3bc), so an absent field shows the runtime default.

**Open:**
- **Our child `flags` bit 2 — fixed.** It meant "keeps its own colours" in `ParticleFamilyBuilder`. WE restarts the child with its parent's periods, and the instance colour reaches it either way (§11.1, §11.3).
- **Our inspector** shows particle JSON raw, so there is nothing to range yet. A particle property editor should take its types, ranges, steps and conditions from this file.

## 11. Particles against WE's particle gallery (ground truth)

**Ground truth.** WE 2.8.0.42 on Windows drew two sets at 1920 × 1080, each as a still about 6 s after opening and a 5 s clip (the peer's `tools/peer/particle_gallery`, README):
- every built-in preset variant: 20 presets, 74 variants of `assets/presets/*/preset.json`, built as they are at the screen's centre over generated backgrounds;
- every particle component preview: `assets/scenes/particleelementpreviews`, 48 scenes.

Particles are random, so the comparison is statistical:
- the clip's coverage: pixels whose largest channel differs from the background (or, for a preview, from the frame's most common colour) by more than 40, at 5 fps and half size;
- its motion (summarize.py);
- the covered pixels' centroid, spread, mean colour and luma histogram.

**Ours.** `WEParticleGalleryTests` (gated by `OWE_PARTICLE_GALLERY`) builds the same projects from the WE install. It draws them through the real loader and renderer (`WEReferenceRenderer`: the still at 5.5 s, then 25 frames at 5 fps). The clip's coverage and motion must match WE's (`Tests/Fixtures/WEParticleGallery/expected.json`) within half or 0.3; known gaps are reported, not failed. The per-item table and WE | ours sheets from the last run are in `/Volumes/980Pro/agentPT-out` (`final-table.tsv`, `final-contact-*.png`); they are not in the repo.

**Result.** Before this pass 19 of the 122 items were outside those tolerances. After it 12 were, each a known gap (test-risks PG1–PG7); the light-shaft effect presets (PG3), the `collisionbounds` preview (PG4) and lightshafts_5 (PG2) have since been fixed or matched (§11.6). Items whose still differs but whose clip matches (magic_6, colorlist, maintaindistancebetweencontrolpoints, stars_0) were caught at another point of a random or periodic cycle.

| Items | Was | Cause | Fix |
|---|---|---|---|
| layerimage preview | a sphere of white halos (coverage 14.6 % against 34.8 %) | the emitter wasn't built | §11.2 |
| spritetrail preview | short ovals (coverage 0.46 % against 4.8 %, motion 0.82 against 4.62) | the trail's stretch took the scene's speed, the emitter's scale (0.102) times WE's | `g_RenderVar0.x` ÷ the emitter's scale |
| hsvcolorrandom, remapinitialvalue previews (`count` 2) | half WE's particles (27.7 % against 42.8 %) | `count` didn't scale the emitters' rate | §11.3 |
| maintaindistancetocontrolpoint, reducemovementnearcontrolpoint previews (`rate` 2.33) | twice WE's (5.0 % against 2.4 %; motion 4.41 against 2.29) | the `rate` override scaled emission; WE binds it to turbulence's `timescale` only | §11.3 |
| wildfire, fog 1 (sprite sheets) | flickered about 2.5 × too fast (motion 7.50 against 4.83) | a sequence played every sheet `duration` | §11.5 |
| star field, refractive and perspective rain, leaves, ash, perspective snow (flag 4) | flat (the star field 0.12 % against 0.61 %, motion 0.03 against 1.42) | particles had no depth, and flag 4 was ignored in 2D scenes | §11.4 |

**11.1 WE's flag tests (the peer's `particle_schema/flagtests`).**
- **Child `flags` 2.** A static child with flags 0 and one with flags 2, both under a layer's `colorn` "1 0 0", are red in WE (133,12,14 and 134,12,14). Ours skipped the tint for flag 2. The flag restarts the child with its parent's periods (§11.3).
- **`remapvalue` `flags`.** Against the same particles without the remap, the clip's light (lifetimefraction 0…0.5 → size × 0…1) is 0.64 with flags 1, 0.65 with flags 2 and 1.33 with flags 0. Ours draws 0.64 / 0.65 / 1.33 within 0.15. So bit 1 clamps the input and bit 2 the output, as the VM tests them (0x140244996, 0x1402450be, 0x140245791).
- The parser reads an absent `flags` as 0 (0x1401ce803; the filler 0x1401bfbb0 writes none), so an absent `flags` clamps nothing. WE's `absent` capture draws like flags 1. It is most likely the previous project captured again (test-risks PG8).
- Tests: `WEParticleGalleryTests.testFlagTestsMatchWE` (`OWE_PARTICLE_FLAGTESTS`), `ParticleOverrideTests.testAChildWithLinkFlag2TakesTheTint`, `ParticleProgramTests.testRemapValueFlagsClampTheInputAndTheOutput`.

**11.2 `layerimage`.**
- **Points (0x1401d3ae0).** The layer's image (its texture's own size w × h) is drawn through `materials/util/downsample_quarter.json` with `WRITEALPHA` (and `OPACITYMASK` when the layer has a mask) into a target a quarter its size, at least 2 × 2. An image larger than 3840 × 2160 is first fitted into that, keeping its aspect.
- The target is read back. Every texel whose alpha is at least 127 becomes a point with its colour. It sits at `trunc(s·(i + ½) − ⌊w/2⌋)` from the image's centre, the same down, with s = w ÷ the target's width. The spawn negates the row.
- **Binding.** The particle object's `dependencies` entry `{"type": "emitterimage", "index": n, "id": …}` names the layer of the system's n-th `layerimage` emitter (0x14022b1d9, 0x1401c6fbf).
- **Spawn (0x140238c45).** One of the points at random. With flag 0x80000 it moves by a random offset between `offsetmin` and `offsetmax`. It is placed through the layer's world matrix and the inverse of the system's, and starts at rest.
- With flag 0x10000 the point's colour multiplies the base colour (0x140239765). Without points nothing spawns.
- **Defaults (0x1401b9930).** Flags 0x10000; `offsetmin` "−5 −5 0" and `offsetmax` "5 5 0" in 2D, "0 0 0" in 3D; `speedmin` / `speedmax` 0.1 / 0.2, which only drive a puppet-warped layer's points.
- **Ours.** `ParticleEmitterImagePoints` draws the same downsample on the GPU once when the content loads, reads it back and builds the points. Both simulations pick among them (`ParticleProgramCPU.emit(image:…)`, `emitFromImage`). The layer's transform is live every frame.
- The preview matches WE's capture: coverage 33.8 % against 34.8 %, motion 3.68 against 3.55. The dots, their grid, colours and place agree. Flags 0x20000 and 0x40000 are logged (PG9).

**11.3 Instance overrides and children.**
- **The key table (0x14024d980)** puts each `instanceoverride` key at an offset: alpha 0xc8, size 0xcc, count 0xd0, speed 0xd4, lifetime 0xd8, rate 0xdc, brightness 0xe0, colorn 0xe4. The particle parser binds fields to those offsets:
  - every emitter's `rate` and `maxtoemitperperiod` to **count** (0x1401c6e6c…0x1401c6ef6, skipped with the system's flag 0x20);
  - its speeds to speed; `lifetimerandom` to lifetime; `sizerandom` to size;
  - **speed** also to `velocityrandom`, `angularvelocityrandom`, `inheritcontrolpointvelocity` and `turbulentvelocityrandom` (0x1401c855f, 0x1401c98ff, 0x1401c870f, 0x1401c8c73), `mapsequencearoundcontrolpoint`'s speeds (0x1401ca151), and the operators `movement` gravity, `angularmovement` force, `oscillateposition` frequency, `controlpointattract` scale, `turbulence` speed and `vortex`/`vortex_v2` speeds (0x1401cb52f, 0x1401cb85e, 0x1401cc416, 0x1401ccd7b, 0x1401cd872, 0x1401cdddc, 0x1401ce39b). Not `oscillatealpha`, `oscillatesize` or `boids`;
  - **size** also to `sizechange`'s start and end values (0x1401cbb48, skipped with flag 0x80);
  - each binding rewrites its field every frame as authored × override (the interpreter at 0x1401d17c0), so a range's minimum and maximum both scale;
  - `turbulentvelocityrandom`'s and `turbulence`'s `timescale` to **rate** (0x1401c8bc5, 0x1401cd7ba). Nothing else reads `rate`.
- The runtime applies alpha, brightness and colorn to the base values (0x1401d15fe…0x1401d16aa).
- Ours scaled the rate by `rate`, and not by `count`. Now `count` scales the emitters' rate, the rope's expected points and the budget's estimate, and `rate` scales the two timescales. The speed override reached only the emitters and the three velocity initializers, and size only `sizerandom`; `ParticleOverrideBindings` now binds the rest.
- **Child `flags` bit 2** is tested in one place (0x14022f7b7). When a periodic emitter of the parent starts a period (0x14022f790), each child with the bit restarts (0x14022f6c0): its time goes to 0, and each emitter's delay, duration, burst, carry and period count reset, as do its sequences. `ParticleChildLink.restartsWithParentPeriod` does that. Bit 1 is the control-point link (`controlpointstartindex` at +0x68).
- Tests: `ParticleOverrideTests.testTheRateOverrideScalesTurbulenceNotEmission`, `testTheSpeedAndSizeOverridesScaleTheFieldsWEBinds`, `testBoundOverridesResolveEveryFrame`, `ParticleEmitterTimingTests.testALinkFlag2ChildRestartsWithItsParentsPeriods`, `ParticleBudgetTests`.

**11.4 Depth and `perspective` systems.**
- WE simulates particles in 3D. A system with flag 4 draws through the temporary camera of a perspective layer even in an orthographic scene (0x140236761 → 0x1401e5b60). That camera's vertical fov is `perspectiveoverridefov` (95), with near 5 and far max(15000, d + 1000), at d = (h/2) / tan(fov/2) above the centre. It keeps `g_EyePosition`.
- Ours was 2D: the z of `directions`, `velocityrandom` and gravity did nothing, and flag 4 was ignored in a 2D scene.
- Particles now carry depth and its velocity in both simulations. The sphere and box emitters spread along z and launch along the 3D offset, `velocityrandom` adds its z, and `movement` moves by it with gravity's z and the drag. The records carry it to WE's shaders.
- A flag-4 system of an orthographic scene draws through `SceneLayerPlacement.perspectiveLayerCamera`. The orthographic view got a depth range so depth doesn't clip.
- The star field now shows WE's streaks toward the viewer (clip coverage 0.69 % against 0.61 %, motion 1.59 against 1.42), and the refractive rain's motion matches (1.32 against 1.35, was 2.70).
- The other operators were still planar (PG1). Tests: `ParticleProgramTests.testMovementAndTheEmitterWorkInDepth`, `ParticleSimulationParityTests.testDepth`.

**11.6 The program in 3D and control point orientation (PG1).**
- WE's VM keeps position, velocity and the previous position as x, y, z (system+0x2b0…0x2f0), and every operator and initializer works in 3D. Control points are 4×4 matrices: base = the `offset` (z included) and, from the object's `controlpointangle<n>` override, rows 0…2 = R(x, y, z) (x first, then y, then z; 0x14022bf53); a `worldspace` system composes them with the model, a flag 2 point of a system in its emitter's space with the inverse (0x14022a070). Flag 16 does nothing at run time.
- Readers of the orientation: the emitter (its offset turns when the system is `worldspace` or its point isn't 0, 0x140237ce3), `velocityrandom`, `turbulentvelocityrandom` and `inheritcontrolpointvelocity` (the emitter's point, 0x14023b364), `mapsequencearoundcontrolpoint` (its axis and basis), `vortex_v2` (its axis, not normalised again, 0x1402434d0) and `maintaindistancetocontrolpoint` (the distance through the inverse). Plain `vortex` doesn't turn its axis.
- Ours is now the same on both simulations: `ParticleProgramState` holds 3D position and velocity, the control points are 3D with their orientation (`ParticleFrameInputs.controlPointAxes`), `turbulence` pushes z by N(Y, Z, X), `oscillateposition` moves z with x's phase, `positionoffsetrandom` samples (z·scale, −time), the remaps read and write 3D vectors, boids and the inheritance take z.
- The vortex orb (magic_12) now matches: coverage 5.22 % against WE's 5.53 % (was 0.59 %), motion 3.03 against 2.94 (was 0.05). DNA (abstract_0) spins in depth (motion 0.23 against 0.21, was 0.17).
- The leaves (0 and 2) are unchanged: with its default `forward` "0 1 0" and `right` "0 0 1", WE's `turbulentvelocityrandom` stays in the xy plane, so their gap isn't the 3D operators (PG11).
- Not done: rotation and angular velocity stay about z only (WE's are vec3, which only a renderer reading x and y would show); a flag 4 point that doesn't copy its parent's matrix (WE converts it between the systems' spaces, [?]) copies it here; an instanced child's instances don't follow their source particle's depth.
- Tests: `ParticleProgram3DTests` (the rotation, the override and its composition, each 3D formula by hand, the GPU against the CPU in three 3D systems).

**11.5 Sprite-sheet playback.**
- For a system whose texture is a sprite sheet and that isn't "randomframe", WE writes each particle's life value as age / lifetime × `sequencemultiplier` (0x14023703b…0x140237075).
- `ComputeSpriteFrame` shows the frame at its fraction, so a sequence plays `sequencemultiplier` times over the particle's life, whatever the sheet's `duration`.
- Ours played it every `duration`. Wildfire's motion is now 4.76 against 4.83 (was 7.50), and fog 1's 0.87 against 0.86 (was 1.41). Test: `ParticleSpriteSheetTests.testASequencePlaysOverTheParticlesLife`.

**11.6 Shapes, the speed override and few-particle presets.**
- **`shape` objects (0x1401907af).** An image subclass: its load (0x14025fac0) sets its size to (h, h), h the scene's orthographic height (stored at 0x1401875fb), then loads as an image. Before its effects load it writes `DIRECTDRAW` 1 into the combos of each pass (0x14025ff50, called per pass at 0x1401e7ad2), so an effect such as `lightshafts` draws on nothing. lightshafts_0…2 cover 0.92 / 0.32 / 0.59 % against 1.05 / 0.40 / 0.64 (were 6.44 / 2.07 / 3.77, white). Test: `SceneShapeObjectTests`.
- **The `speed` override** is bound to every emitter's `speedmin` and `speedmax` (0x1401c6354, 0x1401c6a86, 0x1401c6f9c), as well as to `velocityrandom`, `turbulentvelocityrandom` and others. The `collisionbounds` preview (speed 2.9) now matches (coverage 4.96 against 4.36, motion 8.47 against 7.57). Test: `ParticleOverrideTests.testTheSpeedOverrideScalesTheEmittersSpeed`.
- **Few particles.** An expectation's `seeds` averages the item over that many particle seeds, since a system of two to four particles is one random draw per capture: lightshafts_5 is 4.55 over 4 seeds against 3.88. lightshafts_6 and snow_2 stay open (test-risks PG2, PG5).

## Tests

`OpenWallpaperEngineTests/WEAuthoredValuesTests.swift`:
- `testEveryEffectParameterIsItsAnnotation` walks every bundled effect and every effect shipped in a library wallpaper. For each parameter it checks:
  - the default, range, label, `int`, `type: color` and `linked` against the annotation
  - the default against the constant the renderer resolves
  - every combo's default and options against its `[COMBO]` annotation
- `testEveryLibraryPropertyIsAuthoredValue` checks every library project.json property: min, max, step, precision, value and option labels.
- `SceneCameraMotionTests` checks camera parallax (target, delay easing, `g_ParallaxPosition`, per-object offset) and camera shake against values worked out from `wallpaper64.exe`, and checks a rendered frame's parallax displacement.
- Unit tests cover:
  - project.json parsing (WE's defaults when a field is absent)
  - WE's label table
  - the `general` defaults, with authored values winning
  - the inspector combo override
  - `createScriptProperties` defaults and `scriptproperties` injection, run against WE's own `baseclasses.js`

`OpenWallpaperEngineTests/ParticleProgramTests.swift` checks WE's particle defaults per element (2D and 3D), two operators of a kind, the oscillators' per-particle random, `hsvcolorrandom`'s hue steps, the remap default, movement in the object's units, sequences restarting each period and `starttime`. `ParticleSimulationParityTests` runs every operator and initializer kind on both simulations, several emitters and the low-frame-rate drag and half steps among them. `ParticleRendererOptionsTests` checks the orientations and the rope layout; `ParticleRemapControlPointTests` the remap's control point inputs and outputs and their write-back, on both simulations.

The editor's ground truth (§7) is checked by `SceneTransformTests` (angles), `WEImageBlendModesTests` (the blend-mode list against `common_blending.h` and WE's labels), `WallpaperPropertyScopeTests` (per-display stores, instance grouping, sound once), `ParticleEditorTemplateTests` and `TexClampUVsDefaultTests`; §7.7–7.10 by `EffectCompositeTests`, `SceneColorCorrectionTests`, `SceneMSAATests`, `WETextDefaultsTests` and `SceneTextEffectsTests`.
