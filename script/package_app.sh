#!/usr/bin/env bash
set -euo pipefail

VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg|dmg)
      shift
      ;;
    --version)
      VERSION="${2:-}"
      if [[ -z "$VERSION" ]]; then
        echo "error: --version requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "usage: $0 [--dmg] [--version <version>]" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SubMax"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"

if [[ -z "$VERSION" ]]; then
  VERSION="$(date +%Y%m%d-%H%M%S)"
fi

ARCHIVE_BASENAME="${APP_NAME}-${VERSION}-macOS"
DMG_PATH="$RELEASE_DIR/${ARCHIVE_BASENAME}.dmg"

mkdir -p "$RELEASE_DIR"

"$ROOT_DIR/script/build_and_run.sh" --bundle

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

rm -f "$DMG_PATH"
TMP_DIR="$(mktemp -d "$RELEASE_DIR/dmg.XXXXXX")"
STAGING_DIR="$TMP_DIR/staging"
RW_DMG="$TMP_DIR/${ARCHIVE_BASENAME}.rw.dmg"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG" >/dev/null

hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" >/dev/null
rm -rf "$TMP_DIR"
echo "$DMG_PATH"
