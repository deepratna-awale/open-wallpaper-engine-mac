#!/bin/zsh
# Regenerates every logo asset from the SVGs. See README.md.
# LOGO_VARIANT picks a palette in make_svgs.py (default: its VARIANT).
set -euo pipefail
cd "${0:A:h}"
ROOT=../..
RES=$ROOT/OpenWallpaperEngine/Resources
XCASSETS=$RES/Assets.xcassets
DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
ICTOOL="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x $ICTOOL ]] || { echo "ictool not found; set DEVELOPER_DIR to an Xcode 26+ Developer dir" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 make_svgs.py
swiftc -O -o "$TMP/render" render.swift

# 1. Liquid Glass icon (macOS 26+): layer SVGs into the Icon Composer bundle.
#    icon.json (groups, glass, shadows) is edited in Icon Composer, not here.
#    Only the background fill is set here, from the palette in make_svgs.py.
for l in monitor screen gear hole; do
  cp svg/$l.svg $RES/AppIcon.icon/Assets/
done
python3 make_svgs.py --icon-fill $RES/AppIcon.icon/icon.json

# 2. macOS 14/15 fallback: ictool's own Default rendering, put on the macOS grid.
"$ICTOOL" $RES/AppIcon.icon --export-image --output-file "$TMP/full.png" --platform macOS \
  --rendition Default --width 1024 --height 1024 --scale 1 >/dev/null
SET=$XCASSETS/AppIcon.appiconset
rm -f $SET/*.png
for pt in 16 32 128 256 512; do
  "$TMP/render" frame "$TMP/full.png" $SET/icon_${pt}x${pt}.png $pt
  "$TMP/render" frame "$TMP/full.png" $SET/icon_${pt}x${pt}@2x.png $((pt * 2))
done

# 3. In-app images: we.logo is the app icon, we.placeholder and the docs art the flat logo.
"$TMP/render" frame "$TMP/full.png" $XCASSETS/we.logo.imageset/we.logo.png 512
"$TMP/render" frame "$TMP/full.png" $XCASSETS/we.logo.imageset/we.logo@2x.png 1024
"$TMP/render" svg svg/logo-flat.svg $XCASSETS/we.placeholder.imageset/we.placeholder.png 512
"$TMP/render" svg svg/logo-flat.svg $XCASSETS/we.placeholder.imageset/we.placeholder@2x.png 1024
"$TMP/render" svg svg/logo-flat.svg \
  $ROOT/OpenWallpaperEngine/OpenWallpaperEngine.docc/Resources/documentation-art/OpenWallpaperEngine-icon@2x.png 1024

# 4. Menu bar: the template SVG itself (vector, template rendering intent in Contents.json).
cp svg/menubar-template.svg $XCASSETS/OWEStatusIcon.imageset/OWEStatusIcon.svg
echo "done"
