#!/usr/bin/env bash
# Builds Picolo and assembles a runnable Picolo.app bundle.
# Xcode is not required — this uses only Swift Package Manager + the SDK.
set -euo pipefail

CONFIG="${1:-release}"          # debug | release
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Picolo.app"

echo "▶ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Picolo"

echo "▶ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Picolo"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Picolo.icns" "$APP/Contents/Resources/Picolo.icns"

# Ad-hoc sign so Gatekeeper lets a locally built app run.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ built $APP"
echo "  run with: open '$APP'   (or ./build-app.sh && open Picolo.app)"
