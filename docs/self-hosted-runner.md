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

One runner takes one job at a time, so a run's shards go one after another. That's slower than
GitHub's parallel runners, but the jobs don't wait for a runner that never comes.

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

   The `select-xcode` action then sets `DEVELOPER_DIR` for the job's steps.
4. **Run it as a launch agent** so it starts at login, in your GUI session (the tests need the
   window server and Metal):

   ```sh
   cd /Volumes/980Pro/actions-runner
   ./svc.sh install
   ./svc.sh start
   ```

   It shows as **Idle** under *Settings › Actions › Runners*.
5. **Turn it on.** *Settings › Secrets and variables › Actions › Variables › New repository
   variable*: `OWE_SELF_HOSTED_MAC` = `true`.

## Living with it

- **Test state.** The tests use the isolated `Open Wallpaper Engine (isolated tests)` defaults and
  folders under `~/Library`, the same ones `Scripts/ci-local.sh` and Xcode's tests use. Don't run
  the tests locally while the runner is running a job, or the two will trip over each other.
- **Builds.** CI's `xcodebuild` doesn't go through the local build-slot script, so a CI job and
  local builds compete for the CPU. Pause the runner (`./svc.sh stop`) for heavy local work.
- **Disk.** Checkouts, DerivedData and the WE assets live under
  `/Volumes/980Pro/actions-runner/_work`. Deleting `_work` is safe while the runner is stopped.
- **Permissions.** The audio tests may trigger a macOS audio permission prompt the first time.
  Approve it once yourself, as for local test runs.
- **Turning it off.** Set `OWE_SELF_HOSTED_MAC` to `false`, and the next runs go to GitHub's runners.
  To remove the runner: `./svc.sh stop && ./svc.sh uninstall`, then
  `./config.sh remove --token <token from the Runners page>`.
