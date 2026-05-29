#!/usr/bin/env bash
set -euo pipefail

MODE="sign"
if [[ "${1:-}" == "--dry-run" ]]; then
  MODE="dry-run"
  shift
fi

APP_BUNDLE="${1:-dist/LithePG.app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_ABS="$APP_BUNDLE"
if [[ "$APP_BUNDLE_ABS" != /* ]]; then
  APP_BUNDLE_ABS="$ROOT_DIR/$APP_BUNDLE_ABS"
fi

BUNDLE_NAME="$(basename "$APP_BUNDLE_ABS" .app)"
DIST_DIR="$(dirname "$APP_BUNDLE_ABS")"
ZIP_PATH="${LITHEPG_NOTARY_ZIP:-$DIST_DIR/$BUNDLE_NAME-notary.zip}"
ENTITLEMENTS="${LITHEPG_ENTITLEMENTS:-$ROOT_DIR/Sources/LithePGApp/LithePGApp.entitlements}"
CODESIGN_IDENTITY="${LITHEPG_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${LITHEPG_NOTARY_PROFILE:-}"

fail() {
  printf 'sign/notarize failed: %s\n' "$1" >&2
  exit 1
}

require_config() {
  [[ -n "$CODESIGN_IDENTITY" ]] || fail "missing LITHEPG_CODESIGN_IDENTITY (Apple Developer Application signing identity)"
  [[ -n "$NOTARY_PROFILE" ]] || fail "missing LITHEPG_NOTARY_PROFILE (xcrun notarytool keychain profile name)"
  [[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements file: $ENTITLEMENTS"
}

cd "$ROOT_DIR"
"$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE_ABS"
require_config

if [[ "$MODE" == "dry-run" ]]; then
  printf 'Signing/notarization dry run OK. No changes made.\n'
  printf 'App bundle: %s\n' "$APP_BUNDLE_ABS"
  printf 'Codesign identity: %s\n' "$CODESIGN_IDENTITY"
  printf 'Notary profile: %s\n' "$NOTARY_PROFILE"
  printf 'Entitlements: %s\n' "$ENTITLEMENTS"
  printf 'Notary zip: %s\n' "$ZIP_PATH"
  printf 'Planned commands: codesign -> zip -> notarytool submit --wait -> stapler -> spctl/stapler validation\n'
  exit 0
fi

rm -f -- "$ZIP_PATH"

codesign \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_BUNDLE_ABS"

codesign --verify --strict --deep "$APP_BUNDLE_ABS"
ditto -c -k --keepParent "$APP_BUNDLE_ABS" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE_ABS"
xcrun stapler validate "$APP_BUNDLE_ABS"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE_ABS"

printf 'Signed and notarized: %s\n' "$APP_BUNDLE_ABS"
printf 'Notary zip: %s\n' "$ZIP_PATH"
