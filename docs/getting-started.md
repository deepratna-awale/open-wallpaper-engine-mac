# Getting started

Installing the app, the optional requirements, the Wallpaper Engine assets and bringing in wallpapers. The [README](../README.md) has the short version.

## Requirements

- **macOS 14.0 or later** (Sonoma).

### Optional — needed for specific features

| Feature | Requirement | Install |
|---------|-------------|---------|
| Browsing / downloading from Steam Workshop | `steamcmd` | Automatic (optional: `brew install steamcmd`) |
| Audio visualizers & audio-reactive SceneScript | System Audio Recording permission (Screen & System Audio Recording before macOS 14.2) | Settings → Permissions |
| App Rules' "Is playing audio" condition | macOS 14.2 or later | — |
| Now Playing in wallpapers | macOS 15.4 or later for live updates | — |
| Web wallpapers that need Chromium | The optional Chromium web engine | Settings → Plugins |
| Depth maps in the editors | The Depth Map Generation plugin | Settings → Plugins |
| Control from MCP clients | The MCP Server plugin | Settings → Plugins |
| Live Photo lock screens | iPhone or iPad with iOS / iPadOS 17 or later | — |
| Android export | Wallpaper Engine's Android app on the device | — |

## Wallpaper Engine assets

Scenes use Wallpaper Engine's shared effects, materials, shaders, fonts and SceneScript runtime from your own Wallpaper Engine copy on Steam; the app doesn't ship them. Install them in *Settings → Assets*: the app downloads your copy with steamcmd (the account must own Wallpaper Engine), keeps only the assets and the default wallpapers, and deletes the rest. You can also choose an existing Wallpaper Engine folder. Video and web wallpapers work without them.

## Wallpapers

### Browse & Download from Steam Workshop

1. Nothing to install: the app downloads Valve's SteamCMD in the background the first time it's needed (from Valve, not bundled). Homebrew (`brew install steamcmd`) is optional; an existing steamcmd (Homebrew, Steam, or one you pick) is used if found
2. Switch to the **Workshop** tab and log in with your Steam account (must own Wallpaper Engine)
3. Enter a [Steam Web API key](https://steamcommunity.com/dev/apikey) when prompted, or in *Settings → General*. It is checked with Steam and kept in your keychain; your Steam password is never stored (steamcmd reuses its own cached session)
4. Search, filter, and click **Download** on any wallpaper

### Import from Local Files

- **Folder:** File > Import > Wallpaper from Folder — select wallpaper folders containing `project.json`
- **Zip:** File > Import or drag-and-drop a `.zip` file containing wallpaper packages
- **Manual:** Copy wallpaper folders directly into `~/Documents/Open Wallpaper Engine/`

## What the app connects to

Everything Open Wallpaper Engine saves stays on your Mac: your settings, library, cache and SteamCMD's login. Open Wallpaper Engine has no server and collects no data or analytics. It contacts Valve (Steam when you use the Workshop or install assets, and Valve's server to download SteamCMD) and GitHub, to check for app updates (the appcast on GitHub Pages) and download them from GitHub Releases, without sending any personal data. Update checks can be turned off in Settings › Updates. Optional plugins download only when you install them: the Chromium web engine from the Chromium Embedded Framework's builds, and the depth model from Apple's Hugging Face repository, each checked against the version the app expects. Send over Wi-Fi serves an Android export only to devices on your local network, for 15 minutes. Web wallpapers may load their own online content. Your Steam password and Steam Guard code go straight to SteamCMD and are never stored, logged or sent anywhere else; only your account name is remembered, to reuse SteamCMD's saved login.
