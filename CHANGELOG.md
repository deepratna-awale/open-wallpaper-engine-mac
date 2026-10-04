# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Web wallpapers in Chromium:** with the optional Chromium web engine installed (Settings › Plugins), a web wallpaper that uses Chromium-only features plays in Chromium; the rest stay in WebKit, which uses far less memory. A wallpaper's details have a **Web engine** choice (Automatic, WebKit, Chromium) to force one. In Chromium, user and general properties, the audio and media listeners, pause, mute, suspend while covered, the FPS limit and mouse input work as in WebKit, and local files are served with the same folder containment.
- **Wallpapers that need Chromium** are pointed out when Chromium isn't installed: applying one shows which Chromium-only web APIs it uses, with **Open Plugins** and **Use Anyway** (remembered for that wallpaper until it changes), and its details carry a "Some features only available on Chromium" badge.
- **Wallpaper Editor** (Edit Wallpaper in Details, ⌥⌘E): a window for scene wallpapers with the layer hierarchy (visibility, lock), the live wallpaper as a canvas you can zoom and pan, and an inspector for the selected layer. Move, scale and rotate image and text layers on the canvas or with the inspector, change opacity, colour and blend mode, turn effects on and off, and set the wallpaper's properties; everything can be undone. Edits are kept beside the wallpaper and apply wherever it runs, without changing its files: Revert drops them, and Save as Local Wallpaper adds a copy with the edits to the library. The Scene Inspector is unchanged.
- **Wallpaper Editor: layers and effects.** Add image (imported from a file, converted when needed), text (with a clock or date script), solid colour, composition, fullscreen and sound layers; duplicate, delete, rename, reorder by dragging, group, ungroup and move layers in and out of groups, keeping them where they are. Dragged layers snap to the scene and to each other (with guides), align to the scene, and move, scale and rotate live without reloading. Text is edited on the canvas or in the inspector with its font, size, alignment and padding. Effects are added from Wallpaper Engine's catalog (searchable, by group) or the Workshop effects a wallpaper uses, removed, reordered and toggled, and every parameter is editable with the control its shader declares (sliders, colours, vectors, options, textures), live where the renderer allows; a parameter can follow a user property, and masks are painted on the canvas or imported. An Assets tab lists the wallpaper's textures, models, sounds and fonts and imports dropped files. Everything is undoable, kept in the overlay with its files beside it, and Save as Local Wallpaper writes it all into the copy.
- **Wallpaper Editor: scripts and user properties.** Every field in the inspector has a menu to add a SceneScript (or an object script), edit it, or bind the field to a user property. The script editor docks under the canvas with JavaScript highlighting, line numbers, find (⌘F), autocomplete of the SceneScript API (`engine`, `thisLayer`, `thisScene`, `input`, the audio and media APIs, `WEMath`/`WEVector`/`WEColor`), syntax errors at their line before Apply, the script's own properties, templates (clock, date, audio-reactive scale, follow the cursor, object script) and a console of what the running scripts log and the errors they raise. Apply runs the script in the wallpaper (it reloads). User Properties in the toolbar adds, edits, removes and reorders the wallpaper's properties of every type (checkbox, slider, colour, combo, text input, file, folder, label) with their defaults, slider ranges, combo options and conditions, beside a live preview of the panel; renaming one re-points its conditions and bindings. All of it is undoable, kept with the other edits, and written into scene.json and project.json by Save as Local Wallpaper.
- **Particle editor** in the Wallpaper Editor: add a particle system (blank, or one of Wallpaper Engine's presets), move it on the canvas, duplicate or delete it, and edit it as Wallpaper Engine's editor lays it out: its texture and material, its own settings, emitters, initializers, operators, renderers, child systems, control points (dragged on the canvas) and the layer's instance override. Components are added, removed and reordered in lists, each field with the control Wallpaper Engine gives it. Changes show at once on the running system, only that system starting over (Restart System starts it again on demand), can be undone, and are written as Wallpaper Engine's particle files by Save as Local Wallpaper.

- **Depth Map Generation plugin** (Settings › Plugins, off until installed): downloads Depth Anything V2 Small, Apple's Core ML package (Apache-2.0), from Apple's Hugging Face repository at a pinned commit, checks every file against its pinned SHA-256 and prepares it for the Mac. In the Scene Editor and the Wallpaper Editor, a **Depth Map** section generates a depth map on the Mac for an image, text, solid, composition or fullscreen layer, a particle system (from one frame) or the whole scene, previews it, sets its smoothing, and applies Wallpaper Engine's Depth Parallax effect bound to it (strength adjustable, removable, undoable), which follows the pointer as in Wallpaper Engine (on a scene without camera parallax it turns parallax on with the layers' own movement at 0, and back off with the last depth parallax removed). Depth maps are kept with the wallpaper's edits, so both editors share them and Save as Local Wallpaper writes them as a normal effect and texture. The model is loaded only while generating and released five minutes after the last generation.

