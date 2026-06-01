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

  cp /usr/bin/true "$app_bundle/Contents/MacOS/LithePGApp"
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
  run_helper_capture "$output_file" --help; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "--help did not exit 0"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage: sign_and_notarize.sh [--dry-run] [app-bundle]"
assert_contains "$helper_output" "LITHEPG_CODESIGN_IDENTITY"
assert_contains "$helper_output" "LITHEPG_NOTARY_PROFILE"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$notary_zip" ]] || fail "--help created notary zip: $notary_zip"

if ! LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  run_helper_capture "$output_file" --dry-run --help; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "--dry-run --help did not exit 0"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage: sign_and_notarize.sh [--dry-run] [app-bundle]"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$notary_zip" ]] || fail "--dry-run --help created notary zip: $notary_zip"

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

redacted_dry_run_sentinel="SIGN_AND_NOTARIZE_DRY_RUN_PATH_SHOULD_NOT_LEAK"
redacted_dry_run_app_parent="$fixture_root/$redacted_dry_run_sentinel-app-parent"
redacted_dry_run_app_bundle="$redacted_dry_run_app_parent/LithePG.app"
redacted_dry_run_entitlements_parent="$fixture_root/$redacted_dry_run_sentinel-entitlements-parent"
redacted_dry_run_entitlements="$redacted_dry_run_entitlements_parent/LithePG.entitlements"
redacted_dry_run_notary_parent="$fixture_root/$redacted_dry_run_sentinel-notary-parent"
redacted_dry_run_notary_zip="$redacted_dry_run_notary_parent/LithePG-notary.zip"
mkdir -p "$redacted_dry_run_entitlements_parent" "$redacted_dry_run_notary_parent"
make_minimal_app_bundle "$redacted_dry_run_app_bundle"
printf '<plist version="1.0"><dict/></plist>\n' >"$redacted_dry_run_entitlements"

if ! LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_ENTITLEMENTS="$redacted_dry_run_entitlements" \
  LITHEPG_NOTARY_ZIP="$redacted_dry_run_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$redacted_dry_run_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly failed while checking redacted local paths"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Signing/notarization dry run OK"
assert_contains "$helper_output" "App bundle: LithePG.app"
assert_contains "$helper_output" "Entitlements: configured (redacted)"
assert_contains "$helper_output" "Notary zip: configured (redacted)"
assert_contains "$helper_output" "Codesign identity: present (redacted)"
assert_contains "$helper_output" "Notary profile: present (redacted)"
assert_not_contains "$helper_output" "$redacted_dry_run_sentinel"
assert_not_contains "$helper_output" "$redacted_dry_run_app_parent"
assert_not_contains "$helper_output" "$redacted_dry_run_app_bundle"
assert_not_contains "$helper_output" "$redacted_dry_run_entitlements"
assert_not_contains "$helper_output" "$redacted_dry_run_notary_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$redacted_dry_run_notary_zip" ]] || fail "dry run created redacted-path notary zip: $redacted_dry_run_notary_zip"

missing_entitlements_sentinel="SIGN_AND_NOTARIZE_MISSING_ENTITLEMENTS_PATH_SHOULD_NOT_LEAK"
missing_entitlements_parent="$fixture_root/$missing_entitlements_sentinel-entitlements-parent"
missing_entitlements="$missing_entitlements_parent/LithePG.entitlements"
missing_entitlements_notary_zip="$fixture_root/LithePG-missing-entitlements-notary.zip"
mkdir -p "$missing_entitlements_parent"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_ENTITLEMENTS="$missing_entitlements" \
  LITHEPG_NOTARY_ZIP="$missing_entitlements_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  [[ ! -e "$missing_entitlements_notary_zip" ]] || fail "dry run created notary zip before rejecting missing entitlements: $missing_entitlements_notary_zip"
  fail "dry run unexpectedly passed with missing entitlements file"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "missing entitlements file"
assert_not_contains "$helper_output" "$missing_entitlements_sentinel"
assert_not_contains "$helper_output" "$missing_entitlements_parent"
assert_not_contains "$helper_output" "$missing_entitlements"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$missing_entitlements_notary_zip" ]] || fail "dry run created notary zip after rejecting missing entitlements: $missing_entitlements_notary_zip"

