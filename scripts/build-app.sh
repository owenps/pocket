#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"

swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --product Pocket
BIN_DIR="$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/dist/Pocket.app"
mkdir -p "$APP/Contents/MacOS"
# Replace the inode rather than overwriting an executable that may still be running.
cp "$BIN_DIR/Pocket" "$APP/Contents/MacOS/.Pocket-new"
mv -f "$APP/Contents/MacOS/.Pocket-new" "$APP/Contents/MacOS/Pocket"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

RESOURCES="$APP/Contents/Resources"
mkdir -p "$RESOURCES"
cp -R "$ROOT/Sources/Pocket/Resources/." "$RESOURCES/"

ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/Pocket.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/Pocket.icns"

# Local build only. Public releases need Developer ID signing and notarization.
codesign --force --sign - "$APP"
printf '\nBuilt %s\n' "$APP"
