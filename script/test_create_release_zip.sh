#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/create_release_zip.sh"

fail() {
  printf 'test_create_release_zip failed: %s\n' "$1" >&2
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

assert_matches_sha_line() {
  local haystack="$1"
  [[ "$haystack" =~ SHA-256:\ [0-9a-f]{64} ]] || fail "expected output to contain a SHA-256 digest"
}

assert_size_line_for_zip() {
  local haystack="$1"
  local zip_path="$2"
  local expected_size
  expected_size="$(/usr/bin/stat -f%z "$zip_path")"
  assert_contains "$haystack" "Size bytes: $expected_size"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  [[ -f "$path" ]] || fail "expected file to exist: $path"
  local contents
  contents="$(<"$path")"
  assert_contains "$contents" "$needle"
}

assert_zip_contains_app_wrapper() {
  local zip_path="$1"
  local extract_dir="$2"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  /usr/bin/ditto -x -k "$zip_path" "$extract_dir"
  [[ -f "$extract_dir/LithePG.app/Contents/MacOS/LithePGApp" ]] || fail "zip did not preserve LithePG.app wrapper"
}

make_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/script" "$fixture/dist"
  cp "$HELPER" "$fixture/script/create_release_zip.sh"
  chmod +x "$fixture/script/create_release_zip.sh"

  cat >"$fixture/script/package_verify.sh" <<'FAKE_VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'package_verify %s\n' "${1:-}" >>"${FAKE_VERIFY_LOG:?}"
if [[ "${FAKE_VERIFY_FAIL:-}" == "1" ]]; then
  printf 'fake package verification failed\n' >&2
  exit 42
fi
printf 'fake package verified: %s\n' "${1:-}"
FAKE_VERIFY
  chmod +x "$fixture/script/package_verify.sh"

  mkdir -p "$fixture/dist/LithePG.app/Contents/MacOS"
  printf 'fake app bundle\n' >"$fixture/dist/LithePG.app/Contents/MacOS/LithePGApp"
}

run_helper_capture() {
  local fixture="$1"
  local output_file="$2"
  shift 2
  run_helper_from_cwd_capture "$fixture" "$fixture" "$output_file" "$@"
}

