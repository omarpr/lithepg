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
non_writable_notary_zip_parent=""
cleanup() {
  if [[ -n "$non_writable_notary_zip_parent" && -d "$non_writable_notary_zip_parent" ]]; then
    chmod u+w "$non_writable_notary_zip_parent" 2>/dev/null || true
  fi
  rm -f "$output_file"
  rm -rf "$fixture_root"
}
trap cleanup EXIT

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

existing_notary_zip_marker='EXISTING_NOTARY_ZIP_SHOULD_SURVIVE'
printf '%s\n' "$existing_notary_zip_marker" >"$notary_zip"

if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with existing notary zip without overwrite approval"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip already exists; set LITHEPG_NOTARY_ZIP_OVERWRITE=approved to replace it"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_contains "$(<"$notary_zip")" "$existing_notary_zip_marker"

if ! LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  LITHEPG_NOTARY_ZIP_OVERWRITE=approved \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly failed with existing notary zip and overwrite approval"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_contains "$helper_output" "Codesign identity: present (redacted)"
assert_contains "$helper_output" "Notary profile: present (redacted)"
assert_contains "$(<"$notary_zip")" "$existing_notary_zip_marker"

fake_bin="$fixture_root/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/codesign" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat >"$fake_bin/ditto" <<'SHIM'
#!/usr/bin/env bash
printf 'fake ditto failed before zip creation\n' >&2
exit 42
SHIM
cat >"$fake_bin/xcrun" <<'SHIM'
#!/usr/bin/env bash
printf 'unexpected xcrun invocation after ditto failure\n' >&2
exit 99
SHIM
cat >"$fake_bin/spctl" <<'SHIM'
#!/usr/bin/env bash
printf 'unexpected spctl invocation after ditto failure\n' >&2
exit 99
SHIM
chmod +x "$fake_bin/codesign" "$fake_bin/ditto" "$fake_bin/xcrun" "$fake_bin/spctl"

printf '%s\n' "$existing_notary_zip_marker" >"$notary_zip"
if PATH="$fake_bin:$PATH" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  LITHEPG_NOTARY_ZIP_OVERWRITE=approved \
  run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly passed when ditto failed"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "fake ditto failed before zip creation"
assert_not_contains "$helper_output" "unexpected xcrun invocation"
assert_not_contains "$helper_output" "unexpected spctl invocation"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -f "$notary_zip" ]] || fail "real mode zip-creation failure removed existing approved notary zip"
[[ "$(<"$notary_zip")" == "$existing_notary_zip_marker" ]] || fail "real mode zip-creation failure changed existing approved notary zip"

for overwrite_approval in 1 true yes; do
  if ! LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$notary_zip" \
    LITHEPG_NOTARY_ZIP_OVERWRITE="$overwrite_approval" \
    run_helper_capture "$output_file" --dry-run "$app_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "dry run unexpectedly failed with documented overwrite approval: $overwrite_approval"
  fi

  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "Signing/notarization dry run OK"
  assert_not_contains "$helper_output" "$codesign_sentinel"
  assert_not_contains "$helper_output" "$notary_sentinel"
  assert_contains "$helper_output" "Codesign identity: present (redacted)"
  assert_contains "$helper_output" "Notary profile: present (redacted)"
  assert_contains "$(<"$notary_zip")" "$existing_notary_zip_marker"
done

dangling_notary_zip="$fixture_root/LithePG-dangling-notary.zip"
dangling_notary_zip_target="$fixture_root/missing-dangling-notary-target.zip"
ln -s "$dangling_notary_zip_target" "$dangling_notary_zip"
[[ -L "$dangling_notary_zip" && ! -e "$dangling_notary_zip" ]] || fail "failed to create dangling notary zip symlink fixture"

if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$dangling_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  [[ -L "$dangling_notary_zip" && ! -e "$dangling_notary_zip" ]] || fail "dry run removed dangling notary zip symlink before passing without overwrite approval"
  fail "dry run unexpectedly passed with dangling symlink notary zip without overwrite approval"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip already exists; set LITHEPG_NOTARY_ZIP_OVERWRITE=approved to replace it"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -L "$dangling_notary_zip" && ! -e "$dangling_notary_zip" ]] || fail "dry run removed dangling notary zip symlink: $dangling_notary_zip"

if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  LITHEPG_NOTARY_ZIP_OVERWRITE=TRUE \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with undocumented uppercase overwrite approval"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip already exists; set LITHEPG_NOTARY_ZIP_OVERWRITE=approved to replace it"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_contains "$(<"$notary_zip")" "$existing_notary_zip_marker"

public_release_named_notary_zip="$fixture_root/LithePG.app.zip"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$public_release_named_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with public release artifact notary zip basename"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip must not use public release artifact name"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$public_release_named_notary_zip" ]] || fail "dry run created public release named notary zip: $public_release_named_notary_zip"

inside_bundle_notary_zip="$app_bundle/Contents/Resources/LithePG-notary.zip"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$inside_bundle_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with inside-bundle notary zip"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip must not be inside app bundle"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$inside_bundle_notary_zip" ]] || fail "dry run created inside-bundle notary zip: $inside_bundle_notary_zip"

missing_parent_notary_zip="$fixture_root/missing-parent/LithePG-notary.zip"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$missing_parent_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with missing notary zip parent directory"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip parent directory does not exist"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$missing_parent_notary_zip" ]] || fail "dry run created notary zip with missing parent: $missing_parent_notary_zip"

non_writable_notary_zip_parent="$fixture_root/non-writable-parent"
non_writable_parent_notary_zip="$non_writable_notary_zip_parent/LithePG-notary.zip"
mkdir -p "$non_writable_notary_zip_parent"
chmod a-w "$non_writable_notary_zip_parent"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$non_writable_parent_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with non-writable notary zip parent directory"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip parent directory is not writable"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$non_writable_parent_notary_zip" ]] || fail "dry run created notary zip with non-writable parent: $non_writable_parent_notary_zip"
chmod u+w "$non_writable_notary_zip_parent"

printf 'test_sign_and_notarize passed\n'
