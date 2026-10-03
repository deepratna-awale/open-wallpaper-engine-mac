# Chromium web engine

Web wallpapers run in WKWebView today. Some Workshop web wallpapers expect Chromium (WE ships CEF), so the app can optionally install a Chromium engine: the Chromium Embedded Framework (CEF), downloaded on demand like SteamCMD. Nothing of CEF ships with the app.

This is **phase 1 of 2**:

- **Phase 1 (this):** the installer and updater, the helper process and IOSurface frame sharing, with a debug harness that proves it end to end. No wallpaper uses it yet.
- **Phase 2:** routing web wallpapers to it (a per-wallpaper or global choice), the WE web API (`wallpaperPropertyListener`, user properties, audio and media listeners), input, resize and pausing.

## Architecture

```
Open Wallpaper Engine.app                        (hardened runtime, library validation ON)
├── Settings › Plugins › Chromium web engine     ChromiumEngineSection
├── ChromiumEngineInstaller                      download → verify → unpack → rename
├── ChromiumEngineSession  ◄──── NSXPC ────┐     IOSurface → MTLTexture (no copy)
└── Contents/XPCServices/owe-chromium-helper.xpc (hardened runtime, allow-jit,
                                           │      disable-library-validation)
      main.swift / ChromiumHelperService ──┘     copies CEF's surface into its own ring
      OWECefBridge.m ── dlopen ──► ~/Library/Application Support/Open Wallpaper Engine/
                                     ChromiumEngine/<version>/Chromium Embedded Framework.framework
      CEF renderer / GPU / utility processes = the same helper executable with --type=…
```

| Piece | Where |
|---|---|
| Pins (version → SHA-256) | `OpenWallpaperEngine/Web/Chromium/ChromiumEnginePin.swift` |
| Verify and unpack | `ChromiumEnginePackage.swift` |
| Install, update, prune, remove | `ChromiumEngineInstaller.swift` |
| App end of the XPC connection | `ChromiumEngineSession.swift` |
| Debug harness | `ChromiumFrameCaptureCommand.swift` (Debug builds only) |
| XPC contract (both targets) | `OWEChromiumHelper/ChromiumHelperIPC.swift` |
| Helper | `OWEChromiumHelper/` (target `OWEChromiumHelper`, product `owe-chromium-helper.xpc`) |
| CEF C API headers | `Vendor/cef/include`, the subset the helper includes, copied from the pinned archive (BSD licence in `Vendor/cef/LICENSE.txt`) |

### Install layout

```
<Application Support>/Open Wallpaper Engine/ChromiumEngine/      (isolated copies: "Open Wallpaper Engine (isolated <tag>)")
  <version>/Chromium Embedded Framework.framework
  <version>/LICENSE.txt
  <version>/.owe-chromium-engine.json   written last; a folder without it is not an install
  .state.json                           { active, previous }
  .profile/                             CEF's profile (root_cache_path)
  .staging-<uuid>/                      one install in progress, deleted on exit or next install
```

### Install and update

1. Download `cef_binary_<version>_<platform>_minimal.tar.bz2` from `https://cef-builds.spotifycdn.com/` over HTTPS into `.staging-<uuid>/<name>.partial`, with progress and cancel.
2. Compute its SHA-256 and compare with the pin. **On a mismatch nothing is unpacked** and the staging folder is deleted.
3. Rename `.partial` to the archive name, then clear the quarantine flag from the verified archive only (see below).
4. Unpack only `Release/Chromium Embedded Framework.framework` and `LICENSE.txt` into a scratch folder with `/usr/bin/tar` (bsdtar refuses absolute paths, `..` and writes through symlinks), then assemble `<version>/` inside staging and write the manifest last.
5. Rename into `ChromiumEngine/<version>`. A folder of the same version is set aside first and put back if the rename fails.
6. Record the version as active (the old active one becomes previous) and delete every other version folder. **Only the current and previous versions are kept.**

Updates follow the app: each release pins one build per architecture. When the pin differs from the active install, Settings shows *Update available*. There is no "latest" and no unpinned download. The app ships universal, so both `macosarm64` and `macosx64` are pinned and the host architecture's pin is used.

Pinned now: CEF `154.0.33+ga03e714+chromium-154.0.8037.94` (Chromium 154.0.8037.94).

| Platform | Download | Unpacked | SHA-256 |
|---|---|---|---|
| macosarm64 | 132.2 MB | 337.8 MB | `6de789c942ae948596b1b0c60d72503c0e126f368abdd4fee530e8eaa3776814` |
| macosx64 | 138.7 MB | 358.8 MB | `b1cf9e159b798323ffd17b457dfc410ea3ee192868eb73061f25447865d4fe1a` |

The SHA-1 of both archives matched the CDN's `index.json` when they were pinned.

**To pin a new build:** download both minimal archives, check their SHA-1 against `index.json`, compute `shasum -a 256`, update `ChromiumEnginePin.pinned`, copy the same version's headers into `Vendor/cef/include` (the files `OWECefBridge.m` includes, found with `clang -MD`), and set `CEF_API_VERSION` in the helper's build settings to the new `CEF_API_VERSION_LAST`. The helper checks at run time that `cef_api_hash` agrees with the headers and refuses to start otherwise.

### Frame sharing

