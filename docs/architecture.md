# Architecture

Open Wallpaper Engine for macOS plays Wallpaper Engine (WE) wallpapers: **scene**, **video** and **web**. The `application` type is out of scope. The goal is to run *any* WE wallpaper, including arbitrary Workshop scenes with custom effects, shaders and SceneScripts. So the scene engine implements WE's actual formats and semantics, not per-wallpaper approximations.

This document describes the target structure and the rules for what goes where. [`docs/reorg-plan.md`](reorg-plan.md) lists the steps from today's layout to this one. [`docs/progress-snapshot.md`](progress-snapshot.md) records how complete each feature is. [`docs/optimizations.md`](optimizations.md) records what was tried to make wallpapers cheaper, what shipped and what was rejected.

## Big picture

```
┌──────────────────────── App shell (SwiftUI/AppKit) ────────────────────────┐
│ App/  Library/  Workshop/  Settings/  UI/            (views + view models) │
└───────────────┬───────────────────────────────┬────────────────────────────┘
                │ WEWallpaper                    │
      ┌─────────▼─────────┐  ┌─────────────┐  ┌──▼──────────┐
      │ Scene/  (engine)  │  │ Video/      │  │ Web/        │
      │  Format  → Values │  │ AVPlayer +  │  │ WKWebView + │
      │  Shaders → Render │  │ music sync  │  │ WE web API  │
      │  Scripting, Audio │  └──────┬──────┘  └─────────────┘
      └─────────┬─────────┘         │
                └──────────┬────────┘
                    ┌──────▼──────┐
                    │ Audio/      │  system capture (process tap or SCK), item taps
                    └─────────────┘
Core/  logging, diagnostics, settings store, asset locations: usable by everything above
```

**Dependency direction:** arrows only point down. Code in `Scene/` must never import or reference anything in `UI/`, `Library/`, `Settings/` views or `AppDelegate`. Code in `Core/` depends on nothing else in the app.

## Targets

- **`OpenWallpaperEngine.framework`** (target OpenWallpaperEngineFramework, module `OpenWallpaperEngine`): all of the app's code, the folders below, with the packages it uses (ShaderToolchain, Sparkle, OWEEditor). It is embedded once, in the app's `Contents/Frameworks`. The code's own resources are in the framework's bundle and read through `AppBundleLayout.framework`: the Metal library (`SceneMetalLibrary`), SceneScript's JavaScript, the now-playing adapter, the placeholder media and the legal documents. Objective-C goes through the framework's umbrella header (`OpenWallpaperEngine.h`), not a bridging header.
- **Open Wallpaper Engine.app** (target OpenWallpaperEngine) and **Wallpaper Editor.app** (target WallpaperEditor, embedded in `Contents/Helpers`): small executables, the same `OpenWallpaperEngineApp/main.swift`, which calls `AppMain.run()`; the bundle id says which app it is. Each app's bundle (`Bundle.main`) keeps what belongs to the app: its Info.plist, icon, asset catalog and `Localizable.xcstrings`, which SwiftUI, AppKit and `String(localized:)` look up there. The editor finds the framework through its rpath, `@executable_path/../../../../Frameworks`.
- **Tests** (`OpenWallpaperEngineTests`) link the framework (`@testable import OpenWallpaperEngine`) and run hosted in the app.

## Modules

These are folders in the framework target today. The scene engine (`Scene/`, `Audio/`, `Core/`) is meant to become a local Swift package (`Packages/WEScene`) during Phase 2, so it can be unit-tested and run headless. Keeping the dependency rules now is what makes that extraction a move rather than a rewrite.

### `Core/`: shared infrastructure

- **Logging and diagnostics:** `OWELog`, signposts and frame metrics.
- **Settings:** the global settings model and store.
- The **WE assets location**.
- The **Objective-C exception catcher**.
- It must not reference UI, view models or `AppDelegate`.

