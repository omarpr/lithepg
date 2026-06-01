#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LithePGApp"
BUNDLE_NAME="LithePG"
EXPECTED_BUNDLE_ID="dev.omarpr.lithepg"
EXPECTED_MIN_SYSTEM_VERSION="14.0"
HARD_CAP_BYTES=$((50 * 1024 * 1024))

fail() {
  printf 'package verification failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: script/package_verify.sh [APP_BUNDLE]

Verify a LithePG.app bundle. APP_BUNDLE defaults to dist/LithePG.app.

Optional environment:
  LITHEPG_EXPECTED_MARKETING_VERSION  Expected CFBundleShortVersionString.
  LITHEPG_EXPECTED_BUILD_VERSION      Expected CFBundleVersion.
USAGE
}

[[ "$#" -le 1 ]] || fail "too many arguments"
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

APP_BUNDLE="${1:-dist/LithePG.app}"

if [[ "$#" -eq 1 && "$APP_BUNDLE" == */ && ! "$APP_BUNDLE" =~ ^/+$ ]]; then
  fail "app bundle path must not end with a slash"
fi

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true
}

while [[ "$APP_BUNDLE" != "/" && "$APP_BUNDLE" == */ ]]; do
  APP_BUNDLE="${APP_BUNDLE%/}"
done

[[ "${APP_BUNDLE##*.}" == "app" ]] || fail "bundle path must end in .app"
[[ "${APP_BUNDLE##*/}" == "LithePG.app" ]] || fail "app bundle basename must be LithePG.app"
[[ ! -L "$APP_BUNDLE" ]] || fail "app bundle path must not be a symlink"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found"
app_bundle_mode="$(stat -f%p "$APP_BUNDLE")"
if (( (8#$app_bundle_mode & 07022) != 0 )); then
  fail "app bundle directory mode is unsafe"
fi

CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_BINARY="$MACOS_DIR/$APP_NAME"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

[[ -d "$CONTENTS_DIR" && ! -L "$CONTENTS_DIR" ]] || fail "Contents directory must be a non-symlink directory"
contents_dir_mode="$(stat -f%p "$CONTENTS_DIR")"
if (( (8#$contents_dir_mode & 07022) != 0 )); then
  fail "Contents directory mode is unsafe"
fi
[[ -d "$MACOS_DIR" && ! -L "$MACOS_DIR" ]] || fail "Contents/MacOS directory must be a non-symlink directory"
macos_dir_mode="$(stat -f%p "$MACOS_DIR")"
if (( (8#$macos_dir_mode & 07022) != 0 )); then
  fail "Contents/MacOS directory mode is unsafe"
fi
[[ -f "$APP_BINARY" && ! -L "$APP_BINARY" ]] || fail "app executable must be a regular file"
[[ -x "$APP_BINARY" ]] || fail "app executable is not executable"
app_binary_mode="$(stat -f%p "$APP_BINARY")"
if (( (8#$app_binary_mode & 07022) != 0 )); then
  fail "app executable mode is unsafe"
fi
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]] || fail "Info.plist must be a regular file"
info_plist_mode="$(stat -f%p "$INFO_PLIST")"
if (( (8#$info_plist_mode & 07022) != 0 )); then
  fail "Info.plist mode is unsafe"
fi

executable="$(plist_value CFBundleExecutable)"
bundle_id="$(plist_value CFBundleIdentifier)"
bundle_name="$(plist_value CFBundleName)"
package_type="$(plist_value CFBundlePackageType)"
minimum_system="$(plist_value LSMinimumSystemVersion)"
principal_class="$(plist_value NSPrincipalClass)"
marketing_version="$(plist_value CFBundleShortVersionString)"
build_version="$(plist_value CFBundleVersion)"

[[ "$executable" == "$APP_NAME" ]] || fail "CFBundleExecutable is '$executable', expected '$APP_NAME'"
[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "CFBundleIdentifier is '$bundle_id', expected '$EXPECTED_BUNDLE_ID'"
[[ "$bundle_name" == "$BUNDLE_NAME" ]] || fail "CFBundleName is '$bundle_name', expected '$BUNDLE_NAME'"
[[ "$package_type" == "APPL" ]] || fail "CFBundlePackageType is '$package_type', expected 'APPL'"
[[ "$minimum_system" == "$EXPECTED_MIN_SYSTEM_VERSION" ]] || fail "LSMinimumSystemVersion is '$minimum_system', expected '$EXPECTED_MIN_SYSTEM_VERSION'"
[[ "$principal_class" == "NSApplication" ]] || fail "NSPrincipalClass is '$principal_class', expected 'NSApplication'"
[[ "$marketing_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "CFBundleShortVersionString is '$marketing_version', expected numeric release version"
[[ "$build_version" =~ ^[0-9]+$ ]] || fail "CFBundleVersion is '$build_version', expected numeric build version"

if [[ -n "${LITHEPG_EXPECTED_MARKETING_VERSION:-}" ]]; then
  [[ "$marketing_version" == "$LITHEPG_EXPECTED_MARKETING_VERSION" ]] || fail "CFBundleShortVersionString is '$marketing_version', expected '$LITHEPG_EXPECTED_MARKETING_VERSION' from LITHEPG_EXPECTED_MARKETING_VERSION"
fi

if [[ -n "${LITHEPG_EXPECTED_BUILD_VERSION:-}" ]]; then
  [[ "$build_version" == "$LITHEPG_EXPECTED_BUILD_VERSION" ]] || fail "CFBundleVersion is '$build_version', expected '$LITHEPG_EXPECTED_BUILD_VERSION' from LITHEPG_EXPECTED_BUILD_VERSION"
fi

bytes=$(stat -f%z "$APP_BINARY")
if [[ "$bytes" -gt "$HARD_CAP_BYTES" ]]; then
  mib=$(awk "BEGIN { printf \"%.2f\", $bytes / 1024 / 1024 }")
  fail "app executable exceeds 50 MiB hard cap: ${mib} MiB"
fi

mib=$(awk "BEGIN { printf \"%.2f\", $bytes / 1024 / 1024 }")
printf 'Package verified: %s\n' "$APP_BUNDLE"
printf 'Executable: Contents/MacOS/%s (%s bytes / %s MiB)\n' "$APP_NAME" "$bytes" "$mib"
printf 'Bundle ID: %s\n' "$bundle_id"
printf 'Version: %s (%s)\n' "$marketing_version" "$build_version"
if [[ -n "${LITHEPG_EXPECTED_MARKETING_VERSION:-}" ]]; then
  printf 'Expected marketing version: %s\n' "$LITHEPG_EXPECTED_MARKETING_VERSION"
fi
if [[ -n "${LITHEPG_EXPECTED_BUILD_VERSION:-}" ]]; then
  printf 'Expected build version: %s\n' "$LITHEPG_EXPECTED_BUILD_VERSION"
fi
printf 'Minimum system: %s\n' "$minimum_system"
