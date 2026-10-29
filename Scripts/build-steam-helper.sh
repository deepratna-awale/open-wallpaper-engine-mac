#!/bin/bash
# Builds the Steam helper (SteamHelper/) for both Mac architectures into
# build/steam-helper/<osx-arm64|osx-x64>/owe-steam-helper, where the app's "Embed Steam Helper"
# build phase takes it. A build without it runs but can't log in to Steam.
#
#   Scripts/build-steam-helper.sh             builds with the .NET 9 SDK (https://dot.net)
#   Scripts/build-steam-helper.sh --download  takes the helper CI last built from main (needs gh)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/steam-helper"

if [ "${1:-}" = "--download" ]; then
  RUN=$(gh run list --workflow steam-helper.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId')
  [ -n "$RUN" ] || { echo "No Steam helper built on main yet; build it with the .NET 9 SDK instead." >&2; exit 1; }
  rm -rf "$OUT"
  gh run download "$RUN" --name owe-steam-helper --dir "$OUT"
  chmod +x "$OUT"/*/owe-steam-helper
  echo "Steam helper from run $RUN in $OUT"
  exit 0
fi

command -v dotnet >/dev/null || { echo "The .NET 9 SDK is missing (https://dot.net), or use --download." >&2; exit 1; }
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
for RID in osx-arm64 osx-x64; do
  dotnet publish "$ROOT/SteamHelper/OWESteamHelper.csproj" -c Release -r "$RID" --self-contained \
    -p:PublishSingleFile=true -p:DebugType=embedded -o "$OUT/$RID"
done
ls -l "$OUT"/*/owe-steam-helper
