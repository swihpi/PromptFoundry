#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PromptFoundry"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-1.0.1-unsigned.dmg"

"$ROOT_DIR/script/build_and_run.sh" --build-only

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$ROOT_DIR/INSTALLATION.txt" "$DMG_ROOT/Read Me.txt"
rm -f "$DMG_PATH"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Created unsigned, unnotarized DMG: $DMG_PATH"