### Changed

- **Closing the last window** leaves Open Wallpaper Engine in the menu bar without a Dock icon; the icon comes back when a window opens (from the menu bar, a menu or reopening the app). A minimised window keeps the Dock icon, where it is restored from. The app also starts without a Dock icon when it opens no window.
- **Loading a scene wallpaper** shows a full-resolution picture of the scene's own frame instead of its low-resolution Workshop preview, then crossfades to the live scene as before. The picture is taken when a wallpaper is downloaded or imported, and refreshed once per session while a wallpaper runs (and after its properties change), for each display size. It is stored in the Caches folder, capped in size, and removed with the wallpaper. The Workshop preview is still shown until a wallpaper has one.

### Fixed

- **Wallpaper Editor and Scene Inspector:** a number's unit (×, %, °, px, s, fps) stays beside the number on one line in a narrow inspector or beside a long translated label, instead of the number showing above it.
- **Settings › Assets › Update from Steam** no longer downloads Wallpaper Engine again when the assets are current: it first reads the public build from SteamCMD's app info and reports "up to date" when it matches the installed build and the files are there. If the check fails (offline, not logged in), nothing is downloaded. **Re-download** downloads regardless, to repair a damaged copy.

## [1.0.0]

### Highlights

- **Automatic updates (Sparkle 2):** updates are signed with EdDSA, listed in an appcast on GitHub Pages and downloaded from GitHub Releases. "Update automatically" (on by default) checks, downloads and installs by itself: an update installs on quit, after 10 minutes away from the Mac, or within a day, with a quick relaunch that restores the wallpapers. With it off, "Automatically check for updates" asks before installing. "Receive beta updates" (off by default, on for pre-release builds) offers `vX.Y.Z-(alpha|beta|rc).N` releases. Settings › General › Updates shows when the app last checked, with Check Now; Check for Updates… is in the app menu and the menu bar menu. Builds without the update signing key (Debug and local builds from source) never check.
- **Setup assistant:** replaces the welcome sheet with skippable steps for the language, privacy, SteamCMD, the Steam login, an optional Steam Web API key, the Wallpaper Engine assets and importing wallpapers. The Privacy step has "Keep Open Wallpaper Engine up to date automatically".
- **SteamCMD sets itself up:** Valve's SteamCMD is downloaded when none is found; Homebrew's, Steam's or a chosen one is used when present. Terminal login and privacy notes explain what is sent where.
- **Imports:** Workshop collections and subscriptions read from Steam's Web API, the Workshop items of an existing Steam library (Valve KeyValues/ACF manifests), and wallpaper folders.
- **Assets after signing in:** the Wallpaper Engine assets can install automatically from the user's Steam copy once SteamCMD is logged in, with or without the default wallpapers.
- **Wiki:** Support & FAQ opens the project wiki's Troubleshooting page.

### Changed

- The privacy notes now say the app contacts GitHub, without personal data, to check for and download updates, which can be turned off in Settings › General.
- Quality presets set Shadows (a new Performance control) and volumetrics as Wallpaper Engine does.
- The repository is now `deepratna-awale/open-wallpaper-engine-mac`; the default Wallpaper Storage folder is `~/Documents/Open Wallpaper Engine`, and the assets cache and hidden data move with it.

### Fixed

- A SteamCMD login counts only once SteamCMD confirms it, and the cached Steam session is restored before installing assets.
- Unrated import items list as the Installed rating filter does; asset packs without a type stay out of the library.
- Video: WebM plays through WebKit, AVKit videos keep looping, Metal video frames live until the GPU is done, and wallpaper players let the display sleep.
- Now-playing artwork binds to effect and material passes; inspector sliders update live; puppets without effects draw past their image's rect.

## [0.9.0]

