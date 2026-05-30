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

missing_verify_output="$(mktemp)"
refuse_output="$(mktemp)"
overwrite_output="$(mktemp)"
inside_bundle_output="$(mktemp)"
success_output="$(mktemp)"
outside_cwd_output="$(mktemp)"
help_output="$(mktemp)"
fixture_root="$(mktemp -d)"
trap 'rm -f "$missing_verify_output" "$refuse_output" "$overwrite_output" "$inside_bundle_output" "$success_output" "$outside_cwd_output" "$help_output"; rm -rf "$fixture_root"' EXIT

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
