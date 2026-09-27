# Releasing

`.github/workflows/release.yml` builds the app, signs it with **Developer ID** under the
**hardened runtime**, **notarizes** and **staples** it, and attaches a zip, a DMG and SHA-256
sums to a **draft** GitHub release. Downloads open on any Mac without a Gatekeeper warning.

## One-time setup: repository secrets

Add these under *Settings → Secrets and variables → Actions → New repository secret*.
The workflow's first step fails with a list of whatever is missing.

| Secret | What it is |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | *Developer ID Application* certificate + private key, `.p12`, base64 |
| `P12_PASSWORD` | the password you gave the `.p12` on export |
| `KEYCHAIN_PASSWORD` | any random string; locks the runner's throwaway keychain |
| `DEVELOPMENT_TEAM` | your 10-character Team ID (developer.apple.com → Membership) |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID (UUID) |
| `ASC_KEY_P8_BASE64` | the key's `AuthKey_<ID>.p8`, base64 |
| `USER_PAT` | GitHub token with `contents: write` on this repo, to publish the release |

Fallback instead of the three `ASC_*` secrets: `APPLE_ID` (Apple ID email) and
`APPLE_APP_PASSWORD` (app-specific password from appleid.apple.com → Sign-In and Security).
The API key is preferred: it does not depend on a person's Apple ID or 2FA.

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

## Cutting a release

The version comes from the tag: `vX.Y.Z` → `CFBundleShortVersionString` X.Y.Z;
`CFBundleVersion` is the workflow run number, so every build is unique.

```sh
git tag v0.9.0
git push origin v0.9.0
```

Or *Actions → Release → Run workflow* with `tag` = an **existing** tag such as `v0.9.0`
(the workflow checks out that tag).

The run: check secrets → import certificate into a temporary keychain → archive (manual
signing, hardened runtime, `--timestamp`, no `get-task-allow`) → export (`developer-id`) →
verify every Mach-O is Developer ID + runtime + timestamp → notarize the app
(`notarytool submit --wait`; on failure it prints `notarytool log`) → staple → zip → DMG
(signed, notarized, stapled) → verify with `codesign`, `spctl` and `stapler validate` →
draft release. The keychain and the API key file are deleted in an `always()` step.

Review the draft release on GitHub, edit the notes, then *Publish*.

## Verifying a download

```sh
shasum -a 256 -c OpenWallpaperEngine-0.9.0.sha256     # in the download folder
ditto -x -k OpenWallpaperEngine-0.9.0.zip /tmp/owe-check
APP="/tmp/owe-check/Open Wallpaper Engine.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority=Developer ID|flags=|Timestamp'
spctl -a -t exec -vv "$APP"        # accepted, source=Notarized Developer ID
xcrun stapler validate "$APP"      # The validate action worked!

spctl -a -t open --context context:primary-signature -vv OpenWallpaperEngine-0.9.0.dmg
xcrun stapler validate OpenWallpaperEngine-0.9.0.dmg
```

## Entitlements

`OpenWallpaperEngine/OpenWallpaperEngine.entitlements`: not sandboxed,
`cs.allow-jit` (JavaScriptCore in SceneScript), network client, user-selected files,
Downloads read-only. Metal, WebKit (out of process), ScreenCaptureKit audio (a TCC prompt,
not an entitlement) and running `/usr/bin/perl` with the bundled `nowPlayingAdapter.pl`
(a resource, not an executable) need nothing more under the hardened runtime. The app links
only system frameworks, so no nested code needs signing; the verify step fails if that changes
and something nested is unsigned.