- The helper creates one windowless browser (`windowless_rendering_enabled`, `shared_texture_enabled`) with an external message pump on its main run loop.
- CEF calls `OnAcceleratedPaint` with an IOSurface from its own pool, which goes back to the pool when the callback returns. The helper therefore blits it on the GPU into one of three IOSurfaces it owns, waits for the copy, and sends that surface.
- The message is `ChromiumFrameMessage` (an `IOSurface` plus a frame number) over NSXPC. XPC sends an IOSurface as a Mach port: the pixels are never copied between processes.
- The app wraps the surface with `device.makeTexture(descriptor:iosurface:plane:)`. Frames that aren't BGRA, are over 16384 px or have no frame number are dropped.

**Debug harness** (Debug builds):

```sh
"Open Wallpaper Engine.app/Contents/MacOS/Open Wallpaper Engine" \
  --chromium-capture https://example.com 30 /tmp/frame.png 1280x720
```

It starts the embedded helper on the installed engine, waits for 30 frames and writes the last one as a PNG. Set `OWE_CEF_NO_SANDBOX=1` (Debug builds only) to tell a sandbox problem from anything else.

## Security model

- **Integrity of the download:** HTTPS from Spotify's CEF CDN (the official CEF binary host) plus a SHA-256 pinned in the signed app. A changed or truncated file is refused before anything is unpacked. This is stronger than SteamCMD's trust (audit L9), which has no hash.
- **Quarantine:** files the app downloads with URLSession are not quarantined, so normally there is nothing to clear. If the archive does carry the flag, it is removed from **that verified archive only**, before unpacking, so tar has no flag to copy onto the files. Nothing is cleared wholesale, and no file that wasn't verified is touched.
- **CEF never loads into the app.** The app keeps hardened runtime with library validation. CEF runs only in `owe-chromium-helper`, an XPC service embedded in the app and signed with it. Only the containing app can connect to an embedded XPC service.
- **Helper entitlements** (`OWEChromiumHelper/OWEChromiumHelper.entitlements`), each needed:
  - `com.apple.security.cs.disable-library-validation`: the helper `dlopen`s the CEF framework the app downloaded. CEF's official build is not signed by our team (the arm64 binaries are linker-signed ad hoc, the x86_64 ones unsigned), so library validation would refuse it. The alternative, re-signing CEF with our Developer ID on the user's Mac, isn't possible, and shipping CEF in the app would add about 330 MB to every download for an optional feature. The exception is on the helper only, never the app, and the release workflow fails if the app ever carries it.
  - `com.apple.security.cs.allow-jit`: V8 generates code at run time (`MAP_JIT`). Chrome's own renderer helper has the same entitlement.
  - `com.apple.security.network.client`: wallpapers may load remote content.
- **No re-signing needed:** Apple silicon only requires a valid signature to run code, and CEF's arm64 binaries already carry linker-signed ad-hoc signatures. A process with library validation off may load them. CEF's helper apps (GPU, Renderer, Plugin) are not used: the minimal distribution doesn't ship them, and CEF starts our own helper executable (`browser_subprocess_path`) for every subprocess. That executable is already signed with the app, so nothing downloaded needs `codesign -s -`. If a future CEF drops its linker signature, ad-hoc signing the verified framework after unpacking is the fallback.
- **CEF's sandbox stays on.** Subprocesses enter it through `libcef_sandbox.dylib` from the framework before CEF loads, the way `CefScopedSandboxContext` does. Debug builds can turn it off with `OWE_CEF_NO_SANDBOX=1`.
- **On-disk trust after install:** the install folder is in the user's Application Support, writable by any process running as the user. Such a process could already change the user's login items or shell profile, so this adds no new privilege boundary. It is the same trust as SteamCMD's copy.
- **Profile:** cookies and caches stay in `ChromiumEngine/.profile`. Session cookies are not persisted, and Remove deletes the profile with the engine.

## Sizes

| | arm64 | x86_64 |
|---|---|---|
| Download | 132 MB | 139 MB |
| On disk, one version | 338 MB | 359 MB |
| On disk, during an update (current + previous) | up to ~680 MB | up to ~720 MB |
| Helper in the app bundle | well under 1 MB | |
| Vendored headers in the repo | under 1 MB | |

## Phase 2 plan

1. **Routing:** add a web engine choice (global plus per-wallpaper override) in `WebWallpaperViewModel`. When Chromium is chosen and installed, render with `ChromiumEngineSession` frames in a `CAMetalLayer` instead of WKWebView.
2. **WE web API:** inject the same bridge scripts as `WebWallpaperPropertyBridge` / `WebWallpaperMediaBridge` through a CEF render-process handler and process messages. Deliver user properties, `wallpaperRegisterAudioListener` spectra from `Audio/` and media metadata.
3. **Local content:** serve the wallpaper folder through a CEF scheme handler, mirroring `WebWallpaperSchemeHandler`'s path checks.
4. **Lifecycle:** resize (`was_resized`), pause (`was_hidden`, frame rate 0), one browser per display, crash relaunch, and a proper `cef_shutdown`.
5. **Input:** forward mouse events for interactive wallpapers.
6. **Frame pacing:** drive `send_external_begin_frame` from the display link instead of CEF's own timer.
7. **Auto-update:** once wallpapers depend on it, install a new pin in the background when the previous version was installed.