run_helper_from_cwd_capture() {
  local fixture="$1"
  local cwd="$2"
  local output_file="$3"
  shift 3
  set +e
  (
    cd "$cwd"
    "$fixture/script/create_release_zip.sh" "$@"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"
helper_contents="$(<"$HELPER")"
assert_contains "$helper_contents" "/usr/bin/ditto -c -k --keepParent"
assert_contains "$helper_contents" "/usr/bin/shasum -a 256"
assert_contains "$helper_contents" 'mktemp -d "${output_parent%/}/.release-zip.XXXXXX"'
assert_contains "$helper_contents" '/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$temp_zip"'
assert_contains "$helper_contents" 'rename($ARGV[0], $ARGV[1])'
assert_not_contains "$helper_contents" '/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"'

missing_verify_output="$(mktemp)"
wrong_app_bundle_name_output="$(mktemp)"
symlink_app_bundle_output="$(mktemp)"
symlink_app_bundle_trailing_slash_output="$(mktemp)"
wrong_output_zip_name_output="$(mktemp)"
approved_directory_output="$(mktemp)"
refuse_output="$(mktemp)"
uppercase_overwrite_output="$(mktemp)"
dangling_symlink_output="$(mktemp)"
overwrite_output="$(mktemp)"
approved_symlink_output="$(mktemp)"
approved_non_dangling_symlink_output="$(mktemp)"
inside_bundle_output="$(mktemp)"
case_variant_inside_bundle_output="$(mktemp)"
symlink_inside_bundle_output="$(mktemp)"
symlink_parent_traversal_output="$(mktemp)"
final_symlink_inside_bundle_output="$(mktemp)"
success_output="$(mktemp)"
outside_cwd_output="$(mktemp)"
help_output="$(mktemp)"
fixture_root="$(mktemp -d)"
trap 'rm -f "$missing_verify_output" "$wrong_app_bundle_name_output" "$symlink_app_bundle_output" "$symlink_app_bundle_trailing_slash_output" "$wrong_output_zip_name_output" "$approved_directory_output" "$refuse_output" "$uppercase_overwrite_output" "$dangling_symlink_output" "$overwrite_output" "$approved_symlink_output" "$approved_non_dangling_symlink_output" "$inside_bundle_output" "$case_variant_inside_bundle_output" "$symlink_inside_bundle_output" "$symlink_parent_traversal_output" "$final_symlink_inside_bundle_output" "$success_output" "$outside_cwd_output" "$help_output"; rm -rf "$fixture_root"' EXIT

sensitive_identity="SENSITIVE_CODESIGN_IDENTITY_DO_NOT_PRINT"
sensitive_notary="SENSITIVE_NOTARY_PROFILE_DO_NOT_PRINT"
sensitive_release_marker="SENSITIVE_RELEASE_MARKER_DO_NOT_PRINT"

# Verification failure must stop before zip creation.
verify_fixture="$fixture_root/verify-fails"
make_fixture "$verify_fixture"
verify_log="$verify_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  FAKE_VERIFY_FAIL="1" \
  run_helper_capture "$verify_fixture" "$missing_verify_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly passed when package verification failed"
fi
missing_verify_text="$(<"$missing_verify_output")"
assert_contains "$missing_verify_text" "fake package verification failed"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$verify_fixture/dist/LithePG.app.zip" ]] || fail "zip was created despite package verification failure"

# The public release helper must only package the canonical LithePG.app wrapper.
wrong_app_bundle_name_fixture="$fixture_root/wrong-app-bundle-name"
make_fixture "$wrong_app_bundle_name_fixture"
mv "$wrong_app_bundle_name_fixture/dist/LithePG.app" "$wrong_app_bundle_name_fixture/dist/NotLithePG.app"
verify_log="$wrong_app_bundle_name_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$wrong_app_bundle_name_fixture" "$wrong_app_bundle_name_output" "dist/NotLithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly packaged a non-canonical app bundle name"
fi
wrong_app_bundle_name_text="$(<"$wrong_app_bundle_name_output")"
assert_contains "$wrong_app_bundle_name_text" "app bundle basename must be LithePG.app"
assert_not_contains "$wrong_app_bundle_name_text" "$sensitive_identity"
assert_not_contains "$wrong_app_bundle_name_text" "$sensitive_notary"
assert_not_contains "$wrong_app_bundle_name_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/NotLithePG.app"
[[ ! -e "$wrong_app_bundle_name_fixture/dist/LithePG.app.zip" ]] || fail "zip was created for a non-canonical app bundle name"

# The public release helper must reject a symlinked input path even when the path basename is canonical.
symlink_app_bundle_fixture="$fixture_root/symlink-app-bundle"
make_fixture "$symlink_app_bundle_fixture"
mkdir -p "$symlink_app_bundle_fixture/real-apps"
mv "$symlink_app_bundle_fixture/dist/LithePG.app" "$symlink_app_bundle_fixture/real-apps/LithePG.app"
ln -s "$symlink_app_bundle_fixture/real-apps/LithePG.app" "$symlink_app_bundle_fixture/dist/LithePG.app"
symlink_app_bundle_target="$(readlink "$symlink_app_bundle_fixture/dist/LithePG.app")"
verify_log="$symlink_app_bundle_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$symlink_app_bundle_fixture" "$symlink_app_bundle_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly packaged a symlinked app bundle input"
fi
symlink_app_bundle_text="$(<"$symlink_app_bundle_output")"
assert_contains "$symlink_app_bundle_text" "app bundle path must not be a symlink"
assert_not_contains "$symlink_app_bundle_text" "$sensitive_identity"
assert_not_contains "$symlink_app_bundle_text" "$sensitive_notary"
assert_not_contains "$symlink_app_bundle_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ -L "$symlink_app_bundle_fixture/dist/LithePG.app" ]] || fail "symlinked app bundle input was not preserved"
[[ "$(readlink "$symlink_app_bundle_fixture/dist/LithePG.app")" == "$symlink_app_bundle_target" ]] || fail "symlinked app bundle target changed despite refusal"
[[ ! -e "$symlink_app_bundle_fixture/dist/LithePG.app.zip" ]] || fail "zip was created for a symlinked app bundle input"

# The symlinked input path refusal must not be bypassable with a trailing slash.
symlink_app_bundle_trailing_slash_fixture="$fixture_root/symlink-app-bundle-trailing-slash"
make_fixture "$symlink_app_bundle_trailing_slash_fixture"
mkdir -p "$symlink_app_bundle_trailing_slash_fixture/real-apps"
mv "$symlink_app_bundle_trailing_slash_fixture/dist/LithePG.app" "$symlink_app_bundle_trailing_slash_fixture/real-apps/LithePG.app"
ln -s "$symlink_app_bundle_trailing_slash_fixture/real-apps/LithePG.app" "$symlink_app_bundle_trailing_slash_fixture/dist/LithePG.app"
symlink_app_bundle_trailing_slash_target="$(readlink "$symlink_app_bundle_trailing_slash_fixture/dist/LithePG.app")"
verify_log="$symlink_app_bundle_trailing_slash_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$symlink_app_bundle_trailing_slash_fixture" "$symlink_app_bundle_trailing_slash_output" "dist/LithePG.app/" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly packaged a symlinked app bundle input with a trailing slash"
fi
symlink_app_bundle_trailing_slash_text="$(<"$symlink_app_bundle_trailing_slash_output")"
assert_contains "$symlink_app_bundle_trailing_slash_text" "app bundle path must not be a symlink"
assert_not_contains "$symlink_app_bundle_trailing_slash_text" "$sensitive_identity"
assert_not_contains "$symlink_app_bundle_trailing_slash_text" "$sensitive_notary"
assert_not_contains "$symlink_app_bundle_trailing_slash_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app/"
[[ -L "$symlink_app_bundle_trailing_slash_fixture/dist/LithePG.app" ]] || fail "trailing-slash symlinked app bundle input was not preserved"
[[ "$(readlink "$symlink_app_bundle_trailing_slash_fixture/dist/LithePG.app")" == "$symlink_app_bundle_trailing_slash_target" ]] || fail "trailing-slash symlinked app bundle target changed despite refusal"
[[ ! -e "$symlink_app_bundle_trailing_slash_fixture/dist/LithePG.app.zip" ]] || fail "zip was created for a trailing-slash symlinked app bundle input"

# The public release helper must only create the canonical public zip basename after verification.
wrong_output_zip_name_fixture="$fixture_root/wrong-output-zip-name"
make_fixture "$wrong_output_zip_name_fixture"
verify_log="$wrong_output_zip_name_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$wrong_output_zip_name_fixture" "$wrong_output_zip_name_output" "dist/LithePG.app" "dist/NotLithePG.zip"; then
  fail "helper unexpectedly created a non-canonical output zip basename"
fi
wrong_output_zip_name_text="$(<"$wrong_output_zip_name_output")"
assert_contains "$wrong_output_zip_name_text" "output zip basename must be LithePG.app.zip"
assert_not_contains "$wrong_output_zip_name_text" "$sensitive_identity"
assert_not_contains "$wrong_output_zip_name_text" "$sensitive_notary"
assert_not_contains "$wrong_output_zip_name_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$wrong_output_zip_name_fixture/dist/NotLithePG.zip" ]] || fail "non-canonical output zip was created"