trailing_slash_notary_zip_base="$fixture_root/LithePG-trailing-slash-notary.zip"
trailing_slash_notary_zip="$trailing_slash_notary_zip_base///"
trailing_slash_fake_bin="$fixture_root/trailing-slash-fake-bin"
trailing_slash_ops_marker="$fixture_root/trailing-slash-signing-ops-ran"
mkdir -p "$trailing_slash_fake_bin"
for signing_op in codesign ditto spctl xcrun; do
  cat >"$trailing_slash_fake_bin/$signing_op" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "$signing_op" >>"$trailing_slash_ops_marker"
printf 'unexpected signing/notary operation invoked\n' >&2
exit 97
SHIM
  chmod +x "$trailing_slash_fake_bin/$signing_op"
done

if PATH="$trailing_slash_fake_bin:$PATH" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$trailing_slash_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  [[ ! -e "$trailing_slash_notary_zip_base" ]] || fail "dry run created trailing-slash notary zip path before passing: $trailing_slash_notary_zip_base"
  [[ ! -e "$trailing_slash_ops_marker" ]] || fail "dry run invoked signing/notary operation before passing with trailing-slash notary zip path"
  fail "dry run unexpectedly passed with trailing-slash notary zip path"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip path must not end with a slash"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "unexpected signing/notary operation invoked"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$trailing_slash_notary_zip_base" ]] || fail "dry run created trailing-slash notary zip path: $trailing_slash_notary_zip_base"
[[ ! -e "$trailing_slash_notary_zip" ]] || fail "dry run created trailing-slash notary zip directory: $trailing_slash_notary_zip"
[[ ! -e "$trailing_slash_ops_marker" ]] || fail "dry run invoked signing/notary operation with trailing-slash notary zip path"

extra_arg_notary_zip="$fixture_root/LithePG-extra-arg-notary.zip"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$extra_arg_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle" "$fixture_root/ignored-extra-argument"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  [[ ! -e "$extra_arg_notary_zip" ]] || fail "dry run created notary zip before rejecting extra arguments: $extra_arg_notary_zip"
  fail "dry run unexpectedly passed with an extra positional argument"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "too many arguments"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$extra_arg_notary_zip" ]] || fail "dry run created notary zip after rejecting extra arguments: $extra_arg_notary_zip"

noncanonical_app_bundle="$fixture_root/NotLithePG.app"
noncanonical_notary_zip="$fixture_root/NotLithePG-notary.zip"
make_minimal_app_bundle "$noncanonical_app_bundle"

if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$noncanonical_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$noncanonical_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  [[ ! -e "$noncanonical_notary_zip" ]] || fail "dry run created notary zip for non-canonical app bundle before passing: $noncanonical_notary_zip"
  fail "dry run unexpectedly passed with non-canonical app bundle basename: $noncanonical_app_bundle"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app bundle basename must be LithePG.app"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$noncanonical_notary_zip" ]] || fail "dry run created notary zip for non-canonical app bundle: $noncanonical_notary_zip"

symlinked_app_target="$fixture_root/RealLithePG.app"
symlinked_app_parent="$fixture_root/symlinked-app-input"
symlinked_app_bundle="$symlinked_app_parent/LithePG.app"
mkdir -p "$symlinked_app_parent"
make_minimal_app_bundle "$symlinked_app_target"
ln -s "$symlinked_app_target" "$symlinked_app_bundle"
[[ -L "$symlinked_app_bundle" ]] || fail "failed to create symlinked app bundle fixture"

symlinked_app_inputs=("$symlinked_app_bundle" "$symlinked_app_bundle/")
symlinked_app_labels=("final-symlink" "final-symlink-trailing-slash")
for symlinked_app_index in "${!symlinked_app_inputs[@]}"; do
  symlinked_app_input="${symlinked_app_inputs[$symlinked_app_index]}"
  symlinked_app_label="${symlinked_app_labels[$symlinked_app_index]}"
  symlinked_app_notary_zip="$fixture_root/LithePG-symlinked-app-notary-$symlinked_app_label.zip"
  if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$symlinked_app_notary_zip" \
    run_helper_capture "$output_file" --dry-run "$symlinked_app_input"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    [[ -L "$symlinked_app_bundle" ]] || fail "dry run changed symlinked app bundle before passing: $symlinked_app_bundle"
    [[ ! -e "$symlinked_app_notary_zip" ]] || fail "dry run created notary zip for symlinked app bundle before passing: $symlinked_app_notary_zip"
    fail "dry run unexpectedly passed with symlinked app bundle input: $symlinked_app_input"
  fi

  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "app bundle path must not be a symlink"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "Signing/notarization dry run OK"
  assert_not_contains "$helper_output" "$codesign_sentinel"
  assert_not_contains "$helper_output" "$notary_sentinel"
  [[ -L "$symlinked_app_bundle" ]] || fail "dry run changed symlinked app bundle: $symlinked_app_bundle"
  [[ ! -e "$symlinked_app_notary_zip" ]] || fail "dry run created notary zip for symlinked app bundle: $symlinked_app_notary_zip"
