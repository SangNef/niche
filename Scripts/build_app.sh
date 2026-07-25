#!/bin/bash
# Builds a real Niche.app bundle (release build) so SMAppService
# login-item registration and Automation permission prompts work as expected.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Niche"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT_DIR"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Bundling mediaremote-adapter (now-playing support)"
ADAPTER_DIR="$ROOT_DIR/vendor/mediaremote-adapter"
if [ ! -d "$ADAPTER_DIR" ]; then
    echo "    Missing $ADAPTER_DIR — cloning it now"
    mkdir -p "$ROOT_DIR/vendor"
    git clone https://github.com/ungive/mediaremote-adapter.git "$ADAPTER_DIR"
fi
if [ ! -d "$ADAPTER_DIR/build/MediaRemoteAdapter.framework" ]; then
    echo "    Missing $ADAPTER_DIR/build/MediaRemoteAdapter.framework — building it now"
    mkdir -p "$ADAPTER_DIR/build"
    (cd "$ADAPTER_DIR/build" && cmake .. && cmake --build .)
fi
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp -R "$ADAPTER_DIR/build/MediaRemoteAdapter.framework" "$APP_BUNDLE/Contents/Frameworks/"
cp "$ADAPTER_DIR/bin/mediaremote-adapter.pl" "$APP_BUNDLE/Contents/Resources/"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
echo "    Move it to /Applications, then open it once to grant Automation permissions."
