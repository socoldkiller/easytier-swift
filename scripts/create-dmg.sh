#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${EASYTIER_EXPORT_APP_DIR:-$HOME/Applications/EasyTier.app}}"
OUTPUT_DMG="${2:-$ROOT_DIR/.build/artifacts/EasyTier-macOS.dmg}"
VOLUME_NAME="${EASYTIER_DMG_VOLUME_NAME:-EasyTier}"
CERT_PATH="${EASYTIER_DMG_CODESIGN_CERT_PATH:-${EASYTIER_EXPORT_CODESIGN_CERT_PATH:-}}"
INSTALL_NOTES_PATH="${EASYTIER_DMG_INSTALL_NOTES_PATH:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -x "$APP_PATH/Contents/MacOS/EasyTierMac" ]]; then
  echo "EasyTierMac executable not found in app bundle: $APP_PATH" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required to create a macOS DMG." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/easytier-dmg.XXXXXX")"
DMG_ROOT="$STAGING_DIR/$VOLUME_NAME"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DMG_ROOT" "$(dirname "$OUTPUT_DMG")"

ditto --noextattr --norsrc "$APP_PATH" "$DMG_ROOT/EasyTier.app"
xattr -cr "$DMG_ROOT/EasyTier.app" 2>/dev/null || true
ln -s /Applications "$DMG_ROOT/Applications"

if [[ -n "$CERT_PATH" && -f "$CERT_PATH" ]]; then
  cp "$CERT_PATH" "$DMG_ROOT/EasyTierLocalCodeSigning.cer"
fi

if [[ -n "$INSTALL_NOTES_PATH" && -f "$INSTALL_NOTES_PATH" ]]; then
  cp "$INSTALL_NOTES_PATH" "$DMG_ROOT/SELF_SIGNED_INSTALL.txt"
fi

codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/EasyTier.app" >/dev/null

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG" >/dev/null

echo "$OUTPUT_DMG"