done

loop_notary_zip_sentinel="SIGN_AND_NOTARIZE_LOOP_ZIP_PATH_SHOULD_NOT_LEAK"
loop_notary_parent="$fixture_root/$loop_notary_zip_sentinel-parent"
loop_notary_a="$loop_notary_parent/a"
loop_notary_b="$loop_notary_parent/b"
loop_notary_zip="$loop_notary_a/LithePG-notary.zip"
mkdir -p "$loop_notary_parent"
ln -s b "$loop_notary_a"
ln -s a "$loop_notary_b"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$loop_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with symlink-loop notary zip path"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "could not validate notary zip path"
assert_not_contains "$helper_output" "too many symlinks"
assert_not_contains "$helper_output" "$loop_notary_zip_sentinel"
assert_not_contains "$helper_output" "$loop_notary_parent"
assert_not_contains "$helper_output" "$loop_notary_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -L "$loop_notary_a" ]] || fail "dry run changed symlink-loop notary zip fixture link a: $loop_notary_a"
[[ -L "$loop_notary_b" ]] || fail "dry run changed symlink-loop notary zip fixture link b: $loop_notary_b"

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

notary_zip_directory="$fixture_root/LithePG-directory-notary.zip"
mkdir -p "$notary_zip_directory"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip_directory" \
  LITHEPG_NOTARY_ZIP_OVERWRITE=approved \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with directory notary zip path"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip path must not be a directory"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -d "$notary_zip_directory" ]] || fail "dry run changed directory notary zip path: $notary_zip_directory"

staging_mktemp_sentinel="SIGN_MKTEMP_ZIP_PATH_SHOULD_NOT_LEAK"
staging_mktemp_parent="$fixture_root/$staging_mktemp_sentinel-parent"
staging_mktemp_zip="$staging_mktemp_parent/LithePG-notary.zip"
staging_mktemp_fake_bin="$fixture_root/staging-mktemp-failure-fake-bin"
mkdir -p "$staging_mktemp_parent" "$staging_mktemp_fake_bin"
cat >"$staging_mktemp_fake_bin/mktemp" <<'SHIM'
#!/usr/bin/env bash
printf 'fake mktemp stdout sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_MKTEMP_ZIP_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake mktemp stderr sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_MKTEMP_ZIP_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
exit 42
SHIM
chmod +x "$staging_mktemp_fake_bin/mktemp"

if PATH="$staging_mktemp_fake_bin:$PATH" \
  SIGN_MKTEMP_ZIP_PATH_SHOULD_NOT_LEAK="$staging_mktemp_sentinel" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$staging_mktemp_zip" \
  run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly passed when staging mktemp failed"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$staging_mktemp_sentinel"
assert_not_contains "$helper_output" "fake mktemp"
assert_not_contains "$helper_output" "$staging_mktemp_parent"
assert_not_contains "$helper_output" "$staging_mktemp_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_contains "$helper_output" "could not create notary zip staging directory"
[[ ! -e "$staging_mktemp_zip" ]] || fail "real mode mktemp failure created notary zip: $staging_mktemp_zip"

staging_chmod_sentinel="SIGN_CHMOD_ZIP_PATH_SHOULD_NOT_LEAK"
staging_chmod_parent="$fixture_root/$staging_chmod_sentinel-parent"
staging_chmod_zip="$staging_chmod_parent/LithePG-notary.zip"
staging_chmod_fake_bin="$fixture_root/staging-chmod-failure-fake-bin"
mkdir -p "$staging_chmod_parent" "$staging_chmod_fake_bin"
cat >"$staging_chmod_fake_bin/mktemp" <<'SHIM'
#!/usr/bin/env bash
template="${!#}"
staged_dir="${template%XXXXXX}fixed"
mkdir -p "$staged_dir"
printf '%s\n' "$staged_dir"
exit 0
SHIM
cat >"$staging_chmod_fake_bin/chmod" <<'SHIM'
#!/usr/bin/env bash
printf 'fake chmod stdout sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_CHMOD_ZIP_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake chmod stderr sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_CHMOD_ZIP_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
exit 43
SHIM
chmod +x "$staging_chmod_fake_bin/mktemp" "$staging_chmod_fake_bin/chmod"