# Existing output directory at the canonical zip path is refused even with explicit overwrite approval.
approved_directory_fixture="$fixture_root/refuse-approved-directory-output"
make_fixture "$approved_directory_fixture"
approved_directory_path="$approved_directory_fixture/dist/LithePG.app.zip"
approved_directory_marker="directory output marker"
mkdir -p "$approved_directory_path"
printf '%s\n' "$approved_directory_marker" >"$approved_directory_path/marker.txt"
verify_log="$approved_directory_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_RELEASE_ZIP_OVERWRITE="approved" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$approved_directory_fixture" "$approved_directory_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly accepted an existing output directory with overwrite approval"
fi
approved_directory_text="$(<"$approved_directory_output")"
assert_contains "$approved_directory_text" "output zip path must not be a directory"
assert_not_contains "$approved_directory_text" "$sensitive_identity"
assert_not_contains "$approved_directory_text" "$sensitive_notary"
assert_not_contains "$approved_directory_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ -d "$approved_directory_path" ]] || fail "existing output directory was removed"
[[ "$(<"$approved_directory_path/marker.txt")" == "$approved_directory_marker" ]] || fail "existing output directory contents changed"
[[ ! -e "$approved_directory_path/LithePG.app.zip" ]] || fail "zip was created inside the existing output directory"

