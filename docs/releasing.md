# Releasing

`.github/workflows/release.yml` builds the app, signs it with **Developer ID** under the
**hardened runtime**, **notarizes** and **staples** it, and attaches a zip, a DMG, SHA-256
sums and the zip's Sparkle signature to a **draft** GitHub release. Downloads open on any Mac
without a Gatekeeper warning.

Publishing the draft runs `.github/workflows/appcast.yml`, which adds the release to the
**Sparkle** update feed, `site/appcast.xml`, served by GitHub Pages at
<https://deepratna-awale.github.io/open-wallpaper-engine-mac/appcast.xml>. Installed copies
update themselves from it (Settings › General › Updates).

## One-time setup: repository secrets

CI's asset tests use their own Steam secrets (`OWE_CI_STEAM_*`); see [ci-assets.md](ci-assets.md).

Add these under *Settings → Secrets and variables → Actions → New repository secret*, or with
`gh secret set` as shown below. Each workflow's first step fails with a list of whatever is
missing.

| Secret | What it is |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | *Developer ID Application* certificate + private key, `.p12`, base64 |
| `P12_PASSWORD` | the password you gave the `.p12` on export |
| `KEYCHAIN_PASSWORD` | any random string; locks the runner's throwaway keychain |
| `DEVELOPMENT_TEAM` | your 10-character Team ID (developer.apple.com → Membership) |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID (UUID) |
| `ASC_KEY_P8_BASE64` | the key's `AuthKey_<ID>.p8`, base64 |
| `USER_PAT` | GitHub token with `contents: write` on this repo: publishes the release, uploads the update deltas and pushes `site/appcast.xml` to `main` |
| `SPARKLE_PRIVATE_KEY` | Sparkle's EdDSA private key (`generate_keys -x`); signs every update |
| `SPARKLE_PUBLIC_ED_KEY` | its public key; built into the app as `SUPublicEDKey` |

Fallback instead of the three `ASC_*` secrets: `APPLE_ID` (Apple ID email) and
`APPLE_APP_PASSWORD` (app-specific password from appleid.apple.com → Sign-In and Security).
The API key is preferred: it does not depend on a person's Apple ID or 2FA.

`USER_PAT` pushes the appcast commit: a push made with the workflow's own `GITHUB_TOKEN` would
not start the Pages workflow. If `main` is protected, the token's owner must be allowed to push
to it (or add the appcast commit by hand, see *Appcast* below).

### Developer ID certificate (.p12)

Needs a paid Apple Developer Program membership; only the Account Holder can create a
Developer ID certificate. An *Apple Development* certificate is **not** enough.

1. Xcode → Settings → Accounts → your team → *Manage Certificates…* → **+** →
   *Developer ID Application*. (Or developer.apple.com → Certificates → **+** →
   *Developer ID Application* with a CSR from Keychain Access.)
2. Keychain Access → *login* → *My Certificates* → right-click
   “Developer ID Application: *Name* (*TEAMID*)” → *Export…* → `.p12`, set a password.
   Export from *My Certificates* so the private key is included.
3. `base64 -i DeveloperID.p12 | pbcopy` → paste as `BUILD_CERTIFICATE_BASE64`.
   Store the password as `P12_PASSWORD`. Delete the `.p12` file afterwards.

Check locally: `security find-identity -v -p codesigning` lists
`Developer ID Application: … (TEAMID)`.

### App Store Connect API key

1. appstoreconnect.apple.com → Users and Access → *Integrations* → *App Store Connect API* →
   *Team Keys* → **+**. Name it (e.g. “OWE notarization”), access **Developer**.
2. Download `AuthKey_<KEYID>.p8` (only once). Note the **Key ID** and the **Issuer ID**
   shown above the table.
3. `base64 -i AuthKey_<KEYID>.p8 | pbcopy` → `ASC_KEY_P8_BASE64`; Key ID → `ASC_KEY_ID`;
   Issuer ID → `ASC_ISSUER_ID`.

### Sparkle update keys

Updates are signed with an EdDSA (ed25519) key pair. The app carries the public key and
rejects any update the private key didn't sign, so **keep the private key safe and never lose
it**: a new key pair can't update copies that carry the old public key. Create it once, on your
Mac, with the tools from the Sparkle release the app links (2.10.0, see
`Scripts/release/fetch-sparkle-tools.sh`):

```sh
set -euo pipefail
cd "$(mktemp -d)"
curl -fsSLO https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  Sparkle-2.10.0.tar.xz" | shasum -a 256 -c -
tar -xf Sparkle-2.10.0.tar.xz ./bin

# 1. Creates the key pair (the private key goes into your login Keychain, item
#    "Private key for signing Sparkle updates") and prints the public key.
./bin/generate_keys

# 2. The public key → SPARKLE_PUBLIC_ED_KEY.
./bin/generate_keys -p | gh secret set SPARKLE_PUBLIC_ED_KEY --repo deepratna-awale/open-wallpaper-engine-mac

# 3. The private key → SPARKLE_PRIVATE_KEY, through a file that you trash right after.
./bin/generate_keys -x private.key
gh secret set SPARKLE_PRIVATE_KEY --repo deepratna-awale/open-wallpaper-engine-mac < private.key
trash private.key        # or: rm -P private.key
```

