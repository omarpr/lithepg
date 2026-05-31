#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/sign_and_notarize.sh"

fail() {
  printf 'test_sign_and_notarize failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "output leaked forbidden value: $needle"
}

make_minimal_app_bundle() {
  local app_bundle="$1"
  mkdir -p "$app_bundle/Contents/MacOS"

  cat >"$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>LithePGApp</string>
  <key>CFBundleIdentifier</key>
  <string>dev.omarpr.lithepg</string>
  <key>CFBundleName</key>
  <string>LithePG</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>100</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  cat >"$app_bundle/Contents/MacOS/LithePGApp" <<'APP'
#!/usr/bin/env bash
printf 'LithePG test fixture\n'
APP
  chmod +x "$app_bundle/Contents/MacOS/LithePGApp"
}

run_helper_capture() {
  local output_file="$1"
  shift
  set +e
  (
    cd "$ROOT_DIR"
    "$HELPER" "$@"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

output_file="$(mktemp)"
fixture_root="$(mktemp -d)"
trap 'rm -f "$output_file"; rm -rf "$fixture_root"' EXIT

app_bundle="$fixture_root/LithePG.app"
notary_zip="$fixture_root/LithePG-notary.zip"
codesign_sentinel='Developer ID Application: SHOULD_NOT_LEAK'
notary_sentinel='NOTARY_PROFILE_SHOULD_NOT_LEAK'

make_minimal_app_bundle "$app_bundle"

if ! LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly failed"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_contains "$helper_output" "Codesign identity: present (redacted)"
assert_contains "$helper_output" "Notary profile: present (redacted)"
[[ ! -e "$notary_zip" ]] || fail "dry run created notary zip: $notary_zip"

printf 'test_sign_and_notarize passed\n'
