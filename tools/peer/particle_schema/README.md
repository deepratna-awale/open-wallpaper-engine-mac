# Particle editor schema: what the files give, and what is still open

## Where the schema lives
- There is no particle schema in data files. `ui/dist/scripts/*.js` does not mention any particle component.
- The particle editor's property panels are compiled into `bin/wallpaperui.exe` (Qt).
- Its strings for the particle panels form one contiguous block, dumped with file offsets in `wallpaperui_particle_strings.tsv` (0xAD9000–0xADC000, 380 strings). Component names start around 0xAD9A38 (spritetrail) and run to 0xADB298 (collisionplane).
- The block contains, in order:
  - component ids (`sphererandom`, `sizerandom`, …);
  - field labels (`ui_editor_properties_distance_max`, …);
  - field keys (`minlength`, `animationmode`, …);
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
