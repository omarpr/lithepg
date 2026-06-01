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
  chmod 755 "$app_bundle" "$app_bundle/Contents" "$app_bundle/Contents/MacOS"

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

  chmod 644 "$app_bundle/Contents/Info.plist"

  cat >"$app_bundle/Contents/MacOS/LithePGApp" <<'APP'
#!/usr/bin/env bash
printf 'LithePG test fixture\n'
APP
  chmod 755 "$app_bundle/Contents/MacOS/LithePGApp"
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

run_helper_capture_with_expected_marketing_version() {
  local output_file="$1"
  local expected_marketing_version="$2"
  shift 2
  set +e
  (
    cd "$ROOT_DIR"
    unset LITHEPG_EXPECTED_BUILD_VERSION
    LITHEPG_EXPECTED_MARKETING_VERSION="$expected_marketing_version" "$HELPER" "$@"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

run_helper_capture_with_expected_build_version() {
  local output_file="$1"
  local expected_build_version="$2"
  shift 2
  set +e
  (
    cd "$ROOT_DIR"
    unset LITHEPG_EXPECTED_MARKETING_VERSION
    LITHEPG_EXPECTED_BUILD_VERSION="$expected_build_version" "$HELPER" "$@"
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

metadata_cases=(
  "CFBundleExecutable|CFBundleExecutable mismatch"
  "CFBundleIdentifier|CFBundleIdentifier mismatch"
  "CFBundleName|CFBundleName mismatch"
  "CFBundlePackageType|CFBundlePackageType mismatch"
  "LSMinimumSystemVersion|LSMinimumSystemVersion mismatch"
  "NSPrincipalClass|NSPrincipalClass mismatch"
  "CFBundleShortVersionString|CFBundleShortVersionString is not a numeric release version"
  "CFBundleVersion|CFBundleVersion is not a numeric build version"
)
for metadata_case in "${metadata_cases[@]}"; do
  IFS='|' read -r metadata_key expected_failure <<<"$metadata_case"
  metadata_sentinel="${metadata_key}_METADATA_SENTINEL_SHOULD_NOT_LEAK"
  metadata_bundle="$fixture_root/metadata-$metadata_key/LithePG.app"
  make_minimal_app_bundle "$metadata_bundle"
  /usr/libexec/PlistBuddy -c "Set :$metadata_key $metadata_sentinel" "$metadata_bundle/Contents/Info.plist" >/dev/null
  if run_helper_capture "$output_file" "$metadata_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted invalid $metadata_key metadata"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: $expected_failure"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$metadata_sentinel"
  assert_not_contains "$helper_output" "$metadata_bundle"
done

expected_marketing_sentinel="EXPECTED_MARKETING_VERSION_SENTINEL_SHOULD_NOT_LEAK"
expected_marketing_bundle="$fixture_root/expected-marketing/LithePG.app"
make_minimal_app_bundle "$expected_marketing_bundle"
if run_helper_capture_with_expected_marketing_version "$output_file" "$expected_marketing_sentinel" "$expected_marketing_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted mismatched expected marketing version"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: CFBundleShortVersionString does not match LITHEPG_EXPECTED_MARKETING_VERSION"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$expected_marketing_sentinel"
assert_not_contains "$helper_output" "$expected_marketing_bundle"

expected_build_sentinel="EXPECTED_BUILD_VERSION_SENTINEL_SHOULD_NOT_LEAK"
expected_build_bundle="$fixture_root/expected-build/LithePG.app"
make_minimal_app_bundle "$expected_build_bundle"
if run_helper_capture_with_expected_build_version "$output_file" "$expected_build_sentinel" "$expected_build_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted mismatched expected build version"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: CFBundleVersion does not match LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$expected_build_sentinel"
assert_not_contains "$helper_output" "$expected_build_bundle"

missing_app_sentinel="MISSING_APP_SENTINEL_SHOULD_NOT_LEAK"
missing_app_bundle="$fixture_root/$missing_app_sentinel/LithePG.app"
if run_helper_capture "$output_file" "$missing_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a nonexistent LithePG.app path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle not found"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$missing_app_bundle"
assert_not_contains "$helper_output" "$missing_app_sentinel"

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

for unsafe_mode in 4755 2755 1755; do
  app_bundle_mode_sentinel="APP_BUNDLE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  app_bundle_mode_path="$fixture_root/app-bundle-mode-$unsafe_mode-$app_bundle_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$app_bundle_mode_path"
  chmod "$unsafe_mode" "$app_bundle_mode_path"
  if run_helper_capture "$output_file" "$app_bundle_mode_path"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on LithePG.app"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app bundle directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$app_bundle_mode_path"
  assert_not_contains "$helper_output" "$app_bundle_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 775 757; do
  app_bundle_mode_sentinel="APP_BUNDLE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  app_bundle_mode_path="$fixture_root/app-bundle-mode-$unsafe_mode-$app_bundle_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$app_bundle_mode_path"
  chmod "$unsafe_mode" "$app_bundle_mode_path"
  if run_helper_capture "$output_file" "$app_bundle_mode_path"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on LithePG.app"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app bundle directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$app_bundle_mode_path"
  assert_not_contains "$helper_output" "$app_bundle_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

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

for unsafe_mode in 4755 2755 1755; do
  contents_mode_sentinel="CONTENTS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  contents_mode_bundle="$fixture_root/contents-mode-$unsafe_mode-$contents_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$contents_mode_bundle"
  chmod "$unsafe_mode" "$contents_mode_bundle/Contents"
  if run_helper_capture "$output_file" "$contents_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$contents_mode_bundle"
  assert_not_contains "$helper_output" "$contents_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 775 757; do
  contents_mode_sentinel="CONTENTS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  contents_mode_bundle="$fixture_root/contents-mode-$unsafe_mode-$contents_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$contents_mode_bundle"
  chmod "$unsafe_mode" "$contents_mode_bundle/Contents"
  if run_helper_capture "$output_file" "$contents_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$contents_mode_bundle"
  assert_not_contains "$helper_output" "$contents_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 4755 2755 1755; do
  macos_mode_sentinel="MACOS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  macos_mode_bundle="$fixture_root/macos-mode-$unsafe_mode-$macos_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$macos_mode_bundle"
  chmod "$unsafe_mode" "$macos_mode_bundle/Contents/MacOS"
  if run_helper_capture "$output_file" "$macos_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents/MacOS"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents/MacOS directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$macos_mode_bundle"
  assert_not_contains "$helper_output" "$macos_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 775 757; do
  macos_mode_sentinel="MACOS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  macos_mode_bundle="$fixture_root/macos-mode-$unsafe_mode-$macos_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$macos_mode_bundle"
  chmod "$unsafe_mode" "$macos_mode_bundle/Contents/MacOS"
  if run_helper_capture "$output_file" "$macos_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents/MacOS"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents/MacOS directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$macos_mode_bundle"
  assert_not_contains "$helper_output" "$macos_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

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

for unsafe_mode in 4755 2755 1755; do
  info_plist_special_mode_sentinel="INFO_PLIST_SPECIAL_MODE_SENTINEL_SHOULD_NOT_LEAK"
  info_plist_special_mode_bundle="$fixture_root/info-plist-special-mode-$unsafe_mode-$info_plist_special_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$info_plist_special_mode_bundle"
  chmod "$unsafe_mode" "$info_plist_special_mode_bundle/Contents/Info.plist"
  if run_helper_capture "$output_file" "$info_plist_special_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted special mode $unsafe_mode on Info.plist"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Info.plist mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$info_plist_special_mode_bundle"
  assert_not_contains "$helper_output" "$info_plist_special_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 664 646; do
  info_plist_writable_mode_sentinel="INFO_PLIST_WRITABLE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  info_plist_writable_mode_bundle="$fixture_root/info-plist-writable-mode-$unsafe_mode-$info_plist_writable_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$info_plist_writable_mode_bundle"
  chmod "$unsafe_mode" "$info_plist_writable_mode_bundle/Contents/Info.plist"
  if run_helper_capture "$output_file" "$info_plist_writable_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted mode $unsafe_mode on Info.plist"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Info.plist mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$info_plist_writable_mode_bundle"
  assert_not_contains "$helper_output" "$info_plist_writable_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

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

for unsafe_mode in 4755 2755 1755; do
  special_mode_bundle="$fixture_root/special-mode-$unsafe_mode/LithePG.app"
  make_minimal_app_bundle "$special_mode_bundle"
  chmod "$unsafe_mode" "$special_mode_bundle/Contents/MacOS/LithePGApp"
  if run_helper_capture "$output_file" "$special_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted special mode $unsafe_mode on the app executable"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app executable mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
done

for unsafe_mode in 775 757; do
  writable_mode_bundle="$fixture_root/writable-mode-$unsafe_mode/LithePG.app"
  make_minimal_app_bundle "$writable_mode_bundle"
  chmod "$unsafe_mode" "$writable_mode_bundle/Contents/MacOS/LithePGApp"
  if run_helper_capture "$output_file" "$writable_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted mode $unsafe_mode on the app executable"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app executable mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
done

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
