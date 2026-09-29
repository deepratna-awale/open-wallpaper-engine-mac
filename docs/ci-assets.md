# Wallpaper Engine assets for CI and tests

The asset-gated tests need Wallpaper Engine's built-in files. The repository ships none of them.
`Scripts/fetch-we-assets.sh` downloads them from Steam, logged in as a dedicated **CI Steam
account** that owns Wallpaper Engine (app 431960). CI and local test runs both use it.

It downloads only `assets/`, `locale/ui_*.json` and `projects/defaultprojects/` of the Windows
depot, with [DepotDownloader](https://github.com/SteamRE/DepotDownloader) (MIT). The script pins
the release (3.4.0), verifies its SHA-256 and caches it in the tool folder (`OWE_TOOLS_DIR`).
.NET isn't needed. The output folder is laid out like a WE install, with `.build` (the Steam
build id) and `.owe-assets-info.json` (the format `WallpaperEngineAssetsCache` writes). Point
`OWE_ASSETS`, or `TEST_RUNNER_OWE_ASSETS` through `xcodebuild`, at it.

```sh
Scripts/fetch-we-assets.sh [--dry-run] [--force] [destination]
Scripts/fetch-we-assets.sh --build-id    # the current public build id; no login
```

The script first reads the current build id, without a key, from `api.steamcmd.net` (a mirror of
Steam's app info). It skips the download when the destination's `.build` matches. If that
lookup fails, it downloads anyway. DepotDownloader keeps `.DepotDownloader/depot.config` in the
destination, so a later build downloads only the files that changed. `--dry-run` shows the plan
without logging in, and `--force` downloads even when the build matches.

Default destination: `$OWE_WE_ASSETS_DIR`, else `~/Library/Caches/owe-we-assets`.

## The CI account

1. Create a Steam account used only for CI. Buy or gift Wallpaper Engine to it.
2. Turn on the Steam Guard **mobile authenticator** and export its `shared_secret` (base64),
   for example from a Steam Desktop Authenticator `.maFile` or `steamguard-cli`. Keep the
   revocation code somewhere safe.
3. Add the repository secrets (*Settings → Secrets and variables → Actions*):

| Secret | What it is |
| --- | --- |
| `OWE_CI_STEAM_USER` | the account name |
| `OWE_CI_STEAM_PASSWORD` | its password |
| `OWE_CI_STEAM_SHARED_SECRET` | the authenticator's `shared_secret`, base64 |
| `OWE_CI_STEAM_WEB_API_KEY` | optional, currently unused |

```sh
gh secret set OWE_CI_STEAM_USER
gh secret set OWE_CI_STEAM_PASSWORD
gh secret set OWE_CI_STEAM_SHARED_SECRET
```

The script makes the Steam Guard code itself (`Scripts/steam_totp.py`: HMAC-SHA1 over the 30 s
counter, written as 5 characters of Steam's alphabet). It passes the password and the code to
DepotDownloader on stdin, so neither shows up on a command line. It never prints either one, and
in Actions it masks them.

## CI

`.github/workflows/ci.yml` has two jobs:

- **`build-and-test`** runs the suite without assets, for every push and PR, forks included.
  The asset-gated tests skip. This is the fast signal.
- **`asset-tests`** runs the same suite with `TEST_RUNNER_OWE_ASSETS` set. It runs on pushes
  to `main` and on manual runs from `main` only, never for pull requests. The Steam secrets live
  in the `steam-ci` environment, which only `main` can use. The assets are downloaded fresh on
  every run; they are never cached in Actions or uploaded as artifacts. The nightly workflow
  uses the same environment.

Contributors run the asset tests locally with `OWE_ASSETS` (see Local use).

`OWE_LIBRARY` stays unset in both jobs, so the library-gated tests skip.

## Local use

Store the credentials in your login Keychain, service `owe-ci-steam`. Each command prompts for
the value, so it never lands in your shell history:

```sh
security add-generic-password -U -s owe-ci-steam -a user -w
security add-generic-password -U -s owe-ci-steam -a password -w
security add-generic-password -U -s owe-ci-steam -a shared-secret -w
```

The script reads them with `security find-generic-password -s owe-ci-steam -a <account> -w`.
Environment variables, when set, take precedence. Then:

```sh
Scripts/fetch-we-assets.sh                      # refreshes the default folder
TEST_RUNNER_OWE_ASSETS=~/Library/Caches/owe-we-assets \
  xcodebuild test -project OpenWallpaperEngine.xcodeproj -scheme OpenWallpaperEngine -destination 'platform=macOS'
```

To refresh, run the script again. It does nothing until Steam publishes a new build. To start
over, use `--force` or delete the folder. To remove the credentials, run
`security delete-generic-password -s owe-ci-steam -a <account>`.

`Scripts/fill-assets-cache.sh` still copies the assets from a WE install on disk, when you have
one.

## Troubleshooting

| Exit | Meaning | What to do |
| --- | --- | --- |
| 2 | bad arguments | see `--help` |
| 3 | missing credentials, or a shared secret that isn't base64 | set the secrets or Keychain items above |
| 4 | login failed: wrong password, wrong shared secret, or a clock that's off by more than ~30 s | check the values; sync the clock; a changed authenticator means a new `shared_secret` |
| 5 | Steam is rate limiting logins (`RateLimitExceeded`, `AccountLoginDeniedThrottle`) | wait 30–60 minutes; don't retry in a loop |
| 6 | the account doesn't own Wallpaper Engine | add the licence to the account |
| 7 | the download failed, or the result has no `assets/shaders` | rerun; see DepotDownloader's log |
| 8 | DepotDownloader couldn't be downloaded, or its checksum didn't match | check the network; on a version bump, update the pinned hashes |
| 9 | `--build-id` couldn't read the build | `api.steamcmd.net` is down or returned something other than a number; the download still runs |
