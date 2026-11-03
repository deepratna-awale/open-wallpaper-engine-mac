#!/bin/bash
# Downloads Sparkle's command-line tools (sign_update, generate_appcast, BinaryDelta) for the
# Sparkle version the app links, verifies the archive's SHA-256, and prints the bin folder.
#
#   bin="$(Scripts/release/fetch-sparkle-tools.sh "$RUNNER_TEMP/sparkle")"
#
# Bumping Sparkle in the project: update SPARKLE_VERSION and SPARKLE_SHA256 here; this script
# fails while they disagree with Package.resolved.
set -euo pipefail

SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"

dest="${1:?usage: $0 <destination folder>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
resolved="$root/OpenWallpaperEngine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
linked="$(plutil -extract pins json -o - "$resolved" 2>/dev/null \
  | python3 -c 'import json,sys; print(next(p["state"]["version"] for p in json.load(sys.stdin) if p["identity"]=="sparkle"))')"
if [ "$linked" != "$SPARKLE_VERSION" ]; then
  echo "error: the app links Sparkle $linked but this script fetches $SPARKLE_VERSION; update it" >&2
  exit 1
fi

mkdir -p "$dest"
archive="$dest/Sparkle-$SPARKLE_VERSION.tar.xz"
curl -fsSL --retry 3 -o "$archive" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_SHA256  $archive" | shasum -a 256 -c - >&2
tar -xf "$archive" -C "$dest" ./bin
test -x "$dest/bin/sign_update" && test -x "$dest/bin/generate_appcast"
echo "$dest/bin"