### Highlights

- **Wallpaper Engine's own shaders:** layers, effects and materials draw through each wallpaper's original shaders, translated to Metal in the app, Workshop authors' own effects included.
- **Scene rendering:** composition, fullscreen and solid layers, layers that sample other layers, all 33 blend modes and more effect masks; WE's text layout with outline, blur and drop-shadow font effects; timelines with WE's single, loop and mirror rules; colour lookup tables, colour correction and the image filter and colour options in a wallpaper's properties.
- **Puppet Warp:** images posed by their animations, with bone physics (springs, gravity, limits) and objects attached to their bones.
- **3D and lighting:** 3D models with skinning, animation layers, morph targets and root motion; perspective cameras with paths, fades and shake, 2D layers in depth; scene lights with cookies, shadows, planar reflections, distance and height fog and volumetric lights; WE's HDR bloom, and EDR output with the "Ultra (Display HDR)" quality.
- **Particles:** every system simulated on the GPU, in 3D, with 3D control points; child systems (including event children), bursts, delays and periodic emission, emitting from a layer's image; collision (a model's bones included), audio response, rotation about every axis, and settings bound to user properties.
- **SceneScript:** a complete runtime (modules, the scene/layer/effect/material object model, animation events, `localStorage`, cursor hit testing), each wallpaper's scripts on their own thread; scripts create layers, particle systems and sounds, move the fog, drive bloom and pose puppets and models.
- **Media and audio:** Now Playing for scenes and web wallpapers (macOS 15.4 or later); web wallpapers get their user properties and live audio; WE's stereo audio spectrum; sound layers on the scene's clock with spatial sound.
- **Assets from the user's Steam copy:** Settings › Assets installs Wallpaper Engine's assets from the user's own copy (see Changed).
- **WebM video wallpapers** play through WebKit.
- **Requirements:** macOS 14 or later.

### Changed

- Wallpaper Engine's assets (effects, materials, shaders, models, particles, scripts, fonts and UI strings) no longer ship in the repository or the app. Settings › Assets installs them from the user's own Wallpaper Engine copy on Steam through SteamCMD (keeping only the assets and the default wallpapers, which join the library), or reads them from a chosen Wallpaper Engine folder. Without them, scenes say so and video and web wallpapers still play. Tests read them from `OWE_ASSETS` and skip without it.

### Added

- Added a native Metal scene renderer with layer compositing, keyframe timelines, camera/projection handling, pooled render targets, effect masking, and additive/alpha blending.
- Added roughly 48 native Metal scene effects, including blur variants, bloom, godrays and light shafts, water waves/ripples/caustics/flow, clouds and fog, film grain, glitch/VHS, chromatic aberration, colour key, transform/skew/spin/twirl/perspective, reflection, refraction, shine/shimmer/glitter, and edge detection.
- Added audio-reactive effects (pulse, audio bars, hue shift, hyperdrive) driven by ScreenCaptureKit system-audio capture with a smoothed 16-band spectrum and bass/mid/treble levels.
- Added GLSL to SPIR-V to MSL shader translation using `glslangValidator` and SPIRV-Cross, with COMBO define extraction, include resolution, sampler deduplication, and Metal buffer-slot renumbering.
- Added a hash-gated shader cache under `.open-wallpaper-engine/shaders` storing `.metal`, `.metallib`, and `.reflection.json` artifacts, with background `.metallib` compilation and per-revision `unsupported` markers.
- Added a dynamic scene effect catalog sourced from Wallpaper Engine `assets/effects/*/effect.json` manifests, including multi-pass effects and reflected uniform bindings.
- Added GPU decoding of mipmapped DXT1/DXT3/DXT5 textures and TEXS0001/0002/0003 sprite timelines.
- Added a persistent SceneScript runtime with per-layer contexts, `init()`/`update(value)` lifecycle, `thisScene`/`thisLayer`/`engine`/`input` globals, `audio(low, high)` and `fft(index)`, timers, cursor and resize events, Vec/Mat math, `WEMath`/`WEVector`/`WEColor`, and loading of Wallpaper Engine JS modules.
- Added scripted control of layer alpha, origin, size, scale, angles, brightness and colour, material constants, effect thresholds, and particle emission rate, drag, and alpha fade.
- Added advanced particle behaviour: turbulence, attractors, vortex and boid motion, static and cursor-linked control points, rope segments, trails with alpha/size fade, and spritesheet frame animation.
- Added mouse tracking and parallax for layers with authored `parallaxDepth`.
- Added user-property support for slider, checkbox, combo, text, and colour settings in the scene inspector, with per-property music sync and amount modulation.
- Added a settings diagnostics section reporting shader toolchain paths and shader cache statistics, with a cache invalidation action.
- Added a Wallpaper Engine assets directory setting plus bundled `we-assets/` fallback, and `Scripts/vendor-shader-tools.sh`, `Scripts/vendor-we-assets.sh`, and `Scripts/scene-api-coverage.py`.
- Added quality, anti-aliasing, and post-processing options to the Performance settings page.
- Added music-synced zoom, tilt, and saturation for video wallpapers.
- Added Steam Workshop browsing with tag filters, numbered pagination, cached metadata, author profiles, and downloaded-item filtering.
- Added SteamCMD download queueing, retryable failures, live percentage progress when available, and a dedicated Downloads tab.
- Added Workshop preview windows backed by a bounded cache, with set-wallpaper, playback, and volume controls.
- Added multi-selection, range selection, and confirmation-gated bulk Workshop downloads and Installed wallpaper deletion.
- Added persisted downloaded Workshop IDs and download timestamps, including `Date Downloaded` sorting.
- Added multi-desktop selection and an `All Desktops` control in Display Settings.
- Added wallpaper placement controls for Fill, Fit, Center, Stretch, and Zoom.
- Added audio/video speed linking controls for video wallpapers.
- Added configurable wallpaper storage with an option to move the existing library to the selected location.