# Existing output zip is refused by default after verification.
refuse_fixture="$fixture_root/refuse-existing"
make_fixture "$refuse_fixture"
printf 'existing zip\n' >"$refuse_fixture/dist/LithePG.app.zip"
verify_log="$refuse_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$refuse_fixture" "$refuse_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly overwrote existing output zip by default"
fi
refuse_text="$(<"$refuse_output")"
assert_contains "$refuse_text" "Refusing to overwrite existing output zip"
assert_contains "$refuse_text" "LITHEPG_RELEASE_ZIP_OVERWRITE=1"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ "$(<"$refuse_fixture/dist/LithePG.app.zip")" == "existing zip" ]] || fail "existing zip content changed despite refusal"

# Undocumented uppercase overwrite approval must be refused and preserve the existing zip.
uppercase_overwrite_fixture="$fixture_root/refuse-uppercase-overwrite"
make_fixture "$uppercase_overwrite_fixture"
printf 'existing uppercase zip\n' >"$uppercase_overwrite_fixture/dist/LithePG.app.zip"
verify_log="$uppercase_overwrite_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_RELEASE_ZIP_OVERWRITE="APPROVED" \
  run_helper_capture "$uppercase_overwrite_fixture" "$uppercase_overwrite_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly accepted undocumented uppercase overwrite approval"
fi
uppercase_overwrite_text="$(<"$uppercase_overwrite_output")"
assert_contains "$uppercase_overwrite_text" "Refusing to overwrite existing output zip"
assert_contains "$uppercase_overwrite_text" "LITHEPG_RELEASE_ZIP_OVERWRITE=1"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ "$(<"$uppercase_overwrite_fixture/dist/LithePG.app.zip")" == "existing uppercase zip" ]] || fail "existing zip content changed despite uppercase overwrite refusal"

# Dangling output symlink is refused by default after verification; it must not be followed or removed.
dangling_fixture="$fixture_root/refuse-dangling-symlink"
make_fixture "$dangling_fixture"
dangling_target="$dangling_fixture/missing-target/LithePG.app.zip"
ln -s "$dangling_target" "$dangling_fixture/dist/LithePG.app.zip"
verify_log="$dangling_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$dangling_fixture" "$dangling_symlink_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper unexpectedly followed dangling output symlink by default"
fi
dangling_text="$(<"$dangling_symlink_output")"
assert_contains "$dangling_text" "Refusing to overwrite existing output zip"
assert_contains "$dangling_text" "LITHEPG_RELEASE_ZIP_OVERWRITE=1"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ -L "$dangling_fixture/dist/LithePG.app.zip" && ! -e "$dangling_fixture/dist/LithePG.app.zip" ]] || fail "dangling output symlink changed despite refusal"
[[ ! -e "$dangling_target" ]] || fail "dangling output symlink target was created despite refusal"

# Explicit overwrite approval allows replacing an existing zip.
overwrite_fixture="$fixture_root/overwrite-existing"
make_fixture "$overwrite_fixture"
printf 'old zip\n' >"$overwrite_fixture/dist/LithePG.app.zip"
verify_log="$overwrite_fixture/verify.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_RELEASE_ZIP_OVERWRITE="approved" \
  run_helper_capture "$overwrite_fixture" "$overwrite_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper failed despite explicit overwrite approval"
fi
overwrite_text="$(<"$overwrite_output")"
assert_contains "$overwrite_text" "Created release zip: dist/LithePG.app.zip"
assert_matches_sha_line "$overwrite_text"
assert_size_line_for_zip "$overwrite_text" "$overwrite_fixture/dist/LithePG.app.zip"
assert_zip_contains_app_wrapper "$overwrite_fixture/dist/LithePG.app.zip" "$overwrite_fixture/extracted-overwrite"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Explicit overwrite approval replaces an output symlink at the output path without following it.
approved_symlink_fixture="$fixture_root/overwrite-dangling-symlink"
make_fixture "$approved_symlink_fixture"
approved_symlink_target_dir="$approved_symlink_fixture/missing-target"
approved_symlink_target="$approved_symlink_target_dir/LithePG.app.zip"
mkdir -p "$approved_symlink_target_dir"
ln -s "$approved_symlink_target" "$approved_symlink_fixture/dist/LithePG.app.zip"
verify_log="$approved_symlink_fixture/verify.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_RELEASE_ZIP_OVERWRITE="approved" \
  run_helper_capture "$approved_symlink_fixture" "$approved_symlink_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper failed despite explicit overwrite approval for dangling output symlink"
