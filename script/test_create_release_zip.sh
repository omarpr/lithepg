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

first_log_value() {
  local contents="$1"
  local key="$2"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <<<"$contents"
  fail "expected log value for: $key"
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
if [[ "${FAKE_VERIFY_QUIET:-}" != "1" ]]; then
  printf 'fake package verified: %s\n' "${1:-}"
fi
FAKE_VERIFY
  chmod +x "$fixture/script/package_verify.sh"

  cat >"$fixture/script/v10_release_gate.sh" <<'FAKE_GATE'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_GATE_LOG:-}" ]]; then
  printf 'args=%s\n' "$*" >>"$FAKE_GATE_LOG"
  printf 'zip_path=%s\n' "${LITHEPG_RELEASE_ZIP_PATH:-}" >>"$FAKE_GATE_LOG"
  printf 'zip_sha=%s\n' "${LITHEPG_RELEASE_ZIP_SHA256:-}" >>"$FAKE_GATE_LOG"
  if [[ -f "${LITHEPG_RELEASE_ZIP_PATH:-}" ]]; then
    printf 'zip_exists=1\n' >>"$FAKE_GATE_LOG"
  else
    printf 'zip_exists=0\n' >>"$FAKE_GATE_LOG"
  fi
  if actual_sha_line="$(/usr/bin/shasum -a 256 "${LITHEPG_RELEASE_ZIP_PATH:-}" 2>/dev/null)"; then
    printf 'actual_sha=%s\n' "${actual_sha_line%%[[:space:]]*}" >>"$FAKE_GATE_LOG"
  fi
  if [[ -n "${FAKE_GATE_FINAL_ZIP_PATH:-}" && -e "$FAKE_GATE_FINAL_ZIP_PATH" ]]; then
    printf 'final_zip_exists=1\n' >>"$FAKE_GATE_LOG"
  else
    printf 'final_zip_exists=0\n' >>"$FAKE_GATE_LOG"
  fi
fi

if [[ "$*" != "--artifact-only" ]]; then
  printf 'fake artifact gate expected --artifact-only\n' >&2
  exit 44
