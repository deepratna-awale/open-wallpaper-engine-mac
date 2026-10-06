Goal: run all WE wallpapers except `application`. WE-faithful, no per-name hacks.
Rules: CONTRIBUTING.md. Layout: docs/architecture.md. Status: docs/progress-snapshot.md. Order of work: docs/roadmap.md.
Moves/renames = own commit, no logic, must build.
Logs: `/usr/bin/log` (`log` may be shadowed). Failed shaders: ~/Library/Caches/app.openwallpaperengine/FailedShaders (isolated copies: under `~/Library/Caches/Open Wallpaper Engine (isolated <tag>)/`).
Bump `ShaderVariantTranslator.revision` if translated output changes.
