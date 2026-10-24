#!/usr/bin/env bash
# Builds build/SideScroll.app (universal: Apple silicon + Intel).
#   VERSION=0.1.5 scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat VERSION).0}"
BUILD="${BUILD_NUMBER:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

arch_args=()
for a in $ARCHS; do arch_args+=(--arch "$a"); done

echo "==> Compiling ($ARCHS)"
swift build -c release "${arch_args[@]}"
BIN_DIR="$(swift build -c release "${arch_args[@]}" --show-bin-path)"

APP="build/SideScroll.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SideScroll" "$APP/Contents/MacOS/SideScroll"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/sidescroll "$APP/Contents/Resources/sidescroll"
chmod +x "$APP/Contents/Resources/sidescroll"

echo "==> Icon"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing ($SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --verbose "$APP"

echo "==> Built $APP ($VERSION)"
