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
| Particle editor: emitters, initializers, operators, renderers, children | Raw particle JSON | — | Done (`Particles/`, below): systems added from WE's presets or blank, moved, duplicated, deleted; WE's panel from its schema; control points on the canvas; live rebuild of the edited system |
| SceneScript: per-property scripts, code editor | — (runs scripts) | Driven fields edit their start value; scripts keep running | **P6 (done):** attach/edit/remove per field and object scripts, code editor (highlighting, line numbers, find, API autocomplete, templates), syntax and runtime errors, console, Apply |
| User properties: define, bind, conditions | Values only (Details panel) | Values (the Details panel's own view), undoable; bound fields named | **P6 (done):** add/edit/remove/reorder/rename every type, conditions, Bind to User Property…, live preview |
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
  preview and commit once on release. The desktop runs in Open Wallpaper Engine's process, the
  canvas in the editor's: `WallpaperEditorChangeSync` carries the change across (see Architecture).
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

## P6: scripting and user properties

- **Kept in the overlay** (`SceneEditOverlay.authoring`, `SceneAuthoring`): per object and field path
  (`origin`, `text`, `effects.1.visible`), a driver edit (`SceneFieldDriverEdit`: the script and its
  `scriptproperties`, the user binding, or their removal), applied to scene.json before the value edits so
  an edited value becomes the driver's start `value`; and the edited `general.properties` list
  (`UserPropertyDraft`), which Save as Local Wallpaper writes into project.json (unknown keys kept).
  The properties don't change the scene digest, so editing them doesn't reload the wallpaper.
- **Apply** stores the script; the wallpaper reloads with it through the overlay's coalesced reload.
  The runtime has no in-place swap of one script (a site's id is free again only after its
  `destroy()` ran in a later frame), so a reload is the faithful path.
- **Autocomplete** reads `SceneScriptTypings` (declarations written from WE's documented API and the
  repository's member list of lib.sceneScript.d.ts, `Tests/Fixtures/SceneScript/object-model-members.json`)
  and resolves the expression before a `.` through globals, imports, locals, calls and indexing.
- **Errors**: JavaScriptCore checks the syntax before Apply (module statements blanked so lines
  stay); the runtime's console lines and errors reach the editor through `SceneScriptConsoleTap`.
- **Conditions**: the preview evaluates the subset the app's sidebar does
  (`UserPropertyConditionExpression`); a single comparison edits as a rule.

## Architecture

- `Packages/OWEEditor`: **OWESceneEditing** (Foundation: overlay, outline, gizmo and viewport math,
  `SceneEditSession` with undo, `LocalWallpaperWriter`); **OWEInspectorKit** (SwiftUI controls shared
  with the Scene Inspector: `NumericSliderInput`, `InfoTip`, `InspectorOptionPicker`);
  **OWEEditor** (the window's views, its own string catalog). Package tests run with `swift test`
  (CI job `packages`).
- **Particles** (`OWESceneEditing/Particles`, `OWEEditor/Particles`): WE's particle editor schema
  (docs/we-particle-editor-schema.json, bundled) read in panel order into components and fields
  (control per type, ranges, add values for 2D and 3D, conditions); `ParticleDefinition` edits a
  particle JSON (add with WE's values, remove, reorder, flags) and writes it as WE does;
  `ParticleEditingModel` makes every change an undo step of the session. The overlay's
  `particles` holds the documents it wrote and the systems it added or deleted; the loader reads
  the documents in place of the files, and a change of documents alone builds again only the
  systems that read them (`sceneEditParticlesDidChange`, `rebuildObjects`), the rest of the scene
  running on. Save as Local Wallpaper writes the documents into the copy.
- `OpenWallpaperEngine/Editor`: the app side: `WallpaperEditorController` (window, canvas through
  `WallpaperView` on a preview `WallpaperViewModel`, services the module needs), user-property undo,
  scene reading. `Scene/Loading/SceneEditOverlayFiles` stores overlays; `ScenePreparation` applies them.
- **Separate app** (`Editor/Process`, `Editor/Sync`, `EditorHelper/`). The editor is an app of its
  own, `Open Wallpaper Engine.app/Contents/Helpers/Wallpaper Editor.app`: bundle id
  `<app id>.editor`, its own name, Dock tile, menu bar and badged icon (`EditorHelper/Info.plist`,
  `EditorHelper/WallpaperEditor.icns`, `LSUIElement` false). So macOS never takes it for Open
  Wallpaper Engine: the app's Dock tile and opening the app from Finder always mean the app.
  - **How it is built.** The app target's last build phase runs `Scripts/build-editor-helper.sh`,
    which makes the bundle like the Chromium helper apps beside it: the executable is a copy of the
    app's own (one codebase, no second target; the bundle id puts it in editor mode, `AppLaunchMode`),
    the resources are the app's except the large media the editor never shows (read from the app,
    `AppBundleLayout.appBundle`), and Sparkle.framework is the app's, found through a second rpath
    the app links with (`@executable_path/../../../../Frameworks`). It is signed with the app's
    identity, hardened runtime and entitlements before Xcode seals the app, so library validation
    holds (one team) and the release's Developer ID export, notarization and checks cover it
    (`release.yml`).
  - **Its process.** `AppLaunchPlan` gives it `WallpaperEditorAppDelegate`: none of the main app's
    services start (no desktop wallpapers, menu bar item, screen saver, lock-screen picture,
    Workshop sync, updater, crash watcher or safe restart) and `AppDelegate` is never made; the canvas
    gets its own settings and SceneScript services (`SceneWallpaperHost`). It keeps the app's state:
    `AppStorageLocation` maps its bundle id to the app's (same defaults, folders, keychain and
    isolation), and the app passes its language (`-AppleLanguages`). It has a menu of its own
    (`WallpaperEditorMenu`) and quits with its last window; quitting either app leaves the other
    running, and neither's crash reaches the other (the crash watcher and safe restart are the app's).
  - **Opening.** Edit Wallpaper / ⌥⌘E (`WallpaperEditorLauncher`) opens the editor's app through
    LaunchServices with `--wallpaper-editor <folder>` (not a child process), isolated as the app is,
    or, when one runs (`AppProcessList`), asks it to open the wallpaper (`WallpaperEditorRequests`):
    one editor process for every wallpaper. The messages go through the session's distributed
    notification centre (`AppProcessChannel`): a name and the wallpaper's folder, never data.
  - **Live sync** (`WallpaperEditorChangeSync`). The editor saves overlays as before and names the
    wallpaper in a message; the app reads the overlay and posts its own
    `sceneEditOverlayDidChange` / `sceneEditParticlesDidChange`, so its instances draw or reload
    exactly as in one process. A gizmo drag goes as `<identity>.preview.json` beside the overlay
    (at most 30 a second), a particle restart as `<identity>.restart.json`. The app also watches the
    overlay folder, so a missed message still arrives. User-property saves go both ways, and Save as
    Local Wallpaper refreshes the app's library.
  - Development: `--wallpaper-editor <folder>` also runs the editor from the app's own executable,
    under the app's bundle id (one Dock identity with the app).
- **Timeline (P4)**, in `Timeline` folders of each target. `OWESceneEditing/Timeline`: `TimelineClip`
  (WE's `animation` block read with WE's rules and written back in its format; the overlay's
  `timelines` store clips in that same JSON), `TimelineCurve` (the player's float32 sampler, held
  to the same bits by `EditorTimelineTests`), keyframe, ease and Bézier-handle editing in WE's
  back/front model, and `SceneTimelineEditor` (playhead, playback, selection, clipboard, undo, and
  animated fields keyed at the playhead through `SceneEditSession.animatedFields`).
  `OWEEditor/Timeline`: the dock under the canvas (ruler, keyframe lanes, curve editor, clip
  options), the inspector's keyframe buttons, its own catalog `Timeline.xcstrings`.
  `OpenWallpaperEngine/Editor/Timeline`: while the timeline is open the canvas's scene clock is
  held and every timeline stands at the playhead (`SceneRendererAnimations.scrubTime`).

## Puppet Warp (P5, puppets)

An image layer's inspector has a **Puppet Warp** section: Create Puppet… (an image without a
rig) or Edit Puppet… (its rig, or the editor's edit of it). The puppet editor opens over the
window with five tools, every finished edit one undo step in the window's session:

| Tool | Does |
|---|---|
| Mesh | Generate from alpha (outline traced, simplified and spaced, the inside on a staggered grid, Delaunay, triangles outside the shape dropped; point spacing, edge padding, alpha threshold); select, move, add and delete vertices |
| Skeleton | Add bones by dragging (under the selected bone), move joints (Option leaves the children), turn by the end handle (Shift: 15°), hierarchy, names, parents |
| Weights | Automatic weights by heat diffusion (Baran–Popović bone heat over the mesh's cotangent Laplacian) or distance; a brush per bone (add, subtract, smooth, replace; size, strength) over a heat map; at most four bones a vertex, summing to 1 |
| Animate | Clips (name, fps, length, loop/mirror/single), keys set by posing at a frame, onion skin, the image's animation layers (blend, rate, additive, blend in/out, blend time) previewed as the player evaluates them, root-motion flags and the clip record as WE's model editor writes them |
| Physics | Each bone's physics constraint as WE's Puppet Warp editor offers it (spring or rigid, rotation, position, gravity, limits, tip), stepped live with the player's bone physics; drag to shake |

- **Model:** `OWESceneEditing/Puppets` (Foundation): `PuppetDocument`, `PuppetMDLWriter` (`MDLV0023`,
  `MDLS0004`, `MDLA0006`; the bone properties' compiled keys, docs/models-plan.md §2.14),
  `PuppetMDLReader` (every version the runtime reads; attachments, reference pose, blend shapes and
  per-bone blocks kept while still valid), mesh generation, weights, pose, layers and physics ports
  of the player's, a CPU rasterizer for the preview. Views: `OWEEditor/Puppets`, their text in
  `Resources/Puppets.xcstrings`.
- **Stored** in the overlay (`SceneEditOverlay.puppets`, by layer); they don't change the running
  scene (left out of the digest, so no reload). **Save as Local Wallpaper** writes each as a new
  `.mdl` and model JSON (`<model>_puppet_<id>`) and points the layer at it with its
  `animationlayers` (`PuppetSceneBake`).
- **Tests:** the package's `Puppets` tests (mesh from a synthetic shape, normalised weights, the
  writer–reader round trip, a two-bone bend rendered, the fixtures' rigs saved back) and the app's
  `EditorPuppetMDLTests` (the app's `MDLReader` reads the writer's bytes field for field; the
  preview's layers and physics match `SceneAnimationLayerStack` and `SceneBonePhysics`).
