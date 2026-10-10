# Features

Everything Open Wallpaper Engine does, by area. The [README](../README.md) has the highlights.

## Supported wallpaper types

| Type | Status |
|------|--------|
| Video (.mp4, .webm) | Working |
| Web (HTML/WebGL) | Working (WebKit, or the optional Chromium engine) |
| Scene — image layers & timelines | Working (Metal) |
| Scene — DXT1/DXT3/DXT5 textures | Working (Metal GPU decode) |
| Scene — TEXS sprites / alpha timelines | Working |
| Scene — sprite particles | Working |
| Scene — advanced particles | Working |
| Scene — Wallpaper Engine and Workshop effects (WE's own shaders) | Working |
| Scene — SceneScript | Working |
| Scene — 3D models / rigging / puppet warp | Working |
| Application | Not supported |

## Using the features

### Edit Wallpapers

- **Scene Edit / Export** (Details › Scene Edit / Export, ⌥⌘I) has four tabs, and every export happens there. **Wallpaper** edits the running wallpaper: show, hide, move, resize, recolour and fade layers and change effects, live on the desktop. **Screen Saver** records a version of the wallpaper as your screen saver ([docs/screen-saver.md](screen-saver.md)). **iPhone & iPad Export** turns it into a Live Photo lock screen ([docs/iphone-ipad-export.md](iphone-ipad-export.md)). **Android Export** writes it as a package for Wallpaper Engine's Android app ([docs/android-export.md](android-export.md)). A video wallpaper opens it on its screen saver and export tabs.
- **Wallpaper Editor** (Edit Wallpaper in the library's bottom bar, ⌥⌘E) is an editor in the spirit of Wallpaper Engine's, running as an app of its own: add, arrange and group layers; add effects and particle systems from Wallpaper Engine's catalogs, with previews the app renders in the background once its assets are installed; animate on a timeline; write SceneScript with autocomplete; author user properties; edit particle systems and Puppet Warp rigs. The editor works on a draft: edits show in its canvas and can all be undone, and nothing else runs them (the desktop, the screen saver, playlists) until **File › Save** (⌘S), which every display showing the wallpaper then shows; **Save as New Wallpaper** (⇧⌘S) adds a new wallpaper with them to the library instead, and **Revert to Saved** goes back to the last save. Closing or quitting with unsaved changes asks to save them, and a draft survives a crash: the editor offers to resume it. Edits are kept beside the wallpaper, never in its files.
- **Depth maps** — with the Depth Map Generation plugin, both editors make a depth map of a layer or the whole scene on your Mac and apply Wallpaper Engine's Depth Parallax effect to it ([docs/depth-maps.md](depth-maps.md)).

### Several Displays

**Displays** in the toolbar sets Wallpaper Engine's display layouts: a wallpaper per display, one stretched across every display, or one cloned onto every display, plus stretch and clone groups of some displays, flipped clones, muted displays and displays split into regions, saved as profiles. A clone or stretch renders once. Each display has a miniature of what it shows. [docs/display-layouts.md](display-layouts.md)

### Export to iPhone, iPad and Android

- **iPhone & iPad** — Scene Edit / Export's iPhone & iPad Export tab frames a scene or a video as any of 63 iPhones' and iPads' lock screens and exports a Live Photo, with AirDrop, to a folder or into a Photos album, without changing your desktop. **Export More with These Settings…** makes Live Photos of other wallpapers from the library in one batch, with **AirDrop All**. [docs/iphone-ipad-export.md](iphone-ipad-export.md)
- **Android** — Scene Edit / Export's Android Export tab writes Wallpaper Engine's `.mpkg` packages for its Android app: scenes as live **Dynamic** scenes or a **Pre-Rendered** video, videos byte for byte as they are. **Export More with These Settings…** packs other wallpapers from the library in one batch, and **Send over Wi-Fi** lets the device download them from the Mac with a QR code. [docs/android-export.md](android-export.md)

### Theme macOS

Settings › General › **Theming** lets the menu bar, the accent and highlight colours, tinted icons and folders follow the scheme colour of the wallpaper on the main display, and restores your own colours when it's turned off. [docs/theming.md](theming.md)

### Control from MCP Clients

Install the **MCP Server** plugin in *Settings › Plugins* and MCP clients (AI assistants and other tools that speak the Model Context Protocol) can do what the app's own controls do, through a local connection only your account can open: set wallpapers, playback, volume, user properties, playlists and settings; edit scenes through the Wallpaper Editor's edit model (in its draft, shown in an open editor window, with Undo, and on the displays once saved); export Live Photos; and set up the screen saver and the lock-screen picture. Setup, every tool and the security model: [docs/mcp.md](mcp.md).

## Everything that is supported

### Setup, library & updates
- **Setup assistant** — on first launch, a few skippable steps set the language, show the privacy notes, set up SteamCMD, the Steam login and an optional Steam Web API key, install the Wallpaper Engine assets and bring in your wallpapers.
- **SteamCMD sets itself up** — when none is found, the app downloads Valve's SteamCMD; Homebrew's or Steam's is used if present.
- **Wallpaper Engine assets from your own Steam copy** — installed through SteamCMD after you sign in, optionally with Wallpaper Engine's default wallpapers.
- **Imports** — your Workshop collections and subscriptions (read from Steam's Web API), the Workshop items of an existing Steam library, and wallpaper folders.
- **Wallpaper Engine favourites** — Wallpaper Engine keeps its favourites in your Steam account (they are your Workshop favourites), not in its folder. Once the assets are installed or a Wallpaper Engine folder is chosen, the setup assistant and Settings › Assets ask whether to add them to My Favourites, showing how many are new; your current favourites stay, and importing again adds only new ones. It needs your Steam Web API key and the account's SteamID, found in Steam's own files for the SteamCMD login or for the Steam folder the chosen Wallpaper Engine install is in. *Import Wallpaper Engine Favourites…* in Settings › Assets checks again.
- **The [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — guides, settings reference and troubleshooting; Support & FAQ in the app opens it.
- **Automatic updates** — signed updates install by themselves (on quit, after 10 minutes away, or within a day, then a quick relaunch restores your wallpapers). Settings › Updates lets you only check, or turn checks off, and opt into beta updates. Check for Updates… is in the app menu and the menu bar menu.

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
- **Display layouts** — per display, stretch, clone, groups, flip, mute, splits and profiles, as in Wallpaper Engine ([docs/display-layouts.md](display-layouts.md)).
- **Pause per Display** or **Pause All**, with the playback rules checked for each display, including Wallpaper Engine's maximized-window rule.
- **Application Rules** — pause, stop or mute wallpapers, or load a wallpaper, playlist or display profile, while an app is running, focused, maximized, in full screen or playing audio.
- **Playlists** as in Wallpaper Engine: change wallpaper on a timer, at login, by time of day or by day of week; begin with the first wallpaper, an intro played at startup only, changing while paused; and Wallpaper Engine's 27 **transitions** between wallpapers (or a random one), drawn on the GPU, also for wallpapers chosen in the library ([docs/playlists.md](playlists.md)).
- **Hotkeys** for Wallpaper Engine's actions (including Stop wallpapers) and for each playlist, system-wide, with no Accessibility permission; **Next and Previous Wallpaper** in the menu bar menu.
- **Stop Wallpapers** (menu bar menu, Playback menu, a hotkey): unloads every wallpaper, freeing its CPU, GPU and memory, and shows the macOS desktop picture until Resume.
- **Take Screenshot** of the wallpaper alone, at the display's size, 4K or 8K.
- Per-wallpaper **position, zoom and flip** on each display, and a video's playback rate.
- Per-display user properties, with "Sync properties across displays".
- A wallpaper shown on several displays renders once and is presented on each.
- Quality settings: Render Resolution (Your Display, 4K, Full) with Upscaling (Render Scale 50–75 %), Texture Resolution, Effect Detail (Match Display), reflections, shadows and volumetrics.
- **Safe restart** — a wallpaper that stalled or crashed the app is skipped on the next launch and marked in the library.

### Screen saver, lock screen & theming
- **Screen saver** — a plugin records a seamless loop of a scene, web or WebM wallpaper (videos play their own file) and installs a macOS screen saver that plays it; Scene Edit / Export's Screen Saver tab records your own version and can re-record it daily ([docs/screen-saver.md](screen-saver.md)).
- **Lock screen** — each display's desktop picture, which the lock screen shows, is a picture of its wallpaper.
- **Theming** — the menu bar, accent, tinted icons and folders follow the wallpaper's colour ([docs/theming.md](theming.md)).

### Workshop & library
- Wallpaper Engine's Workshop filters: Show Only, a resolution filter, genres combined with AND/OR, a Wallpaper/Preset category, and tags on every card.
- **Discover** — Wallpaper Engine's curated Workshop lists; Workshop items can be blocked (or their author), reported in Steam, and lead to related wallpapers.
- **Workshop preset items** play their base wallpaper with the preset's values, as in Wallpaper Engine.
- **Library folders** — add folders of wallpapers beside Wallpaper Storage (Settings › Assets); they're watched and never written to.
- **Animated previews** — wallpaper tiles in the library play their Workshop preview animation (GIF), so you can see a wallpaper move before applying it. They play only while visible, and pause when the window is hidden or in Low Power Mode.
- Installed wallpapers show and filter by their Workshop tags; asset-only and dependency-only items stay out of Installed.
- Missing Workshop dependencies download automatically, and unused ones are removed after a delete. Every download lands in the Wallpaper Storage folder.
- **Reset** in Details returns a wallpaper's properties, and its scene edits, to the defaults its author set.
- **iPhone & iPad Export** in Scene Edit / Export turns a scene or video wallpaper into a Live Photo lock screen for any iPhone or iPad that shows one, with AirDrop, to a folder or into a Photos album, without changing your desktop, one wallpaper or a batch.
- **Android Export** in Scene Edit / Export writes Wallpaper Engine's `.mpkg` packages for its Android app, one wallpaper or a batch, sent to the device over Wi-Fi or copied.
- Property conditions, text rows and slider formats from the wallpaper's settings are honoured.
- Steam passwords are never stored, and the Steam Web API key is kept in the Keychain.

### Interface & languages
- **Liquid Glass** on macOS 26 — a native split view, toolbar and inspector with glass controls. Earlier macOS versions keep the familiar look.
- **15 languages besides English**: German, French, Spanish, Brazilian Portuguese, Italian, Japanese, Korean, Simplified and Traditional Chinese, Russian, Polish, Turkish, Ukrainian, Arabic and Hindi, chosen from the Language picker in Settings.
- A new app icon, and a menu bar icon that follows the menu bar's appearance.
