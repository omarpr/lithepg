#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/package_verify.sh"

fail() {
  printf 'test_package_verify failed: %s\n' "$1" >&2
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
  <string>1.0</string>
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
    unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
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
make_minimal_app_bundle "$app_bundle"

if ! run_helper_capture "$output_file" --help; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier --help unexpectedly failed"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage:"
assert_contains "$helper_output" "LITHEPG_EXPECTED_MARKETING_VERSION"
assert_contains "$helper_output" "LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"

if ! run_helper_capture "$output_file" -h; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier -h unexpectedly failed"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage:"
assert_contains "$helper_output" "LITHEPG_EXPECTED_MARKETING_VERSION"
assert_contains "$helper_output" "LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"

if ! run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verification unexpectedly failed for a valid fixture"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: $app_bundle"
assert_contains "$helper_output" "Bundle ID: dev.omarpr.lithepg"
assert_contains "$helper_output" "Version: 1.0 (100)"

wrong_basename_bundle="$fixture_root/NotLithePG.app"
make_minimal_app_bundle "$wrong_basename_bundle"
if run_helper_capture "$output_file" "$wrong_basename_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an app bundle with the wrong basename"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle basename must be LithePG.app"
assert_not_contains "$helper_output" "Package verified:"

extra_arg_sentinel="EXTRA_ARG_SHOULD_NOT_BE_USED_OR_LEAKED"
if run_helper_capture "$output_file" "$app_bundle" "$extra_arg_sentinel"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an extra positional argument"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "too many arguments"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$extra_arg_sentinel"

printf 'test_package_verify passed\n'