fi
approved_symlink_text="$(<"$approved_symlink_output")"
assert_contains "$approved_symlink_text" "Created release zip: dist/LithePG.app.zip"
assert_matches_sha_line "$approved_symlink_text"
assert_size_line_for_zip "$approved_symlink_text" "$approved_symlink_fixture/dist/LithePG.app.zip"
[[ -f "$approved_symlink_fixture/dist/LithePG.app.zip" && ! -L "$approved_symlink_fixture/dist/LithePG.app.zip" ]] || fail "approved dangling output symlink was not replaced with a regular zip"
[[ ! -e "$approved_symlink_target" ]] || fail "approved dangling output symlink target was created"
assert_zip_contains_app_wrapper "$approved_symlink_fixture/dist/LithePG.app.zip" "$approved_symlink_fixture/extracted-approved-symlink"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Explicit overwrite approval replaces a non-dangling output symlink without touching its target.
approved_non_dangling_symlink_fixture="$fixture_root/overwrite-non-dangling-symlink"
make_fixture "$approved_non_dangling_symlink_fixture"
approved_non_dangling_target="$approved_non_dangling_symlink_fixture/existing-target.zip"
approved_non_dangling_target_contents="existing target zip with SENSITIVE_SYMLINK_TARGET_CONTENTS_DO_NOT_PRINT"
printf '%s\n' "$approved_non_dangling_target_contents" >"$approved_non_dangling_target"
ln -s "$approved_non_dangling_target" "$approved_non_dangling_symlink_fixture/dist/LithePG.app.zip"
verify_log="$approved_non_dangling_symlink_fixture/verify.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_RELEASE_ZIP_OVERWRITE="approved" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$approved_non_dangling_symlink_fixture" "$approved_non_dangling_symlink_output" "dist/LithePG.app" "dist/LithePG.app.zip"; then
  fail "helper failed despite explicit overwrite approval for non-dangling output symlink"
fi
approved_non_dangling_symlink_text="$(<"$approved_non_dangling_symlink_output")"
assert_contains "$approved_non_dangling_symlink_text" "Created release zip: dist/LithePG.app.zip"
assert_matches_sha_line "$approved_non_dangling_symlink_text"
assert_size_line_for_zip "$approved_non_dangling_symlink_text" "$approved_non_dangling_symlink_fixture/dist/LithePG.app.zip"
assert_not_contains "$approved_non_dangling_symlink_text" "$sensitive_identity"
assert_not_contains "$approved_non_dangling_symlink_text" "$sensitive_notary"
assert_not_contains "$approved_non_dangling_symlink_text" "$sensitive_release_marker"
assert_not_contains "$approved_non_dangling_symlink_text" "$approved_non_dangling_target_contents"
[[ -f "$approved_non_dangling_symlink_fixture/dist/LithePG.app.zip" && ! -L "$approved_non_dangling_symlink_fixture/dist/LithePG.app.zip" ]] || fail "approved non-dangling output symlink was not replaced with a regular zip"
[[ -f "$approved_non_dangling_target" ]] || fail "approved non-dangling output symlink target was removed"
[[ "$(<"$approved_non_dangling_target")" == "$approved_non_dangling_target_contents" ]] || fail "approved non-dangling output symlink target contents changed"
assert_zip_contains_app_wrapper "$approved_non_dangling_symlink_fixture/dist/LithePG.app.zip" "$approved_non_dangling_symlink_fixture/extracted-approved-non-dangling-symlink"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Output paths inside the app bundle are refused to avoid recursive/self-embedding artifacts.
inside_fixture="$fixture_root/inside-app-output"
make_fixture "$inside_fixture"
verify_log="$inside_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$inside_fixture" "$inside_bundle_output" "dist/LithePG.app" "dist/LithePG.app/Contents/LithePG.app.zip"; then
  fail "helper unexpectedly allowed output zip inside the app bundle"
fi
inside_bundle_text="$(<"$inside_bundle_output")"
assert_contains "$inside_bundle_text" "output zip must not be inside the app bundle"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$inside_fixture/dist/LithePG.app/Contents/LithePG.app.zip" ]] || fail "zip was created inside the app bundle"

absolute_inside_fixture="$fixture_root/absolute-inside-app-output"
make_fixture "$absolute_inside_fixture"
verify_log="$absolute_inside_fixture/verify.log"
absolute_inside_output="$absolute_inside_fixture/dist/LithePG.app/Contents/LithePG.app.zip"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$absolute_inside_fixture" "$inside_bundle_output" "./dist/LithePG.app" "$absolute_inside_output"; then
  fail "helper unexpectedly allowed an absolute output zip inside the app bundle"
