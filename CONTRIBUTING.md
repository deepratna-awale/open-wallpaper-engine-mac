# Contributing

Read [`docs/architecture.md`](docs/architecture.md) first. It explains the module layout and what goes where. This file holds the rules for changing the code. They exist because each of them was broken once and hid a real bug (see [`docs/progress-snapshot.md`](docs/progress-snapshot.md)).

## Building

- Open `OpenWallpaperEngine.xcodeproj`, scheme **OpenWallpaperEngine**, macOS 14+ (Xcode 26.3 or newer; CI and release use 26.3).
- **Debug builds sign with *Apple Development*.** macOS ties the Screen Recording grant (needed for audio-reactive features) to the signature, and ad-hoc signing loses it on every rebuild.
  - If you aren't on the project's team, set your own team in *Signing & Capabilities* and don't commit that change.
- **Shaders:** WE shaders are translated in process by the glslang and SPIRV-Cross libraries linked into the app (`Vendor/ShaderToolchain`). You don't need to install anything.
- **WE assets:** none are in the repository or the app. The app reads them from a WE install the user chose, or from the cache Settings › Assets fills from the user's Steam copy (`<Wallpaper Storage>/.owe-assets`). For development, `Scripts/fetch-we-assets.sh` downloads them from Steam with the CI account (credentials in your login Keychain, see [docs/ci-assets.md](docs/ci-assets.md)), or `Scripts/fill-assets-cache.sh <WE install> <folder>` copies them from a WE install on disk.

## Where code goes

| You are adding… | Put it in… |
|---|---|
| A new WE file format or field | `Scene/Format/`: plain `Decodable` models, no side effects |
| Anything that reads a value that can be user-, script- or animation-bound | resolve it through `Scene/Values`; never read the raw JSON |
| Shader translation, reflection, caching | `Scene/Shaders/` |
| Metal drawing, render passes, render targets | `Scene/Rendering/` |
| A SceneScript API member | `Scene/Scripting/` (JS-side code in a bundled `.js` resource, not a Swift string) |
| A settings control or scene inspector UI | `Settings/` or `Scene/UI/`; the view model sits next to its view |
| Anything used by several features (logging, settings, asset paths) | `Core/` |

There is **one type per file** unless the types are tiny and private to it. A file over about 600 lines, or a function over about 80 lines, needs a reason. Split along a real seam.

## Rules

1. **Implement WE's behaviour, not a look-alike.**
   - Don't add native approximations of WE effects, invented parameter names, or remapped ranges.
   - Don't add special cases keyed on a layer, effect, file or property *name* (`"cloud"`, `"clock"`, `"snow"`…). If a wallpaper renders wrong, find the missing general feature.
   - The existing heuristics are listed in the progress snapshot (§B8) and are being removed.
2. **Fail loudly.**
   - Don't use `try?` on file IO, decoding, shader translation or pipeline creation. Use `do/catch` and log the error once, with the wallpaper, layer, effect and reason.
   - `try?` is fine for genuinely optional lookups, and a comment should say so.
   - Decode collections element by element, so one bad entry doesn't drop its siblings.
3. **No new global state.**
   - Don't add a new `static let shared`, `AppDelegate.shared` lookups from engine code, or `UserDefaults.standard`. Defaults go through `UserDefaults.app` (`@AppStorage(…, store: .app)`) and files through `AppStorageLocation.current` (`supportDirectory`, `cachesDirectory`), so tests and development copies stay isolated from the user's data.
   - Pass dependencies in. State belongs to a wallpaper instance.
4. **Typed keys.** Don't add new `"_owe_…"` string keys. Add a case to the typed settings or property identifiers instead.
5. **Logging** goes through `OWELog`: `.debug` for per-frame detail, `.info` for lifecycle, `.error` for failures. Don't use `print` or raw `NSLog`, and don't log anything every frame at `.info` or above.
6. **Caches are versioned.** Any on-disk cache is keyed on its inputs *and* a revision constant you bump whenever the producing code changes. `ShaderVariantTranslator.revision` is the example; `ShaderVariantCacheTests` fails when translated output changes without a bump. Shader and pipeline caches are keyed on that revision, the toolchain, the device and the OS build, never the app version. `ShaderRevisionGuardTests` hashes the translated MSL of the fixture shaders (and of every WE asset shader with `OWE_ASSETS`) against `Tests/Fixtures/ShaderRevision/expected.json`; after a bump, re-record the pair with `TEST_RUNNER_OWE_RECORD_SHADER_HASH=1 TEST_RUNNER_OWE_ASSETS=<assets folder> xcodebuild test -project OpenWallpaperEngine.xcodeproj -scheme OpenWallpaperEngine -destination 'platform=macOS' -only-testing:OpenWallpaperEngineTests/ShaderRevisionGuardTests` and commit the fixture.
7. **Concurrency.** Mark UI types `@MainActor`. Don't share mutable state across threads without an owner: prefer actors, or one lock that is documented and owns specific fields. Don't add `nonisolated(unsafe)` without a comment explaining why it's safe.
8. **Keep dead code out.** Delete it; git has history. Don't comment code out, and don't keep an unused alternate render path.
9. **UI text goes through `Localizable.xcstrings`.**
   - Pass literals to localizing APIs (`Text`, `Button`, `Label`, `.help`…), or use `String(localized:)` / `LocalizedStringResource` where the text travels as a value (AppKit, errors, view models). A `String` handed to `Text` shows in English in every language.
   - Counts use the catalog's plural variations, not a hand-made "s"; numbers, sizes, durations and lists use the Foundation formatters.
   - Values that are stored or sent (tags, types, ratings) stay English; show them through `LocalizedLabels`.
   - The app ships in 15 languages besides English. A new string needs a translation in each, using the terms in [`docs/localization-glossary.md`](docs/localization-glossary.md). `LocalizationCatalogTests` and `LocalizationLintTests` fail otherwise.