The login Keychain keeps the private key; back it up (e.g. export it to a password manager).
`release.yml` checks that `SPARKLE_PUBLIC_ED_KEY` is the public key of `SPARKLE_PRIVATE_KEY`
before building, so a mismatched pair fails the run instead of shipping an app that rejects its
own updates. The private key only ever reaches `sign_update` and `generate_appcast` on stdin
(`--ed-key-file -`); it is never written to disk or printed.

**Where the public key goes:** `OpenWallpaperEngine-Info.plist` has
`SUPublicEDKey = $(SPARKLE_PUBLIC_ED_KEY)`, a build setting that is empty in the project and
set on the `xcodebuild archive` command line by `release.yml`. Debug and local builds therefore
have no key, and `AppUpdateConfiguration.isConfigured` is false: the updater never starts, the
menu items are disabled and Settings says updates are off in this build. `OWEVersionLabel`
works the same way (`$(OWE_VERSION_LABEL)`, defaulting to `$(MARKETING_VERSION)`).

## Cutting a release

Tags decide everything:

| Tag | `CFBundleShortVersionString` | Label (`OWEVersionLabel`, appcast `shortVersionString`) | GitHub release | Update channel |
| --- | --- | --- | --- | --- |
| `v1.2.0` | 1.2.0 | 1.2.0 | draft | everyone |
| `v1.2.0-beta.1` | 1.2.0 | 1.2.0-beta.1 | draft, **pre-release** | `beta` only |
| `v1.2.0-rc.1` | 1.2.0 | 1.2.0-rc.1 | draft, **pre-release** | `beta` only |
| `v1.2.0-alpha.1` | 1.2.0 | 1.2.0-alpha.1 | draft, **pre-release** | `beta` only |

`CFBundleVersion` is the workflow run number, so it always increases; Sparkle compares
builds by it. Anything else (`v1.2`, `v1.2.0-preview.1`, leading zeros) fails the run
(`Scripts/release/release-version.sh`, tested by `Scripts/release/test-release-version.sh`).

```sh
# A beta, then a release candidate, then the release, all from main:
git tag v1.1.0-beta.1 && git push origin v1.1.0-beta.1
git tag v1.1.0-rc.1   && git push origin v1.1.0-rc.1
git tag v1.1.0        && git push origin v1.1.0
```

Or *Actions → Release → Run workflow* with `tag` = an **existing** tag (the workflow checks
out that tag).

The run: check secrets → check out → parse the tag → check the Sparkle key pair → import the
certificate into a temporary keychain → archive (manual signing, hardened runtime,
`--timestamp`, no `get-task-allow`, `SPARKLE_PUBLIC_ED_KEY` and `OWE_VERSION_LABEL` set) →
export (`developer-id`) → verify every Mach-O is Developer ID + runtime + timestamp, the
version, label, `SUPublicEDKey` and `SUFeedURL`, and that the only executables besides the app
are Sparkle's → notarize the app (`notarytool submit --wait`; on failure it prints
`notarytool log`) → staple → zip → DMG (signed, notarized, stapled) → verify with
`codesign`, `spctl` and `stapler validate` → sign the zip with `sign_update` into
`<zip>.sparkle.json` → draft release named *Open Wallpaper Engine 1.1.0 Beta 1* (for
`v1.1.0-beta.1`). The keychain and the API key file are deleted in an `always()` step.

