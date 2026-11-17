#!/usr/bin/env bash
# ORBIO installer (macOS) / ORBIO kurucusu
# https://github.com/serdarabdulkadir/ORBIO
set -euo pipefail

REPO="serdarabdulkadir/ORBIO"
API="https://api.github.com/repos/${REPO}/releases"
DL_PREFIX="https://github.com/${REPO}/releases/download/"
APP_NAME="ORBIO"
BUNDLE_ID="com.btekosistem.mac"

VERSION=""
OPEN_AFTER=1
MODE="install"

usage() {
  cat <<'USAGE'
ORBIO installer / ORBIO kurucusu

Usage / Kullanim:
  install.sh [--version vX.Y.Z] [--no-open]
  install.sh --android [--version vX.Y.Z]
  install.sh --uninstall
  install.sh --help

  --version vX.Y.Z  Install a specific release (default: latest) / Belirli surumu kur (varsayilan: en son)
  --no-open         Do not launch the app afterwards / Kurulumdan sonra acma
  --android         Download the APK to ~/Downloads; install with adb if a device is connected
                    APK'yi ~/Downloads'a indirir; adb ve bagli cihaz varsa kurar
  --uninstall       Remove ORBIO.app / ORBIO.app'i kaldir

Note: ORBIO is ad-hoc signed, not notarized. After verifying the SHA-256 checksum this script
removes the macOS quarantine flag. / ORBIO notarize degildir; saglama toplami dogrulandiktan
sonra bu betik macOS karantina isaretini kaldirir.
USAGE
}

say() { printf '%s\n' "$*"; }
die() { printf 'Error / Hata: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || die "--version needs a value / --version bir deger ister"; VERSION="$2"; shift ;;
    --version=*) VERSION="${1#--version=}" ;;
    --no-open) OPEN_AFTER=0 ;;
    --uninstall) MODE="uninstall" ;;
    --android) MODE="android" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option / Bilinmeyen secenek: $1" ;;
  esac
  shift
done

if [ -n "$VERSION" ]; then
  case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
  printf '%s' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$' \
    || die "Invalid version / Gecersiz surum: $VERSION"
fi

command -v curl >/dev/null 2>&1 || die "curl not found / curl bulunamadi"

# --- uninstall ---------------------------------------------------------------
if [ "$MODE" = "uninstall" ]; then
  [ "$(uname -s)" = "Darwin" ] || die "macOS only / Yalnizca macOS"
  pkill -x BTEkosistem 2>/dev/null || true
  found=0
  for d in "/Applications" "$HOME/Applications"; do
    if [ -d "$d/$APP_NAME.app" ]; then
      rm -rf "$d/$APP_NAME.app" && say "Removed / Kaldirildi: $d/$APP_NAME.app"
      found=1
    fi
  done
  [ "$found" = 1 ] || say "ORBIO.app not found / ORBIO.app bulunamadi"
  say "User data (pairings) is kept in ~/Library/Application Support/BTrack. Delete it manually to remove it."
  say "Kullanici verisi (eslemeler) ~/Library/Application Support/BTrack altinda kalir; kaldirmak icin elle silin."
  exit 0
fi

# --- release lookup ----------------------------------------------------------
if [ -n "$VERSION" ]; then
  URL="${API}/tags/${VERSION}"
else
  URL="${API}/latest"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/orbio-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail_lookup() {
  cat >&2 <<MSG
Error / Hata: could not fetch release information (${URL}).
  - Check your internet connection, or GitHub API rate limit; try again later.
  - No release published yet? See https://github.com/${REPO}/releases
Hata: surum bilgisi alinamadi. Internet baglantinizi ve GitHub API sinirini kontrol edin,
  sonra tekrar deneyin. Henuz surum yayinlanmamis olabilir: https://github.com/${REPO}/releases
MSG
  exit 1
}

curl -fsSL --retry 2 -H "Accept: application/vnd.github+json" "$URL" -o "$TMP/release.json" || fail_lookup

# JSON parsing without jq: python3 (preferred), else grep
asset_urls() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -I - "$TMP/release.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("TAG\t" + d.get("tag_name", ""))
for a in d.get("assets", []):
    print("ASSET\t" + a.get("browser_download_url", ""))
PY
  else
    grep -o '"tag_name": *"[^"]*"' "$TMP/release.json" | head -n1 | sed 's/.*: *"\(.*\)"/TAG\t\1/'
    grep -o '"browser_download_url": *"[^"]*"' "$TMP/release.json" | sed 's/.*: *"\(.*\)"/ASSET\t\1/'
  fi
}