fi
if [[ ! "${LITHEPG_RELEASE_ZIP_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'fake artifact gate expected 64-hex SHA\n' >&2
  exit 45
fi
if [[ ! -f "${LITHEPG_RELEASE_ZIP_PATH:-}" ]]; then
  printf 'fake artifact gate expected staged zip file\n' >&2
  exit 46
fi

if [[ "${FAKE_ARTIFACT_GATE_FAIL:-}" == "1" ]]; then
  printf 'fake artifact gate stdout leak: %s %s\n' "${FAKE_ARTIFACT_GATE_SENTINEL:-}" "${LITHEPG_RELEASE_ZIP_PATH:-}"
  printf 'fake artifact gate stderr leak: %s %s\n' "${FAKE_ARTIFACT_GATE_SENTINEL:-}" "${FAKE_ARTIFACT_GATE_FIXTURE_PATH:-}" >&2
  exit 43
fi
FAKE_GATE
  chmod +x "$fixture/script/v10_release_gate.sh"

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
assert_contains "$helper_contents" '/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE_ABS" "$temp_zip"'
assert_contains "$helper_contents" 'rename($ARGV[0], $ARGV[1])'
assert_contains "$helper_contents" 'exec { $bash } $bash, "-p", @ARGV;'
assert_not_contains "$helper_contents" '/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"'

missing_verify_output="$(mktemp)"
initial_bash_path_shadow_output="$(mktemp)"
startup_env_shadow_output="$(mktemp)"
startup_env_sanitizer_fail_closed_output="$(mktemp)"
startup_env_sanitizer_empty_bash_env_fail_closed_output="$(mktemp)"
perl_startup_shadow_output="$(mktemp)"
wrong_app_bundle_name_output="$(mktemp)"
symlink_app_bundle_output="$(mktemp)"
symlink_app_bundle_trailing_slash_output="$(mktemp)"
wrong_output_zip_name_output="$(mktemp)"
trailing_slash_output_zip_output="$(mktemp)"
approved_directory_output="$(mktemp)"
output_parent_file_output="$(mktemp)"
dangling_output_parent_symlink_output="$(mktemp)"
output_parent_creation_failure_output="$(mktemp)"
refuse_output="$(mktemp)"
refuse_sentinel_output="$(mktemp)"
uppercase_overwrite_output="$(mktemp)"
dangling_symlink_output="$(mktemp)"
overwrite_output="$(mktemp)"
approved_symlink_output="$(mktemp)"
approved_non_dangling_symlink_output="$(mktemp)"
success_path_redaction_output="$(mktemp)"
cleanup_redaction_output="$(mktemp)"
root_resolution_shadow_output="$(mktemp)"
path_shadow_output="$(mktemp)"
inside_bundle_output="$(mktemp)"
inside_bundle_sentinel_output="$(mktemp)"
temp_creation_failure_output="$(mktemp)"
case_variant_inside_bundle_output="$(mktemp)"
symlink_inside_bundle_output="$(mktemp)"
symlink_parent_traversal_output="$(mktemp)"
final_symlink_inside_bundle_output="$(mktemp)"
artifact_gate_failure_output="$(mktemp)"
success_output="$(mktemp)"
outside_cwd_output="$(mktemp)"
help_output="$(mktemp)"
fixture_root="$(mktemp -d)"
trap 'rm -f "$missing_verify_output" "$initial_bash_path_shadow_output" "$startup_env_shadow_output" "$startup_env_sanitizer_fail_closed_output" "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "$perl_startup_shadow_output" "$wrong_app_bundle_name_output" "$symlink_app_bundle_output" "$symlink_app_bundle_trailing_slash_output" "$wrong_output_zip_name_output" "$trailing_slash_output_zip_output" "$approved_directory_output" "$output_parent_file_output" "$dangling_output_parent_symlink_output" "$output_parent_creation_failure_output" "$refuse_output" "$refuse_sentinel_output" "$uppercase_overwrite_output" "$dangling_symlink_output" "$overwrite_output" "$approved_symlink_output" "$approved_non_dangling_symlink_output" "$success_path_redaction_output" "$cleanup_redaction_output" "$root_resolution_shadow_output" "$path_shadow_output" "$inside_bundle_output" "$inside_bundle_sentinel_output" "$temp_creation_failure_output" "$case_variant_inside_bundle_output" "$symlink_inside_bundle_output" "$symlink_parent_traversal_output" "$final_symlink_inside_bundle_output" "$artifact_gate_failure_output" "$success_output" "$outside_cwd_output" "$help_output"; chmod -R u+rwx "$fixture_root" 2>/dev/null || true; rm -rf "$fixture_root"' EXIT

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

# Executable startup must not route through PATH-selected bash before helper code runs.
initial_bash_path_shadow_sentinel="CREATE_RELEASE_ZIP_INITIAL_BASH_PATH_SHADOW_SENTINEL_DO_NOT_PRINT"
initial_bash_path_shadow_fixture="$fixture_root/initial-bash-path-shadow"
initial_bash_path_shadow_fake_bin="$initial_bash_path_shadow_fixture/fake-bin"
initial_bash_path_shadow_marker="$initial_bash_path_shadow_fixture/fake-bash-invoked"
make_fixture "$initial_bash_path_shadow_fixture"
mkdir -p "$initial_bash_path_shadow_fake_bin"
cat >"$initial_bash_path_shadow_fake_bin/bash" <<'FAKE_BASH'
#!/bin/sh
/usr/bin/printf '%s fake bash invoked\n' "${CREATE_RELEASE_ZIP_INITIAL_BASH_PATH_SHADOW_SENTINEL:-}" >&2
/usr/bin/printf 'bash\n' >"${CREATE_RELEASE_ZIP_INITIAL_BASH_PATH_SHADOW_MARKER:?}"
exit 97
FAKE_BASH
chmod +x "$initial_bash_path_shadow_fake_bin/bash"
if ! CREATE_RELEASE_ZIP_INITIAL_BASH_PATH_SHADOW_SENTINEL="$initial_bash_path_shadow_sentinel" \
  CREATE_RELEASE_ZIP_INITIAL_BASH_PATH_SHADOW_MARKER="$initial_bash_path_shadow_marker" \
  PATH="$initial_bash_path_shadow_fake_bin:$PATH" \
  run_helper_capture "$initial_bash_path_shadow_fixture" "$initial_bash_path_shadow_output" "--help"; then
  initial_bash_path_shadow_text="$(<"$initial_bash_path_shadow_output")"
  printf '%s\n' "$initial_bash_path_shadow_text" >&2
  fail "create release zip executable invocation used PATH-selected bash"
fi
initial_bash_path_shadow_text="$(<"$initial_bash_path_shadow_output")"
assert_contains "$initial_bash_path_shadow_text" "Usage:"
assert_not_contains "$initial_bash_path_shadow_text" "$initial_bash_path_shadow_fixture"
assert_not_contains "$initial_bash_path_shadow_text" "$initial_bash_path_shadow_sentinel"
assert_not_contains "$initial_bash_path_shadow_text" "fake bash invoked"
[[ ! -e "$initial_bash_path_shadow_marker" ]] || fail "create release zip executable invocation used PATH-selected bash: $(<"$initial_bash_path_shadow_marker")"

# Bash and Perl startup environments, including exported shell functions, must be
# sanitized before normal helper logic or child helpers can observe them.
startup_env_shadow_sentinel="CREATE_RELEASE_ZIP_STARTUP_ENV_SHADOW_SENTINEL_DO_NOT_PRINT"
startup_env_shadow_fixture="$fixture_root/startup-env-shadow"
startup_env_shadow_bash_env="$startup_env_shadow_fixture/poison.bash_env"
startup_env_shadow_perl_lib="$startup_env_shadow_fixture/perl-lib"
startup_env_shadow_bash_marker="$startup_env_shadow_fixture/bash-startup-invoked"
startup_env_shadow_export_marker="$startup_env_shadow_fixture/exported-function-invoked"
startup_env_shadow_perl_marker="$startup_env_shadow_fixture/perl-startup-invoked"
make_fixture "$startup_env_shadow_fixture"
mkdir -p "$startup_env_shadow_perl_lib"
cat >"$startup_env_shadow_bash_env" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${CREATE_RELEASE_ZIP_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${CREATE_RELEASE_ZIP_STARTUP_ENV_BASH_MARKER:?}"
  exit 97
}
BASHENV
cat >"$startup_env_shadow_perl_lib/CreateReleaseZipStartupPoison.pm" <<'PERLMOD'
package CreateReleaseZipStartupPoison;
BEGIN {
  my $sentinel = $ENV{CREATE_RELEASE_ZIP_STARTUP_ENV_SHADOW_SENTINEL} // '';
  my $marker = $ENV{CREATE_RELEASE_ZIP_STARTUP_ENV_PERL_MARKER} // '';
  if ($marker ne '' && open(my $fh, '>', $marker)) {
    print {$fh} "perl\n";
    close $fh;
  }
  print STDERR "$sentinel Perl startup invoked\n";
  exit 97;
}
1;
PERLMOD
verify_log="$startup_env_shadow_fixture/verify.log"
set +e
(
  command cd "$startup_env_shadow_fixture"
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${CREATE_RELEASE_ZIP_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${CREATE_RELEASE_ZIP_STARTUP_ENV_EXPORT_MARKER:?}"
    exit 97
  }
  export -f set
  FAKE_VERIFY_LOG="$verify_log" \
    CREATE_RELEASE_ZIP_STARTUP_ENV_SHADOW_SENTINEL="$startup_env_shadow_sentinel" \
    CREATE_RELEASE_ZIP_STARTUP_ENV_BASH_MARKER="$startup_env_shadow_bash_marker" \
    CREATE_RELEASE_ZIP_STARTUP_ENV_EXPORT_MARKER="$startup_env_shadow_export_marker" \
    CREATE_RELEASE_ZIP_STARTUP_ENV_PERL_MARKER="$startup_env_shadow_perl_marker" \
    BASH_ENV="$startup_env_shadow_bash_env" \
    PERL5LIB="$startup_env_shadow_perl_lib" \
    PERLLIB="$startup_env_shadow_perl_lib" \
    PERL5OPT=-MCreateReleaseZipStartupPoison \
    "$startup_env_shadow_fixture/script/create_release_zip.sh" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"
) >"$startup_env_shadow_output" 2>&1
startup_env_shadow_status=$?
set -e
if [[ "$startup_env_shadow_status" -ne 0 ]]; then
  startup_env_shadow_text="$(<"$startup_env_shadow_output")"
  printf '%s\n' "$startup_env_shadow_text" >&2
  fail "create release zip was affected by Bash/Perl startup environment shadowing"
fi
startup_env_shadow_text="$(<"$startup_env_shadow_output")"
assert_contains "$startup_env_shadow_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$startup_env_shadow_text"
assert_size_line_for_zip "$startup_env_shadow_text" "$startup_env_shadow_fixture/artifacts/public/LithePG.app.zip"
assert_not_contains "$startup_env_shadow_text" "$startup_env_shadow_fixture"
assert_not_contains "$startup_env_shadow_text" "$startup_env_shadow_sentinel"
assert_not_contains "$startup_env_shadow_text" "BASH_ENV set function invoked"
assert_not_contains "$startup_env_shadow_text" "exported set function invoked"
assert_not_contains "$startup_env_shadow_text" "Perl startup invoked"
[[ ! -e "$startup_env_shadow_bash_marker" ]] || fail "create release zip invoked BASH_ENV-defined set function: $(<"$startup_env_shadow_bash_marker")"
[[ ! -e "$startup_env_shadow_export_marker" ]] || fail "create release zip invoked exported set function: $(<"$startup_env_shadow_export_marker")"
[[ ! -e "$startup_env_shadow_perl_marker" ]] || fail "create release zip honored Perl startup environment: $(<"$startup_env_shadow_perl_marker")"
[[ -f "$startup_env_shadow_fixture/artifacts/public/LithePG.app.zip" ]] || fail "startup-env-shadow zip was not created"
assert_zip_contains_app_wrapper "$startup_env_shadow_fixture/artifacts/public/LithePG.app.zip" "$startup_env_shadow_fixture/extracted-startup-env-shadow"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# If dirty startup environment remains after the sanitizer marker is already set,
# the executable helper must fail closed instead of re-sanitizing and continuing.
startup_env_sanitizer_fail_closed_sentinel="CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_SENTINEL_DO_NOT_PRINT"
startup_env_sanitizer_fail_closed_fixture="$fixture_root/startup-env-sanitizer-fail-closed"
startup_env_sanitizer_fail_closed_bash_env="$startup_env_sanitizer_fail_closed_fixture/poison.bash_env"
startup_env_sanitizer_fail_closed_bash_marker="$startup_env_sanitizer_fail_closed_fixture/bash-startup-invoked"
startup_env_sanitizer_fail_closed_export_marker="$startup_env_sanitizer_fail_closed_fixture/exported-function-invoked"
startup_env_sanitizer_fail_closed_zip="$startup_env_sanitizer_fail_closed_fixture/artifacts/fail-closed/LithePG.app.zip"
make_fixture "$startup_env_sanitizer_fail_closed_fixture"
cat >"$startup_env_sanitizer_fail_closed_bash_env" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_BASH_MARKER:?}"
  exit 97
}
BASHENV
verify_log="$startup_env_sanitizer_fail_closed_fixture/verify.log"
set +e
(
  command cd "$startup_env_sanitizer_fail_closed_fixture"
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_EXPORT_MARKER:?}"
    exit 97
  }
  export -f set
  FAKE_VERIFY_LOG="$verify_log" \
    CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_SENTINEL="$startup_env_sanitizer_fail_closed_sentinel" \
    CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_BASH_MARKER="$startup_env_sanitizer_fail_closed_bash_marker" \
    CREATE_RELEASE_ZIP_SANITIZER_FAIL_CLOSED_EXPORT_MARKER="$startup_env_sanitizer_fail_closed_export_marker" \
    LITHEPG_CREATE_RELEASE_ZIP_STARTUP_ENV_SANITIZED=1 \
    BASH_ENV="$startup_env_sanitizer_fail_closed_bash_env" \
    "$startup_env_sanitizer_fail_closed_fixture/script/create_release_zip.sh" "dist/LithePG.app" "artifacts/fail-closed/LithePG.app.zip"
) >"$startup_env_sanitizer_fail_closed_output" 2>&1
startup_env_sanitizer_fail_closed_status=$?
set -e
startup_env_sanitizer_fail_closed_text="$(<"$startup_env_sanitizer_fail_closed_output")"
assert_not_contains "$startup_env_sanitizer_fail_closed_text" "$startup_env_sanitizer_fail_closed_fixture"
assert_not_contains "$startup_env_sanitizer_fail_closed_text" "$startup_env_sanitizer_fail_closed_sentinel"
assert_not_contains "$startup_env_sanitizer_fail_closed_text" "BASH_ENV set function invoked"
assert_not_contains "$startup_env_sanitizer_fail_closed_text" "exported set function invoked"
if [[ "$startup_env_sanitizer_fail_closed_status" -ne 2 ]]; then
  printf '%s\n' "$startup_env_sanitizer_fail_closed_text" >&2
  fail "create release zip sanitizer marker with dirty startup env should exit 2, got $startup_env_sanitizer_fail_closed_status"