Review the draft on GitHub, edit the notes (they become the update's release notes), then
*Publish*. **Draft + pre-release** is deliberate: GitHub lets a draft carry the pre-release
flag, it stays a pre-release when published, `releases/latest` and the stable update channel
skip it, and the `release: published` event that runs the appcast fires for pre-releases too.
Nothing reaches users until you publish.

The site's Download button shows the newest *published* release, pre-releases included
(labelled e.g. “Download 1.1.0 Beta 1 (beta)”), falling back to `releases/latest` and then to
the static releases link.

## Appcast (updates)

`appcast.yml` runs when a release is published (or by hand with its tag, to redo it):

1. Downloads the release's zip and `<zip>.sparkle.json`, and the full zips of the three newest
   items already in `site/appcast.xml` (`Scripts/release/appcast.py previous`).
2. Runs Sparkle's `generate_appcast` on them with `SPARKLE_PRIVATE_KEY`: it signs the new zip
   and makes **binary deltas** (`.delta`) from each older build to the new one, keeping a
   delta only when it is clearly smaller than the zip.
3. Checks that its signature and length for the new zip equal the release job's.
4. Converts the release notes (Markdown) to HTML through GitHub's API.
5. `appcast.py merge` takes the new item, points its enclosure and deltas at the release's
   assets (the deltas are renamed `OpenWallpaperEngine-<label>-from-<build>.delta` and
   uploaded to the release), sets `sparkle:shortVersionString` to the label,
   `sparkle:minimumSystemVersion` 14.0, `sparkle:channel` `beta` for a pre-release, the notes
   as the item's `description`, and the release page as `sparkle:fullReleaseNotesLink`, and
   puts it first in `site/appcast.xml` (replacing an item of the same build).
6. Commits `site/appcast.xml` to `main` as `chore(appcast): <label>`; the push deploys Pages.

A copy that finds the update downloads the smallest thing that applies: a delta from its own
build when there is one, otherwise the full zip. Deltas are made from the stapled, notarized
apps inside the published zips, so the patched app is byte-for-byte the notarized one, and
Sparkle checks its signature before installing it. Older releases stay in the feed; only the
newest release gets deltas.

**Channels:** pre-release items carry `<sparkle:channel>beta</sparkle:channel>`. The app asks
for the `beta` channel only when *Receive beta updates* is on, which it is by default on a
pre-release build (`AppUpdateConfiguration.allowedChannels`). Items without a channel reach
everyone.

**Fixing the feed by hand:** edit `site/appcast.xml` on `main` (keep each item's
`sparkle:edSignature` and `length`; they sign the archive, not the XML) and push, or re-run
*Actions → Appcast* with the tag.

## Updating installed copies

- **Update automatically** (on by default) checks daily, downloads in the background and
  installs: on quit, or once the Mac has been idle for 10 minutes, or at the latest a day after
  the download (`PendingUpdateInstallPolicy`). The relaunch takes a few seconds and restores
  the wallpapers, and the windows, tab and Settings page that were open
  (`UpdateRelaunchState`); a copy running only in the menu bar comes back without a window.
- With it off, *Automatically check for updates* makes Sparkle ask before installing, and
  *Check for Updates…* is in the app menu and the menu bar menu.
- The first time the main window opens after an update, *What's New* shows the notes of every
  version since the last one seen, cached from the appcast when the update was found (so it
  works offline) or taken from the bundled `CHANGELOG.md`. A first install shows nothing.
  *Don't show release notes* turns it off.

**What an update keeps.** Sparkle replaces only the app bundle, and the app writes nothing
inside its bundle (`UpdatePreservesUserStateTests` checks the sources): the defaults
(settings, per-display wallpapers, playlists, first-launch and setup-assistant flags), the
keychain items (Steam Web API key), Application Support (SteamCMD and its login, SceneScript
storage, the safe-restart ledger), the Wallpaper Storage with its `.owe-assets` cache, and
the caches under `~/Library/Caches` all stay. No store is keyed on the app version.

**Shader caches across updates.** The translated-shader cache is keyed on
`ShaderVariantTranslator.revision` and the toolchain fingerprint, and the Metal pipeline
archive on the device, the OS build, that revision and toolchain, and its own revision; neither
includes the app version, so an update that doesn't change translated output keeps both.
`ShaderRevisionGuardTests` fails when translated output changes without a revision bump.

**Keychain across signatures.** Keychain items are generic passwords under the bundle
identifier's service prefix, this-device-only. The data protection keychain needs an
application-identifier entitlement, which Developer ID builds without a provisioning profile
don't have, so items live in the login keychain, whose access list names the app that created
them by its designated requirement (bundle identifier + Developer ID + team). Every release is
signed by the same team, so updates read them without a prompt. A copy signed differently
(an *Apple Development* Debug build, an ad-hoc build) has a different requirement: the first
time the release reads an item such a build created, macOS asks to allow access once
(*Always Allow* ends it); or re-enter the Steam Web API key in Settings.

## Verifying a download

```sh
shasum -a 256 -c OpenWallpaperEngine-1.0.0.sha256     # in the download folder
ditto -x -k OpenWallpaperEngine-1.0.0.zip /tmp/owe-check
APP="/tmp/owe-check/Open Wallpaper Engine.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority=Developer ID|flags=|Timestamp'
spctl -a -t exec -vv "$APP"        # accepted, source=Notarized Developer ID
xcrun stapler validate "$APP"      # The validate action worked!

spctl -a -t open --context context:primary-signature -vv OpenWallpaperEngine-1.0.0.dmg
xcrun stapler validate OpenWallpaperEngine-1.0.0.dmg
```

A pre-release's files carry its label: `OpenWallpaperEngine-1.1.0-beta.1.zip`.

## Entitlements and nested code

`OpenWallpaperEngine/OpenWallpaperEngine.entitlements`: not sandboxed,
`cs.allow-jit` (JavaScriptCore in SceneScript), network client, user-selected files,
Downloads read-only. Metal, WebKit (out of process), ScreenCaptureKit audio (a TCC prompt,
not an entitlement) and running `/usr/bin/perl` with the bundled `nowPlayingAdapter.pl`
(a resource, not an executable) need nothing more under the hardened runtime.

The only nested code is `Sparkle.framework` (Swift package, embedded by Xcode) with its
`Autoupdate` tool, `Updater.app` and two XPC services. The app isn't sandboxed, so it doesn't
use the XPC services; they ship inside the framework, signed. Xcode's `developer-id` export
re-signs all of it with the Developer ID identity, hardened runtime and a timestamp; the verify
step checks every Mach-O for that, checks each Sparkle component with
`codesign --verify --strict`, and fails on any other executable. No `--deep` signing is used
(Apple advises against it); `codesign --verify --deep --strict` checks the whole bundle.
