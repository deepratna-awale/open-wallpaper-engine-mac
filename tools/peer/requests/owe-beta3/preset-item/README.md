# Workshop preset item: 3332091404 "Pixels - Green Forest" (preset of 3122339805 "Pixels")

## How it was installed
- **Subscribe:** clicked through WE 2.8.42's own Workshop tab. The item is rated Everyone, with the tag Category: Preset.
- **Base item:** Steam **downloaded the base item 3122339805 automatically as a separate Workshop item**, into its own folder `workshop/content/431960/3122339805/` (project.json, scene.pkg, shaders).
- **Visibility:** the Steam page lists the base under "Required items". The base wasn't visible on the first page of WE's Installed tab, but it is on disk.

## Preset folder (`preset_3332091404/`, copied as installed)
- **Files:** `project.json`, `preview.jpg`, and `files/` with 3 user images the preset references.
- **`project.json` has no `file` and no `type`.** It points to the base with **`"dependency": "3122339805"`** (a string Workshop ID).
- **`"preset"`** is a **flat object `{propertyKey: value}`**. Values are raw:
  - bools, e.g. `"_24hourtime": true`;
  - numbers, e.g. `"rate": 100`;
  - strings, with colours as `"r g b"` floats;
  - asset paths relative to the preset folder, e.g. `"customimageleft": "files/7b1b….gif"`;
  - `null` for unset values (`"_d0": null`).
- **Other keys:** `contentrating`, `ratingsex`, `ratingviolence`, `preview`, `tags`, `title`, `visibility`, `snapshotformat`, `snapshotoverlay`.
- **Keys:** they match the base's `general.properties` keys. Values replace each property's `value`. The base keeps the full `{index, order, text, type, value}` descriptors.

## Base (`base_3122339805/project.json`)
- `type: scene` and `file: scene.json` (inside scene.pkg).
- `general.properties` holds descriptors such as `_24hourtime: {index, order, text, type: bool, value: true}`.

## How WE shows it
- **`we_workshop_panel.png`:** the Workshop tab detail panel. It shows "Scene 1 MB" and tags; there is **no preset label**.
- **`we_installed_tab.png`:** the Installed tab, where the preset appears as **a normal tile with its own preview and title, without a badge**. The side panel lists the base scene's properties, with the preset's values applied.