## Debugging

- Read the app's logs with `/usr/bin/log` (a shell `log` alias or function may shadow it), e.g. `/usr/bin/log show --last 10m --predicate 'process == "Open Wallpaper Engine"'`.
- Shaders the translator rejects are written to `/tmp/owe-failed-shaders` for inspection.

## Tests

- **Where tests go:** the `OpenWallpaperEngineTests` target (unit tests hosted in the app, which starts without its delegate under XCTest). Fixtures live in `Tests/Fixtures/`, outside the target, and are read with `Fixtures.url(_:)`.
- **Every fix or feature comes with a test.** Format and value tests decode fixtures. Rendering checks go in `RenderCheckTests`.
- **Known gaps** are asserted with `XCTExpectFailure("<snapshot id>: …")`. It's strict, so fixing a gap makes its test fail until you delete the expectation.
- **Tests never touch the user's state.** The test host is the app, so under XCTest `AppStorageLocation` switches to the defaults suite `com.winddog.wallpaper-engine.isolated.tests`, `Open Wallpaper Engine (isolated tests)` under Application Support and Caches, and isolated keychain services. `AppStorageIsolationTests` guards this. Tests never read the user's assets either: the asset-dependent tests use `OWE_ASSETS=<assets folder or WE install>` (`TEST_RUNNER_OWE_ASSETS` through `xcodebuild`) and skip without it, as on CI. A test that needs them starts with `_ = try Fixtures.assets()`.
- **Launch development copies isolated.** Every build shares the bundle id, so an agent or script that launches a copy of the app (screenshots, smoke runs) must set `OWE_ISOLATED_STATE=<tag>` in its environment or pass `-OWEIsolatedState <tag>`, e.g. `OWE_ISOLATED_STATE=shots "<build>/Open Wallpaper Engine.app/Contents/MacOS/Open Wallpaper Engine" -CustomWallpapersDirectory <library>`. Launch arguments (`-Key value`) still override defaults in the isolated suite. Never launch a dev copy against the real domain: it overwrites the user's playlists, per-screen wallpapers and safe-restart sentinel.
- **Before pushing,** run `TEST_RUNNER_OWE_SLOW_TESTS=1 TEST_RUNNER_OWE_ASSETS=<assets folder> xcodebuild test -project OpenWallpaperEngine.xcodeproj -scheme OpenWallpaperEngine`, so the asset-dependent tests run too. With the fetched cache that's `Scripts/fetch-we-assets.sh && TEST_RUNNER_OWE_ASSETS=~/Library/Caches/owe-we-assets xcodebuild test …`. CI (`.github/workflows/ci.yml`) runs the suite twice: without assets for every PR, where they skip, and with assets fetched from Steam for pushes and same-repository PRs ([docs/ci-assets.md](docs/ci-assets.md)). Tests slower than about a minute skip unless `OWE_SLOW_TESTS=1`; the nightly workflow (`.github/workflows/nightly.yml`) runs them.

## Commits and PRs

- Use [Conventional Commits](https://www.conventionalcommits.org/): `fix:`, `feat:`, `perf:`, `refactor:`, `build:`, `docs:`, `test:`.
- Keep commits small and single-purpose. File moves and renames go in their own commit with no logic changes, so review and `git log --follow` stay useful. Asset or vendor drops never share a commit with code.
- The PR description says what changed, why, and how it was verified.

## Changing the project file

- New files: once the project uses folder-synced groups (Phase 1), putting a file in the right folder is enough. Until then, add it through Xcode.
- Never add Wallpaper Engine files to the repository, the app or `Tests/Fixtures`: tests get them from `OWE_ASSETS`, and fixtures are written for the project.