fi
absolute_inside_text="$(<"$inside_bundle_output")"
assert_contains "$absolute_inside_text" "output zip must not be inside the app bundle"
assert_file_contains "$verify_log" "package_verify ./dist/LithePG.app"
[[ ! -e "$absolute_inside_output" ]] || fail "absolute zip was created inside the app bundle"

case_variant_inside_fixture="$fixture_root/case-variant-inside-app-output"
make_fixture "$case_variant_inside_fixture"
case_variant_contents="$case_variant_inside_fixture/dist/lithepg.app/Contents"
if [[ -d "$case_variant_contents" && "$case_variant_contents" -ef "$case_variant_inside_fixture/dist/LithePG.app/Contents" ]]; then
  verify_log="$case_variant_inside_fixture/verify.log"
  if FAKE_VERIFY_LOG="$verify_log" \
    run_helper_capture "$case_variant_inside_fixture" "$case_variant_inside_bundle_output" "dist/LithePG.app" "dist/lithepg.app/Contents/LithePG.app.zip"; then
    fail "helper unexpectedly allowed a case-variant output zip inside the app bundle"
  fi
  case_variant_inside_text="$(<"$case_variant_inside_bundle_output")"
  assert_contains "$case_variant_inside_text" "output zip must not be inside the app bundle"
  assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
  [[ ! -e "$case_variant_inside_fixture/dist/LithePG.app/Contents/LithePG.app.zip" ]] || fail "zip was created inside the app bundle through a case-variant path"
else
  printf 'Skipping case-variant inside-bundle output assertion on case-sensitive filesystem\n'
fi

symlink_inside_fixture="$fixture_root/symlink-inside-app-output"
make_fixture "$symlink_inside_fixture"
ln -s "$symlink_inside_fixture/dist/LithePG.app/Contents" "$symlink_inside_fixture/dist/out-link"
verify_log="$symlink_inside_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$symlink_inside_fixture" "$symlink_inside_bundle_output" "dist/LithePG.app" "dist/out-link/LithePG.app.zip"; then
  fail "helper unexpectedly allowed a symlinked output parent inside the app bundle"
fi
symlink_inside_text="$(<"$symlink_inside_bundle_output")"
assert_contains "$symlink_inside_text" "output zip must not be inside the app bundle"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$symlink_inside_fixture/dist/LithePG.app/Contents/LithePG.app.zip" ]] || fail "zip was created inside the app bundle through a symlinked parent"

symlink_parent_traversal_fixture="$fixture_root/symlink-parent-traversal-inside-app-output"
make_fixture "$symlink_parent_traversal_fixture"
ln -s "$symlink_parent_traversal_fixture/dist/LithePG.app/Contents" "$symlink_parent_traversal_fixture/dist/out-link"
verify_log="$symlink_parent_traversal_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$symlink_parent_traversal_fixture" "$symlink_parent_traversal_output" "dist/LithePG.app" "dist/out-link/../LithePG.app.zip"; then
  fail "helper unexpectedly allowed a symlink-plus-parent-traversal output inside the app bundle"
fi
symlink_parent_traversal_text="$(<"$symlink_parent_traversal_output")"
assert_contains "$symlink_parent_traversal_text" "output zip must not be inside the app bundle"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$symlink_parent_traversal_fixture/dist/LithePG.app/LithePG.app.zip" ]] || fail "zip was created inside the app bundle through symlink-plus-parent traversal"

# A final output symlink physically located inside the app bundle must be refused even if it points outside.
final_symlink_inside_fixture="$fixture_root/final-symlink-inside-app-output"
make_fixture "$final_symlink_inside_fixture"
mkdir -p "$final_symlink_inside_fixture/dist/LithePG.app/Contents/Resources"
ln -s "$final_symlink_inside_fixture/dist/LithePG.app/Contents/Resources" "$final_symlink_inside_fixture/dist/out-link"
final_symlink_inside_target="$final_symlink_inside_fixture/outside-target.zip"
final_symlink_inside_target_contents="outside target zip with SENSITIVE_FINAL_SYMLINK_TARGET_CONTENTS_DO_NOT_PRINT"
printf '%s\n' "$final_symlink_inside_target_contents" >"$final_symlink_inside_target"
final_symlink_inside_output_path="$final_symlink_inside_fixture/dist/out-link/LithePG.app.zip"
ln -s "$final_symlink_inside_target" "$final_symlink_inside_output_path"
verify_log="$final_symlink_inside_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_RELEASE_ZIP_OVERWRITE="approved" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$final_symlink_inside_fixture" "$final_symlink_inside_bundle_output" "dist/LithePG.app" "dist/out-link/LithePG.app.zip"; then
  final_symlink_inside_text="$(<"$final_symlink_inside_bundle_output")"
  printf '%s\n' "$final_symlink_inside_text" >&2
  fail "helper unexpectedly allowed a final output symlink inside the app bundle pointing outside"