### `Scene/`: the WE scene engine

| Area | Responsibility | Examples |
|---|---|---|
| `Scene/Format/` | Decode WE files into plain Swift models. It does no rendering and has no side effects. | `scene.json`, `project.json` scene properties, `effect.json`, materials, models, particles, `.pkg`, `.tex` |
| `Scene/Values/` | Resolve every dynamic value the same way: literal, `{"user":…}`, `{"user":{"name","condition"}}`, `{"script":…}`, `{"animation":…}`. User bindings live in one table per loaded scene (`Values/Bindings`). | `UserPropertyBindingTable`, `SceneValueSource` |
| `Scene/Shaders/` | GLSL → SPIR-V → MSL translation (in a helper process, `--shader-compile-helper`), reflection, the translation cache and the effect catalog. | `ShaderVariantTranslator`, `HelperShaderCompiler`, `ShaderCompileHelperServer`, `InProcessShaderCompiler`, `SceneDynamicEffectCatalog` |
| `Scene/Rendering/` | Metal: layers, the effect pass graph, render targets, text, particles and the camera. | `SceneMetalRenderer`, `SceneShaders.metal` |
| `Scene/Scripting/` | The SceneScript runtime (JavaScriptCore), one per wallpaper instance on its own thread, and the WE JS API surface as extensions; `Host/` ties a runtime to the renderer (docs/scenescript-plan.md). | `SceneScriptRuntime`, `SceneScriptWallpaper`, `SceneScriptSceneMirror` |
| `Scene/Loading/` | Turns a wallpaper into render content: loads, resolves and builds. | `SceneWallpaperViewModel` (to be split) |
| `Scene/UI/` | Scene-specific SwiftUI: the inspector and user properties. These are the **only** scene files allowed to import SwiftUI views. | `SceneInspectorView`, `SceneUserPropertiesView`, `SceneHelp` |

### `Audio/`

- System audio capture (a Core Audio process tap on macOS 14.2+, ScreenCaptureKit before or as the fallback) with a restart lifecycle.
- Per-player taps (`AudioLevelTap`).
- Spectrum and waveform snapshots.
- One producer, many consumers: scene shaders, SceneScript `registerAudioBuffers`, video music sync.

### `Video/` and `Web/`

- Each holds its player, view, view model and type-specific features: video music sync, and the web wallpaper property/audio bridge.
- **`Web/Chromium/`:** the optional Chromium engine (CEF), installed on demand and pinned by SHA-256. CEF runs only in the `owe-chromium-helper` XPC service (target `OWEChromiumHelper/`), never in the app, and its frames reach the app as IOSurfaces. See [`docs/chromium-engine.md`](chromium-engine.md).
- **Web engine routing:** WebKit by default; Chromium only for a wallpaper that needs it (a Chromium-only API found) while the engine is installed, or when the wallpaper's override says so (`WebEngineRouting`). `WebWallpaperViewModel` drives either engine through `WebWallpaperPage` (a `WKWebView` or a `ChromiumBrowserPage`), so the WE bridge is one implementation. Without Chromium, `ChromiumFeatureAdvisor` points out wallpapers that use Chromium-only APIs (static scan plus WebKit's runtime probe).

### `Library/`, `Workshop/`, `Settings/`, `UI/`, `App/`

- **`Library/`:** app-shell features. It holds the wallpaper library model and the import paths (`WEProject`, `WallpaperDirectory`, zip/pkg import).
  - Installed lists what WE lists (`InstalledLibrary`): items whose project.json `type` is scene, video, web or application. Asset items (`"category": "Asset"`, no `type`) and items downloaded only as another wallpaper's dependency (`WorkshopDependencyIndex`, a hidden file in the library folder) stay on disk, where `WorkshopAssetResolver` finds them, but aren't listed. Downloading such an item yourself makes it yours and lists it.
  - Deleting a wallpaper removes the dependency-only items nothing left in the library references (`WorkshopDependencyCleanup`, logged). WE leaves required items to Steam, where the user can still see and unsubscribe them; here they are hidden, so keeping them would leave them on disk with no way to remove them.
