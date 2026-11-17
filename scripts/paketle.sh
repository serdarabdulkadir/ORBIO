#!/bin/bash
# ORBIO.app paketini uretir.
#   Yerel kullanim: scripts/paketle.sh [--ac] [--izin-sifirla]   -> ~/Applications/ORBIO.app
#   Surum paketi:   scripts/paketle.sh --release [--version X.Y.Z] -> dist/ORBIO.app, dist/ORBIO-macos-<surum>.zip, .sha256
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ORBIO"
BUNDLE_ID="com.btekosistem.mac"
ARGS=" $* "
RELEASE=0
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release) RELEASE=1 ;;
    --version) VERSION="${2:-}"; shift ;;
    --version=*) VERSION="${1#--version=}" ;;
    --ac|--izin-sifirla) ;;
    *) echo "Bilinmeyen secenek: $1" >&2; exit 2 ;;
  esac
  shift
done
PLIST_SRC="Sources/BTEkosistem/Info.plist"

if [ -z "$VERSION" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")"
fi
VERSION="${VERSION#v}"

swift build -c release

if [ "$RELEASE" = 1 ]; then
  OUT="dist"
  rm -rf "$OUT"
  mkdir -p "$OUT"
else
  OUT="$HOME/Applications"
  mkdir -p "$OUT"
fi
APP="$OUT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BTEkosistem "$APP/Contents/MacOS/BTEkosistem"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
if [ -n "${BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
cp assets/logo/final/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/logo/final/menubar/MenuBarIcon.png assets/logo/final/menubar/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# Ad-hoc imza (notarize degil)
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"

if [ "$RELEASE" = 1 ]; then
  ZIP="$OUT/$APP_NAME-macos-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  (cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  echo "Hazir: $APP"
  echo "Hazir: $ZIP"
  echo "Hazir: $ZIP.sha256"
  exit 0
fi

# Izin kaydini yalnizca istenirse sifirla (her paketlemede sifirlanirsa izin penceresi tekrar cikar)
case "$ARGS" in *" --izin-sifirla "*) tccutil reset Bluetooth "$BUNDLE_ID" >/dev/null 2>&1 || true ;; esac
pkill -x BTEkosistem 2>/dev/null || true
echo "Hazir: $APP"
case "$ARGS" in *" --ac "*) open "$APP" ;; esac
