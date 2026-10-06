Open Wallpaper Engine
=========

**English** | [Deutsch](resources/readme/README.de.md) | [Français](resources/readme/README.fr.md) | [Español](resources/readme/README.es.md) | [Português (Brasil)](resources/readme/README.pt-BR.md) | [Italiano](resources/readme/README.it.md) | [日本語](resources/readme/README.ja.md) | [한국어](resources/readme/README.ko.md) | [简体中文](resources/readme/README.zh-Hans.md) | [繁體中文](resources/readme/README.zh-Hant.md) | [Русский](resources/readme/README.ru.md) | [Polski](resources/readme/README.pl.md) | [Türkçe](resources/readme/README.tr.md) | [Українська](resources/readme/README.uk.md) | [العربية](resources/readme/README.ar.md) | [हिन्दी](resources/readme/README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

Open Wallpaper Engine is a free, open-source macOS player for Wallpaper Engine wallpapers: scene, video and web. It has a native Metal renderer and supports effects, particles, 3D models, lighting, SceneScript, audio-reactive visuals and the Steam Workshop. It began as a fork of Haren Chen's and MrWindDog's [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) and has since been largely rewritten.

> **Note:** This is NOT affiliated with the commercial Wallpaper Engine on Steam. This is an open-source macOS app that can display wallpaper assets from Wallpaper Engine's Steam Workshop. → [ATTRIBUTION.txt](ATTRIBUTION.txt)

**Website:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki:** [guides and troubleshooting](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![The library](docs/images/library.png)

## Highlights

- **Scene, video and web wallpapers** — scenes draw through each wallpaper's own Wallpaper Engine shaders, translated to Metal, with effects, particles, 3D models, lights, timelines, SceneScript and audio-reactive visuals. Web wallpapers run in WebKit or the optional Chromium engine.
- **Steam Workshop** — browse, filter and download from the Workshop inside the app, or import wallpaper folders and zips.
- **Scene Editor (Live)** — change the running wallpaper's layers and effects live on the desktop, record your own screen saver from it, or export it as a Live Photo lock screen for iPhone and iPad.

  ![Scene Editor (Live)](docs/images/scene-editor-live.png)

- **Wallpaper Editor** — an editor in the spirit of Wallpaper Engine's: layers, effects with previews, a timeline, SceneScript, user properties, particles and Puppet Warp. Your edits are kept beside the wallpaper, never in its files.

  ![Wallpaper Editor](docs/images/wallpaper-editor.png)

- **Displays** — a wallpaper per display, one stretched across them or cloned onto each, groups, splits and profiles, as in Wallpaper Engine.

  ![Displays](docs/images/displays.png)

- **Playlists** — change wallpapers on a timer, at login, by time of day or day of week, with Wallpaper Engine's transitions.

  ![Playlist settings](docs/images/playlists.png)

- **Export** — Live Photo lock screens for iPhone and iPad, and Wallpaper Engine's Android packages, sent to the phone over Wi-Fi with a QR code.

  ![Send over Wi-Fi](docs/images/send-over-wifi.png)

- **Theming** — the menu bar, accent colour and tinted folders follow the wallpaper's colours.

  ![Theming](docs/images/theming.png)

- **MCP Server plugin** — MCP clients can set wallpapers, playlists and settings and edit scenes through a local connection only your account can open.

  ![MCP Server plugin](docs/images/mcp-plugin.png)

Everything else, area by area: [docs/features.md](docs/features.md).

## Install

1. Download the latest release from [openwallpaperengine.app](https://openwallpaperengine.app/) or [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). It's signed and notarized, and updates itself.
2. Open the DMG and drag **Open Wallpaper Engine** to Applications.

You need **macOS 14.0 (Sonoma) or later**. Some features need a later macOS, a permission or a plugin: see [Getting started](docs/getting-started.md#requirements).

## Quick start

1. Open the app. The setup assistant sets the language, SteamCMD, your Steam login and the Wallpaper Engine assets; every step can be skipped.
2. Install the Wallpaper Engine assets (*Settings › Assets*) if you want scene wallpapers. They come from your own copy of Wallpaper Engine on Steam; video and web wallpapers work without them.
3. Find wallpapers in the **Workshop** tab, or import a wallpaper folder or zip (*File › Import*).
4. Click a wallpaper in the library, then **Set Wallpaper** in its details. Its properties are listed below it.

More: [Getting started](docs/getting-started.md) and the [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Privacy

Everything the app saves stays on your Mac, and it collects no data or analytics. It contacts Steam (for the Workshop and the assets) and GitHub (for updates), and plugins download only when you install them. Details: [what the app connects to](docs/getting-started.md#what-the-app-connects-to) and the [Privacy Policy](docs/legal/privacy-policy.md).

## Documentation

- [Getting started](docs/getting-started.md) — requirements, assets, the Workshop and importing
- [Features](docs/features.md) — everything the app supports, and how to use it
- Guides: [display layouts](docs/display-layouts.md) · [playlists](docs/playlists.md) · [screen saver](docs/screen-saver.md) · [iPhone & iPad export](docs/iphone-ipad-export.md) · [Android export](docs/android-export.md) · [depth maps](docs/depth-maps.md) · [theming](docs/theming.md) · [MCP Server](docs/mcp.md) · [Chromium web engine](docs/chromium-engine.md)
- [Development](docs/development.md) — building from source and the project layout; [CONTRIBUTING.md](CONTRIBUTING.md) and [architecture](docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — guides, settings reference and troubleshooting

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
