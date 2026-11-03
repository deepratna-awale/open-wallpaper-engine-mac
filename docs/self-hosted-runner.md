# Self-hosted CI runner

GitHub's free macOS runners are shared, and when they run short a job waits 15 minutes and is
cancelled ("The job was not acquired by Runner"). CI can run its macOS jobs on the maintainer's
own Mac instead.

## What runs where

While the repository variable `OWE_SELF_HOSTED_MAC` is `true`, the macOS jobs of
[`ci.yml`](../.github/workflows/ci.yml) (build, test shards, packages, asset cache and asset
shards) and [`nightly.yml`](../.github/workflows/nightly.yml) run on a self-hosted runner with the
labels `self-hosted`, `macOS`, `ARM64` and `owe-mac`, for:

- pushes to `main`, the nightly schedule and manual runs;
- pull requests from **this repository's own branches**.

Pull requests from **forks always run on GitHub's `macos-26` runners**: a fork's code never runs on
the Mac. The Linux jobs (gate, plan, the final checks) stay on GitHub. Release, Appcast, CodeQL,
the Steam helper and the PR asset tests stay on GitHub's runners too.

When the variable is anything else, or unset, every job runs on GitHub's runners as before. Turn
it off when the Mac will be off or asleep for a while: a job sent to the Mac waits for it (up to
a day) and doesn't fall back to GitHub's runners.

One runner takes one job at a time, so on the Mac the tests and the asset tests each run as one
shard instead of three and four, with one test copy of the app at a time (`OWE_TEST_WORKERS=1`)
rather than three. The jobs don't wait for a runner that never comes.

## What the Mac keeps between runs

On the Mac the jobs skip the Actions cache, the products artifact and the Steam download, and use
what is already on the disk (`.github/actions/mac-cache`):

- **DerivedData and the Swift packages** live in `_work/_owe-cache`, so `xcodebuild` builds only
  what changed since the last run. The build job clones (APFS, no copy) its products into
  `_work/_owe-cache/products/<run id>` for that run's test jobs; clones over two days old are
  removed. The packages job's builds stay there too.
- **The shader and pipeline caches** are the isolated test copy's own under `~/Library/Caches`,
  which simply stay.
- **The WE assets** come from the folder `OWE_CI_ASSETS` names in the runner's `.env` (step 3). The
  asset jobs then never log in to Steam. Without it they restore or download the assets as on
  GitHub's runners. The other test jobs run without assets, as on GitHub's runners.

## Setting it up (once, on the Mac)

1. **Keep fork workflows behind approval.** In *Settings › Actions › General › Fork pull request
   workflows from outside collaborators*, choose **Require approval for all external
   contributors**. The workflow already sends fork PRs to GitHub's runners, but a fork can edit the
   workflow in its own PR, so nothing from a fork may run until you've read it.
2. **Add the runner.** *Settings › Actions › Runners › New self-hosted runner*, macOS, ARM64.
   GitHub shows the commands with the current runner version and a one-time token. Run them in
   Terminal, with two changes:
   - Make the folder on the external drive, not the nearly full startup disk:
     `mkdir -p /Volumes/980Pro/actions-runner && cd /Volumes/980Pro/actions-runner`.
   - When `./config.sh` asks for extra labels, enter `owe-mac`. Keep the default name and work
     folder (`_work`).
3. **Point it at Xcode 26.3.** CI builds with Xcode 26.3, and the runner never runs
   `xcode-select`. Add this line to `/Volumes/980Pro/actions-runner/.env`:

   ```
   OWE_CI_XCODE=/Volumes/980Pro/Applications/Xcode-26.3.0.app
   ```

   The `select-xcode` action then sets `DEVELOPER_DIR` for the job's steps. Add the WE assets
   folder too (the one holding `assets/shaders`), so the asset jobs use it:

   ```
   OWE_CI_ASSETS=/Volumes/980Pro/.claude/owe-assets-ci
   ```

   The runner reads `.env` when it starts: restart it after changing the file.
4. **Run it as a launch agent** so it starts at login, in your GUI session (the tests need the
   window server and Metal):

   ```sh
   cd /Volumes/980Pro/actions-runner
   ./svc.sh install
   ./svc.sh start
   ```

   It shows as **Idle** under *Settings › Actions › Runners*.

   macOS doesn't let a launch agent read an external drive. `svc.sh` runs `runsvc.sh` through
   `/bin/bash`, which then fails with `Operation not permitted`. Instead, point the agent's
   `ProgramArguments` in `~/Library/LaunchAgents/actions.runner.*.plist` at
   `/Volumes/980Pro/actions-runner/bin/Runner.Listener run --startuptype service`, with
   `KeepAlive` on and `PATH` (from `.path`) under `EnvironmentVariables`. Then add that
   `Runner.Listener` under *System Settings › Privacy & Security › Full Disk Access*, so only the
   runner gets the access.
5. **Turn it on.** *Settings › Secrets and variables › Actions › Variables › New repository
   variable*: `OWE_SELF_HOSTED_MAC` = `true`.

## Living with it

- **Test state.** The tests use the isolated `Open Wallpaper Engine (isolated tests)` defaults and
  folders under `~/Library`, the same ones `Scripts/ci-local.sh` and Xcode's tests use. Don't run
  the tests locally while the runner is running a job, or the two will trip over each other.
- **Your library stays out of CI.** Tests that read `/Volumes/980Pro` (the wallpaper library,
  WE's install, the SceneScript corpus, reference captures) skip in CI on the Mac just as on
  GitHub's runners: the workflows set `TEST_RUNNER_OWE_HERMETIC=1`
  ([`OwnerMachine.swift`](../OpenWallpaperEngineTests/Support/OwnerMachine.swift)). They still run
  locally, in Xcode and `Scripts/ci-local.sh`.
- **Builds.** CI's `xcodebuild` doesn't go through the local build-slot script, so a CI job and
  local builds compete for the CPU. Pause the runner (`./svc.sh stop`) for heavy local work.
- **Disk.** Checkouts and the kept DerivedData live under
  `/Volumes/980Pro/actions-runner/_work`. Deleting `_work` (or just `_work/_owe-cache`, for a clean
  build) is safe while the runner is stopped.
- **Permissions.** The audio tests may trigger a macOS audio permission prompt the first time.
  Approve it once yourself, as for local test runs.
- **Turning it off.** Set `OWE_SELF_HOSTED_MAC` to `false`, and the next runs go to GitHub's runners.
  To remove the runner: `./svc.sh stop && ./svc.sh uninstall`, then
  `./config.sh remove --token <token from the Runners page>`.