PARSED="$(asset_urls)" || fail_lookup
TAG="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="TAG"{print $2; exit}')"
[ -n "$TAG" ] || fail_lookup
printf '%s' "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$' || die "Unexpected tag / Beklenmeyen etiket: $TAG"
V="${TAG#v}"

pick_asset() { # $1 = exact file name
  printf '%s\n' "$PARSED" | awk -F'\t' -v want="${DL_PREFIX}${TAG}/$1" '$1=="ASSET" && $2==want {print $2; exit}'
}

# Download only from the official repo release path, then verify sha256.
fetch_verified() { # $1 = file name ; result in $TMP/$1
  local name="$1" file_url sum_url expected actual
  file_url="$(pick_asset "$name")"
  sum_url="$(pick_asset "$name.sha256")"
  [ -n "$file_url" ] || die "Release $TAG has no asset $name / $TAG surumunde $name dosyasi yok"
  [ -n "$sum_url" ] || die "No checksum file for $name; refusing to install unverified / $name icin sha256 dosyasi yok; dogrulanmamis kurulum yapilmaz"
  say "Downloading / Indiriliyor: $name"
  curl -fL --retry 2 --progress-bar "$file_url" -o "$TMP/$name" || die "Download failed / Indirme basarisiz: $name"
  curl -fsSL --retry 2 "$sum_url" -o "$TMP/$name.sha256" || die "Checksum download failed / Sha256 indirilemedi"
  expected="$(awk '{print tolower($1); exit}' "$TMP/$name.sha256")"
  printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$' || die "Bad checksum file / Gecersiz sha256 dosyasi"
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$TMP/$name" | awk '{print $1}')"
  else
    actual="$(sha256sum "$TMP/$name" | awk '{print $1}')"
  fi
  [ "$actual" = "$expected" ] || die "SHA-256 mismatch, aborting / SHA-256 uyusmuyor, islem durduruldu"
  say "SHA-256 OK / Dogrulandi"
}

# --- android -----------------------------------------------------------------
if [ "$MODE" = "android" ]; then
  APK="ORBIO-android-${V}.apk"
  fetch_verified "$APK"
  DEST="$HOME/Downloads"
  mkdir -p "$DEST"
  cp "$TMP/$APK" "$DEST/$APK"
  say "APK saved / APK kaydedildi: $DEST/$APK"
  if command -v adb >/dev/null 2>&1 && [ "$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')" -ge 1 ]; then
    say "Installing with adb / adb ile kuruluyor..."
    adb install -r "$DEST/$APK" && say "Done / Tamam"
  else
    say "No adb device found. Copy the APK to your phone and open it (allow unknown sources),"
    say "or enable USB debugging, connect the phone and run: adb install -r \"$DEST/$APK\""
    say "adb cihazi bulunamadi. APK'yi telefona aktarip acin (bilinmeyen kaynaklara izin verin) ya da"
    say "USB hata ayiklamayi acip telefonu baglayin ve yukaridaki adb komutunu calistirin."
  fi
  exit 0
fi

# --- macOS install -----------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "The Mac app installs on macOS only (use --android for the APK) / Mac uygulamasi yalnizca macOS'a kurulur (APK icin --android)"
for t in ditto unzip xattr; do command -v "$t" >/dev/null 2>&1 || die "$t not found / $t bulunamadi"; done

ZIP="ORBIO-macos-${V}.zip"
fetch_verified "$ZIP"

mkdir "$TMP/x"
ditto -x -k "$TMP/$ZIP" "$TMP/x"
[ -d "$TMP/x/$APP_NAME.app" ] || die "ORBIO.app missing in archive / Arsivde ORBIO.app yok"
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TMP/x/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || true)"
[ "$BID" = "$BUNDLE_ID" ] || die "Unexpected bundle id / Beklenmeyen bundle id: $BID"

if [ -d "/Applications" ] && [ -w "/Applications" ]; then
  DEST_DIR="/Applications"
else
  DEST_DIR="$HOME/Applications"
  mkdir -p "$DEST_DIR"
fi

if pgrep -x BTEkosistem >/dev/null 2>&1; then
  say "Closing running ORBIO / Calisan ORBIO kapatiliyor..."
  pkill -x BTEkosistem || true
  sleep 1
fi

rm -rf "$DEST_DIR/$APP_NAME.app"
ditto "$TMP/x/$APP_NAME.app" "$DEST_DIR/$APP_NAME.app"
xattr -dr com.apple.quarantine "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true

say "Installed / Kuruldu: $DEST_DIR/$APP_NAME.app ($TAG)"
say "Note: ad-hoc signed, not notarized. / Not: ad-hoc imzali, notarize degil."
if [ "$OPEN_AFTER" = 1 ]; then
  open "$DEST_DIR/$APP_NAME.app" || true
fi
