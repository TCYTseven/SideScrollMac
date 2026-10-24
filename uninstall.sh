#!/bin/bash
# Removes SideScroll completely:
#   curl -fsSL https://raw.githubusercontent.com/TCYTseven/SideScrollMac/main/uninstall.sh | bash
# Puts every window back on screen, removes the login item, the app, its
# settings, caches, command-line tool and Accessibility entry.
set -u
BUNDLE_ID="app.sidescroll.SideScroll"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

if pgrep -x SideScroll >/dev/null; then
  bold "Quitting SideScroll (windows go back on screen)…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  for _ in $(seq 1 50); do pgrep -x SideScroll >/dev/null || break; sleep 0.2; done
  pkill -x SideScroll 2>/dev/null
  sleep 0.5
fi

# Every installed copy, wherever it is.
apps=$( { mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | grep '\.app$' | grep -v -e '^/Volumes/' -e '^/private/var/folders/'
          for p in /Applications/SideScroll.app "$HOME/Applications/SideScroll.app"; do [ -d "$p" ] && echo "$p"; done; } | sort -u)

while IFS= read -r app; do
  [ -n "$app" ] && [ -d "$app" ] || continue
  # Remove the login item while the app is still there to unregister it.
  "$app/Contents/MacOS/SideScroll" --unregister-login-item >/dev/null 2>&1
  bold "Removing $app"
  if [ -w "$(dirname "$app")" ]; then rm -rf "$app"; else sudo rm -rf "$app"; fi
done <<< "$apps"

for bin in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  if [ -L "$bin/sidescroll" ] && readlink "$bin/sidescroll" | grep -q 'SideScroll.app/'; then
    rm -f "$bin/sidescroll" 2>/dev/null || sudo rm -f "$bin/sidescroll"
  fi
done

defaults delete "$BUNDLE_ID" >/dev/null 2>&1
rm -rf "$HOME/Library/Application Support/SideScroll" \
       "$HOME/Library/Preferences/$BUNDLE_ID.plist" \
       "$HOME/Library/Caches/$BUNDLE_ID" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies" \
       "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
       "$HOME/Library/Logs/SideScroll"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1

bold "SideScroll removed."
