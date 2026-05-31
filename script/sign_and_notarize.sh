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

is_approved() {
  case "${1:-}" in
    1|true|yes|approved)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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

validate_notary_zip_public_release_name() {
  [[ "$(basename "$ZIP_PATH")" != "LithePG.app.zip" ]] || fail "notary zip must not use public release artifact name"
}

validate_notary_zip_parent_dir() {
  local zip_parent
  zip_parent="$(dirname "$ZIP_PATH")"
  [[ -d "$zip_parent" ]] || fail "notary zip parent directory does not exist"
  [[ -w "$zip_parent" ]] || fail "notary zip parent directory is not writable"
}

validate_notary_zip_not_directory() {
  [[ ! -d "$ZIP_PATH" ]] || fail "notary zip path must not be a directory"
}

validate_notary_zip_overwrite() {
  if [[ ( -e "$ZIP_PATH" || -L "$ZIP_PATH" ) ]] && ! is_approved "${LITHEPG_NOTARY_ZIP_OVERWRITE:-}"; then
    fail "notary zip already exists; set LITHEPG_NOTARY_ZIP_OVERWRITE=approved to replace it"
  fi
}

ZIP_PATH="$(make_absolute_path "$ZIP_PATH")"
cd "$ROOT_DIR"
"$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE_ABS"
require_config
validate_notary_zip_location
validate_notary_zip_public_release_name
validate_notary_zip_parent_dir
validate_notary_zip_not_directory
validate_notary_zip_overwrite

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

STAGED_ZIP_DIR=""
cleanup_staged_zip() {
  if [[ -n "$STAGED_ZIP_DIR" ]]; then
    rm -rf -- "$STAGED_ZIP_DIR"
  fi
}
trap cleanup_staged_zip EXIT

ZIP_PARENT="$(dirname "$ZIP_PATH")"
STAGED_ZIP_DIR="$(mktemp -d "$ZIP_PARENT/.lithepg-notary.XXXXXX")"
chmod 700 "$STAGED_ZIP_DIR"
STAGED_ZIP="$STAGED_ZIP_DIR/$(basename "$ZIP_PATH")"

codesign \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_BUNDLE_ABS"

codesign --verify --strict --deep "$APP_BUNDLE_ABS"
ditto -c -k --keepParent "$APP_BUNDLE_ABS" "$STAGED_ZIP"
/usr/bin/perl -e 'use strict; use warnings; rename($ARGV[0], $ARGV[1]) or die "rename failed: $!\n";' "$STAGED_ZIP" "$ZIP_PATH" || fail "could not replace notary zip: $ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE_ABS"
xcrun stapler validate "$APP_BUNDLE_ABS"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE_ABS"

printf 'Signed and notarized: %s\n' "$APP_BUNDLE_ABS"
printf 'Notary zip: %s\n' "$ZIP_PATH"