if PATH="$staging_chmod_fake_bin:$PATH" \
  SIGN_CHMOD_ZIP_PATH_SHOULD_NOT_LEAK="$staging_chmod_sentinel" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$staging_chmod_zip" \
  run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly passed when staging chmod failed"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$staging_chmod_sentinel"
assert_not_contains "$helper_output" "fake chmod"
assert_not_contains "$helper_output" "$staging_chmod_parent"
assert_not_contains "$helper_output" "$staging_chmod_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_contains "$helper_output" "could not secure notary zip staging directory"
[[ ! -e "$staging_chmod_zip" ]] || fail "real mode chmod failure created notary zip: $staging_chmod_zip"

cleanup_rm_sentinel="SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK"
cleanup_rm_parent="$fixture_root/$cleanup_rm_sentinel-parent"
cleanup_rm_zip="$cleanup_rm_parent/LithePG-notary.zip"
cleanup_rm_fake_bin="$fixture_root/cleanup-rm-failure-fake-bin"
mkdir -p "$cleanup_rm_parent" "$cleanup_rm_fake_bin"
cat >"$cleanup_rm_fake_bin/codesign" <<'SHIM'
#!/usr/bin/env bash
printf 'fake codesign stdout sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake codesign stderr sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
exit 44
SHIM
cat >"$cleanup_rm_fake_bin/rm" <<'SHIM'
#!/usr/bin/env bash
printf 'fake rm stdout sentinel=%s cleanup args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake rm stderr sentinel=%s cleanup args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
exit 45
SHIM
chmod +x "$cleanup_rm_fake_bin/codesign" "$cleanup_rm_fake_bin/rm"

if PATH="$cleanup_rm_fake_bin:$PATH" \
  SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK="$cleanup_rm_sentinel" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$cleanup_rm_zip" \
  run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly passed when codesign failed before cleanup rm failed"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "codesign failed"
assert_not_contains "$helper_output" "$cleanup_rm_sentinel"
assert_not_contains "$helper_output" "fake codesign"
assert_not_contains "$helper_output" "fake rm"
assert_not_contains "$helper_output" "$cleanup_rm_parent"
assert_not_contains "$helper_output" "$cleanup_rm_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$cleanup_rm_zip" ]] || fail "real mode cleanup rm failure created notary zip: $cleanup_rm_zip"

fake_bin="$fixture_root/fake-bin"
noisy_ditto_failure_sentinel="SIGN_AND_NOTARIZE_NOISY_DITTO_FAILURE_SHOULD_NOT_LEAK"
mkdir -p "$fake_bin"
cat >"$fake_bin/codesign" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat >"$fake_bin/ditto" <<'SHIM'
#!/usr/bin/env bash
printf 'fake ditto stdout sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_AND_NOTARIZE_NOISY_DITTO_FAILURE_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake ditto stderr sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$SIGN_AND_NOTARIZE_NOISY_DITTO_FAILURE_SHOULD_NOT_LEAK" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
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
  SIGN_AND_NOTARIZE_NOISY_DITTO_FAILURE_SHOULD_NOT_LEAK="$noisy_ditto_failure_sentinel" \
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
assert_contains "$helper_output" "notary zip creation failed"
assert_not_contains "$helper_output" "fake ditto stdout"
assert_not_contains "$helper_output" "fake ditto stderr"
assert_not_contains "$helper_output" "$noisy_ditto_failure_sentinel"
assert_not_contains "$helper_output" "$app_bundle"
assert_not_contains "$helper_output" "$notary_zip"
assert_not_contains "$helper_output" "unexpected xcrun invocation"
assert_not_contains "$helper_output" "unexpected spctl invocation"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -f "$notary_zip" ]] || fail "real mode zip-creation failure removed existing approved notary zip"
[[ "$(<"$notary_zip")" == "$existing_notary_zip_marker" ]] || fail "real mode zip-creation failure changed existing approved notary zip"

