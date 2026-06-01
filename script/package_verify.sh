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

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true
}

while [[ "$APP_BUNDLE" != "/" && "$APP_BUNDLE" == */ ]]; do
  APP_BUNDLE="${APP_BUNDLE%/}"
done

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ "${APP_BUNDLE##*.}" == "app" ]] || fail "bundle path must end in .app"

CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_BINARY="$MACOS_DIR/$APP_NAME"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

[[ -d "$CONTENTS_DIR" ]] || fail "missing Contents directory"
[[ -d "$MACOS_DIR" ]] || fail "missing Contents/MacOS directory"
[[ -f "$APP_BINARY" ]] || fail "missing app executable: Contents/MacOS/$APP_NAME"
[[ -x "$APP_BINARY" ]] || fail "app executable is not executable"
[[ -f "$INFO_PLIST" ]] || fail "missing Info.plist"

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
