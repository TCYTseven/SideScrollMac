#!/usr/bin/env bash
# Packs build/SideScroll.app into dist/SideScroll.zip and dist/SideScroll.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SideScroll.app"
[ -d "$APP" ] || { echo "Run scripts/build-app.sh first"; exit 1; }
rm -rf dist
mkdir -p dist

ditto -c -k --sequesterRsrc --keepParent "$APP" dist/SideScroll.zip

STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
1. Drag SideScroll into Applications.
2. Open it. If macOS says it can't verify the developer:
   System Settings > Privacy & Security > scroll down > "Open Anyway".
   (Or skip all of this: paste the one-line installer from the README into Terminal.)
3. Allow Accessibility access when asked. SideScroll appears in the menu bar.
TXT
hdiutil create -volname "SideScroll" -srcfolder "$STAGE" -ov -format UDZO dist/SideScroll.dmg >/dev/null
rm -rf "$STAGE"
ls -lh dist
