# WE install layout: WE 2.8.0.42, Windows Steam install

`gather.py` produces everything below. Paths are relative to `steamapps/common/wallpaper_engine/`.

## A1: install tree
- **Listing:** `tree_2_levels.txt` has the top two levels. Crash dumps and logs are left out.
- **Top-level folders:** `assets/`, `bin/`, `config_backups/`, `distribution/`, `dlc/`, `locale/`, `projects/`.
- **Top-level files:** `config.json`, `launcher.exe`, `installer.exe`, `ChromaAppInfo.xml`, `wallpaper32/64.exe`.
- **`assets/`:** effects, fonts, materials, models, particles, presets, scenes, scripts, shaders, zcompat.
- **`projects/defaultprojects/`:** exists, with 19 folders. `defaultprojects.json` has `type`, `file` and `contentrating` for each.
  - `type` is **absent** in `audiophile` (file audiophile.json), `sheep` (sheep.exe) and `techno` (techno.json).
  - `web`: corsair_collection, corsair_o_tron.
  - Scenes whose file isn't `scene.json`: fantasticcar.json, ricepod.json.
  - `contentrating` is present only in `dino_run` and `neon_sunset` ("Everyone"), and absent everywhere else.
- **`projects/myprojects/`:** the user's editor projects. Local test projects live here too.

## A2: locale
- `locale/ui_*.json` and `locale/core_*.json` sit at the install root, next to `assets/`: `wallpaper_engine/locale/ui_en-us.json`.
- There are 36 languages, for example ar-sa … zh-cht.

## A3: config.json
**Path and backups**
- The file is `wallpaper_engine/config.json`, at the install root.
- WE keeps daily copies in `config_backups/config_YYYY-MM-DD.json`.

**Shape** (`config_shape_redacted.json`; values replaced by types, usernames and paths redacted)
- The top level has `"?installdirectory"` and one object per **Windows username**: `{ general, version, wproperties }`.
- `general` contains `browser`, `editor`, `user` (the settings: fps, playback*, `preset`, `monitormap`…), `wallpaperconfig`, `wallpaperconfigrecent` and `wallpaperconfigscreensaver`.

**Current selection** is `general.wallpaperconfig`:
```
{ "layout": <number>,
  "profile": { "splits": {} },
  "selectedwallpapers": { "Monitor1": { "file": "<abs path to project.json>" } } }
```
- **Playlist storage is unverified.** I have not confirmed where a playlist is stored (see below).
- `wallpaperconfigrecent[]` entries are `{ config: <same shape>, playlist: <bool>, title }`.
- **This machine has no saved playlists.** Every recent entry has `playlist: false`, and there is no `playlists` array. So I can't show a real playlist object. If needed, I can create a test playlist in the UI and capture its shape; tell me.

**Per-wallpaper user properties** are `wproperties`:
```
"wproperties": { "<abs path to project.json>": { "Monitor0": { "<propertyKey>": <value>, … }, "Monitor1": { … } } }
```
- They are keyed by the project.json path, then by monitor, then by the user-property key.
- Values are raw: numbers, bools, strings, colors as "r g b" strings.

**Presets**
- `general.user.preset` is a string: the selected UI/performance preset.
- Workshop "Preset" items are separate workshop entries, category tag `Preset`, and are not stored in config.json.

## A4: appworkshop_431960.acf
- `appworkshop_431960_redacted.acf`: the real file, trimmed to 3 items, with `subscribedby` (a SteamID) redacted.
- **Blocks:**
  - `WorkshopItemsInstalled` has `{ size, timeupdated, manifest }` per item.
  - `WorkshopItemDetails` has `{ manifest, timeupdated, timetouched, subscribedby, latest_timeupdated, latest_manifest }`.
- **Content:** item folders are in `steamapps/workshop/content/431960/<id>/`.

## A5: EULA / terms
- **No end-user EULA.** WE 2.8 shows no end-user EULA dialog on first run or in-app. The Steam store and Steam's own terms cover that.
- **Licence files:** third-party licences only: `bin/licenses/licenses_main.html`, `licenses_editor_extensions.html`, `freeimage-license.txt`, and the font licences in `assets/fonts/`.
- **Workshop agreement:** the only agreement text is in the **editor's publish flow**. `ui_en-us.json` has keys `ui_editor_workshop_eula_*` ("Workshop EULA Changed … accept the latest Steam Workshop Subscriber Agreement") and `ui_editor_publish_modal_publish_prompt_agreement`. These link out to Steam's Workshop agreement.