redacted_success_sentinel="SIGN_AND_NOTARIZE_SUCCESS_PATH_SHOULD_NOT_LEAK"
redacted_success_app_parent="$fixture_root/$redacted_success_sentinel-app-parent"
redacted_success_app_bundle="$redacted_success_app_parent/LithePG.app"
redacted_success_entitlements_parent="$fixture_root/$redacted_success_sentinel-entitlements-parent"
redacted_success_entitlements="$redacted_success_entitlements_parent/LithePG.entitlements"
redacted_success_notary_parent="$fixture_root/$redacted_success_sentinel-notary-parent"
redacted_success_notary_zip="$redacted_success_notary_parent/LithePG-notary.zip"
redacted_success_fake_bin="$fixture_root/redacted-success-fake-bin"
mkdir -p "$redacted_success_entitlements_parent" "$redacted_success_notary_parent" "$redacted_success_fake_bin"
make_minimal_app_bundle "$redacted_success_app_bundle"
printf '<plist version="1.0"><dict/></plist>\n' >"$redacted_success_entitlements"
cat >"$redacted_success_fake_bin/codesign" <<'SHIM'
#!/usr/bin/env bash
printf 'fake codesign stdout: %s\n' "$*"
printf 'fake codesign stderr: %s\n' "$*" >&2
exit 0
SHIM
cat >"$redacted_success_fake_bin/ditto" <<'SHIM'
#!/usr/bin/env bash
dest="${!#}"
printf 'fake ditto stdout: %s\n' "$*"
printf 'fake ditto stderr: %s\n' "$*" >&2
printf 'FAKE_NOTARY_ZIP\n' >"$dest"
exit 0
SHIM
cat >"$redacted_success_fake_bin/xcrun" <<'SHIM'
#!/usr/bin/env bash
printf 'fake xcrun stdout: %s\n' "$*"
printf 'fake xcrun stderr: %s\n' "$*" >&2
exit 0
SHIM
cat >"$redacted_success_fake_bin/spctl" <<'SHIM'
#!/usr/bin/env bash
printf 'fake spctl stdout: %s\n' "$*"
printf 'fake spctl stderr: %s\n' "$*" >&2
exit 0
SHIM
chmod +x "$redacted_success_fake_bin/codesign" "$redacted_success_fake_bin/ditto" "$redacted_success_fake_bin/xcrun" "$redacted_success_fake_bin/spctl"

if ! PATH="$redacted_success_fake_bin:$PATH" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_ENTITLEMENTS="$redacted_success_entitlements" \
  LITHEPG_NOTARY_ZIP="$redacted_success_notary_zip" \
  run_helper_capture "$output_file" "$redacted_success_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly failed with fake signing/notary tools while checking redacted success paths"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Signed and notarized: LithePG.app"
assert_contains "$helper_output" "Notary zip: created (redacted)"
assert_not_contains "$helper_output" "$redacted_success_sentinel"
assert_not_contains "$helper_output" "$redacted_success_app_parent"
assert_not_contains "$helper_output" "$redacted_success_app_bundle"
assert_not_contains "$helper_output" "$redacted_success_entitlements"
assert_not_contains "$helper_output" "$redacted_success_notary_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -f "$redacted_success_notary_zip" ]] || fail "real mode fake tools did not create notary zip"
[[ "$(<"$redacted_success_notary_zip")" == "FAKE_NOTARY_ZIP" ]] || fail "real mode fake tools created unexpected notary zip contents"

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

case_variant_public_release_named_notary_zip="$fixture_root/lithepg.app.zip"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$case_variant_public_release_named_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with case-variant public release artifact notary zip basename"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip must not use public release artifact name"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$case_variant_public_release_named_notary_zip" ]] || fail "dry run created case-variant public release named notary zip: $case_variant_public_release_named_notary_zip"

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

mkdir -p "$app_bundle/Contents/Resources"
final_symlink_outside_target_marker='FINAL_SYMLINK_OUTSIDE_TARGET_SHOULD_SURVIVE'
final_symlink_outside_target="$fixture_root/final-symlink-outside-target.zip"
final_symlink_inside_bundle_zip="$app_bundle/Contents/Resources/LithePG-final-symlink-notary.zip"
printf '%s\n' "$final_symlink_outside_target_marker" >"$final_symlink_outside_target"
ln -s "$final_symlink_outside_target" "$final_symlink_inside_bundle_zip"
[[ -L "$final_symlink_inside_bundle_zip" ]] || fail "failed to create inside-bundle final notary zip symlink fixture"

if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$final_symlink_inside_bundle_zip" \
  LITHEPG_NOTARY_ZIP_OVERWRITE=approved \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with final notary zip symlink inside app bundle pointing outside"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle must not contain symlinks"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_not_contains "$helper_output" "$final_symlink_outside_target_marker"
