#!/bin/bash
# SideScroll installer.
#   curl -fsSL https://raw.githubusercontent.com/TCYTseven/SideScrollMac/main/install.sh | bash
# Downloads the latest release, puts it in /Applications and opens it.
# Falls back to building from source if no release can be downloaded.
set -euo pipefail

REPO="TCYTseven/SideScrollMac"
APP="SideScroll.app"
ZIP_URL="https://github.com/$REPO/releases/latest/download/SideScroll.zip"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "SideScroll runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || fail "SideScroll needs macOS 13 Ventura or newer (you have $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bold "Downloading SideScroll…"
if curl -fL --progress-bar "$ZIP_URL" -o "$tmp/SideScroll.zip"; then
  ditto -x -k "$tmp/SideScroll.zip" "$tmp"
else
  bold "No release download available; building from source instead."
  command -v swift >/dev/null || fail "Building needs the Xcode Command Line Tools. Run: xcode-select --install"
  git clone --depth 1 "https://github.com/$REPO.git" "$tmp/src"
  (cd "$tmp/src" && ARCHS="$(uname -m)" scripts/build-app.sh)
  mv "$tmp/src/build/$APP" "$tmp/$APP"
fi
[ -d "$tmp/$APP" ] || fail "Download did not contain $APP."

DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

if pgrep -x SideScroll >/dev/null; then
  bold "Closing the running copy…"
  pkill -x SideScroll || true
  sleep 1
fi

bold "Installing to $DEST…"
rm -rf "${DEST:?}/$APP"
ditto "$tmp/$APP" "$DEST/$APP"
# Downloaded with curl, so Gatekeeper has nothing to quarantine; clear it anyway.
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true
# Each build has a new signature, which leaves a stale Accessibility entry
# behind. Clearing it lets macOS ask again cleanly.
tccutil reset Accessibility app.sidescroll.SideScroll >/dev/null 2>&1 || true

open "$DEST/$APP"
bold "Done. SideScroll is in your menu bar."
echo "Grant Accessibility access when asked (System Settings > Privacy & Security > Accessibility)."