fi
assert_contains "$startup_env_sanitizer_fail_closed_text" "unsanitized startup environment remains after create_release_zip sanitizer"
assert_not_contains "$startup_env_sanitizer_fail_closed_text" "Created release zip:"
[[ ! -e "$startup_env_sanitizer_fail_closed_zip" ]] || fail "zip was created despite sanitizer fail-closed dirty startup environment"
[[ ! -e "$startup_env_sanitizer_fail_closed_bash_marker" ]] || fail "create release zip invoked BASH_ENV-defined set function: $(<"$startup_env_sanitizer_fail_closed_bash_marker")"
[[ ! -e "$startup_env_sanitizer_fail_closed_export_marker" ]] || fail "create release zip invoked exported set function: $(<"$startup_env_sanitizer_fail_closed_export_marker")"

# An empty-but-present BASH_ENV is still dirty startup environment. If the
# sanitizer marker is already set, the copied helper must fail closed before
# normal usage/package/zip output.
startup_env_sanitizer_empty_bash_env_fail_closed_sentinel="CREATE_RELEASE_ZIP_EMPTY_BASH_ENV_FAIL_CLOSED_SENTINEL_DO_NOT_PRINT"
startup_env_sanitizer_empty_bash_env_fail_closed_fixture="$fixture_root/startup-env-sanitizer-empty-bash-env-fail-closed"
startup_env_sanitizer_empty_bash_env_fail_closed_zip="$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/artifacts/fail-closed/LithePG.app.zip"
make_fixture "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
verify_log="$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/verify.log"
set +e
(
  command cd "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
  FAKE_VERIFY_LOG="$verify_log" \
    CREATE_RELEASE_ZIP_EMPTY_BASH_ENV_FAIL_CLOSED_SENTINEL="$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel" \
    LITHEPG_CREATE_RELEASE_ZIP_STARTUP_ENV_SANITIZED=1 \
    BASH_ENV="" \
    "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/script/create_release_zip.sh" "dist/LithePG.app" "artifacts/fail-closed/LithePG.app.zip"
) >"$startup_env_sanitizer_empty_bash_env_fail_closed_output" 2>&1
startup_env_sanitizer_empty_bash_env_fail_closed_status=$?
set -e
startup_env_sanitizer_empty_bash_env_fail_closed_text="$(<"$startup_env_sanitizer_empty_bash_env_fail_closed_output")"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel"
if [[ "$startup_env_sanitizer_empty_bash_env_fail_closed_status" -ne 2 ]]; then
  printf '%s\n' "$startup_env_sanitizer_empty_bash_env_fail_closed_text" >&2
  fail "create release zip sanitizer marker with empty BASH_ENV should exit 2, got $startup_env_sanitizer_empty_bash_env_fail_closed_status"
fi
assert_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "unsanitized startup environment remains after create_release_zip sanitizer"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "Usage:"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "Created release zip:"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "SHA-256:"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_text" "Size bytes:"
[[ ! -e "$startup_env_sanitizer_empty_bash_env_fail_closed_zip" ]] || fail "zip was created despite sanitizer fail-closed empty BASH_ENV startup environment"
[[ ! -e "$verify_log" ]] || fail "package verification ran despite sanitizer fail-closed empty BASH_ENV startup environment"