fi
final_symlink_inside_text="$(<"$final_symlink_inside_bundle_output")"
assert_contains "$final_symlink_inside_text" "output zip must not be inside the app bundle"
assert_not_contains "$final_symlink_inside_text" "$sensitive_identity"
assert_not_contains "$final_symlink_inside_text" "$sensitive_notary"
assert_not_contains "$final_symlink_inside_text" "$sensitive_release_marker"
assert_not_contains "$final_symlink_inside_text" "$final_symlink_inside_target_contents"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ -L "$final_symlink_inside_output_path" ]] || fail "inside-bundle final output symlink was not preserved"
[[ "$(readlink "$final_symlink_inside_output_path")" == "$final_symlink_inside_target" ]] || fail "inside-bundle final output symlink target changed despite refusal"
[[ "$(<"$final_symlink_inside_target")" == "$final_symlink_inside_target_contents" ]] || fail "outside final output symlink target contents changed"

# Success creates parent directories, preserves the .app wrapper, prints SHA-256, and does not leak secret-ish env values.
success_fixture="$fixture_root/success"
make_fixture "$success_fixture"
verify_log="$success_fixture/verify.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$success_fixture" "$success_output" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"; then
  fail "helper failed on successful zip creation"
fi
success_text="$(<"$success_output")"
assert_contains "$success_text" "Created release zip: artifacts/public/LithePG.app.zip"
assert_matches_sha_line "$success_text"
assert_size_line_for_zip "$success_text" "$success_fixture/artifacts/public/LithePG.app.zip"
assert_not_contains "$success_text" "$sensitive_identity"
assert_not_contains "$success_text" "$sensitive_notary"
assert_not_contains "$success_text" "$sensitive_release_marker"
[[ -f "$success_fixture/artifacts/public/LithePG.app.zip" ]] || fail "success zip was not created in nested output directory"
assert_zip_contains_app_wrapper "$success_fixture/artifacts/public/LithePG.app.zip" "$success_fixture/extracted-success"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Default paths resolve from the helper's repository root, not the caller's cwd.
outside_fixture="$fixture_root/default-from-outside-cwd"
make_fixture "$outside_fixture"
outside_cwd="$fixture_root/outside-cwd"
mkdir -p "$outside_cwd"
verify_log="$outside_fixture/verify.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  run_helper_from_cwd_capture "$outside_fixture" "$outside_cwd" "$outside_cwd_output"; then
  fail "helper failed when invoked from outside the repository root with default paths"
fi
outside_cwd_text="$(<"$outside_cwd_output")"
assert_contains "$outside_cwd_text" "Created release zip: dist/LithePG.app.zip"
assert_matches_sha_line "$outside_cwd_text"
assert_size_line_for_zip "$outside_cwd_text" "$outside_fixture/dist/LithePG.app.zip"
[[ -f "$outside_fixture/dist/LithePG.app.zip" ]] || fail "default output zip was not created under helper repository root"
[[ ! -e "$outside_cwd/dist/LithePG.app.zip" ]] || fail "default output zip was created under caller cwd"
assert_zip_contains_app_wrapper "$outside_fixture/dist/LithePG.app.zip" "$outside_fixture/extracted-default"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Help exits 0 and does not require an app bundle.
help_fixture="$fixture_root/help"
make_fixture "$help_fixture"
rm -rf "$help_fixture/dist/LithePG.app"
if ! FAKE_VERIFY_LOG="$help_fixture/verify.log" \
  run_helper_capture "$help_fixture" "$help_output" "--help"; then
  fail "--help did not exit 0"
fi
help_text="$(<"$help_output")"
assert_contains "$help_text" "Usage:"
assert_contains "$help_text" "create_release_zip.sh [app-bundle] [output-zip]"
[[ ! -e "$help_fixture/verify.log" ]] || fail "help unexpectedly ran package verification"

printf 'test_create_release_zip passed\n'
