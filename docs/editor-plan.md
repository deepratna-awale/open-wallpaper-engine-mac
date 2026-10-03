# Wallpaper Editor plan

A Wallpaper Editor for scene wallpapers, in its own window, opened from a wallpaper's Details
(**Edit Wallpaper**, ⌥⌘E, Window › Wallpaper Editor). It is a separate module (`Packages/OWEEditor`)
and does **not** replace the Scene Inspector, which stays as it is; the two share controls through
`OWEInspectorKit`. Publishing to the Workshop is out of scope.

## 1. Gap: Wallpaper Engine's editor vs ours

Columns: WE's editor ([docs.wallpaperengine.io](https://docs.wallpaperengine.io)); the Scene
Inspector today; the editor after phase 1 (this PR) and the phase that closes the rest (§4).

| WE editor | Scene Inspector today | Editor, phase 1 | Rest |
|---|---|---|---|
| Layer list: hierarchy, visibility, lock, select on canvas | Flat object list, visibility switch, versions | Hierarchy (parents), visibility, lock, select on canvas, hover outline | Reorder, duplicate, delete, group: P2 |
| Transform gizmo (move, scale, rotate), snapping | Arrow nudges, size slider, align buttons | Move/scale/rotate gizmo for image and text layers, arrow nudges, Shift for free scale / 15° steps | Snapping, guides, align, multi-select: P2 |
| Layer properties (alpha, colour, blend, size, alignment, …) | Raw object JSON, blend mode, material blending | Position, scale, rotation, opacity, colour, blend mode; user-bound fields show their property | Size, alignment, text content and font, perspective, parallax depth: P2 |
| Effects: add, remove, reorder, edit, paint masks | Edit authored effects (sliders, combos, colours, music sync), toggle, mask preview | Effect list with on/off toggles and help | Parameters (Inspector's controls), reorder, add/remove from WE's catalog: P2; mask painting: P3 |
| Add layers (image, text, composition, fullscreen, particles, sound, model, light), asset browser and import | — | — | P3 |
| Timeline: keyframe animation of properties | — (plays authored timelines) | — | P4 |
| Puppet warp: mesh, bones, animations | — (plays authored rigs) | — | P5 (view/pose first, authoring later) |
| Particle editor: emitters, initializers, operators, renderers, children | Raw particle JSON | — | P5 |
| SceneScript: per-property scripts, code editor | — (runs scripts) | Driven fields edit their start value; scripts keep running | Script editor: P6 |
| User properties: define, bind, conditions | Values only (Details panel) | Values (the Details panel's own view), undoable; bound fields named | Authoring and binding: P6 |
| Scene settings: camera, bloom, clear colour, lights, 3D | Effects of `general` via properties | Scene size, layer count | P3 (2D settings), P7 (3D camera, lights, models) |
| Custom shaders/effects | — | — | P7 |
| Workshop publishing | — | — | Out of scope |

## 2. UX choices

Wallpaper tweakers come first (change what's there, see it live, undo anything); authoring
appears progressively behind the same layout rather than in a different mode.

| Choice | From | Why |
|---|---|---|
| **Canvas-first, three panes**: layers left, live canvas centre, contextual inspector right (`NavigationSplitView` + `.inspector`) | Pixelmator Pro, Figma, Rive, Spline, Motion | The wallpaper is the document; macOS's own split view and inspector give resizing, collapsing and Liquid Glass sidebars for free (HIG: sidebars and inspectors). |
| **The canvas is the real renderer** (the wallpaper's own `SceneWallpaperInstance` in a preview model) | WE's editor, Unity's Scene view | What you edit is what runs; no second, approximate renderer to drift. |
| **Topmost layer first, parents as disclosure groups**, eye and lock per row (lock only shown on hover or when on) | Photoshop, Pixelmator Pro, Figma, Blender's outliner | The convention every tweaker already knows; hidden controls keep rows calm. |
| **Contextual inspector**: the selected layer's Transform, Appearance, Effects and Details; nothing selected shows the scene and its user properties | Figma, Pixelmator Pro, Unity's Inspector | One place to look; progressive disclosure (Details folded, advanced authoring later in more sections, not more windows). |
| **Direct manipulation gizmo**: drag body to move, corners to scale (proportional; Shift free), top handle to rotate (Shift: 15°), arrow keys nudge (10, Shift 50, Control 1 — the Inspector's steps) | Photoshop free transform, Figma, Unity/Blender gizmos | Fast for the common edit; modifiers match the Inspector so habits carry over. |
| **Navigation**: scroll or Space-drag pans, pinch or ⌘-scroll zooms about the pointer, ⌘0 fit, ⌘= / ⌘− steps, a glass zoom capsule | Pixelmator Pro, Preview, Figma | Trackpad-native; zoom keeps what's under the pointer still. |
| **Every change is one undo step** in the window's `UndoManager` (⌘Z / ⇧⌘Z, toolbar), slider drags and gizmo drags coalesced, menu titles name the action | Photoshop History, Final Cut | Fearless tweaking; Revert itself is undoable. |
| **Bound values say so** instead of offering a control ("Set by the user property “x”") | WE's editor | Editing a bound value would be overridden at runtime; saying why is clearer than a dead control. |
| **Non-destructive with an explicit way out**: Revert, Save as Local Wallpaper… | Final Cut/Motion (library vs. project), Lightroom | Workshop files stay pristine; a copy is the explicit, shareable artefact. |
| Liquid Glass chrome only (toolbar, zoom capsule, banners); content stays opaque | HIG (macOS 26) | Glass for controls, not for the content being edited. |

### Wireframes

```
┌ Rainy City ─ Wallpaper Editor ─────────────────────────────────────────────────────────────┐
│ [↶][↷]                                         [⟲ Revert] [⤓ Save as Local Wallpaper…] [▤] │
├───────────────┬───────────────────────────────────────────────────────┬────────────────────┤
│ LAYERS        │                                                       │ Logo        Image  │
│ ▾ 📁 City   👁 │   ┌───────────────────────────────────────────────┐   │ ─ Transform ─────  │
│    🖼 Rain • 👁 │   │                  ○  (rotate)                  │   │ Position  [1700][900]
│    🅣 Clock 🔒👁│   │            □───────────────□                  │   │ Scale  ──●── 1.00× │
│ ✨ Sparks    👁 │   │            │   Logo  ┼     │   live scene     │   │ ☑ Keep Proportions │
│ 🖼 Logo      👁 │   │            □───────────────□                  │   │ Rotation ─●─ 0.0°  │
│ 🖼 Background👁 │   │                                               │   │ ─ Appearance ────  │
│               │   └───────────────────────────────────────────────┘   │ Opacity ──●── 100% │
│               │              ( − )  [ 52 % ▾ ]  ( + )                 │ Color [■]  Blend ▾ │
│               │                                                       │ ─ Effects ───────  │
│               │                                                       │ ☑ Waterripple ⓘ    │
│               │                                                       │ ▸ Details          │
└───────────────┴───────────────────────────────────────────────────────┴────────────────────┘
```

Nothing selected: the inspector shows Scene (size, layers, edited layers) and the wallpaper's User
Properties. Later phases add a timeline under the canvas (P4) and an asset strip in the sidebar (P3):

```
├───────────────┬──────────────────── canvas ───────────────────────────┬──── inspector ─────┤
│ Layers│Assets │                                                       │                    │
├───────────────┴───────────────────────────────────────────────────────┴────────────────────┤
│ Timeline  ▶ 00:03.2   Logo.origin ◆─────────◆──────◆    Logo.alpha ◆────────◆              │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 3. Edits stay non-destructive

- **The overlay** (`SceneEditOverlay`, JSON, versioned) holds per-object field changes (`origin`,
  `scale`, `angles`, `alpha`, `color`, `colorBlendMode`, `visible`, …), per-effect `visible` and
  first-pass `constants`, and editor-only locks. Objects are keyed by `id` (index without one),
  effects by index, as the Inspector keys its edits.
- **Applied at load, everywhere** the wallpaper runs: `ScenePreparation.resolvedScene` applies it to
  scene.json before the Inspector's own edits (those stay the user's on top). A driven field
  (`script`/`animation`) gets a new start `value` and keeps its driver; a user-bound field isn't
  edited. The scene cache key covers the overlay's digest.
- **Live**: saving posts `sceneEditOverlayDidChange`; every running instance of the wallpaper (the
  canvas and the desktop) reloads through its existing coalesced reload path. Gizmo drags draw a
  preview and commit once on release.
- **Stored** per wallpaper in `<Application Support>/Open Wallpaper Engine/editor/<identity>.json`
  (the settings identity: Workshop id, else a project hash), never in the wallpaper's folder or the
  property store. An empty overlay removes its file.
- **Structure** (version 2 of the file, written only when used, so an older app still reads a
  version-1 overlay): layers added (`added`, their scene.json objects under new ids), deleted
  (`removed`) and reordered (`order`, every id in draw order); per object, effects added
  (`addedEffects`, keyed `+1`, `+2`…) and their order (`effectOrder`, which also removes); per
  effect, `combos`, `textures` (masks) and `bindings` (a constant following a user property)
  beside `visible` and `constants`. Effect edits are keyed by the effect, not its place, so they
  follow it when it moves. Objects without an `id` get their index as one once the structure changes.
- **Files the editor adds** (imported images, sounds and fonts, painted masks) live beside the
  overlay in `<identity>.assets` under the scene's own paths (`materials/editor/…`,
  `models/editor/…`, `sounds/editor/…`, `fonts/editor/…`, `materials/masks/editor_…`), named by
  their content's hash; the loader finds them after the wallpaper's own files. Images other than PNG
  and JPEG are converted to PNG; an image gets WE's `genericimage2` material and model. Adding a
  built-in effect copies its `dependencies` (materials, shaders, textures) there too, as WE's editor
  copies them into the project: WE reads them at the project root, not in `assets/effects/<name>/`.
- **Live channel**: a change of a layer's `origin`, `scale`, `angles`, `alpha` or `color`, or of an
  effect's `visible` or a literal constant, is drawn per frame without reading the scene again
  (`SceneEditLiveValues` against the overlay the scene was read with; the renderer's
  `SceneEditorLive`). Gizmo drags are sent live while they last and saved once on release.
  Everything else (structure, combos, textures, bindings, text, a field a script drives) reloads.
- **Revert** drops the scene edits (undoable). **Save as Local Wallpaper…** copies the folder into
  the library (hidden files and symbolic links left behind, a `.pkg` written out as loose files),
  writes the merged scene.json and a project.json without the Workshop id, so the copy is a local
  wallpaper with its own identity.

## 4. Phases

Each phase ships on its own; effort is focused engineering time.

| Phase | Delivers | Effort |
|---|---|---|
| **P1 Foundation** (this PR) | `OWEEditor` package (edit model, shared kit, views), the window, live canvas with fit/zoom/pan, hierarchy with visibility and lock, contextual inspector (transform, opacity, colour, blend, effect toggles, user properties), canvas selection and gizmo for image/text layers, undo/redo, overlay persistence and live reload, Revert, Save as Local Wallpaper, 15 languages, tests | 2–3 weeks |
| **P2 Tweaking complete** (done, except multi-select and music sync of effect parameters) | Effect parameters, combos, colours and music sync through the Inspector's effect controls (moved to `OWEInspectorKit`); live transform channel (the renderer's `object` binding class instead of a reload); snapping, guides, align, multi-select; text content and font; layer reorder, duplicate, delete (structural overlay ops) | 3–4 weeks |
| **P3 Adding things** (done, except scene settings) | Add image/text/fullscreen/composition/sound layers and WE's catalog effects; asset browser and import into an editor project folder; scene settings (clear colour, bloom); mask painting | 4–6 weeks |
| **P4 Timeline** | Keyframe tracks for WE's `animation` values, curves, scrubbing the live canvas | 4–6 weeks |
| **P5 Particles and puppets** | Particle editor (emitters, initializers, operators, renderers, children, control points); puppet warp view and pose, then authoring | 6–8 weeks |
| **P6 Logic** | SceneScript editor (JavaScriptCore diagnostics), user property authoring, binding and conditions in project.json | 4 weeks |
| **P7 3D and shaders** | Camera, lights and models with 3D gizmos; custom effect/shader editing on the existing translator | 6–8 weeks |

## Architecture

- `Packages/OWEEditor`: **OWESceneEditing** (Foundation: overlay, outline, gizmo and viewport math,
  `SceneEditSession` with undo, `LocalWallpaperWriter`); **OWEInspectorKit** (SwiftUI controls shared
  with the Scene Inspector: `NumericSliderInput`, `InfoTip`, `InspectorOptionPicker`);
  **OWEEditor** (the window's views, its own string catalog). Package tests run with `swift test`
  (CI job `packages`).
- `OpenWallpaperEngine/Editor`: the app side: `WallpaperEditorController` (window, canvas through
  `WallpaperView` on a preview `WallpaperViewModel`, services the module needs), user-property undo,
  scene reading. `Scene/Loading/SceneEditOverlayFiles` stores overlays; `ScenePreparation` applies them.