# Perl startup environment alone must trigger sanitization before normal helper
# /usr/bin/perl calls can observe PERL5OPT/PERL5LIB/PERLLIB.
perl_startup_shadow_sentinel="CREATE_RELEASE_ZIP_PERL_STARTUP_SHADOW_SENTINEL_DO_NOT_PRINT"
perl_startup_shadow_fixture="$fixture_root/perl-startup-shadow"
perl_startup_shadow_perl_lib="$perl_startup_shadow_fixture/perl-lib"
perl_startup_shadow_perl_marker="$perl_startup_shadow_fixture/perl-startup-invoked"
make_fixture "$perl_startup_shadow_fixture"
mkdir -p "$perl_startup_shadow_perl_lib"
cat >"$perl_startup_shadow_perl_lib/CreateReleaseZipPerlStartupPoison.pm" <<'PERLMOD'
package CreateReleaseZipPerlStartupPoison;
BEGIN {
  my $sentinel = $ENV{CREATE_RELEASE_ZIP_PERL_STARTUP_SHADOW_SENTINEL} // '';
  my $marker = $ENV{CREATE_RELEASE_ZIP_PERL_STARTUP_MARKER} // '';
  if ($marker ne '' && open(my $fh, '>', $marker)) {
    print {$fh} "perl\n";
    close $fh;
  }
  print STDERR "$sentinel Perl startup invoked\n";
  exit 97;
}
1;
PERLMOD
verify_log="$perl_startup_shadow_fixture/verify.log"
set +e
(
  command cd "$perl_startup_shadow_fixture"
  unset BASH_ENV
  FAKE_VERIFY_LOG="$verify_log" \
    CREATE_RELEASE_ZIP_PERL_STARTUP_SHADOW_SENTINEL="$perl_startup_shadow_sentinel" \
    CREATE_RELEASE_ZIP_PERL_STARTUP_MARKER="$perl_startup_shadow_perl_marker" \
    PERL5LIB="$perl_startup_shadow_perl_lib" \
    PERLLIB="$perl_startup_shadow_perl_lib" \
    PERL5OPT=-MCreateReleaseZipPerlStartupPoison \
    "$perl_startup_shadow_fixture/script/create_release_zip.sh" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"
) >"$perl_startup_shadow_output" 2>&1
perl_startup_shadow_status=$?
set -e
if [[ "$perl_startup_shadow_status" -ne 0 ]]; then
  perl_startup_shadow_text="$(<"$perl_startup_shadow_output")"
  printf '%s\n' "$perl_startup_shadow_text" >&2
  fail "create release zip was affected by Perl-only startup environment shadowing"
fi
perl_startup_shadow_text="$(<"$perl_startup_shadow_output")"
assert_contains "$perl_startup_shadow_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$perl_startup_shadow_text"
assert_size_line_for_zip "$perl_startup_shadow_text" "$perl_startup_shadow_fixture/artifacts/public/LithePG.app.zip"
assert_not_contains "$perl_startup_shadow_text" "$perl_startup_shadow_fixture"
assert_not_contains "$perl_startup_shadow_text" "$perl_startup_shadow_sentinel"
assert_not_contains "$perl_startup_shadow_text" "Perl startup invoked"
[[ ! -e "$perl_startup_shadow_perl_marker" ]] || fail "create release zip honored Perl-only startup environment: $(<"$perl_startup_shadow_perl_marker")"
[[ -f "$perl_startup_shadow_fixture/artifacts/public/LithePG.app.zip" ]] || fail "perl-startup-shadow zip was not created"
assert_zip_contains_app_wrapper "$perl_startup_shadow_fixture/artifacts/public/LithePG.app.zip" "$perl_startup_shadow_fixture/extracted-perl-startup-shadow"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

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

# A trailing slash on the canonical output zip path is refused after verification before creating directories.
trailing_slash_output_zip_fixture="$fixture_root/trailing-slash-output-zip"
make_fixture "$trailing_slash_output_zip_fixture"
trailing_slash_output_zip_path="$trailing_slash_output_zip_fixture/dist/LithePG.app.zip"
verify_log="$trailing_slash_output_zip_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$trailing_slash_output_zip_fixture" "$trailing_slash_output_zip_output" "dist/LithePG.app" "dist/LithePG.app.zip/"; then
  fail "helper unexpectedly accepted an output zip path ending in a slash"
fi
trailing_slash_output_zip_text="$(<"$trailing_slash_output_zip_output")"
assert_contains "$trailing_slash_output_zip_text" "output zip path must not end with a slash"
assert_not_contains "$trailing_slash_output_zip_text" "$sensitive_identity"
assert_not_contains "$trailing_slash_output_zip_text" "$sensitive_notary"
assert_not_contains "$trailing_slash_output_zip_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$trailing_slash_output_zip_path" && ! -L "$trailing_slash_output_zip_path" ]] || fail "trailing-slash output path created a directory or zip"
[[ ! -e "$trailing_slash_output_zip_path/LithePG.app.zip" && ! -L "$trailing_slash_output_zip_path/LithePG.app.zip" ]] || fail "trailing-slash output path created a nested zip"

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

# Existing output parent path must be a directory, not a regular file.
output_parent_file_fixture="$fixture_root/refuse-output-parent-file"
make_fixture "$output_parent_file_fixture"
output_parent_file_path="$output_parent_file_fixture/dist/output-parent-file"
output_parent_file_marker="output parent file marker"
printf '%s\n' "$output_parent_file_marker" >"$output_parent_file_path"
verify_log="$output_parent_file_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$output_parent_file_fixture" "$output_parent_file_output" "dist/LithePG.app" "dist/output-parent-file/LithePG.app.zip"; then
  fail "helper unexpectedly accepted an output zip parent that is a regular file"
fi
output_parent_file_text="$(<"$output_parent_file_output")"
assert_contains "$output_parent_file_text" "output zip parent path must be a directory"
assert_not_contains "$output_parent_file_text" "$sensitive_identity"
assert_not_contains "$output_parent_file_text" "$sensitive_notary"
assert_not_contains "$output_parent_file_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ -f "$output_parent_file_path" && ! -L "$output_parent_file_path" ]] || fail "output parent file was replaced"
[[ "$(<"$output_parent_file_path")" == "$output_parent_file_marker" ]] || fail "output parent file contents changed"
[[ ! -e "$output_parent_file_path/LithePG.app.zip" && ! -L "$output_parent_file_path/LithePG.app.zip" ]] || fail "zip was created under output parent file"

# Existing output parent path must be a directory, not a dangling symlink.
dangling_output_parent_symlink_fixture="$fixture_root/refuse-dangling-output-parent-symlink"
make_fixture "$dangling_output_parent_symlink_fixture"
dangling_output_parent_symlink_path="$dangling_output_parent_symlink_fixture/dist/output-parent-link"
dangling_output_parent_symlink_target="$dangling_output_parent_symlink_fixture/missing-output-parent"
ln -s "$dangling_output_parent_symlink_target" "$dangling_output_parent_symlink_path"
verify_log="$dangling_output_parent_symlink_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$dangling_output_parent_symlink_fixture" "$dangling_output_parent_symlink_output" "dist/LithePG.app" "dist/output-parent-link/LithePG.app.zip"; then
  fail "helper unexpectedly accepted an output zip parent that is a dangling symlink"
fi
dangling_output_parent_symlink_text="$(<"$dangling_output_parent_symlink_output")"
assert_contains "$dangling_output_parent_symlink_text" "output zip parent path must be a directory"
assert_not_contains "$dangling_output_parent_symlink_text" "$sensitive_identity"
assert_not_contains "$dangling_output_parent_symlink_text" "$sensitive_notary"
assert_not_contains "$dangling_output_parent_symlink_text" "$sensitive_release_marker"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ -L "$dangling_output_parent_symlink_path" && ! -e "$dangling_output_parent_symlink_path" ]] || fail "dangling output parent symlink changed despite refusal"
[[ ! -e "$dangling_output_parent_symlink_target" && ! -L "$dangling_output_parent_symlink_target" ]] || fail "dangling output parent symlink target was created"
[[ ! -e "$dangling_output_parent_symlink_path/LithePG.app.zip" && ! -L "$dangling_output_parent_symlink_path/LithePG.app.zip" ]] || fail "zip was created under dangling output parent symlink"

