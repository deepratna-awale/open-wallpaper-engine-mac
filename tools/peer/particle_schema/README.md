# Particle editor schema: what the files give, and what is still open

## Where the schema lives
- There is no particle schema in data files. `ui/dist/scripts/*.js` does not mention any particle component.
- The particle editor's property panels are compiled into `bin/wallpaperui.exe` (Qt).
- Its strings for the particle panels form one contiguous block, dumped with file offsets in `wallpaperui_particle_strings.tsv` (0xAD9000â€“0xADC000, 380 strings). Component names start around 0xAD9A38 (spritetrail) and run to 0xADB298 (collisionplane).
- The block contains, in order:
  - component ids (`sphererandom`, `sizerandom`, â€¦);
  - field labels (`ui_editor_properties_distance_max`, â€¦);
  - field keys (`minlength`, `animationmode`, â€¦);
  - **visibility conditions written as JS expressions**, e.g. `checkBit(findProperty('flags').value, 4)`, `checkFlags(4)`, `pList[6].value==='sequence'`, `findProperty('uvscrolling').value`.
- The numeric slider ranges, steps and add-defaults are not in this string block. They are presumably immediates or float tables in the code that builds each panel, reachable from references to these strings. Resolving them needs disassembly, or the editor itself (below).

## `particle_fields_observed.json` (from `build_inventory.py`)
- **Sources:** 410 particle JSONs, namely every `particles/*.json` under `wallpaper_engine/assets` (presets, component previews, templates) plus every `particles/*.json` inside the user's downloaded Workshop `scene.pkg` files.
- **Coverage:** 45 components plus `_system`, `controlpoint` and `children`.
- **Per field:** the JSON types seen (int, float, vecN, bool, string, user/script-bound object), occurrence count, observed min and max, and up to 25 distinct values.
- WE writes scenes with "default removal rules" (changelog REV 4366). A field absent from a component therefore means it is at its runtime default, which the binary already gives you.
- **Observed ranges are not slider limits.** They are the values authors actually used, and they are often a useful sanity bound.
- `assets/particles/example*.json` are the editor's creation templates (Basic = `example.json`).

## Still open
The following can't be resolved from files alone:
- slider min, max and step, and whether typing past the slider is clamped;
- add-defaults (what the editor writes when you ADD a component);
- combo option lists for particle fields (e.g. `collisionbehavior`, `audioprocessingmode`, `operation`, `transformfunction`, `limitbehavior`, sprite `orientation`, `animationmode`).

Two ways to close these:
1. **Binary:** follow references to each label in `wallpaperui_particle_strings.tsv` (offsets given) to the panel-building code and read the range and default immediates.
2. **Editor via UI Automation:** a PowerShell script drives the particle editor. It adds each component to a fresh system, reads each slider's Minimum, Maximum and SmallChange through the Windows UIA RangeValue pattern, saves, and diffs scene.json to get the add-defaults. This needs the editor open on the user's screen, and the user's go-ahead.

## Update: editor-observed schema, `particle_fields.json` (UI Automation)
- **Method:**
  - The WE editor's panels are an embedded Chromium page. Windows UI Automation exposes its accessibility tree, and no debug port was needed.
  - `harvest2.ps1` works on a Basic particle system. For each item in each category's **+** dialog it: adds the item (the category is empty, or the new item is the last one of that name), selects it, reads the panel with `Read-Panel`, then removes it with its own **x**.
  - `general_panels.json` covers System, Material, Viewport and a control point.
  - Nothing was saved. The user's project was left as it was.
- **Coverage:** 4 renderers, 3 emitters, 16 initializers and 24 operators, which is every entry in the add dialogs, plus System and Material.
- **The result:** 344 fields, each with its label, type and `add_default` (the value shown right after ADD). There are 32 combos with complete option lists.
- **Ranges:**
  - Only 8 fields have a slider: rope and ropetrail subdivision 0–16, uvscale 0.1–3, ropetrail segments 2–16, hsvcolorrandom hue steps 1–30, colorlist colors 1–10, and material overbright 0–5. These have `slider_min` and `slider_max`.
  - **Every other numeric field is a number box without a range.** UIA min and max are both 0, so the editor does not limit or clamp them.
  - The step is not exposed.
- **Id mapping:** editor display names map to component ids in `build_schema.py`. Note that the editor's "Vortex" = `vortex_v2`, "Control point force" = `controlpointattract` and "Collision rectangle" = `collisionquad`.
- **X/Y/Z:** vector sub-fields keep the labels X, Y and Z, in panel order. `json_fields_seen` lists the matching JSON keys for that component.
- **Still open:**
  - checkbox fields (e.g. Worldspace, the disable-override flags, emitter flags). Chromium does not expose them as CheckBox, so they are not in the table; the `flags` bits are listed in the wallpaperui string conditions.
  - the step size;
  - labels of vector fields, beyond X/Y/Z order;
  - the older `vortex` operator. The dialog only offers "Vortex" (v2).
