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

trailing_slash_sentinel="TRAILING_SLASH_SENTINEL_SHOULD_NOT_LEAK"
trailing_slash_app_bundle="$fixture_root/$trailing_slash_sentinel/LithePG.app"
make_minimal_app_bundle "$trailing_slash_app_bundle"
if run_helper_capture "$output_file" "$trailing_slash_app_bundle/"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an app bundle path with a trailing slash"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not end with a slash"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$trailing_slash_sentinel"

symlink_sentinel="SYMLINK_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlink_target_bundle="$fixture_root/$symlink_sentinel/LithePG.app"
make_minimal_app_bundle "$symlink_target_bundle"
symlink_parent="$fixture_root/symlink-input"
mkdir -p "$symlink_parent"
symlinked_app_bundle="$symlink_parent/LithePG.app"
ln -s "$symlink_target_bundle" "$symlinked_app_bundle"
if run_helper_capture "$output_file" "$symlinked_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked app bundle path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not be a symlink"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlink_sentinel"

if run_helper_capture "$output_file" "$symlinked_app_bundle/"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked app bundle path with a trailing slash"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not end with a slash"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlink_sentinel"

dangling_symlink_sentinel="DANGLING_SYMLINK_TARGET_SENTINEL_SHOULD_NOT_LEAK"
dangling_symlink_parent="$fixture_root/dangling-symlink-input"
mkdir -p "$dangling_symlink_parent"
dangling_symlinked_app_bundle="$dangling_symlink_parent/LithePG.app"
dangling_symlink_target="$fixture_root/$dangling_symlink_sentinel/LithePG.app"
ln -s "$dangling_symlink_target" "$dangling_symlinked_app_bundle"
if run_helper_capture "$output_file" "$dangling_symlinked_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a dangling symlinked app bundle path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not be a symlink"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$dangling_symlink_sentinel"
assert_not_contains "$helper_output" "$dangling_symlinked_app_bundle"

symlinked_contents_sentinel="SYMLINKED_CONTENTS_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_contents_bundle="$fixture_root/symlinked-contents/LithePG.app"
make_minimal_app_bundle "$symlinked_contents_bundle"
symlinked_contents_target="$fixture_root/$symlinked_contents_sentinel/Contents-target"
mkdir -p "${symlinked_contents_target%/*}"
mv "$symlinked_contents_bundle/Contents" "$symlinked_contents_target"
ln -s "$symlinked_contents_target" "$symlinked_contents_bundle/Contents"
if run_helper_capture "$output_file" "$symlinked_contents_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked Contents directory"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: Contents directory must be a non-symlink directory"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_contents_sentinel"
assert_not_contains "$helper_output" "Contents-target"

symlinked_macos_sentinel="SYMLINKED_MACOS_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_macos_bundle="$fixture_root/symlinked-macos/LithePG.app"
make_minimal_app_bundle "$symlinked_macos_bundle"
symlinked_macos_target="$fixture_root/$symlinked_macos_sentinel/MacOS-target"
mkdir -p "${symlinked_macos_target%/*}"
mv "$symlinked_macos_bundle/Contents/MacOS" "$symlinked_macos_target"
ln -s "$symlinked_macos_target" "$symlinked_macos_bundle/Contents/MacOS"
if run_helper_capture "$output_file" "$symlinked_macos_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked Contents/MacOS directory"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: Contents/MacOS directory must be a non-symlink directory"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_macos_sentinel"
assert_not_contains "$helper_output" "MacOS-target"

symlinked_executable_sentinel="SYMLINKED_EXECUTABLE_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_executable_bundle="$fixture_root/symlinked-executable/LithePG.app"
make_minimal_app_bundle "$symlinked_executable_bundle"
symlinked_executable_target_dir="$fixture_root/$symlinked_executable_sentinel"
symlinked_executable_target="$symlinked_executable_target_dir/LithePGApp-target"
mkdir -p "$symlinked_executable_target_dir"
cat >"$symlinked_executable_target" <<'APP'
#!/usr/bin/env bash
printf 'LithePG symlink executable target fixture\n'
APP
chmod +x "$symlinked_executable_target"
rm "$symlinked_executable_bundle/Contents/MacOS/LithePGApp"
ln -s "$symlinked_executable_target" "$symlinked_executable_bundle/Contents/MacOS/LithePGApp"
if run_helper_capture "$output_file" "$symlinked_executable_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked app executable"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app executable must be a regular file"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_executable_sentinel"
assert_not_contains "$helper_output" "LithePGApp-target"

symlinked_plist_sentinel="SYMLINKED_INFO_PLIST_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_plist_bundle="$fixture_root/symlinked-info-plist/LithePG.app"
make_minimal_app_bundle "$symlinked_plist_bundle"
symlinked_plist_target_dir="$fixture_root/$symlinked_plist_sentinel"
symlinked_plist_target="$symlinked_plist_target_dir/Info-target.plist"
mkdir -p "$symlinked_plist_target_dir"
cp "$symlinked_plist_bundle/Contents/Info.plist" "$symlinked_plist_target"
rm "$symlinked_plist_bundle/Contents/Info.plist"
ln -s "$symlinked_plist_target" "$symlinked_plist_bundle/Contents/Info.plist"
if run_helper_capture "$output_file" "$symlinked_plist_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked Info.plist"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: Info.plist must be a regular file"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_plist_sentinel"
assert_not_contains "$helper_output" "Info-target.plist"

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
