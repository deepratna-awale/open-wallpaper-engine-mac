#!/bin/sh
# Builds the Wallpaper Editor's own app inside Open Wallpaper Engine (docs/editor-plan.md,
# "Separate process"): <app>/Contents/Helpers/Wallpaper Editor.app, with its own bundle id
# (<app id>.editor), name, Info.plist (EditorHelper/Info.plist) and badged icon, so macOS treats
# it as an app of its own (its own Dock tile, menu bar and LaunchServices identity).
#
# Run by the app target's "Wallpaper Editor Helper" build phase, after "Chromium Helper Apps"
# (which recreates Contents/Helpers) and before Xcode signs the app, which then seals it.
#
# - The executable is a copy of the app's own (one codebase; the bundle id puts it in editor
#   mode, `AppLaunchMode`). The app links with a second rpath, @executable_path/../../../../Frameworks
#   (LD_RUNPATH_SEARCH_PATHS), which from here is <app>/Contents/Frameworks: the copy loads the
#   app's Sparkle.framework, no second copy, and library validation sees the same team. In the app
#   itself the first rpath always finds it.
# - Resources are the app's, except the large media the editor never shows (the code reads those
#   from the app around it, `AppBundleLayout.appBundle`).
# - Signed with the app's identity, hardened runtime and entitlements; ad hoc when the build
#   doesn't sign (so it still launches on Apple silicon).
set -euo pipefail

CONTENTS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
NAME="Wallpaper Editor"
APP="$CONTENTS/Helpers/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$CONTENTS/MacOS/${EXECUTABLE_NAME}" "$APP/Contents/MacOS/$NAME"
# A Debug build's executable is a stub that loads @rpath/<name>.debug.dylib from the app's MacOS
# folder (ENABLE_DEBUG_DYLIB): the copy looks there instead of the app's Frameworks (which the
# dylib's own rpaths still reach; the stub has no room for another rpath).
if [ -f "$CONTENTS/MacOS/${EXECUTABLE_NAME}.debug.dylib" ]; then
  install_name_tool -rpath "@executable_path/../../../../Frameworks" "@executable_path/../../../../MacOS" \
    "$APP/Contents/MacOS/$NAME"
fi

rsync -a --exclude "WallpaperNotFound.mp4" --exclude "maxwell-cat.gif" --exclude "AppIcon.icns" \
  "$CONTENTS/Resources/" "$APP/Contents/Resources/"
cp "${SRCROOT}/EditorHelper/WallpaperEditor.icns" "$APP/Contents/Resources/WallpaperEditor.icns"

PLIST="$APP/Contents/Info.plist"
cp "${SRCROOT}/EditorHelper/Info.plist" "$PLIST"
read_app() { /usr/libexec/PlistBuddy -c "Print :$1" "$CONTENTS/Info.plist"; }
plutil -replace CFBundleIdentifier -string "${PRODUCT_BUNDLE_IDENTIFIER}.editor" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$(read_app CFBundleShortVersionString)" "$PLIST"
plutil -replace CFBundleVersion -string "$(read_app CFBundleVersion)" "$PLIST"
plutil -replace LSMinimumSystemVersion -string "${MACOSX_DEPLOYMENT_TARGET}" "$PLIST"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ENTITLEMENTS="${SRCROOT}/OpenWallpaperEngine/OpenWallpaperEngine.entitlements"
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  # shellcheck disable=SC2086 # OTHER_CODE_SIGN_FLAGS holds several flags.
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime ${OTHER_CODE_SIGN_FLAGS:-} \
    --entitlements "$ENTITLEMENTS" "$APP"
else
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
fi
