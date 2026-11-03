# Development

Building from source and where the code lives. Read [CONTRIBUTING.md](../CONTRIBUTING.md) for the rules and [architecture.md](architecture.md) for the module layout.

## Build from source

### Prerequisites
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK). The code is Swift 6 language mode; CI builds with Xcode 26.3 (Swift 6.2), which is stricter than newer Xcodes about some concurrency checks, so see CONTRIBUTING.md › Building for checking with CI's compiler.
- Xcode Command Line Tools
- Optional: the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0), to build the Steam helper (`Scripts/build-steam-helper.sh`). Without it, `Scripts/build-steam-helper.sh --download` takes the copy CI built from `main` (needs the `gh` CLI, signed in); without either, the app builds and runs but can't sign in to Steam.

### Steps
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

In Xcode, change the signing certificate to your own or select "Sign to Run Locally", then press `Cmd + R` to build and run.

Building from source fetches the Sparkle Swift package on first build. Builds from source don't check for updates.

## Shaders

Wallpaper Engine ships its effects as GLSL. They are translated to Metal (GLSL → SPIR-V → MSL) by glslang and SPIRV-Cross, which are built into the app (`Vendor/ShaderToolchain`), the first time a wallpaper uses them, then cached on disk. Nothing needs to be installed. A shader whose translation hung the app, or crashed it twice, is skipped on later launches, and every other shader still translates.

## Project layout

- `OpenWallpaperEngine/Scene/Format/` — PKG, TEX/TEXS, and scene.json parsers and models
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL translation (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), caching and the pipeline archive; `FrontEnd/` is the HLSL front end (WE's dialect as GLSL, [architecture](architecture.md#shader-translation))
- `Vendor/ShaderToolchain/` — glslang and SPIRV-Cross sources, built into the app as a local package
- `Vendor/ufbx/` — ufbx (FBX and OBJ loader, MIT), a local package the Wallpaper Editor's model import uses
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript runtime and audio/FFT bindings
- `OpenWallpaperEngine/Audio/` — system audio capture (`SystemAudioCapture.swift`, `ProcessTapAudioCapture.swift`, `SystemAudioBackend.swift`) and the per-player level tap (`AudioLevelTap.swift`)
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — the Metal scene renderer and shader library
- `OpenWallpaperEngine/Workshop/` — the Steam login (`SteamAccount.swift`, `SteamLogin.swift`, `SteamSignInView.swift`), the helper's client (`SteamHelperClient.swift`, `SteamHelperDownload.swift`), Workshop browsing and downloads (`WorkshopAPIService.swift`, `WorkshopDownloadService.swift`, `WorkshopViewModel.swift`), subscriptions, favourites, comments and update checks
- `SteamHelper/` — `owe-steam-helper`, the .NET program the app runs for every Steam request (QR or password sign-in, Workshop queries, downloads, the assets); its protocol and licence (GPL-2.0-or-later) are in [SteamHelper/README.md](../SteamHelper/README.md). `Vendor/DepotDownloader/` is the download code it includes
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — library storage, import, and package conversion
- `OpenWallpaperEngine/Library/DisplayLayout/` — display layouts, groups, splits and profiles ([docs/display-layouts.md](display-layouts.md))
- `OpenWallpaperEngine/Editor/`, `Packages/OWEEditor/` — the Wallpaper Editor
- `OpenWallpaperEngine/ScreenSaver/`, `OpenWallpaperEngineSaver/` — screen saver loops and the screen saver itself ([docs/screen-saver.md](screen-saver.md))
- `OpenWallpaperEngine/LivePhoto/`, `OpenWallpaperEngine/AndroidExport/` — iPhone & iPad and Android export ([docs/iphone-ipad-export.md](iphone-ipad-export.md), [docs/android-export.md](android-export.md))
- `OpenWallpaperEngine/DepthMaps/` — the Depth Map Generation plugin ([docs/depth-maps.md](depth-maps.md))
- `OpenWallpaperEngine/Theming/`, `Packages/OWETheming/` — Theming ([docs/theming.md](theming.md))
- `OpenWallpaperEngine/MCP/`, `Packages/OWEControl/`, `MCPServer/` — the MCP Server plugin: the app's control socket and the `owe-mcp` server ([docs/mcp.md](mcp.md))
- `OWESaverBroker/`, `OpenWallpaperEngineSaverExtension/` — the live screen saver's launcher and extension; `OWEChromiumHelper/` — the Chromium web engine's XPC service; `EditorHelper/` — the Wallpaper Editor app's bundle files ([architecture](architecture.md#targets))
- `Scripts/build-steam-helper.sh` — builds the Steam helper into `build/steam-helper/` (`--download` fetches CI's build instead)
- `Scripts/fill-assets-cache.sh` — development helper: copies the assets subset of a Wallpaper Engine install into a local folder or the Wallpaper Storage cache
- `Scripts/scene-api-coverage.py` — reports which SceneScript APIs installed wallpapers use versus what is implemented