[[ -L "$final_symlink_inside_bundle_zip" ]] || fail "dry run changed inside-bundle final notary zip symlink: $final_symlink_inside_bundle_zip"
[[ "$(readlink "$final_symlink_inside_bundle_zip")" == "$final_symlink_outside_target" ]] || fail "dry run retargeted inside-bundle final notary zip symlink: $final_symlink_inside_bundle_zip"
[[ "$(<"$final_symlink_outside_target")" == "$final_symlink_outside_target_marker" ]] || fail "dry run changed outside final symlink target: $final_symlink_outside_target"
rm "$final_symlink_inside_bundle_zip"

symlink_parent_traversal_link="$fixture_root/notary-link-to-app-resources"
ln -s "$app_bundle/Contents/Resources" "$symlink_parent_traversal_link"
symlink_parent_traversal_notary_zip="$symlink_parent_traversal_link/../LithePG-notary.zip"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$symlink_parent_traversal_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with symlink-plus-parent-traversal notary zip inside app bundle"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip must not be inside app bundle"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$app_bundle/Contents/LithePG-notary.zip" ]] || fail "dry run created notary zip through symlink-plus-parent traversal: $app_bundle/Contents/LithePG-notary.zip"

case_variant_inside_bundle_parent="$fixture_root/lithepg.app/Contents"
case_variant_inside_notary_zip="$case_variant_inside_bundle_parent/LithePG-notary.zip"
if [[ -d "$case_variant_inside_bundle_parent" && "$case_variant_inside_bundle_parent" -ef "$app_bundle/Contents" ]]; then
  if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$case_variant_inside_notary_zip" \
    run_helper_capture "$output_file" --dry-run "$app_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "dry run unexpectedly passed with case-variant notary zip inside app bundle"
  fi

  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "notary zip must not be inside app bundle"
  assert_not_contains "$helper_output" "$codesign_sentinel"
  assert_not_contains "$helper_output" "$notary_sentinel"
  [[ ! -e "$app_bundle/Contents/LithePG-notary.zip" ]] || fail "dry run created notary zip through case-variant app bundle path: $app_bundle/Contents/LithePG-notary.zip"
else
  printf 'Skipping case-variant inside-bundle notary zip assertion on case-sensitive filesystem\n'
fi

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

notary_zip_parent_file="$fixture_root/notary-zip-parent-file"
notary_zip_parent_file_marker='NOTARY_ZIP_PARENT_FILE_SHOULD_SURVIVE'
notary_zip_under_parent_file="$notary_zip_parent_file/LithePG-notary.zip"
printf '%s\n' "$notary_zip_parent_file_marker" >"$notary_zip_parent_file"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip_under_parent_file" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with regular-file notary zip parent path"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip parent path must be a directory"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -f "$notary_zip_parent_file" && ! -L "$notary_zip_parent_file" ]] || fail "dry run replaced regular-file notary zip parent path: $notary_zip_parent_file"
[[ "$(<"$notary_zip_parent_file")" == "$notary_zip_parent_file_marker" ]] || fail "dry run changed regular-file notary zip parent path: $notary_zip_parent_file"
[[ ! -e "$notary_zip_under_parent_file" && ! -L "$notary_zip_under_parent_file" ]] || fail "dry run created notary zip under regular-file parent path: $notary_zip_under_parent_file"

dangling_notary_zip_parent="$fixture_root/notary-zip-parent-dangling-link"
dangling_notary_zip_parent_target="$fixture_root/missing-notary-zip-parent-target"
dangling_parent_notary_zip="$dangling_notary_zip_parent/LithePG-notary.zip"
ln -s "$dangling_notary_zip_parent_target" "$dangling_notary_zip_parent"
[[ -L "$dangling_notary_zip_parent" && ! -e "$dangling_notary_zip_parent" ]] || fail "failed to create dangling notary zip parent symlink fixture"
if LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$dangling_parent_notary_zip" \
  run_helper_capture "$output_file" --dry-run "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "dry run unexpectedly passed with dangling-symlink notary zip parent path"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "notary zip parent path must be a directory"
assert_not_contains "$helper_output" "Signing/notarization dry run OK"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ -L "$dangling_notary_zip_parent" && ! -e "$dangling_notary_zip_parent" ]] || fail "dry run changed dangling notary zip parent symlink: $dangling_notary_zip_parent"
[[ ! -e "$dangling_notary_zip_parent_target" && ! -L "$dangling_notary_zip_parent_target" ]] || fail "dry run created dangling notary zip parent symlink target: $dangling_notary_zip_parent_target"
[[ ! -e "$dangling_parent_notary_zip" && ! -L "$dangling_parent_notary_zip" ]] || fail "dry run created notary zip under dangling-symlink parent path: $dangling_parent_notary_zip"

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
