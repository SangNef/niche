#!/bin/bash
# Packages Niche.app into a distributable Niche.dmg with the standard macOS
# installer layout: app icon on the left, an Applications shortcut on the
# right, arrow background in between. Requires Niche.app to already exist —
# run Scripts/build_app.sh first.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Niche"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
DMG_FINAL="$ROOT_DIR/$APP_NAME.dmg"
VOL_NAME="$APP_NAME"
BACKGROUND_IMG="$ROOT_DIR/Resources/dmg-background.png"

# Must match the arrow artwork in Scripts/generate_dmg_background.swift.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128
APP_ICON_X=180
APP_ICON_Y=190
APPS_ICON_X=480
APPS_ICON_Y=190

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Missing $APP_BUNDLE — run Scripts/build_app.sh first" >&2
    exit 1
fi
if [ ! -f "$BACKGROUND_IMG" ]; then
    echo "Missing $BACKGROUND_IMG — run:" >&2
    echo "  swift Scripts/generate_dmg_background.swift Resources/dmg-background.png" >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d)"
MOUNT_DIR=""
cleanup() {
    if [ -n "$MOUNT_DIR" ] && hdiutil info | grep -q "$MOUNT_DIR"; then
        hdiutil detach "$MOUNT_DIR" -quiet -force || true
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "==> Staging DMG contents"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir "$STAGING_DIR/.background"
cp "$BACKGROUND_IMG" "$STAGING_DIR/.background/background.png"

echo "==> Building read-write DMG"
mkdir -p "$ROOT_DIR/.build"
RW_DMG="$ROOT_DIR/.build/$APP_NAME-rw.dmg"
rm -f "$RW_DMG" "$DMG_FINAL"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDRW -ov -quiet "$RW_DMG"

echo "==> Mounting and styling window (grant Finder automation access if macOS prompts)"
MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 200 + $WINDOW_WIDTH, 120 + $WINDOW_HEIGHT}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" to {$APP_ICON_X, $APP_ICON_Y}
        set position of item "Applications" to {$APPS_ICON_X, $APPS_ICON_Y}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

echo "==> Converting to compressed read-only DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG_FINAL"
rm -f "$RW_DMG"

echo "==> Done: $DMG_FINAL"