# Output parent directory creation failures must not echo caller-supplied output parents or mkdir's local-path diagnostics.
output_parent_creation_failure_sentinel="MKDIR_SENTINEL_DO_NOT_PRINT"
output_parent_creation_failure_fixture="$fixture_root/output-parent-creation-failure"
make_fixture "$output_parent_creation_failure_fixture"
output_parent_creation_failure_blocked_dir="$output_parent_creation_failure_fixture/blocked"
output_parent_creation_failure_zip="blocked/$output_parent_creation_failure_sentinel/LithePG.app.zip"
output_parent_creation_failure_parent="$output_parent_creation_failure_fixture/blocked/$output_parent_creation_failure_sentinel"
mkdir -p "$output_parent_creation_failure_blocked_dir"
chmod 500 "$output_parent_creation_failure_blocked_dir"
verify_log="$output_parent_creation_failure_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$output_parent_creation_failure_fixture" "$output_parent_creation_failure_output" "dist/LithePG.app" "$output_parent_creation_failure_zip"; then
  chmod u+rwx "$output_parent_creation_failure_blocked_dir"
  fail "helper unexpectedly created a zip under an uncreatable sentinel output parent"
fi
chmod u+rwx "$output_parent_creation_failure_blocked_dir"
output_parent_creation_failure_text="$(<"$output_parent_creation_failure_output")"
assert_contains "$output_parent_creation_failure_text" "could not create output zip parent directory"
assert_not_contains "$output_parent_creation_failure_text" "$output_parent_creation_failure_zip"
assert_not_contains "$output_parent_creation_failure_text" "blocked/$output_parent_creation_failure_sentinel"
assert_not_contains "$output_parent_creation_failure_text" "$output_parent_creation_failure_parent"
assert_not_contains "$output_parent_creation_failure_text" "$output_parent_creation_failure_sentinel"
assert_not_contains "$output_parent_creation_failure_text" "mkdir:"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$output_parent_creation_failure_parent" && ! -L "$output_parent_creation_failure_parent" ]] || fail "sentinel output parent was created despite parent creation failure"
[[ ! -e "$output_parent_creation_failure_fixture/$output_parent_creation_failure_zip" && ! -L "$output_parent_creation_failure_fixture/$output_parent_creation_failure_zip" ]] || fail "zip was created under uncreatable sentinel output parent"

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

# Existing output zip refusal must not echo caller-supplied output directories, which can contain local paths or sentinel values.
refuse_sentinel="REFUSE_EXISTING_OUTPUT_SENTINEL_DO_NOT_PRINT"
refuse_sentinel_fixture="$fixture_root/refuse-existing-sentinel"
make_fixture "$refuse_sentinel_fixture"
refuse_sentinel_zip="artifacts/$refuse_sentinel/LithePG.app.zip"
mkdir -p "$(dirname "$refuse_sentinel_fixture/$refuse_sentinel_zip")"
printf 'existing sentinel zip\n' >"$refuse_sentinel_fixture/$refuse_sentinel_zip"
verify_log="$refuse_sentinel_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$refuse_sentinel_fixture" "$refuse_sentinel_output" "dist/LithePG.app" "$refuse_sentinel_zip"; then
  fail "helper unexpectedly overwrote existing sentinel output zip by default"
fi
refuse_sentinel_text="$(<"$refuse_sentinel_output")"
assert_contains "$refuse_sentinel_text" "Refusing to overwrite existing output zip"
assert_contains "$refuse_sentinel_text" "LITHEPG_RELEASE_ZIP_OVERWRITE=1"
assert_not_contains "$refuse_sentinel_text" "$refuse_sentinel_zip"
assert_not_contains "$refuse_sentinel_text" "$refuse_sentinel"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ "$(<"$refuse_sentinel_fixture/$refuse_sentinel_zip")" == "existing sentinel zip" ]] || fail "existing sentinel zip content changed despite refusal"

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
assert_contains "$overwrite_text" "Created release zip: LithePG.app.zip"
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
assert_contains "$approved_symlink_text" "Created release zip: LithePG.app.zip"
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
assert_contains "$approved_non_dangling_symlink_text" "Created release zip: LithePG.app.zip"
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

# Success output must not echo caller-supplied output directories, which can contain local paths or sentinel values.
success_path_redaction_sentinel="SUCCESS_PATH_REDACTION_SENTINEL_DO_NOT_PRINT"
success_path_redaction_fixture="$fixture_root/success-path-redaction"
make_fixture "$success_path_redaction_fixture"
verify_log="$success_path_redaction_fixture/verify.log"
success_path_redaction_zip="artifacts/$success_path_redaction_sentinel/LithePG.app.zip"
if ! FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$success_path_redaction_fixture" "$success_path_redaction_output" "dist/LithePG.app" "$success_path_redaction_zip"; then
  fail "helper failed when creating a release zip under a sentinel output directory"
fi
success_path_redaction_text="$(<"$success_path_redaction_output")"
assert_contains "$success_path_redaction_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$success_path_redaction_text"
assert_size_line_for_zip "$success_path_redaction_text" "$success_path_redaction_fixture/$success_path_redaction_zip"
assert_not_contains "$success_path_redaction_text" "$success_path_redaction_zip"
assert_not_contains "$success_path_redaction_text" "$success_path_redaction_sentinel"
assert_not_contains "$success_path_redaction_text" "$sensitive_identity"
assert_not_contains "$success_path_redaction_text" "$sensitive_notary"
assert_not_contains "$success_path_redaction_text" "$sensitive_release_marker"
[[ -f "$success_path_redaction_fixture/$success_path_redaction_zip" ]] || fail "success-path-redaction zip was not created"
assert_zip_contains_app_wrapper "$success_path_redaction_fixture/$success_path_redaction_zip" "$success_path_redaction_fixture/extracted-success-path-redaction"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Cleanup failures after zip creation must not leak caller-controlled temp paths or make a successful zip fail.
cleanup_redaction_sentinel="CLEANUP_RM_SENTINEL_DO_NOT_PRINT"
cleanup_redaction_fixture="$fixture_root/cleanup-redaction"
make_fixture "$cleanup_redaction_fixture"
mkdir -p "$cleanup_redaction_fixture/fake-bin"
cat >"$cleanup_redaction_fixture/fake-bin/rm" <<'FAKE_RM'
#!/usr/bin/env bash
printf 'fake rm leaked args: %s\n' "$*"
printf 'fake rm leaked sentinel: CLEANUP_RM_SENTINEL_DO_NOT_PRINT\n' >&2
printf 'fake rm leaked signing identity: %s\n' "${LITHEPG_CODESIGN_IDENTITY:-}" >&2
printf 'fake rm leaked notary profile: %s\n' "${LITHEPG_NOTARY_PROFILE:-}"
printf 'fake rm leaked release marker: %s\n' "${LITHEPG_RELEASE_MARKER:-}" >&2
exit 1
FAKE_RM
chmod +x "$cleanup_redaction_fixture/fake-bin/rm"
verify_log="$cleanup_redaction_fixture/verify.log"
cleanup_redaction_zip="artifacts/$cleanup_redaction_sentinel/LithePG.app.zip"
if ! FAKE_VERIFY_LOG="$verify_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  PATH="$cleanup_redaction_fixture/fake-bin:$PATH" \
  run_helper_capture "$cleanup_redaction_fixture" "$cleanup_redaction_output" "dist/LithePG.app" "$cleanup_redaction_zip"; then
  fail "helper failed when cleanup rm failed after creating the zip"
