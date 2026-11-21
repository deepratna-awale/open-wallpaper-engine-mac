#!/bin/bash
# Development helper for when you have a WE install on disk; Scripts/fetch-we-assets.sh downloads
# the files from Steam instead (docs/ci-assets.md) and is what CI uses. Copies the Wallpaper
# Engine assets the app uses out of a local Wallpaper Engine install, the same parts Settings ›
# Assets downloads from the user's Steam copy (`SteamHelperDownload.assetsFileList`), laid out as
# the install is.
#
#   ./Scripts/fill-assets-cache.sh <wallpaper_engine install or its assets dir> [destination]
#
# The destination defaults to the assets folder of the default Wallpaper Storage folder,
# `~/Documents/Open Wallpaper Engine/.owe-assets`. Point it at a folder of your own (e.g.
# /Volumes/980Pro/owe-local-assets) and set OWE_ASSETS to it to run the asset-dependent tests.
# Nothing it copies may be committed: the repository ships no Wallpaper Engine files.
#
# Kept: effect manifests (without editor preview projects), GLSL shaders and shared headers
# (without Direct3D or editor shaders), materials, models, particles, the editor's particle presets
# (without their preview projects), the SceneScript runtime, the compatibility patches, the
# built-in fonts with their licence files, the UI strings (`locale/ui_*.json`, beside `assets`)
# that translate label keys, WE's project templates for New Wallpaper (`projects/templates`) and
# the script editor's snippets (`ui/dist/monaco/snippets/*.js`).

set -euo pipefail

ASSETS="${1:-}"
DEST="${2:-$HOME/Documents/Open Wallpaper Engine/.owe-assets}"

[[ -n "$ASSETS" ]] || { echo "usage: $0 <wallpaper_engine install or assets dir> [destination]" >&2; exit 2; }
[[ "$(basename "$ASSETS")" == "assets" ]] || ASSETS="$ASSETS/assets"
[[ -d "$ASSETS/shaders" && -d "$ASSETS/effects" ]] || { echo "error: $ASSETS is not a Wallpaper Engine assets folder" >&2; exit 1; }

echo "source: $ASSETS"
echo "destination: $DEST"
STAGING="$DEST.partial"
rm -rf "$STAGING"
mkdir -p "$STAGING/assets"

rsync -a --prune-empty-dirs \
    --exclude '*/preview*/' --exclude 'preview*/' --exclude '.DS_Store' \
    "$ASSETS/effects/" "$STAGING/assets/effects/"

if [[ -d "$ASSETS/presets" ]]; then
    rsync -a --prune-empty-dirs \
        --exclude '*/preview*/' --exclude 'preview*/' --exclude '.DS_Store' \
        "$ASSETS/presets/" "$STAGING/assets/presets/"
fi

rsync -a --prune-empty-dirs --exclude 'HLSL/' --exclude 'editor/' --exclude '.DS_Store' \
    "$ASSETS/shaders/" "$STAGING/assets/shaders/"

for dir in fonts materials models particles scripts zcompat; do
    [[ -d "$ASSETS/$dir" ]] || continue
    rsync -a --exclude '.DS_Store' "$ASSETS/$dir/" "$STAGING/assets/$dir/"
done

LOCALE="$(dirname "$ASSETS")/locale"
if [[ -d "$LOCALE" ]]; then
    mkdir -p "$STAGING/locale"
    rsync -a --include 'ui_*.json' --exclude '*' "$LOCALE/" "$STAGING/locale/"
fi

# Only an install has these; an assets folder alone doesn't.
TEMPLATES="$(dirname "$ASSETS")/projects/templates"
if [[ -d "$TEMPLATES" ]]; then
    mkdir -p "$STAGING/projects"
    rsync -a --exclude '.DS_Store' "$TEMPLATES/" "$STAGING/projects/templates/"
fi

SNIPPETS="$(dirname "$ASSETS")/ui/dist/monaco/snippets"
if [[ -d "$SNIPPETS" ]]; then
    mkdir -p "$STAGING/ui/dist/monaco/snippets"
    rsync -a --include '*.js' --exclude '*' "$SNIPPETS/" "$STAGING/ui/dist/monaco/snippets/"
    rmdir -p "$STAGING/ui/dist/monaco/snippets" 2>/dev/null || true
fi

# What the app shows in Settings › Assets for assets it didn't download itself.
printf '{\n  "installedAt" : "%s"\n}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$STAGING/.owe-assets-info.json"

rm -rf "$DEST"
mv "$STAGING" "$DEST"
echo "done: $(find "$DEST" -type f | wc -l | tr -d ' ') files"