- **`Workshop/`:** steamcmd and the Workshop API. Steam secrets live in the keychain (`Core/Keychain`, `SteamCredentials`): the Web API key and the steamcmd account name. The password and Steam Guard code are piped to steamcmd on stdin and never stored; steamcmd keeps its own login token. The API key goes in the `x-webapi-key` header, never a URL.
  - Every download lands in the Wallpaper Storage folder as `<storage>/<id>` (`WorkshopItemInstaller`): steamcmd's `force_install_dir` is a hidden `.owe-steamcmd` folder inside it, the finished item is renamed into place and the staging folder deleted. A preview the user applies moves from the preview cache into storage the same way (copied into a hidden folder there, then renamed). A storage folder on a disconnected volume fails the download with that reason; nothing falls back to another folder. steamcmd runs through `SteamCmdRunning`, so tests use a fake.
- **`Settings/`:** settings pages.
- **`UI/`:** the main window and shared components.
- **`App/`:** the entry point, `AppDelegate`, windows and menus.
- Each view model lives next to its view.

### `Editor/` and `Packages/OWEEditor`: the Wallpaper Editor

- The editor ([`docs/editor-plan.md`](editor-plan.md)) is a local Swift package with three modules: `OWESceneEditing` (Foundation only: the edit overlay over scene.json, the layer outline, gizmo and canvas math, `SceneEditSession` with undo, Save as Local Wallpaper), `OWEInspectorKit` (controls the Scene Inspector shares with it) and `OWEEditor` (the window's views and their own string catalog). The package depends on nothing in the app; its tests run with `swift test`.
- `Editor/` is the app's side: the window (`WallpaperEditorController`), whose canvas is the wallpaper's own instance in a preview `WallpaperViewModel`, and the services the module asks for (the user properties view, WE's blend modes, effect help, saving a copy).
- The editor is an **app of its own** inside the app, `Contents/Helpers/Wallpaper Editor.app` (bundle id `<app id>.editor`, target WallpaperEditor, a small executable running the app's framework, `Core/AppBundleLayout`), launched with `--wallpaper-editor <folder>` (`App/Launch/AppLaunchMode`, `AppLaunchPlan`); its delegate (`Editor/Process/WallpaperEditorAppDelegate`) starts none of the main app's launch services and never makes `AppDelegate.shared`. The app launches it through LaunchServices, or asks the running one to open a wallpaper, over the session's distributed notifications (`AppProcessChannel`: a name and a folder, no data). What the editor saves reaches the app's instances through `Editor/Sync/WallpaperEditorChangeSync` (messages plus a watcher on the overlay folder), which posts the same in-process notifications as before. See [`docs/editor-plan.md`](editor-plan.md), "Separate process".
- Edits are an overlay per wallpaper (`<supportDirectory>/editor/<identity>.json`, `Scene/Loading/SceneEditOverlayFiles`), never written into the wallpaper, with the files the editor added beside it (`<identity>.assets`, `EditorAssetStore`), which the scene loader reads after the wallpaper's own (`SceneWallpaperViewModel.wallpaperData`). `ScenePreparation` applies the overlay (layers added, deleted and reordered, effects added and reordered, every field and effect value) before the Scene Inspector's edits, and the scene cache key covers it.
- A change of values the renderer takes per frame (a layer's transform, opacity and colour, an effect's visibility and constants) is drawn live: the instance measures the editor's overlay against the one its scene was read with (`SceneEditLiveValues`, `SceneWallpaperInstance+EditorLive`) and the renderer applies the difference (`SceneEditorLive`: transforms like user bindings, effect constants as writes under the scripts'). Anything else reloads every running instance of the wallpaper.
- Scripting and user-property authoring (P6) live in `Scripting/` and `Properties/` subfolders of `OWESceneEditing` (the overlay's `SceneAuthoring`, the SceneScript typings and autocomplete, the syntax check, templates, `UserPropertyDraft` and its conditions) and of `OWEEditor` (the script editor, binding sheet, property editor and preview); the app's `Editor/Scripting/SceneScriptConsoleTap` hands the runtime's console lines and errors to an open editor.
- The particle editor (`Particles/` in both modules) keeps particle definitions and materials it wrote in the overlay; the view model reads them before any file (`setEditorAssets`), and a change of those documents alone rebuilds only the particle objects that read them (`particleObjectIDs(using:)`, `rebuildObjects`) instead of reloading the scene.

### `Resources/`

- `Assets.xcassets`, `Localizable.xcstrings`, media.
- No Wallpaper Engine files ship in the repository or the app. `Core/WallpaperEngineAssets` resolves them at runtime: a WE install the user chose, else the cache in the Wallpaper Storage folder (`<storage>/.owe-assets`, filled by `Workshop/WallpaperEngineAssetsService` from the user's Steam copy through SteamCMD), else none (scenes show that they need them). Tests read them only from `OWE_ASSETS`.

## Scene data flow

1. **Load.** `Scene/Format` decodes `project.json`, `scene.json` (from disk or the `.pkg`, with the Wallpaper Editor's overlay and the Scene Inspector's edits applied, `ScenePreparation`), then models, materials, effects and textures (`.tex`).
2. **Resolve.** `Scene/Values` binds user properties (per wallpaper), scripts and animations to typed values. Nothing downstream reads raw JSON or string-keyed dictionaries.
   - Every `{"user": …}` of scene.json and of every JSON document the build reads (effects, materials, particle systems, models, Workshop dependencies, WE's assets) is recorded in the scene's `UserPropertyBindingTable`, with its path, the typed target it drives and a class: `uniform` (a shader constant, updated in place), `object` (a transform, colour, visibility, particle override or script-read value: the object's state updates) or `structural` (a combo, texture, size or anything unrecognised: the object is rebuilt alone, `SceneObjectReplacement`). The parsers decode the table's resolution of each document, so none can drop a binding.
   - A property change is looked up in the table (`SceneBindingUpdate`). The owners it touches move to a new binding revision (`SceneBindingRevisions`), which every cache of a bound value keys on. Only the app's own keys, scene-wide structure (`general`) and objects the scene's stages hold (lights, sounds, models, cameras) rebuild the content; editing properties ends with one rebuild, the reconcile.
3. **Build.** `Scene/Loading` produces render content: an ordered layer list in authored object order. Each layer carries its full parent transform, its effect pass graph (from `effect.json` passes, `fbos`, `bind`, `target` and combos) and its text, particle and sound state.
4. **Render.** `Scene/Rendering` executes the pass graph each frame through translated WE shaders. Uniforms come from reflection, plus built-ins such as `g_Time`, resolutions, pointer and audio spectrum, plus resolved constants.
5. **Script.** `Scene/Scripting` runs once per frame in one context per wallpaper instance, on its own thread. Layer objects read and write a shared object table; the renderer feeds it each object's drawn values before the frame and draws what scripts wrote after it (`SceneRendererScripts`).

## Wallpaper instances

A wallpaper runs **once**, however many displays show it with the same user properties.

- **The registry.** `WallpaperInstanceRegistry` (`Core/`) holds the running instances, keyed by `WallpaperInstanceKey` (the wallpaper's folder, file and type, and the user-property store it runs with). It belongs to the `WallpaperViewModel` whose displays show them (`sceneInstances`, `videoInstances`), so the Workshop preview window runs its own. Each display holds its instance through a `WallpaperInstanceLease`; the instance stops when no display holds it, one main-queue turn after the last release, so a display that is rebuilt (screens changed) takes hold again first and the wallpaper keeps running. `WallpaperView` keys a display's view by its instance key (`WallpaperViewModel.instanceKeys`), so a display switched to another wallpaper, or to other properties, splits off into that instance.
- **User properties per display.** As in WE, the same wallpaper on two displays has independent user properties (`WallpaperPropertyScope`): each display has its own store (`SceneUserProperties.<identity>.display.<id>`, started from the shared `SceneUserProperties.<identity>`). Settings → General → "Sync properties across displays" (off by default, WE's "Wallpaper per display") makes every display use the shared store. `WallpaperPropertyGroups` regroups the displays when a wallpaper, the setting or saved properties change: displays of a wallpaper whose stores are equal share one instance (the first display's store), a display whose properties differ runs its own. The sidebar and the inspector edit the selected displays' stores (`WallpaperPropertyTargets`); the running store of an instance is `WallpaperPropertyScope.runtimeKey`. AVKit videos have no properties and keep one player per video.
- **Scenes** (and videos on the Metal path): `SceneWallpaperInstance` owns the loader, one `SceneMetalRenderer` (scripts, particles, timelines, effect graph, sound layers) and the observers. Each display is a `SceneWallpaperPresenter` with its own `MTKView`. With one display the renderer draws straight onto it. With several, the display with the highest frame rate drives (`SceneFrameSchedule`; another takes over if it stops drawing): `renderShared` renders the frame once, at the largest scene target any display needs (`SceneViewport`), through the post-process onto a finished frame; every display then `present(in:)`s it with its own size and placement, one copy pass. The cursor is read from the display it is on, through that display's placement.
- **Loading snapshots.** While a scene loads, each display shows a full-resolution picture of the scene's own frame (`ScenePreviewPlaceholder`), crossfaded to the live scene once it draws: the snapshot for the display's pixel size, else the nearest size scaled, else the Workshop preview. `SceneLoadingSnapshotStore` keeps them as HEIC (JPEG where HEIC can't be written) under `<Caches>/Open Wallpaper Engine/LoadingSnapshots`, keyed by the wallpaper's folder, the display's pixel size and a hash of the folder's top-level files, capped as an LRU. The prepare-on-arrival helper (`--prepare-wallpapers`) writes one per connected display after a second of scene time; a running scene (`SceneLoadingSnapshotCapture`, driven by `SceneRenderLoop`) refreshes its display size once per session, and again after its user properties change, reading the frame back off the render thread. Deleting a wallpaper removes its snapshots.
- **AVKit videos:** one `VideoWallpaperViewModel` (one decoding player, one audio player) per video; each display's `AVPlayerView` shows the shared player.
- **Web:** a `WKWebView` can't be in two windows, so each display keeps its page. Only the page on the wallpaper's audible display plays sound; the others are muted (`WebPageAudio`).
- **Sound** (`WallpaperAudioRouting`): each running wallpaper plays its sound once; a web wallpaper's from its audible display (the main display when it shows it, else the lowest display id), and a wallpaper running as several instances (different properties) from the instance on that display. Different wallpapers on different displays each play theirs. Settings → Audio Output silences all of them; volume and mute (the status menu) apply to all.
- **The watchdog** gets one frame time per rendered frame of an instance, not one per display.

## Lock screen and screen saver

- **Lock screen** (`App/LockScreenPicture`, Settings › General › "Show Wallpaper on Lock Screen", on by default). When a scene wallpaper is set, each display's system desktop picture becomes that scene's loading snapshot (`SceneLoadingSnapshotStore`, nothing new is captured), copied to `<Caches>/Open Wallpaper Engine/DesktopSnapshots/lock-<display>-<a|b>.<heic|jpg>`. The picture each display showed first is recorded per display and put back when the setting is turned off or the app quits. The menu bar tint's pictures (`DesktopSnapshotCache`) stay for video and web wallpapers; turning the tint off leaves a lock-screen picture alone.
- **Screen saver** (`ScreenSaver/`, Settings › Plugins › Screen Saver, off by default). While on, the current scene, web or WebM video wallpaper's loop video is made for each display's pixel size by the helper run `--render-screensaver-loop` (`ScreenSaverLoopRenderer`, `ScreenSaverWebLoopRecorder`): a `.library` job on the `PreparationPool` under the power policy, in its own process at background priority, HEVC through `AVAssetWriter`, scripts seeing `engine.isScreensaver()` true.
  - **Loop length.** With only periodic motion (timelines, sprite sheets; no particles or scripts) the loop is the least common multiple of the periods, at most 60 s, a whole number of frames, and frame N is checked against frame 0 (`ScreenSaverLoopLength`). Otherwise up to 60 s is rendered and the loop ends before the frame most like frame 0 after 5 s, compared at 64×36 (`ScreenSaverSeamFinder`), with a 0.25 s crossfade when that seam is still visible.
  - **Video wallpapers.** No render: the wallpaper's own MP4/MOV (H.264 or HEVC) goes in the folder as a hard link, else a symbolic link, or as its repaired copy when its track is `hev1`/`avc3` (`ScreenSaverVideoSource`); the manifest entry takes the track's size and the playback speed, and the saver loops it with `AVPlayerLooper`, muted. WebM is recorded as a web page (below).
  - **Web pages and WebM videos** (`ScreenSaverWebLoopRecorder`, same helper argument plus the user properties as JSON). The page loads in an offscreen `WKWebView` of the display's size in points, configured as on the desktop (scheme handler and WE patches, pause script, WE web API bridge, properties and FPS, a silent audio feed, muted). Its time is stepped: an injected virtual clock drives `performance.now`, `Date.now`, animation frames, timers, CSS animations and `<video>` time 1/30 s per frame, and `takeSnapshot` captures each frame (no Screen Recording permission; the per-frame time is logged). The loop is always the seam finder's search; frames are kept in a near-lossless intermediate video and re-encoded into the loop. A page that doesn't load exits 3 and the Details pane says Not Available with the reason. Clocks a page draws itself aren't hidden. Application wallpapers stay ineligible.
  - **Storage.** macOS runs third-party savers sandboxed in `legacyScreenSaver`, which can read only its own container, so the videos and `current.json` (`ScreenSaverManifest`) go in `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Open Wallpaper Engine/ScreenSaver`. Each video is named by wallpaper and content, a hash of its user properties, the pixel size and `ScreenSaverVideoStore.revision`; anything the manifest no longer lists is removed.
  - **Saver.** The `OpenWallpaperEngineSaver` target (`OWESaverView`: a `ScreenSaverView` with an `AVPlayerLayer` and `AVPlayerLooper`) is embedded in the app and copied to `~/Library/Screen Savers`; the app then opens the Screen Saver settings for the user to choose it and changes no system setting itself. Turning the plugin off stops rendering and removes the saver and the videos.
- **Isolation.** An isolated copy never sets the desktop picture, installs or removes the saver, or writes where the saver reads (its videos go under its own support folder).

## Invariants

- **WE semantics, not approximations.** Wallpaper Engine's shaders and effect definitions are the reference. Hand-written "native" effects and name/regex heuristics are technical debt to delete, not a pattern to extend (see [`CONTRIBUTING.md`](../CONTRIBUTING.md)).
- **Per-wallpaper state.** State belongs to a wallpaper *instance* (one per wallpaper and set of user properties, shared by the displays showing it), never to a process-wide singleton.
- **Loud failure.** A shader that fails to build, a layer that can't be decoded, or a script that throws is logged once, with the wallpaper, layer and reason.
- **Honest caches.** Everything derived from inputs (shader translations, `.metallib`s, parsed scenes) is keyed on its inputs *and* the version of the code that produced it.