fi
cleanup_redaction_text="$(<"$cleanup_redaction_output")"
assert_contains "$cleanup_redaction_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$cleanup_redaction_text"
assert_size_line_for_zip "$cleanup_redaction_text" "$cleanup_redaction_fixture/$cleanup_redaction_zip"
assert_not_contains "$cleanup_redaction_text" "$cleanup_redaction_zip"
assert_not_contains "$cleanup_redaction_text" "$cleanup_redaction_sentinel"
assert_not_contains "$cleanup_redaction_text" "$sensitive_identity"
assert_not_contains "$cleanup_redaction_text" "$sensitive_notary"
assert_not_contains "$cleanup_redaction_text" "$sensitive_release_marker"
[[ -f "$cleanup_redaction_fixture/$cleanup_redaction_zip" ]] || fail "cleanup-redaction zip was not created"
assert_zip_contains_app_wrapper "$cleanup_redaction_fixture/$cleanup_redaction_zip" "$cleanup_redaction_fixture/extracted-cleanup-redaction"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Exported shell functions named like root-resolution builtins, plus PATH-shadowed realpath,
# must not affect repository-root setup or release zip creation.
root_resolution_shadow_realpath_sentinel="ROOT_REALPATH_PATH_SHADOW_SENTINEL_DO_NOT_PRINT"
root_resolution_shadow_command_sentinel="ROOT_COMMAND_FUNCTION_SHADOW_SENTINEL_DO_NOT_PRINT"
root_resolution_shadow_builtin_sentinel="ROOT_BUILTIN_FUNCTION_SHADOW_SENTINEL_DO_NOT_PRINT"
root_resolution_shadow_cd_sentinel="ROOT_CD_FUNCTION_SHADOW_SENTINEL_DO_NOT_PRINT"
root_resolution_shadow_pwd_sentinel="ROOT_PWD_FUNCTION_SHADOW_SENTINEL_DO_NOT_PRINT"
root_resolution_shadow_fixture="$fixture_root/root-resolution-shadow"
make_fixture "$root_resolution_shadow_fixture"
root_resolution_shadow_fake_bin="$root_resolution_shadow_fixture/fake-bin"
root_resolution_shadow_marker_dir="$root_resolution_shadow_fixture/root-shadow-markers"
mkdir -p "$root_resolution_shadow_fake_bin" "$root_resolution_shadow_marker_dir"
cat >"$root_resolution_shadow_fake_bin/realpath" <<'FAKE_REALPATH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s fake realpath stdout\n' "${ROOT_RESOLUTION_SHADOW_REALPATH_SENTINEL:?}"
printf '%s fake realpath stderr\n' "${ROOT_RESOLUTION_SHADOW_REALPATH_SENTINEL:?}" >&2
printf 'realpath\n' >"${ROOT_RESOLUTION_SHADOW_MARKER_DIR:?}/realpath"
exit 97
FAKE_REALPATH
chmod +x "$root_resolution_shadow_fake_bin/realpath"
verify_log="$root_resolution_shadow_fixture/verify.log"
set +e
(
  command cd "$root_resolution_shadow_fixture"
  command() {
    /usr/bin/printf '%s command invoked\n' "${ROOT_RESOLUTION_SHADOW_COMMAND_SENTINEL:?}" >&2
    /usr/bin/printf 'command\n' >"${ROOT_RESOLUTION_SHADOW_MARKER_DIR:?}/command"
    exit 97
  }
  builtin() {
    /usr/bin/printf '%s builtin invoked\n' "${ROOT_RESOLUTION_SHADOW_BUILTIN_SENTINEL:?}" >&2
    /usr/bin/printf 'builtin\n' >"${ROOT_RESOLUTION_SHADOW_MARKER_DIR:?}/builtin"
    exit 97
  }
  cd() {
    /usr/bin/printf '%s cd invoked\n' "${ROOT_RESOLUTION_SHADOW_CD_SENTINEL:?}" >&2
    /usr/bin/printf 'cd\n' >"${ROOT_RESOLUTION_SHADOW_MARKER_DIR:?}/cd"
    exit 97
  }
  pwd() {
    /usr/bin/printf '%s pwd invoked\n' "${ROOT_RESOLUTION_SHADOW_PWD_SENTINEL:?}" >&2
    /usr/bin/printf 'pwd\n' >"${ROOT_RESOLUTION_SHADOW_MARKER_DIR:?}/pwd"
    /usr/bin/printf '%s\n' "${ROOT_RESOLUTION_SHADOW_FAKE_PWD:?}"
  }
  export -f command
  export -f builtin
  export -f cd
  export -f pwd
  FAKE_VERIFY_LOG="$verify_log" \
    LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
    LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
    LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
    ROOT_RESOLUTION_SHADOW_MARKER_DIR="$root_resolution_shadow_marker_dir" \
    ROOT_RESOLUTION_SHADOW_FAKE_PWD="$fixture_root/root-resolution-wrong-root" \
    ROOT_RESOLUTION_SHADOW_REALPATH_SENTINEL="$root_resolution_shadow_realpath_sentinel" \
    ROOT_RESOLUTION_SHADOW_COMMAND_SENTINEL="$root_resolution_shadow_command_sentinel" \
    ROOT_RESOLUTION_SHADOW_BUILTIN_SENTINEL="$root_resolution_shadow_builtin_sentinel" \
    ROOT_RESOLUTION_SHADOW_CD_SENTINEL="$root_resolution_shadow_cd_sentinel" \
    ROOT_RESOLUTION_SHADOW_PWD_SENTINEL="$root_resolution_shadow_pwd_sentinel" \
    PATH="$root_resolution_shadow_fake_bin:$PATH" \
    "$root_resolution_shadow_fixture/script/create_release_zip.sh" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"
) >"$root_resolution_shadow_output" 2>&1
root_resolution_shadow_status=$?
set -e
if [[ "$root_resolution_shadow_status" -ne 0 ]]; then
  if [[ -e "$root_resolution_shadow_marker_dir/command" || -e "$root_resolution_shadow_marker_dir/builtin" || -e "$root_resolution_shadow_marker_dir/cd" || -e "$root_resolution_shadow_marker_dir/pwd" ]]; then
    fail "helper root resolution invoked a function-shadowed shell builtin"
  fi
  if [[ -e "$root_resolution_shadow_marker_dir/realpath" ]]; then
    fail "helper root resolution invoked a PATH-shadowed realpath"
  fi
  fail "helper failed under root-resolution shadowing"
