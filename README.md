Open Wallpaper Engine
=========

**English** | [Deutsch](resources/readme/README.de.md) | [Français](resources/readme/README.fr.md) | [Español](resources/readme/README.es.md) | [Português (Brasil)](resources/readme/README.pt-BR.md) | [Italiano](resources/readme/README.it.md) | [日本語](resources/readme/README.ja.md) | [한국어](resources/readme/README.ko.md) | [简体中文](resources/readme/README.zh-Hans.md) | [繁體中文](resources/readme/README.zh-Hant.md) | [Русский](resources/readme/README.ru.md) | [Polski](resources/readme/README.pl.md) | [Türkçe](resources/readme/README.tr.md) | [Українська](resources/readme/README.uk.md) | [العربية](resources/readme/README.ar.md) | [हिन्दी](resources/readme/README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

Open Wallpaper Engine is a free, open-source macOS player for Wallpaper Engine wallpapers: scene, video and web. It has a native Metal renderer and supports effects, particles, 3D models, lighting, SceneScript, audio-reactive visuals and the Steam Workshop. It began as a fork of Haren Chen's and MrWindDog's [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) and has since been largely rewritten.

> **Note:** This is NOT affiliated with the commercial Wallpaper Engine on Steam. This is an open-source macOS app that can display wallpaper assets from Wallpaper Engine's Steam Workshop. → [ATTRIBUTION.txt](ATTRIBUTION.txt)

**Wiki:** guides and documentation are in the [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

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
cd open-wallpaper-engine-mac
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

## Current Limitations

- **SceneScript stubs** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` do nothing yet.
- **SceneScript parity** — Not every proprietary event name, input callback, lifecycle edge case, or exact timing semantic is reproduced.
- **Rare particle features** — Renderers after a system's first are not supported.
- **WebM videos** — WebM (VP8/VP9) plays through WebKit, so music-sync effects don't apply to it.
- **Some JPEG thumbnails** — A small number of TEXB format 1 files contain non-standard JPEG data that macOS cannot decode.
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

## Privacy

Everything Open Wallpaper Engine saves stays on your Mac: your settings, library, cache and SteamCMD's login. Open Wallpaper Engine has no server and collects no data or analytics. It contacts Valve (Steam when you use the Workshop or install assets, and Valve's server to download SteamCMD) and GitHub, to check for app updates (the appcast on GitHub Pages) and download them from GitHub Releases, without sending any personal data. Update checks can be turned off in Settings › Updates. Web wallpapers may load their own online content. Your Steam password and Steam Guard code go straight to SteamCMD and are never stored, logged or sent anywhere else; only your account name is remembered, to reuse SteamCMD's saved login.

## Project Layout

- `OpenWallpaperEngine/Scene/Format/` — PKG, TEX/TEXS, and scene.json parsers and models
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL translation (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), caching and the pipeline archive
- `Vendor/ShaderToolchain/` — glslang and SPIRV-Cross sources, built into the app as a local package
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript runtime and audio/FFT bindings
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit system audio capture
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — the Metal scene renderer and shader library
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — Steam Workshop browsing and downloads
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — library storage, import, and package conversion
- `Scripts/fill-assets-cache.sh` — development helper: copies the assets subset of a Wallpaper Engine install into a local folder or the Wallpaper Storage cache
- `Scripts/scene-api-coverage.py` — reports which SceneScript APIs installed wallpapers use versus what is implemented

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

## Legal

[Terms of Use](docs/legal/terms-of-use.md) · [Privacy Policy](docs/legal/privacy-policy.md) · [Security Policy](SECURITY.md)

- **English:** Please read the Terms of Use and the Privacy Policy.
- **Deutsch:** Bitte lesen Sie die Nutzungsbedingungen und die Datenschutzrichtlinie.
- **Français :** Veuillez lire les conditions d’utilisation et la politique de confidentialité.
- **Español:** Lee las condiciones de uso y la política de privacidad.
- **Português (Brasil):** Leia os Termos de Uso e a Política de Privacidade.
- **Italiano:** Leggi le condizioni d’uso e l’informativa sulla privacy.
- **日本語：** 利用規約とプライバシーポリシーをお読みください。
- **한국어:** 이용 약관과 개인정보 처리방침을 읽어 주십시오.
- **简体中文：** 请阅读使用条款和隐私政策。
- **繁體中文：** 請閱讀使用條款和隱私權政策。
- **Русский:** Прочитайте условия использования и политику конфиденциальности.
- **Polski:** Przeczytaj warunki korzystania i politykę prywatności.
- **Türkçe:** Lütfen Kullanım Koşulları’nı ve Gizlilik Politikası’nı okuyun.
- **Українська:** Прочитайте умови використання та політику приватності.
- **العربية:** يُرجى قراءة شروط الاستخدام وسياسة الخصوصية.
- **हिन्दी:** कृपया उपयोग की शर्तें और गोपनीयता नीति पढ़ें।
