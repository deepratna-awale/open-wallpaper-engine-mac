# Agent guide

For coding agents (and people) working in this repository. The rules themselves are in
[CONTRIBUTING.md](CONTRIBUTING.md) and the module layout in [docs/architecture.md](docs/architecture.md);
read both before changing code. This page is the short version, plus what an automated change
tends to get wrong.

## Goal

Run every Wallpaper Engine (WE) wallpaper type except `application` (scene, video, web),
following WE's own behaviour. Fixes are general and spec-faithful: no special cases keyed on a
wallpaper, layer, effect or property name, no native look-alikes of WE effects.

## Build and test

- Xcode 26.3 or newer, scheme **OpenWallpaperEngine**, macOS 14+. CI builds with **Xcode 26.3
  (Swift 6.2)**, which rejects some code newer compilers accept: check a build with
  `DEVELOPER_DIR=<Xcode 26.3>/Contents/Developer xcodebuild …`, never by changing `xcode-select`.
- Every target is Swift 6 language mode with complete concurrency checking. Main-actor code that
  runs off main traps at run time, so run the tests that reach any callback you changed.
- Tests: `xcodebuild test -project OpenWallpaperEngine.xcodeproj -scheme OpenWallpaperEngine -destination 'platform=macOS'`.
  The local gate before a merge is `Scripts/ci-local.sh` (with `OWE_ASSETS=<WE assets>` and
  `OWE_SLOW_TESTS=1` for the asset and slow tiers). Asset tests skip without `OWE_ASSETS`.
- The Steam login goes through `owe-steam-helper` (`SteamHelper/`, .NET 9), which Xcode doesn't
  build: `Scripts/build-steam-helper.sh` (or `--download` for CI's build from `main`). Its own
  tests are `dotnet test SteamHelper/Tests`.
- Launch any development copy of the app isolated (`OWE_ISOLATED_STATE=<tag>`), or it overwrites
  the owner's real playlists and settings.
- Logs: `/usr/bin/log show --last 10m --predicate 'process == "Open Wallpaper Engine"'` (a shell
  `log` may shadow it). The app also keeps its own `.info` and `.error` messages on disk for
  Report a Problem (`RecentLog`): `~/Library/Caches/app.openwallpaperengine/Logs/current.log`, and
  `previous.log` for the last run, which survive a crash. An isolated copy keeps its own under
  `~/Library/Caches/Open Wallpaper Engine (isolated <tag>)/`. Shaders the translator rejected:
  `~/Library/Caches/app.openwallpaperengine/FailedShaders`.

## Things that are easy to miss

- **Steam:** SteamCMD and the Steam Web API key are gone (deprecated since 1.0.0-beta.13). One
  Steam sign-in (QR code from the Steam mobile app, or password and Steam Guard code) through
  `owe-steam-helper` does browsing, downloads, the assets, subscriptions, favourites and ratings.
  Don't reintroduce either as a fallback.
- **Shader output:** bump `ShaderVariantTranslator.revision` whenever translated MSL changes, and
  re-record `Tests/Fixtures/ShaderRevision/expected.json` (CONTRIBUTING.md, rule 6).
- **UI text** goes through `Localizable.xcstrings` with a translation in all 15 languages, using
  [docs/localization-glossary.md](docs/localization-glossary.md).
- **Settings and files** go through `UserDefaults.app` and `AppStorageLocation.current`, never
  `UserDefaults.standard` or a hard-coded path.
- **Test map:** a new source folder or test class the patterns in
  [`.github/test-map.yml`](.github/test-map.yml) don't reach needs an entry there.
- **No WE files** in the repository, the app or `Tests/Fixtures`.
- **Content:** look only at wallpapers whose `project.json` `contentrating` is `Everyone`.
- **Credentials:** never type passwords, Steam Guard codes, Apple IDs or keys, and never click
  macOS permission prompts; give the owner the command instead.

## Commits, branches and PRs

- Conventional Commits (`fix:`, `feat:`, `docs:`, `build:`, `ci:`, `test:`, `refactor:`, `perf:`).
  Small, single-purpose commits; moves and renames get their own commit with no logic change, and
  it must build.
- No AI or tool attribution anywhere: no `Co-Authored-By` lines, no "generated with" footers, in
  commits, PRs, release notes, docs or code.
- Branches are `<type>/<topic>` from `main` (`fix/issue-<number>-<topic>` for an issue), one PR
  per change, against `main`, with the [PR template](.github/pull_request_template.md)'s sections.
- Draft PRs don't run CI; mark the PR ready (or label it **ready to merge**) once it's done and up
  to date with `main`. Merging is the maintainer's call.
- A user-visible change should add a line to `CHANGELOG.md` under *Unreleased*, so the release
  notes don't miss it.

## Docs to keep in step

When behaviour a user can see changes, update the matching page:
[README.md](README.md) and its translations in [`resources/readme/`](resources/readme),
[docs/features.md](docs/features.md), [docs/getting-started.md](docs/getting-started.md), the guide
for the feature in [`docs/`](docs), [docs/mcp.md](docs/mcp.md) for MCP tools and settings, and the
[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki). README pictures and
demo clips carry an explicit `width` ([docs/media/demo/README.md](docs/media/demo/README.md)).
`Scripts/check-doc-links.py` checks the relative links.