fi
root_resolution_shadow_text="$(<"$root_resolution_shadow_output")"
assert_contains "$root_resolution_shadow_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$root_resolution_shadow_text"
assert_size_line_for_zip "$root_resolution_shadow_text" "$root_resolution_shadow_fixture/artifacts/public/LithePG.app.zip"
assert_not_contains "$root_resolution_shadow_text" "$root_resolution_shadow_realpath_sentinel"
assert_not_contains "$root_resolution_shadow_text" "$root_resolution_shadow_command_sentinel"
assert_not_contains "$root_resolution_shadow_text" "$root_resolution_shadow_builtin_sentinel"
assert_not_contains "$root_resolution_shadow_text" "$root_resolution_shadow_cd_sentinel"
assert_not_contains "$root_resolution_shadow_text" "$root_resolution_shadow_pwd_sentinel"
assert_not_contains "$root_resolution_shadow_text" "$sensitive_identity"
assert_not_contains "$root_resolution_shadow_text" "$sensitive_notary"
assert_not_contains "$root_resolution_shadow_text" "$sensitive_release_marker"
for tool in realpath command builtin cd pwd; do
  [[ ! -e "$root_resolution_shadow_marker_dir/$tool" ]] || fail "helper root resolution invoked shadowed $tool"
done
[[ -f "$root_resolution_shadow_fixture/artifacts/public/LithePG.app.zip" ]] || fail "root-resolution-shadow zip was not created"
assert_zip_contains_app_wrapper "$root_resolution_shadow_fixture/artifacts/public/LithePG.app.zip" "$root_resolution_shadow_fixture/extracted-root-resolution-shadow"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# PATH-shadowed core utility names must not affect release zip creation or leak fake-tool output.
path_shadow_sentinel="PATH_SHADOW_SENTINEL_DO_NOT_PRINT"
path_shadow_fixture="$fixture_root/path-shadowed-core-utilities"
make_fixture "$path_shadow_fixture"
path_shadow_fake_bin="$path_shadow_fixture/fake-bin"
path_shadow_fake_tool_log="$path_shadow_fixture/fake-tool.log"
mkdir -p "$path_shadow_fake_bin"
for utility in basename dirname mkdir mktemp rm; do
  cat >"$path_shadow_fake_bin/$utility" <<FAKE_CORE_UTILITY
#!/usr/bin/env bash
printf '$path_shadow_sentinel fake $utility stdout\n'
printf '$path_shadow_sentinel fake $utility stderr\n' >&2
if [[ -n "\${PATH_SHADOW_FAKE_TOOL_LOG:-}" ]]; then
  printf '$path_shadow_sentinel fake $utility invoked\n' >>"\$PATH_SHADOW_FAKE_TOOL_LOG"
fi
exit 97
FAKE_CORE_UTILITY
  chmod +x "$path_shadow_fake_bin/$utility"
done
verify_log="$path_shadow_fixture/verify.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  PATH_SHADOW_FAKE_TOOL_LOG="$path_shadow_fake_tool_log" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  PATH="$path_shadow_fake_bin:$PATH" \
  run_helper_capture "$path_shadow_fixture" "$path_shadow_output" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"; then
  path_shadow_text="$(<"$path_shadow_output")"
  printf '%s\n' "$path_shadow_text" >&2
  fail "helper failed with PATH-shadowed core utilities"
fi
path_shadow_text="$(<"$path_shadow_output")"
assert_contains "$path_shadow_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$path_shadow_text"
assert_size_line_for_zip "$path_shadow_text" "$path_shadow_fixture/artifacts/public/LithePG.app.zip"
assert_not_contains "$path_shadow_text" "$path_shadow_sentinel"
[[ ! -s "$path_shadow_fake_tool_log" ]] || fail "helper invoked a PATH-shadowed core utility"
assert_not_contains "$path_shadow_text" "$sensitive_identity"
assert_not_contains "$path_shadow_text" "$sensitive_notary"
assert_not_contains "$path_shadow_text" "$sensitive_release_marker"
[[ -f "$path_shadow_fixture/artifacts/public/LithePG.app.zip" ]] || fail "path-shadowed utility zip was not created"
assert_zip_contains_app_wrapper "$path_shadow_fixture/artifacts/public/LithePG.app.zip" "$path_shadow_fixture/extracted-path-shadowed-core-utilities"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"

# Temporary output directory creation failures must not echo caller-supplied output parents or mktemp's local-path diagnostics.
temp_creation_failure_sentinel="TEMP_CREATION_FAILURE_SENTINEL_DO_NOT_PRINT"
temp_creation_failure_fixture="$fixture_root/temp-creation-failure"
make_fixture "$temp_creation_failure_fixture"
temp_creation_failure_parent="$temp_creation_failure_fixture/artifacts/$temp_creation_failure_sentinel"
temp_creation_failure_zip="artifacts/$temp_creation_failure_sentinel/LithePG.app.zip"
mkdir -p "$temp_creation_failure_parent"
chmod 500 "$temp_creation_failure_parent"
verify_log="$temp_creation_failure_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$temp_creation_failure_fixture" "$temp_creation_failure_output" "dist/LithePG.app" "$temp_creation_failure_zip"; then
  chmod u+rwx "$temp_creation_failure_parent"
  fail "helper unexpectedly created a zip under an unwritable sentinel output parent"
fi
chmod u+rwx "$temp_creation_failure_parent"
temp_creation_failure_text="$(<"$temp_creation_failure_output")"
assert_contains "$temp_creation_failure_text" "could not create temporary output directory"
assert_not_contains "$temp_creation_failure_text" "$temp_creation_failure_zip"
assert_not_contains "$temp_creation_failure_text" "$temp_creation_failure_parent"
assert_not_contains "$temp_creation_failure_text" "$temp_creation_failure_sentinel"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$temp_creation_failure_fixture/$temp_creation_failure_zip" ]] || fail "zip was created under unwritable sentinel output parent"

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

# Inside-app-bundle output refusal must not echo caller-supplied path segments.
inside_bundle_sentinel="INSIDE_APP_OUTPUT_SENTINEL_DO_NOT_PRINT"
inside_bundle_sentinel_fixture="$fixture_root/inside-app-output-sentinel"
make_fixture "$inside_bundle_sentinel_fixture"
inside_bundle_sentinel_zip="dist/LithePG.app/Contents/$inside_bundle_sentinel/LithePG.app.zip"
verify_log="$inside_bundle_sentinel_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  run_helper_capture "$inside_bundle_sentinel_fixture" "$inside_bundle_sentinel_output" "dist/LithePG.app" "$inside_bundle_sentinel_zip"; then
  fail "helper unexpectedly allowed sentinel output zip inside the app bundle"
fi
inside_bundle_sentinel_text="$(<"$inside_bundle_sentinel_output")"
assert_contains "$inside_bundle_sentinel_text" "output zip must not be inside the app bundle"
assert_not_contains "$inside_bundle_sentinel_text" "$inside_bundle_sentinel_zip"
assert_not_contains "$inside_bundle_sentinel_text" "$inside_bundle_sentinel"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$inside_bundle_sentinel_fixture/$inside_bundle_sentinel_zip" ]] || fail "sentinel zip was created inside the app bundle"

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

