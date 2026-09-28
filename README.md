Open Wallpaper Engine
=========

**English** | [Deutsch](resources/readme/README.de.md) | [Français](resources/readme/README.fr.md) | [Español](resources/readme/README.es.md) | [Português (Brasil)](resources/readme/README.pt-BR.md) | [Italiano](resources/readme/README.it.md) | [日本語](resources/readme/README.ja.md) | [한국어](resources/readme/README.ko.md) | [简体中文](resources/readme/README.zh-Hans.md) | [繁體中文](resources/readme/README.zh-Hant.md) | [Русский](resources/readme/README.ru.md) | [Polski](resources/readme/README.pl.md) | [Türkçe](resources/readme/README.tr.md) | [Українська](resources/readme/README.uk.md) | [العربية](resources/readme/README.ar.md) | [हिन्दी](resources/readme/README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

Open Wallpaper Engine is a free, open-source macOS player for Wallpaper Engine wallpapers: scene, video and web. It has a native Metal renderer and supports effects, particles, 3D models, lighting, SceneScript, audio-reactive visuals and the Steam Workshop. It began as a fork of Haren Chen's and MrWindDog's [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) and has since been largely rewritten.

> **Note:** This is NOT affiliated with the commercial Wallpaper Engine on Steam. This is an open-source macOS app that can display wallpaper assets from Wallpaper Engine's Steam Workshop. → [ATTRIBUTION.txt](ATTRIBUTION.txt)

**Wiki:** guides and documentation are in the [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Related Projects

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — A PyQt6 GUI for [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), with Steam Workshop integration and UI design ported from this macOS version.

## Credits

This project is built on top of the work of:

- **[MrWindDog](https://github.com/MrWindDog)** — Maintainer of the upstream [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) fork, added new features and UI refinements
- **[Haren Chen](https://github.com/haren724)** — Original creator of [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), built the core app architecture (SwiftUI, video wallpaper playback, import system, playlist UI)
- **1ris_W** — Chinese i18n translation
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Original app logo design
- **[Chen Chia Yang](https://github.com/Unayung)** — Scene wallpaper rendering, web wallpaper fixes, Steam Workshop integration, multi-display support, zip import
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal scene renderer and effect pipeline, GLSL→MSL shader translation and caching, SceneScript runtime, audio-reactive rendering, Workshop/Downloads overhaul, placement and performance settings, logo redesign

Licensed under [GPL-3.0](LICENSE), same as the original project.

## From 0.8.1 to 1.0.0

### Where it started

This fork starts from upstream 0.8.1 (commit `aa29a89e`, March 2026). 0.8.1 played video and web wallpapers, had multi-display and multi-desktop support, playlists, a recent-wallpapers menu, zip and folder import, and a Steam Workshop browser that downloaded through Homebrew's SteamCMD. Scenes were drawn with SpriteKit from PKG and TEX files: image layers with position, tint and blend modes, falling back to the preview image for DXT textures. Wallpaper Engine shaders and effects, particles, sprite and timeline animation, camera parallax, audio-reactive scripts, 3D models, puppets, lighting and SceneScript were not supported.

### What was added

Since then, 1,118 commits have added:

- **Rendering:** a new Metal scene renderer with Wallpaper Engine's shaders translated in-process and cached, effects, bloom and HDR.
- **Scene content:** particles simulated on the GPU; 3D models, puppets with skeletal animation, and lighting.
- **Behaviour:** a SceneScript runtime, property timelines, audio-reactive visuals and spatial sound.
- **Displays and Workshop:** per-display rules, a reworked Workshop browser and downloads, and more import paths. Wallpaper Engine's assets come from the user's own Steam copy; none are bundled.
- **App:** a setup assistant, automatic SteamCMD installation, Sparkle updates, a Liquid Glass interface and 15 languages.
- **Quality:** a test suite of about 1,900 tests, CI that runs them with Wallpaper Engine's assets, and signed and notarized releases.
- **Documentation:** a project website and the wiki.

The full list is in [What 1.0.0 Supports](#what-100-supports); guides are in the [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## What 1.0.0 Supports

### Setup, library & updates
- **Setup assistant** — on first launch, a few skippable steps set the language, show the privacy notes, set up SteamCMD, the Steam login and an optional Steam Web API key, install the Wallpaper Engine assets and bring in your wallpapers.
- **SteamCMD sets itself up** — when none is found, the app downloads Valve's SteamCMD; Homebrew's or Steam's is used if present.
- **Wallpaper Engine assets from your own Steam copy** — installed through SteamCMD after you sign in, optionally with Wallpaper Engine's default wallpapers.
- **Imports** — your Workshop collections and subscriptions (read from Steam's Web API), the Workshop items of an existing Steam library, and wallpaper folders.
- **The [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — guides, settings reference and troubleshooting; Support & FAQ in the app opens it.
- **Automatic updates** — signed updates install by themselves (on quit, after 10 minutes away, or within a day, then a quick relaunch restores your wallpapers). Settings › General › Updates lets you only check, or turn checks off, and opt into beta updates. Check for Updates… is in the app menu and the menu bar menu.

### Scene rendering
- **Wallpaper Engine's own shaders** — layers, effects and materials now draw through each wallpaper's original shaders, translated to Metal, including effects that Workshop authors made themselves.
- Composition, fullscreen and solid layers, layers that sample other layers, all 33 blend modes, and more effect masks.
- **Faithful text layout** — text is sized, aligned and positioned as in Wallpaper Engine, with outline, blur and drop-shadow font effects.
- **Timelines** — keyframe and texture animations follow Wallpaper Engine's single, loop and mirror rules.
- Colour lookup tables, Wallpaper Engine's colour correction, and the image filter and colour options in a wallpaper's properties.
- **Puppet Warp** images posed by their animations, with bone physics (springs, gravity, limits) and objects attached to their bones.

### 3D & lighting
- **3D models** with skinning, animation layers, morph targets and root motion.
- Perspective scene cameras with camera paths, fades and shake; 2D layers sit in depth.
- **Scene lights** with light cookies, shadows, planar reflections, distance and height fog, and volumetric lights.
- **HDR** — HDR scenes render with Wallpaper Engine's HDR bloom, and the "Ultra (Display HDR)" quality outputs EDR on displays that can show it.

### Particles
- **GPU particles** — every particle system is simulated on the GPU, in 3D, with 3D control points.
- Child systems, including ones triggered by their parent's particles; emitter bursts, delays and periodic emission; emitting from a layer's image.
- Collision, including with a model's bones, audio response, and rotation about every axis.
- Particle settings bound to a wallpaper's user properties.

### SceneScript & media
- A complete **SceneScript runtime** — modules, the scene/layer/effect/material object model, animation events, `localStorage`, and cursor hit testing, with each wallpaper's scripts on their own thread.
- Scripts can create layers, particle systems and sounds, move the fog, drive bloom, and pose puppets and models.
- **Now Playing** — scenes and web wallpapers receive the current track and playback state (macOS 15.4 or later).
- Web wallpapers receive their user properties and live audio.

### Audio
- The audio spectrum is computed the way Wallpaper Engine computes it, in stereo.
- **Sound layers** play on the scene's clock, with **spatial sound** placed as in Wallpaper Engine.

### Displays & playback
- **Pause per Display** or **Pause All**, with the playback rules checked for each display, including Wallpaper Engine's maximized-window rule.
- Per-display user properties, with "Sync properties across displays".
- A wallpaper shown on several displays renders once and is presented on each.
- New quality settings: Render Resolution, Texture Resolution, Match Display scene detail, reflections, shadows and volumetrics.
- **Safe restart** — a wallpaper that stalled or crashed the app is skipped on the next launch and marked in the library.

### Workshop & library
- Wallpaper Engine's Workshop filters: Show Only, a resolution filter, genres combined with AND/OR, and tags on every card.
- Installed wallpapers show and filter by their Workshop tags; asset-only and dependency-only items stay out of Installed.
- Missing Workshop dependencies download automatically, and unused ones are removed after a delete. Every download lands in the Wallpaper Storage folder.
- **Reset** in Details returns a wallpaper's properties, and its Scene Inspector edits, to the defaults its author set.
- Property conditions, text rows and slider formats from the wallpaper's settings are honoured.
- Steam passwords are never stored, and the Steam Web API key is kept in the Keychain.

### Interface & languages
- **Liquid Glass** on macOS 26 — a native split view, toolbar and inspector with glass controls. Earlier macOS versions keep the familiar look.
- **15 new languages**: German, French, Spanish, Brazilian Portuguese, Italian, Japanese, Korean, Simplified and Traditional Chinese, Russian, Polish, Turkish, Ukrainian, Arabic and Hindi, chosen from the Language picker in Settings.
- A new app icon, and a menu bar icon that follows the menu bar's appearance.

<details>
<summary>Previously in 0.8.1</summary>

### Wallpaper playback
- **Scene wallpapers** rendered natively with Metal — image layers, transforms, keyframe timelines, depth ordering, and camera/projection data from `scene.json`.
- **Video wallpapers** (`.mp4`, `.webm`) with playback rate, volume, audio/video speed linking, and optional music-synced zoom/tilt/saturation. WebM (VP8/VP9) plays through WebKit, where music sync doesn't apply.
- **Web wallpapers** (HTML/WebGL) with local file access enabled so WebGL textures and assets load correctly, plus external embeds (YouTube/Vimeo).
- **Placement modes** — Fill, Fit, Center, Stretch, Zoom.
- **Multi-display** — a different wallpaper per monitor, per-screen enable/disable, visual monitor layout, and auto-detection of newly connected displays.
- **Multi-desktop (Spaces)** — continuous playback across all desktops, including an `All Desktops` assignment option.
- **Playback rules** — keep running, mute, pause, or stop when another app is focused; correct behaviour on sleep/wake and desktop switches.

### Scene format support
- **PKG parser** for Wallpaper Engine `PKGV` archives (scene.json, materials, textures, shaders).
- **TEX parser** for `TEXV0005` containers: embedded JPEG/PNG, mipmapped DXT1/DXT3/DXT5 decoded on the GPU via a Metal compute shader.
- **TEXS sprite timelines** (0001/0002/0003), including single-atlas frame rectangles and multi-image sequences.
- **Flexible scene.json decoding** that handles Wallpaper Engine's polymorphic fields (plain values or `{"script":…,"value":…}`).
- **Preview fallback** to `preview.jpg/png/gif` when textures can't be extracted.

### Effects and shaders
- **~48 native Metal effects** covering distortion, blur (standard/precise/radial/motion), bloom, godrays and light shafts, water waves/ripples/caustics/flow, clouds and fog, film grain, glitch/VHS, chromatic aberration, colour key, transform/skew/spin/twirl/perspective, reflection, refraction, shine/shimmer/glitter, edge detection, and more.
- **Audio-reactive effects** — pulse, audio bars, audio-synced hue shift, and hyperdrive driven by live system-audio spectrum data.
- **Semantic material effects** — brightness, contrast, saturation, exposure, gamma, hue, bloom threshold, bloom, and blur mapped to native Metal passes.
- **GLSL → SPIR-V → MSL translation** at load time by glslang and SPIRV-Cross linked into the app, with COMBO defines, include resolution, and Metal buffer-slot renumbering.
- **Precompiled shader cache** — translated `.metal`, compiled `.metallib`, and `.reflection.json` sidecars are cached under `.open-wallpaper-engine/shaders`, hash-gated so only changed shaders are retranslated, and compiled in the background so rendering is never blocked.
- **Dynamic effect catalog** read from the Wallpaper Engine `assets/effects/*/effect.json` manifests, including multi-pass effects and reflected uniform bindings.
- **Effect masking** (up to 4 mask textures per layer), additive and alpha blending, and a pooled render-target system.

### Particles
- Sprite emitters with randomized lifetime, size, velocity, colour, rotation, angular velocity, gravity, drag, and alpha fades.
- Advanced behaviour — turbulence, attractors, vortex and boid motion, static and cursor-linked control points, connected rope segments, and trails with alpha/size fade.
- Spritesheet frame animation via `.tex-json` sequences.
- Scripted operators for emission rate, drag, and alpha-fade timing.

### SceneScript runtime
- Persistent per-layer script contexts with `init()` called once and `update(value)` called every frame.
- Globals: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, real `fft(index)`, `setTimeout`/`setInterval`, and persistent script globals.
- Full `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` math library plus `WEMath`, `WEVector`, and `WEColor` helpers.
- Wallpaper Engine runtime JS modules loaded from `assets/scripts/jsmodules` and `jsclasses`.
- Cursor events (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) and `resizeScreen`.
- Scripts can drive layer alpha, origin, size, scale, angles, brightness/colour, material constants, effect thresholds, and particle rates.
- Deduplicated script exception logging with repeat counts.

### Audio
- System audio capture via ScreenCaptureKit feeding a smoothed 16-band spectrum, waveform, and bass/mid/treble levels.
- Per-property **music sync** — any user property can be modulated by audio level with a configurable amount.

### User properties & inspector
- Slider, checkbox, combo, text, and colour project settings exposed in the scene sidebar, live-applied, and readable from SceneScript.
- Mouse tracking and parallax for layers with authored `parallaxDepth`.

### Steam Workshop
- Browse, search, and filter by content rating, type, and genre tags, with Trending / Most Recent / Most Popular / Most Subscribed sorting and numbered pagination.
- Preview windows with set-wallpaper, playback, and volume controls, backed by a bounded cache; applied previews are promoted to the library without re-downloading.
- SteamCMD integration with auto-detection, password / Steam Guard / cached-session login, a dedicated Downloads tab, queued and retryable downloads, and live progress.
- Multi-selection, range selection, confirmation-gated bulk downloads and deletions, persisted downloaded IDs, and `Date Downloaded` sorting.

### Library & settings
- Import from folders, from `.zip` packages, or by drag-and-drop.
- Configurable wallpaper storage location with migration of an existing library.
- Recent wallpapers menu in the status bar.
- Performance settings — quality, anti-aliasing, post-processing, and focus-loss playback behaviour.
- Diagnostics — the bundled assets path, the built-in shader compiler's library versions, and shader cache statistics.

</details>

<details>
<summary>Previously in 0.8.0</summary>

### Multi-Display Support
Assign different wallpapers to each connected monitor with per-screen enable/disable control.
- **Display Settings panel** — Visual monitor layout showing all connected screens, click to select
- **Per-screen wallpaper** — Each display can show a different wallpaper independently
- **Enable/disable toggle** — Turn wallpaper on or off per monitor
- **Auto-detect** — New monitors are automatically detected and enabled when connected

### Multi-Desktop Support
Wallpapers now display across all macOS desktops (Spaces) with continuous playback — no interruption when switching desktops.

### Recent Wallpapers Menu
Quickly switch wallpapers from the status bar menu. The last 10 wallpapers you've used are listed for one-click access.

### Playback Settings — Fixed
Performance playback settings (pause/mute/stop when other apps are focused) now work correctly for all wallpaper types.

### Steam Workshop Browser
Browse, search, and download wallpapers directly from the Steam Workshop without leaving the app.
- **Search & filter** — Search by name, filter by content rating (Everyone/Questionable/Mature), type (Scene/Video/Web), and genre tags
- **Sort options** — Trending, Most Recent, Most Popular, Most Subscribed
- **steamcmd integration** — Downloads Valve's SteamCMD automatically the first time it's needed (not bundled); an existing steamcmd (Homebrew, Steam, or a custom path) is used if found
- **Steam login** — Supports password, Steam Guard, and cached session authentication
- **Download with progress** — Real-time status updates during download (authenticating, downloading %, validating, copying)
- **Safe defaults** — Content rating defaults to "Everyone" to filter out mature content

### Zip Import
Import wallpaper packages directly from `.zip` files — no need to manually extract first. Works via File > Import and drag-and-drop.

### Multi-Select & Batch Unsubscribe
Cmd+click to select multiple wallpapers, then right-click to batch unsubscribe.

### Wallpaper Storage Isolation
Wallpapers are now stored in `~/Documents/Open Wallpaper Engine/` instead of the raw Documents directory, preventing "error" wallpapers when cloning the repo on a fresh machine.

</details>

<details>
<summary>Early changes from the original project</summary>

### Web Wallpapers — Fixed gray/blank rendering
WebGL-based wallpapers rendered as gray rectangles because `WKWebView` blocked local file access for textures and assets.

**Fix:** Enabled `allowFileAccessFromFileURLs` and `allowUniversalAccessFromFileURLs` on the WKWebView configuration, allowing WebGL shaders to load local texture files.

### Scene Wallpapers — Implemented from scratch
Scene wallpapers (the most common type on Steam Workshop) were completely unimplemented — just showed "Hello, World!".

**New implementation includes:**
- **PKG parser** — Reads Wallpaper Engine's PKGV archive format to extract scene.json, models, materials, and textures
- **TEX parser** — Reads TEXV0005 texture containers, extracts embedded JPEG/PNG image data, and reads DXT1/DXT3/DXT5 mipmaps
- **Scene JSON decoder** — Parses scene.json with flexible decoding that handles Wallpaper Engine's polymorphic fields (values can be plain types or `{"script":..,"value":..}` objects)
- **Metal renderer** — Renders scene image layers with GPU texture compositing and a foundation for future shader effects
- **GPU DXT decode** — Expands DXT1 (TEXI 7), DXT3 (TEXI 6), and DXT5 (TEXI 4) textures through a Metal compute shader when the scene loads
- **Sprite particles** — Renders common `sphererandom` sprite emitters with randomized lifetime, size, velocity, alpha, color, rotation, angular velocity, gravity, drag, and alpha fades
- **Advanced particles** — Supports rotation, color variation, turbulence, static and cursor-linked control points, connected rope segments, trails, and `.tex-json` spritesheet frame animation
- **TEXS animation** — Decodes TEXS0001/0002/0003 timelines, including single-atlas frame rectangles and multi-image texture sequences
- **Scene timelines** — Interpolates object alpha, origin, scale, and angles keyframes at 60 FPS
- **SceneScript runtime** — Evaluates expression and `export function update(value)` property scripts against ScreenCaptureKit system audio. `thisScene` timing, `thisLayer.value`, `engine`, input cursor, `audio(low, high)`, real `fft(index)`, property lookup, and persistent globals drive image transforms, alpha, and particle emission rates.
- **Persistent SceneScript lifecycle** — Reuses per-layer script contexts, calls `init()` once, and calls `update()` across frames with shared `dt`, frame, mouse, button, modifier, cursor, audio, FFT, property, and layer state.
- **Scripted particle operators** — Supports scripts for particle emission rate, movement drag, and alpha fade timing, with flexible numeric/string particle fields.
- **Mouse tracking and parallax** — Applies cursor-relative translation and optional perspective scaling to layers with authored `parallaxDepth` metadata; cursor-linked particles use the same scene-space cursor.
- **Scripted visual properties** — Supports scripted object brightness/RGB color, material effect constants, scalar/vector transforms, and effect threshold overrides.
- **User properties** — Exposes documented slider, checkbox, combo, text, and color project settings in the scene sidebar and makes numeric and boolean values available to SceneScript
- **Built-in scene effects** — Executes authored `pulse`, `shake`, `iris`, and `waterwaves` effect graph entries in the Metal renderer
- **Semantic material effects** — Maps common material constants and scripts for brightness, contrast, saturation, exposure, gamma, hue, bloom threshold, bloom, and blur to native Metal effects
- **GLSL shader translation** — Converts packaged Wallpaper Engine GLSL shaders to SPIR-V and MSL at load time with glslang and SPIRV-Cross linked into the app; translated variants are cached under `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants`
- **Preview fallback** — Falls back to preview.jpg/png/gif when textures can't be extracted

### Import — Fixed folder import
The import panel now correctly handles both individual wallpaper folders and parent directories containing multiple wallpapers.

</details>

## Current Limitations

- **Application wallpapers** — `type: "application"` wallpapers are not supported and will not run.
- **SceneScript stubs** — `effect.executeMaterialFunction()`, `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `getVideoTexture()`, `engine.openUserShortcut()` do nothing yet.
- **SceneScript parity** — Not every proprietary event name, input callback, lifecycle edge case, or exact timing semantic is reproduced.
- **Rare particle features** — Emitter shapes other than sphere, box and layer image, and renderers after a system's first, are not supported.
- **Wallpaper Engine assets required** — Scenes need the assets from your own Wallpaper Engine copy (Settings → Assets); without them only video and web wallpapers play.
- **WebM videos** — WebM (VP8/VP9) plays through WebKit, so music-sync effects don't apply to it.
- **Some JPEG thumbnails** — A small number of TEXB format 1 files contain non-standard JPEG data that macOS cannot decode.
- **Performance settings scope** — Quality, anti-aliasing, and post-processing options are designed for scene wallpapers and have limited effect on video and web wallpapers.
- **Audio features require permission** — Without Screen Recording permission, audio visualizers and audio-reactive SceneScript receive silence.

## Supported Wallpaper Types

| Type | Status |
|------|--------|
| Video (.mp4, .webm) | Working |
| Web (HTML/WebGL) | Working |
| Scene — image layers & timelines | Working (Metal) |
| Scene — DXT1/DXT3/DXT5 textures | Working (Metal GPU decode) |
| Scene — TEXS sprites / alpha timelines | Working |
| Scene — sprite particles | Working |
| Scene — advanced particles | Partial (see Limitations) |
| Scene — Wallpaper Engine and Workshop effects (WE's own shaders) | Working |
| Scene — SceneScript | Partial (see Limitations) |
| Scene — 3D models / rigging / puppet warp | Working |
| Application | Not supported |

## Requirements

### Required
- **macOS 14.0 or later** (Sonoma). ScreenCaptureKit audio capture and Metal scene rendering both depend on it.

### Optional — needed for specific features

| Feature | Requirement | Install |
|---------|-------------|---------|
| Browsing / downloading from Steam Workshop | `steamcmd` | Automatic (optional: `brew install steamcmd`) |
| Audio visualizers & audio-reactive SceneScript | Screen Recording permission | Settings → Permissions |

#### Shaders

Wallpaper Engine ships its effects as GLSL. They are translated to Metal (GLSL → SPIR-V → MSL) by glslang and SPIRV-Cross, which are built into the app (`Vendor/ShaderToolchain`), the first time a wallpaper uses them, then cached on disk. Nothing needs to be installed. A shader whose translation hung the app, or crashed it twice, is skipped on later launches, and every other shader still translates.

#### Wallpaper Engine assets

Scenes use Wallpaper Engine's shared effects, materials, shaders, fonts and SceneScript runtime from your own Wallpaper Engine copy on Steam; the app doesn't ship them. Install them in *Settings → Assets*: the app downloads your copy with steamcmd (the account must own Wallpaper Engine), keeps only the assets and the default wallpapers, and deletes the rest. You can also choose an existing Wallpaper Engine folder. Video and web wallpapers work without them.

## Build from Source

### Prerequisites
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK)
- Xcode Command Line Tools

### Steps
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

In Xcode, change the signing certificate to your own or select "Sign to Run Locally", then press `Cmd + R` to build and run.

Building from source fetches the Sparkle Swift package on first build. Builds from source don't check for updates.

## Usage

### Browse & Download from Steam Workshop

1. Nothing to install: the app downloads Valve's SteamCMD in the background the first time it's needed (from Valve, not bundled). Homebrew (`brew install steamcmd`) is optional; an existing steamcmd (Homebrew, Steam, or one you pick) is used if found
2. Switch to the **Workshop** tab and log in with your Steam account (must own Wallpaper Engine)
3. Enter a [Steam Web API key](https://steamcommunity.com/dev/apikey) when prompted, or in *Settings → General*. It is checked with Steam and kept in your keychain; your Steam password is never stored (steamcmd reuses its own cached session)
4. Search, filter, and click **Download** on any wallpaper

### Import from Local Files

- **Folder:** File > Import > Wallpaper from Folder — select wallpaper folders containing `project.json`
- **Zip:** File > Import or drag-and-drop a `.zip` file containing wallpaper packages
- **Manual:** Copy wallpaper folders directly into `~/Documents/Open Wallpaper Engine/`

## Privacy

Everything Open Wallpaper Engine saves stays on your Mac: your settings, library, cache and SteamCMD's login. Open Wallpaper Engine has no server and collects no data or analytics. It contacts Valve (Steam when you use the Workshop or install assets, and Valve's server to download SteamCMD) and GitHub, to check for app updates (the appcast on GitHub Pages) and download them from GitHub Releases, without sending any personal data. Update checks can be turned off in Settings › General. Web wallpapers may load their own online content. Your Steam password and Steam Guard code go straight to SteamCMD and are never stored, logged or sent anywhere else; only your account name is remembered, to reuse SteamCMD's saved login.

## Project Layout

- `OpenWallpaperEngine/Services/SceneParsers/` — PKG, TEX/TEXS, and scene.json parsers and models
- `OpenWallpaperEngine/Services/SceneEffects/` — dynamic effect catalog and authored effect parameter ranges
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL translation (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), caching and the pipeline archive
- `Vendor/ShaderToolchain/` — glslang and SPIRV-Cross sources, built into the app as a local package
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — SceneScript runtime and audio/FFT bindings
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit system audio capture
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — the Metal scene renderer and shader library
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — Steam Workshop browsing and downloads
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — library storage, import, and package conversion
- `Scripts/fill-assets-cache.sh` — development helper: copies the assets subset of a Wallpaper Engine install into a local folder or the Wallpaper Storage cache
- `Scripts/scene-api-coverage.py` — reports which SceneScript APIs installed wallpapers use versus what is implemented
