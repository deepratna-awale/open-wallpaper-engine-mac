# Security Policy

## Supported versions

Open Wallpaper Engine is in beta. Security fixes go into the next release only; older builds are not patched.

| Version | Supported |
|---|---|
| Latest 1.0.0 beta (1.0.0-beta.12 today) | ✅ |
| Older betas | ❌ Update first |

The app updates itself through Sparkle. To get a fix, choose **Check for Updates…** in the app menu (⌥⌘U), or download the latest release from [openwallpaperengine.app](https://openwallpaperengine.app/) or [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). Every release is a beta, so keep **Receive beta updates** on in Settings → Updates; with it off, Sparkle offers no update until a stable release is out.

## Reporting a vulnerability

Please report security problems **privately**, not in public issues, pull requests or discussions.

[Report a vulnerability](https://github.com/deepratna-awale/open-wallpaper-engine-mac/security/advisories/new) through GitHub's private vulnerability reporting (the repository's **Security** tab → **Report a vulnerability**). Only the maintainers can see the report. Please include:

- the version of Open Wallpaper Engine (in About Open Wallpaper Engine) and of macOS;
- what an attacker can do, and what they need first (for example, a user who subscribes to a crafted wallpaper);
- steps or a minimal wallpaper that reproduces it.

You'll get a reply in the advisory as soon as possible. Please give us reasonable time to ship a fix before you disclose it publicly. Once the fix is released, the advisory is published, crediting you unless you'd rather not be named.

## Scope

In scope:

- the app, its screen saver, helpers and plugins in this repository;
- how it handles wallpapers: every wallpaper (scene, web, video, `.pkg` or loose files, from the Workshop or imported) is treated as untrusted input, so escaping the wallpaper sandbox, reading or writing files outside the wallpaper, or running code from a wallpaper is a vulnerability;
- updates: the Sparkle feed (`appcast.xml`), update signing and the release pipeline (GitHub Actions workflows, signing and notarization);
- the openwallpaperengine.app site.

Out of scope: Steam, Wallpaper Engine, macOS and third-party wallpapers, which belong to their own owners and go to them. A wallpaper that is merely heavy, ugly or crashes the renderer is a normal bug; please open an issue for it.
