#!/bin/bash
# SideScroll installer and updater.
#   curl -fsSL https://raw.githubusercontent.com/TCYTseven/SideScrollMac/main/install.sh | bash
#
# Downloads the latest release, checks it against the SHA-256 digest GitHub
# publishes for it, replaces any existing copy (wherever it is installed),
# links the `sidescroll` command-line tool, and opens the app.
set -euo pipefail

REPO="TCYTseven/SideScrollMac"
BUNDLE_ID="app.sidescroll.SideScroll"
API="https://api.github.com/repos/$REPO/releases/latest"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "SideScroll runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || fail "SideScroll needs macOS 13 Ventura or newer (you have $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bold "Looking up the latest release…"
curl -fsSL -H "Accept: application/vnd.github+json" "$API" -o "$tmp/release.json" \
  || fail "Couldn't reach GitHub. Check your connection and try again."
tag=$(plutil -extract tag_name raw -o - "$tmp/release.json")

url=""; digest=""
i=0
while name=$(plutil -extract "assets.$i.name" raw -o - "$tmp/release.json" 2>/dev/null); do
  if [ "$name" = "SideScroll.zip" ]; then
    url=$(plutil -extract "assets.$i.browser_download_url" raw -o - "$tmp/release.json")
    digest=$(plutil -extract "assets.$i.digest" raw -o - "$tmp/release.json" 2>/dev/null || true)
    break
  fi
  i=$((i + 1))
done
[ -n "$url" ] || fail "Release $tag has no SideScroll.zip."
case "$url" in https://github.com/*) ;; *) fail "Unexpected download location: $url" ;; esac

bold "Downloading SideScroll $tag…"
curl -fL --progress-bar "$url" -o "$tmp/SideScroll.zip"

expected=${digest#sha256:}
actual=$(shasum -a 256 "$tmp/SideScroll.zip" | cut -d' ' -f1)
if [ -n "$expected" ] && [ "$expected" != "$digest" ]; then
  [ "$actual" = "$expected" ] || fail "Checksum mismatch: the download is not what GitHub published. Nothing was installed."
  echo "Checksum OK."
else
  fail "GitHub didn't publish a checksum for this download, so it can't be verified. Nothing was installed."
fi

ditto -x -k "$tmp/SideScroll.zip" "$tmp/unpacked"
new="$tmp/unpacked/SideScroll.app"
[ -d "$new" ] || fail "The download did not contain SideScroll.app."
[ "$(defaults read "$new/Contents/Info.plist" CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "The download is not SideScroll."

# Update the copy that is already installed, wherever it is; otherwise /Applications.
existing=""
for p in "/Applications/SideScroll.app" "$HOME/Applications/SideScroll.app"; do
  [ -z "$existing" ] && [ -d "$p" ] && existing="$p"
done
if [ -z "$existing" ]; then
  # Installed somewhere else (skip disk images, the Trash and temp folders).
  existing=$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | grep '\.app$' \
    | grep -v -e "^$tmp" -e '^/private/var/folders/' -e '^/Volumes/' -e '/\.Trash/' | head -1 || true)
fi
if [ -n "$existing" ]; then
  dest="$existing"
elif [ -w /Applications ]; then
  dest="/Applications/SideScroll.app"
else
  mkdir -p "$HOME/Applications"
  dest="$HOME/Applications/SideScroll.app"
fi

if pgrep -x SideScroll >/dev/null; then
  bold "Quitting the running copy (windows go back on screen)…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do pgrep -x SideScroll >/dev/null || break; sleep 0.2; done
  # SideScroll treats SIGTERM as a normal quit too.
  pkill -x SideScroll 2>/dev/null || true
  sleep 0.5
fi

bold "Installing to $dest…"
SUDO=""
if [ ! -w "$(dirname "$dest")" ] || { [ -e "$dest" ] && [ ! -w "$dest" ]; }; then
  echo "$(dirname "$dest") needs an administrator password."
  SUDO="sudo"
fi
$SUDO rm -rf "$dest"
$SUDO ditto "$new" "$dest"
$SUDO xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
# Each build has a new signature, which leaves a stale Accessibility entry
# behind. Clearing it lets macOS ask again cleanly.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

# Command-line tool: link into the first writable bin folder.
tool="$dest/Contents/Resources/sidescroll"
for bin in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  [ "$bin" = "$HOME/.local/bin" ] && mkdir -p "$bin"
  if [ -d "$bin" ] && [ -w "$bin" ]; then
    if [ ! -e "$bin/sidescroll" ] || readlink "$bin/sidescroll" | grep -q 'SideScroll.app/'; then
      ln -sf "$tool" "$bin/sidescroll" && echo "Command-line tool: $bin/sidescroll"
    fi
    break
  fi
done

open "$dest"
bold "Done. SideScroll $tag is in your menu bar."
echo "Allow Accessibility access when asked (System Settings → Privacy & Security → Accessibility)."
echo "To remove it later: menu bar icon → Uninstall SideScroll…, or run uninstall.sh."