### Changed

- Scene wallpapers now render through Metal instead of SpriteKit.
- Reduced scene rendering hot-path overhead by caching effect descriptors that do not vary per frame and taking a single user-property snapshot per frame.
- Installed and Workshop grids now size their pages from the available viewport and current icon size.
- Installed tile selection now previews an item; applying a wallpaper is an explicit action from the sidebar or preview window.
- Cached Workshop previews are promoted to the permanent wallpaper library when applied, without a second download.
- Scene image layers use explicit SpriteKit depth ordering.
- Only one desktop video wallpaper outputs audio to avoid duplicate playback artifacts.
- Renamed the Installed sort label to `Date Downloaded` while preserving the existing saved preference value.
- Paused foreground thumbnail and sidebar GIF animations while the app is inactive, and avoided redundant GIF image decoding during SwiftUI updates.

### Fixed

- Fixed shaders exceeding Metal's 31 buffer-slot limit by densely renumbering bindings emitted by `glslang --auto-map-bindings`.
- Fixed spirv-cross output that declared helper parameters as `thread const T&` where Metal entry points require `constant T&`.
- Fixed repeated retranslation of unchanged shaders by hashing sources and gating on a pipeline revision.
- Fixed SceneScript exception spam by deduplicating identical errors within a time window and reporting repeat counts.
- Fixed SteamCMD downloads failing when the default Homebrew location is not writable by using a local forced install directory.
- Fixed stale Workshop previews replacing newer selections.
- Fixed cached Workshop download status not being reflected after app restart.
- Fixed Workshop Hide Downloaded pages leaving empty grid positions.
- Fixed SF Symbol warnings caused by empty symbol names.
- Fixed preview rendering requiring window movement before redraw.
- Fixed preview audio continuing after the preview window closes.
- Fixed author lookup when downloaded projects have an empty `workshopid` by falling back to the numeric wallpaper folder name.
- Fixed saved wallpaper assignments, recents, and the downloaded-ID index after moving the wallpaper library.
- Preserved compatibility with legacy Workshop metadata cache encodings.
- Fixed white flashes during wallpaper-window and SpriteKit scene initialization by using explicit black backing colors.

### Removed

- Removed hover-triggered Workshop preview downloads.
- Removed the bottom download queue panel in favor of the Downloads tab.
- Removed the external glslang/spirv-cross command-line fallback compiler and its Diagnostics rows. A shader whose in-process translation hung the app, or crashed it twice, is now skipped on later launches while every other shader keeps translating.
- Removed the old Wallpaper Engine assets folder setting (a previously saved folder is ignored and left in place). Superseded in this release: the app ships no assets, and Settings › Assets installs them from the user's Steam copy or reads a chosen Wallpaper Engine folder (see Changed).