# A failing artifact-only v1.0 gate must stop before the final rename and only emit a generic failure.
artifact_gate_failure_sentinel="ARTIFACT_GATE_FAILURE_SENTINEL_DO_NOT_PRINT"
artifact_gate_failure_fixture="$fixture_root/artifact-gate-failure"
artifact_gate_failure_zip="$artifact_gate_failure_fixture/artifacts/public/LithePG.app.zip"
artifact_gate_failure_log="$artifact_gate_failure_fixture/artifact-gate.log"
make_fixture "$artifact_gate_failure_fixture"
verify_log="$artifact_gate_failure_fixture/verify.log"
if FAKE_VERIFY_LOG="$verify_log" \
  FAKE_VERIFY_QUIET="1" \
  FAKE_GATE_LOG="$artifact_gate_failure_log" \
  FAKE_GATE_FINAL_ZIP_PATH="$artifact_gate_failure_zip" \
  FAKE_ARTIFACT_GATE_FAIL="1" \
  FAKE_ARTIFACT_GATE_SENTINEL="$artifact_gate_failure_sentinel" \
  FAKE_ARTIFACT_GATE_FIXTURE_PATH="$artifact_gate_failure_fixture" \
  run_helper_capture "$artifact_gate_failure_fixture" "$artifact_gate_failure_output" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"; then
  fail "helper unexpectedly passed when artifact gate failed"
fi
artifact_gate_failure_text="$(<"$artifact_gate_failure_output")"
[[ "$artifact_gate_failure_text" == "create_release_zip failed: release artifact validation failed" ]] || fail "artifact gate failure output was not only the generic failure"
assert_not_contains "$artifact_gate_failure_text" "$artifact_gate_failure_fixture"
assert_not_contains "$artifact_gate_failure_text" "$artifact_gate_failure_sentinel"
assert_not_contains "$artifact_gate_failure_text" "fake artifact gate stdout leak"
assert_not_contains "$artifact_gate_failure_text" "fake artifact gate stderr leak"
assert_not_contains "$artifact_gate_failure_text" "Created release zip:"
assert_not_contains "$artifact_gate_failure_text" "SHA-256:"
assert_not_contains "$artifact_gate_failure_text" "Size bytes:"
assert_file_contains "$artifact_gate_failure_log" "args=--artifact-only"
assert_file_contains "$artifact_gate_failure_log" "zip_exists=1"
assert_file_contains "$artifact_gate_failure_log" "final_zip_exists=0"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
[[ ! -e "$artifact_gate_failure_zip" ]] || fail "final zip was created despite artifact gate failure"

# Success creates parent directories, preserves the .app wrapper, prints SHA-256, and does not leak secret-ish env values.
success_fixture="$fixture_root/success"
make_fixture "$success_fixture"
verify_log="$success_fixture/verify.log"
success_gate_log="$success_fixture/artifact-gate.log"
if ! FAKE_VERIFY_LOG="$verify_log" \
  FAKE_GATE_LOG="$success_gate_log" \
  FAKE_GATE_FINAL_ZIP_PATH="$success_fixture/artifacts/public/LithePG.app.zip" \
  LITHEPG_CODESIGN_IDENTITY="$sensitive_identity" \
  LITHEPG_NOTARY_PROFILE="$sensitive_notary" \
  LITHEPG_RELEASE_MARKER="$sensitive_release_marker" \
  run_helper_capture "$success_fixture" "$success_output" "dist/LithePG.app" "artifacts/public/LithePG.app.zip"; then
  fail "helper failed on successful zip creation"
fi
success_text="$(<"$success_output")"
assert_contains "$success_text" "Created release zip: LithePG.app.zip"
assert_matches_sha_line "$success_text"
assert_size_line_for_zip "$success_text" "$success_fixture/artifacts/public/LithePG.app.zip"
assert_not_contains "$success_text" "$sensitive_identity"
assert_not_contains "$success_text" "$sensitive_notary"
assert_not_contains "$success_text" "$sensitive_release_marker"
[[ -f "$success_fixture/artifacts/public/LithePG.app.zip" ]] || fail "success zip was not created in nested output directory"
assert_zip_contains_app_wrapper "$success_fixture/artifacts/public/LithePG.app.zip" "$success_fixture/extracted-success"
assert_file_contains "$verify_log" "package_verify dist/LithePG.app"
success_gate_text="$(<"$success_gate_log")"
assert_contains "$success_gate_text" "args=--artifact-only"
assert_contains "$success_gate_text" "zip_exists=1"
assert_contains "$success_gate_text" "final_zip_exists=0"
success_gate_path="$(first_log_value "$success_gate_text" "zip_path")"
success_gate_sha="$(first_log_value "$success_gate_text" "zip_sha")"
success_gate_actual_sha="$(first_log_value "$success_gate_text" "actual_sha")"
success_fixture_real="$(/bin/realpath "$success_fixture")"
success_final_zip_real="$success_fixture_real/artifacts/public/LithePG.app.zip"
[[ "$success_gate_path" == "$success_fixture_real/artifacts/public/.release-zip."*/LithePG.app.zip ]] || fail "artifact gate did not receive staged temporary zip path"
[[ "$success_gate_path" != "$success_final_zip_real" ]] || fail "artifact gate received final zip path instead of staged zip path"
[[ "$success_gate_sha" =~ ^[0-9a-f]{64}$ ]] || fail "artifact gate did not receive a 64-hex SHA"
[[ "$success_gate_sha" == "$success_gate_actual_sha" ]] || fail "artifact gate SHA did not match staged zip content"
assert_contains "$success_text" "SHA-256: $success_gate_sha"

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
assert_contains "$outside_cwd_text" "Created release zip: LithePG.app.zip"
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
help_fake_bin="$help_fixture/fake-bin"
help_fake_tool_log="$help_fixture/fake-tool.log"
help_cat_sentinel="CREATE_RELEASE_ZIP_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN"
mkdir -p "$help_fake_bin"
cat >"$help_fake_bin/cat" <<FAKE_CAT
#!/usr/bin/env bash
printf '$help_cat_sentinel fake cat stdout\n'
printf '$help_cat_sentinel fake cat stderr\n' >&2
if [[ -n "\${PATH_SHADOW_FAKE_TOOL_LOG:-}" ]]; then
  printf '$help_cat_sentinel fake cat invoked\n' >>"\$PATH_SHADOW_FAKE_TOOL_LOG"
fi
exit 97
FAKE_CAT
chmod +x "$help_fake_bin/cat"
if ! FAKE_VERIFY_LOG="$help_fixture/verify.log" \
  PATH_SHADOW_FAKE_TOOL_LOG="$help_fake_tool_log" \
  PATH="$help_fake_bin:$PATH" \
  run_helper_capture "$help_fixture" "$help_output" "--help"; then
  help_text="$(<"$help_output")"
  printf '%s\n' "$help_text" >&2
  fail "--help did not exit 0"
fi
help_text="$(<"$help_output")"
assert_contains "$help_text" "Usage:"
assert_contains "$help_text" "create_release_zip.sh [app-bundle] [output-zip]"
assert_not_contains "$help_text" "$help_cat_sentinel"
[[ ! -s "$help_fake_tool_log" ]] || fail "create release zip --help invoked PATH-shadowed cat"
[[ ! -e "$help_fixture/verify.log" ]] || fail "help unexpectedly ran package verification"

printf 'test_create_release_zip passed\n'
