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

make_absolute_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

canonicalize_path_for_location_check() {
  local path="$1"
  local absolute_path
  absolute_path="$(make_absolute_path "$path")"

  local dir
  local tail
  dir="$(dirname "$absolute_path")"
  tail="$(basename "$absolute_path")"

  while [[ "$dir" != "/" && ! -d "$dir" ]]; do
    tail="$(basename "$dir")/$tail"
    dir="$(dirname "$dir")"
  done

  if [[ -d "$dir" ]]; then
    local physical_dir
    physical_dir="$(cd "$dir" && pwd -P)"
    if [[ "$physical_dir" == "/" ]]; then
      printf '/%s\n' "$tail"
    else
      printf '%s/%s\n' "$physical_dir" "$tail"
    fi
  else
    printf '%s\n' "$absolute_path"
  fi
}

require_config() {
  [[ -n "$CODESIGN_IDENTITY" ]] || fail "missing LITHEPG_CODESIGN_IDENTITY (Apple Developer Application signing identity)"
  [[ -n "$NOTARY_PROFILE" ]] || fail "missing LITHEPG_NOTARY_PROFILE (xcrun notarytool keychain profile name)"
  [[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements file: $ENTITLEMENTS"
}

validate_notary_zip_location() {
  local app_bundle_check_path
  local zip_check_path
  app_bundle_check_path="$(canonicalize_path_for_location_check "$APP_BUNDLE_ABS")"
  zip_check_path="$(canonicalize_path_for_location_check "$ZIP_PATH")"

  if [[ "$zip_check_path" == "$app_bundle_check_path" || "$zip_check_path" == "$app_bundle_check_path/"* ]]; then
    fail "notary zip must not be inside app bundle"
  fi
}

cd "$ROOT_DIR"
"$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE_ABS"
require_config
validate_notary_zip_location

if [[ "$MODE" == "dry-run" ]]; then
  printf 'Signing/notarization dry run OK. No changes made.\n'
  printf 'App bundle: %s\n' "$APP_BUNDLE_ABS"
  printf 'Codesign identity: present (redacted)\n'
  printf 'Notary profile: present (redacted)\n'
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
