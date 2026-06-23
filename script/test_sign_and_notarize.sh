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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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

  mkdir -p "$app_bundle/Contents/Resources"
  chmod 755 "$app_bundle/Contents/Resources"
  printf '\x69\x63\x6e\x73\x00\x00\x00\x4a\x69\x63\x31\x30\x00\x00\x00\x42\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x04\x00\x00\x00\x04\x00\x08\x06\x00\x00\x00\x7f\x1d\x2b\x83\x00\x00\x00\x01\x49\x44\x41\x54\x78\x76\xe6\x84\xe6\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' >"$app_bundle/Contents/Resources/AppIcon.icns"
  chmod 644 "$app_bundle/Contents/Resources/AppIcon.icns"
}

make_startup_hardening_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/script" "$fixture/dist" "$fixture/Sources/LithePGApp"
  cp "$HELPER" "$fixture/script/sign_and_notarize.sh"
  chmod +x "$fixture/script/sign_and_notarize.sh"
  make_minimal_app_bundle "$fixture/dist/LithePG.app"
  printf '<plist version="1.0"><dict/></plist>\n' >"$fixture/Sources/LithePGApp/LithePGApp.entitlements"

  cat >"$fixture/script/package_verify.sh" <<'FAKE_VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'fake package verified: %s\n' "${1##*/}"
FAKE_VERIFY
  chmod +x "$fixture/script/package_verify.sh"
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
helper_contents="$(<"$HELPER")"
assert_contains "$helper_contents" 'CODESIGN_BIN=/usr/bin/codesign'
assert_contains "$helper_contents" 'DITTO_BIN=/usr/bin/ditto'
assert_contains "$helper_contents" 'XCRUN_BIN=/usr/bin/xcrun'
assert_contains "$helper_contents" 'SPCTL_BIN=/usr/sbin/spctl'
assert_contains "$helper_contents" 'run_quiet "codesign failed" "$CODESIGN_BIN"'
assert_contains "$helper_contents" 'run_quiet "codesign verification failed" "$CODESIGN_BIN"'
assert_contains "$helper_contents" 'run_quiet "notary zip creation failed" "$DITTO_BIN"'
assert_contains "$helper_contents" 'run_quiet "notary submission failed" "$XCRUN_BIN"'
assert_contains "$helper_contents" 'run_quiet "staple failed" "$XCRUN_BIN"'
assert_contains "$helper_contents" 'run_quiet "staple validation failed" "$XCRUN_BIN"'
assert_contains "$helper_contents" 'run_quiet "spctl assessment failed" "$SPCTL_BIN"'
assert_not_contains "$helper_contents" 'run_quiet "codesign failed" codesign'
assert_not_contains "$helper_contents" 'run_quiet "codesign verification failed" codesign'
assert_not_contains "$helper_contents" 'run_quiet "notary zip creation failed" ditto'
assert_not_contains "$helper_contents" 'run_quiet "notary submission failed" xcrun'
assert_not_contains "$helper_contents" 'run_quiet "staple failed" xcrun'
assert_not_contains "$helper_contents" 'run_quiet "staple validation failed" xcrun'
assert_not_contains "$helper_contents" 'run_quiet "spctl assessment failed" spctl'

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

# Executable startup must not route through PATH-selected bash before helper code runs.
initial_bash_path_shadow_sentinel="SIGN_AND_NOTARIZE_INITIAL_BASH_PATH_SHADOW_SENTINEL_DO_NOT_PRINT"
initial_bash_path_shadow_fixture="$fixture_root/initial-bash-path-shadow"
initial_bash_path_shadow_fake_bin="$initial_bash_path_shadow_fixture/fake-bin"
initial_bash_path_shadow_marker="$initial_bash_path_shadow_fixture/fake-bash-invoked"
make_startup_hardening_fixture "$initial_bash_path_shadow_fixture"
mkdir -p "$initial_bash_path_shadow_fake_bin"
cat >"$initial_bash_path_shadow_fake_bin/bash" <<'FAKE_BASH'
#!/bin/sh
/usr/bin/printf '%s fake bash invoked\n' "${SIGN_AND_NOTARIZE_INITIAL_BASH_PATH_SHADOW_SENTINEL:-}" >&2
/usr/bin/printf 'bash\n' >"${SIGN_AND_NOTARIZE_INITIAL_BASH_PATH_SHADOW_MARKER:?}"
exit 97
FAKE_BASH
chmod +x "$initial_bash_path_shadow_fake_bin/bash"
set +e
(
  cd "$initial_bash_path_shadow_fixture"
  SIGN_AND_NOTARIZE_INITIAL_BASH_PATH_SHADOW_SENTINEL="$initial_bash_path_shadow_sentinel" \
    SIGN_AND_NOTARIZE_INITIAL_BASH_PATH_SHADOW_MARKER="$initial_bash_path_shadow_marker" \
    PATH="$initial_bash_path_shadow_fake_bin:$PATH" \
    "$initial_bash_path_shadow_fixture/script/sign_and_notarize.sh" --help
) >"$output_file" 2>&1
initial_bash_path_shadow_status=$?
set -e
initial_bash_path_shadow_output="$(<"$output_file")"
if [[ "$initial_bash_path_shadow_status" -ne 0 ]]; then
  printf '%s\n' "$initial_bash_path_shadow_output" >&2
  fail "sign/notarize executable invocation used PATH-selected bash"
fi
assert_contains "$initial_bash_path_shadow_output" "Usage: sign_and_notarize.sh [--dry-run] [app-bundle]"
assert_not_contains "$initial_bash_path_shadow_output" "$initial_bash_path_shadow_sentinel"
assert_not_contains "$initial_bash_path_shadow_output" "fake bash invoked"
[[ ! -e "$initial_bash_path_shadow_marker" ]] || fail "sign/notarize executable invocation used PATH-selected bash: $(<"$initial_bash_path_shadow_marker")"

# Bash and Perl startup environments, including exported shell functions, must be
# sanitized before normal dry-run helper logic or the fake package verifier can observe them.
startup_env_shadow_sentinel="SIGN_AND_NOTARIZE_STARTUP_ENV_SHADOW_SENTINEL_DO_NOT_PRINT"
startup_env_shadow_fixture="$fixture_root/startup-env-shadow"
startup_env_shadow_bash_env="$startup_env_shadow_fixture/poison.bash_env"
startup_env_shadow_perl_lib="$startup_env_shadow_fixture/perl-lib"
startup_env_shadow_bash_marker="$startup_env_shadow_fixture/bash-startup-invoked"
startup_env_shadow_export_marker="$startup_env_shadow_fixture/exported-function-invoked"
startup_env_shadow_perl_marker="$startup_env_shadow_fixture/perl-startup-invoked"
startup_env_shadow_notary_zip="$startup_env_shadow_fixture/dist/LithePG-notary.zip"
make_startup_hardening_fixture "$startup_env_shadow_fixture"
mkdir -p "$startup_env_shadow_perl_lib"
cat >"$startup_env_shadow_bash_env" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${SIGN_AND_NOTARIZE_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${SIGN_AND_NOTARIZE_STARTUP_ENV_BASH_MARKER:?}"
  exit 97
}
BASHENV
cat >"$startup_env_shadow_perl_lib/SignAndNotarizeStartupPoison.pm" <<'PERLMOD'
package SignAndNotarizeStartupPoison;
BEGIN {
  my $sentinel = $ENV{SIGN_AND_NOTARIZE_STARTUP_ENV_SHADOW_SENTINEL} // '';
  my $marker = $ENV{SIGN_AND_NOTARIZE_STARTUP_ENV_PERL_MARKER} // '';
  if ($marker ne '' && open(my $fh, '>', $marker)) {
    print {$fh} "perl\n";
    close $fh;
  }
  print STDERR "$sentinel Perl startup invoked\n";
  exit 97;
}
1;
PERLMOD
set +e
(
  command cd "$startup_env_shadow_fixture"
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${SIGN_AND_NOTARIZE_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${SIGN_AND_NOTARIZE_STARTUP_ENV_EXPORT_MARKER:?}"
    exit 97
  }
  export -f set
  SIGN_AND_NOTARIZE_STARTUP_ENV_SHADOW_SENTINEL="$startup_env_shadow_sentinel" \
    SIGN_AND_NOTARIZE_STARTUP_ENV_BASH_MARKER="$startup_env_shadow_bash_marker" \
    SIGN_AND_NOTARIZE_STARTUP_ENV_EXPORT_MARKER="$startup_env_shadow_export_marker" \
    SIGN_AND_NOTARIZE_STARTUP_ENV_PERL_MARKER="$startup_env_shadow_perl_marker" \
    BASH_ENV="$startup_env_shadow_bash_env" \
    PERL5LIB="$startup_env_shadow_perl_lib" \
    PERLLIB="$startup_env_shadow_perl_lib" \
    PERL5OPT=-MSignAndNotarizeStartupPoison \
    LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$startup_env_shadow_notary_zip" \
    "$startup_env_shadow_fixture/script/sign_and_notarize.sh" --dry-run dist/LithePG.app
) >"$output_file" 2>&1
startup_env_shadow_status=$?
set -e
startup_env_shadow_output="$(<"$output_file")"
if [[ "$startup_env_shadow_status" -ne 0 ]]; then
  printf '%s\n' "$startup_env_shadow_output" >&2
  fail "sign/notarize was affected by Bash/Perl startup environment shadowing"
fi
assert_contains "$startup_env_shadow_output" "fake package verified: LithePG.app"
assert_contains "$startup_env_shadow_output" "Signing/notarization dry run OK"
assert_contains "$startup_env_shadow_output" "Codesign identity: present (redacted)"
assert_contains "$startup_env_shadow_output" "Notary profile: present (redacted)"
assert_not_contains "$startup_env_shadow_output" "$startup_env_shadow_fixture"
assert_not_contains "$startup_env_shadow_output" "$startup_env_shadow_sentinel"
assert_not_contains "$startup_env_shadow_output" "BASH_ENV set function invoked"
assert_not_contains "$startup_env_shadow_output" "exported set function invoked"
assert_not_contains "$startup_env_shadow_output" "Perl startup invoked"
assert_not_contains "$startup_env_shadow_output" "$codesign_sentinel"
assert_not_contains "$startup_env_shadow_output" "$notary_sentinel"
[[ ! -e "$startup_env_shadow_bash_marker" ]] || fail "sign/notarize invoked BASH_ENV-defined set function: $(<"$startup_env_shadow_bash_marker")"
[[ ! -e "$startup_env_shadow_export_marker" ]] || fail "sign/notarize invoked exported set function: $(<"$startup_env_shadow_export_marker")"
[[ ! -e "$startup_env_shadow_perl_marker" ]] || fail "sign/notarize honored Perl startup environment: $(<"$startup_env_shadow_perl_marker")"
[[ ! -e "$startup_env_shadow_notary_zip" ]] || fail "startup-env dry run created notary zip: $startup_env_shadow_notary_zip"

# If dirty startup environment remains after the sanitizer marker is already set,
# the copied executable helper must fail closed instead of re-sanitizing and continuing.
startup_env_sanitizer_fail_closed_sentinel="SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_SENTINEL_DO_NOT_PRINT"
startup_env_sanitizer_fail_closed_fixture="$fixture_root/startup-env-sanitizer-fail-closed"
startup_env_sanitizer_fail_closed_bash_env="$startup_env_sanitizer_fail_closed_fixture/poison.bash_env"
startup_env_sanitizer_fail_closed_bash_marker="$startup_env_sanitizer_fail_closed_fixture/bash-startup-invoked"
startup_env_sanitizer_fail_closed_export_marker="$startup_env_sanitizer_fail_closed_fixture/exported-function-invoked"
startup_env_sanitizer_fail_closed_notary_zip="$startup_env_sanitizer_fail_closed_fixture/dist/LithePG-notary.zip"
make_startup_hardening_fixture "$startup_env_sanitizer_fail_closed_fixture"
cat >"$startup_env_sanitizer_fail_closed_bash_env" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_BASH_MARKER:?}"
  exit 97
}
BASHENV
set +e
(
  command cd "$startup_env_sanitizer_fail_closed_fixture"
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_EXPORT_MARKER:?}"
    exit 97
  }
  export -f set
  SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_SENTINEL="$startup_env_sanitizer_fail_closed_sentinel" \
    SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_BASH_MARKER="$startup_env_sanitizer_fail_closed_bash_marker" \
    SIGN_AND_NOTARIZE_SANITIZER_FAIL_CLOSED_EXPORT_MARKER="$startup_env_sanitizer_fail_closed_export_marker" \
    LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$startup_env_sanitizer_fail_closed_notary_zip" \
    LITHEPG_SIGN_AND_NOTARIZE_STARTUP_ENV_SANITIZED=1 \
    BASH_ENV="$startup_env_sanitizer_fail_closed_bash_env" \
    "$startup_env_sanitizer_fail_closed_fixture/script/sign_and_notarize.sh" --dry-run dist/LithePG.app
) >"$output_file" 2>&1
startup_env_sanitizer_fail_closed_status=$?
set -e
startup_env_sanitizer_fail_closed_output="$(<"$output_file")"
if [[ "$startup_env_sanitizer_fail_closed_status" -ne 2 ]]; then
  printf '%s\n' "$startup_env_sanitizer_fail_closed_output" >&2
  fail "sign/notarize sanitizer marker with dirty startup env should exit 2, got $startup_env_sanitizer_fail_closed_status"
fi
assert_contains "$startup_env_sanitizer_fail_closed_output" "unsanitized startup environment remains after sign_and_notarize sanitizer"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "$startup_env_sanitizer_fail_closed_fixture"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "$startup_env_sanitizer_fail_closed_sentinel"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "BASH_ENV set function invoked"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "exported set function invoked"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "fake package verified:"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "Signing/notarization dry run OK"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "$codesign_sentinel"
assert_not_contains "$startup_env_sanitizer_fail_closed_output" "$notary_sentinel"
[[ ! -e "$startup_env_sanitizer_fail_closed_notary_zip" ]] || fail "sanitizer fail-closed dry run created notary zip: $startup_env_sanitizer_fail_closed_notary_zip"
[[ ! -e "$startup_env_sanitizer_fail_closed_bash_marker" ]] || fail "sign/notarize invoked BASH_ENV-defined set function: $(<"$startup_env_sanitizer_fail_closed_bash_marker")"
[[ ! -e "$startup_env_sanitizer_fail_closed_export_marker" ]] || fail "sign/notarize invoked exported set function: $(<"$startup_env_sanitizer_fail_closed_export_marker")"

# An empty-but-present BASH_ENV is still dirty startup environment. If the
# sanitizer marker is already set, the copied helper must fail closed before
# normal usage/package/dry-run output.
startup_env_sanitizer_empty_bash_env_fail_closed_sentinel="SIGN_AND_NOTARIZE_EMPTY_BASH_ENV_FAIL_CLOSED_SENTINEL_DO_NOT_PRINT"
startup_env_sanitizer_empty_bash_env_fail_closed_fixture="$fixture_root/startup-env-sanitizer-empty-bash-env-fail-closed"
startup_env_sanitizer_empty_bash_env_fail_closed_notary_zip="$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/dist/LithePG-notary.zip"
make_startup_hardening_fixture "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
set +e
(
  command cd "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
  SIGN_AND_NOTARIZE_EMPTY_BASH_ENV_FAIL_CLOSED_SENTINEL="$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel" \
    LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$startup_env_sanitizer_empty_bash_env_fail_closed_notary_zip" \
    LITHEPG_SIGN_AND_NOTARIZE_STARTUP_ENV_SANITIZED=1 \
    BASH_ENV="" \
    "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/script/sign_and_notarize.sh" --dry-run dist/LithePG.app
) >"$output_file" 2>&1
startup_env_sanitizer_empty_bash_env_fail_closed_status=$?
set -e
startup_env_sanitizer_empty_bash_env_fail_closed_output="$(<"$output_file")"
if [[ "$startup_env_sanitizer_empty_bash_env_fail_closed_status" -ne 2 ]]; then
  printf '%s\n' "$startup_env_sanitizer_empty_bash_env_fail_closed_output" >&2
  fail "sign/notarize sanitizer marker with empty BASH_ENV should exit 2, got $startup_env_sanitizer_empty_bash_env_fail_closed_status"
fi
if [[ "$startup_env_sanitizer_empty_bash_env_fail_closed_output" != "unsanitized startup environment remains after sign_and_notarize sanitizer" ]]; then
  printf '%s\n' "$startup_env_sanitizer_empty_bash_env_fail_closed_output" >&2
  fail "sign/notarize empty BASH_ENV fail-closed output was not exactly generic and redacted"
fi
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "Usage: sign_and_notarize.sh"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "fake package verified:"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "Signing/notarization dry run OK"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "$codesign_sentinel"
assert_not_contains "$startup_env_sanitizer_empty_bash_env_fail_closed_output" "$notary_sentinel"
[[ ! -e "$startup_env_sanitizer_empty_bash_env_fail_closed_notary_zip" ]] || fail "sanitizer fail-closed dry run created notary zip: $startup_env_sanitizer_empty_bash_env_fail_closed_notary_zip"

# Perl startup environment alone must trigger sanitization before the helper's
# own /usr/bin/perl calls can observe PERL5OPT/PERL5LIB/PERLLIB.
perl_startup_shadow_sentinel="SIGN_AND_NOTARIZE_PERL_STARTUP_SHADOW_SENTINEL_DO_NOT_PRINT"
perl_startup_shadow_fixture="$fixture_root/perl-startup-shadow"
perl_startup_shadow_perl_lib="$perl_startup_shadow_fixture/perl-lib"
perl_startup_shadow_perl_marker="$perl_startup_shadow_fixture/perl-startup-invoked"
perl_startup_shadow_notary_zip="$perl_startup_shadow_fixture/dist/LithePG-notary.zip"
make_startup_hardening_fixture "$perl_startup_shadow_fixture"
mkdir -p "$perl_startup_shadow_perl_lib"
cat >"$perl_startup_shadow_perl_lib/SignAndNotarizePerlStartupPoison.pm" <<'PERLMOD'
package SignAndNotarizePerlStartupPoison;
BEGIN {
  my $sentinel = $ENV{SIGN_AND_NOTARIZE_PERL_STARTUP_SHADOW_SENTINEL} // '';
  my $marker = $ENV{SIGN_AND_NOTARIZE_PERL_STARTUP_MARKER} // '';
  if ($marker ne '' && open(my $fh, '>', $marker)) {
    print {$fh} "perl\n";
    close $fh;
  }
  print STDERR "$sentinel Perl startup invoked\n";
  exit 97;
}
1;
PERLMOD
set +e
(
  command cd "$perl_startup_shadow_fixture"
  unset BASH_ENV
  SIGN_AND_NOTARIZE_PERL_STARTUP_SHADOW_SENTINEL="$perl_startup_shadow_sentinel" \
    SIGN_AND_NOTARIZE_PERL_STARTUP_MARKER="$perl_startup_shadow_perl_marker" \
    PERL5LIB="$perl_startup_shadow_perl_lib" \
    PERLLIB="$perl_startup_shadow_perl_lib" \
    PERL5OPT=-MSignAndNotarizePerlStartupPoison \
    LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_NOTARY_ZIP="$perl_startup_shadow_notary_zip" \
    "$perl_startup_shadow_fixture/script/sign_and_notarize.sh" --dry-run dist/LithePG.app
) >"$output_file" 2>&1
perl_startup_shadow_status=$?
set -e
perl_startup_shadow_output="$(<"$output_file")"
if [[ "$perl_startup_shadow_status" -ne 0 ]]; then
  printf '%s\n' "$perl_startup_shadow_output" >&2
  fail "sign/notarize was affected by Perl-only startup environment shadowing"
fi
assert_contains "$perl_startup_shadow_output" "fake package verified: LithePG.app"
assert_contains "$perl_startup_shadow_output" "Signing/notarization dry run OK"
assert_contains "$perl_startup_shadow_output" "Codesign identity: present (redacted)"
assert_contains "$perl_startup_shadow_output" "Notary profile: present (redacted)"
assert_not_contains "$perl_startup_shadow_output" "$perl_startup_shadow_fixture"
assert_not_contains "$perl_startup_shadow_output" "$perl_startup_shadow_sentinel"
assert_not_contains "$perl_startup_shadow_output" "Perl startup invoked"
assert_not_contains "$perl_startup_shadow_output" "$codesign_sentinel"
assert_not_contains "$perl_startup_shadow_output" "$notary_sentinel"
[[ ! -e "$perl_startup_shadow_perl_marker" ]] || fail "sign/notarize honored Perl-only startup environment: $(<"$perl_startup_shadow_perl_marker")"
[[ ! -e "$perl_startup_shadow_notary_zip" ]] || fail "perl-startup dry run created notary zip: $perl_startup_shadow_notary_zip"

help_cat_path_shadow_sentinel="SIGN_AND_NOTARIZE_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN"
help_cat_path_shadow_fake_bin="$fixture_root/help-cat-path-shadow-fake-bin"
help_cat_path_shadow_marker="$fixture_root/help-cat-path-shadow-invoked"
mkdir -p "$help_cat_path_shadow_fake_bin"
cat >"$help_cat_path_shadow_fake_bin/cat" <<'SHIM'
#!/usr/bin/env bash
printf 'fake cat stdout sentinel=%s args=%s\n' "${HELP_CAT_PATH_SHADOW_SENTINEL:-}" "$*"
printf 'fake cat stderr sentinel=%s args=%s\n' "${HELP_CAT_PATH_SHADOW_SENTINEL:-}" "$*" >&2
printf 'cat\n' >"${HELP_CAT_PATH_SHADOW_MARKER:?}"
exit 73
SHIM
chmod +x "$help_cat_path_shadow_fake_bin/cat"

if ! PATH="$help_cat_path_shadow_fake_bin:$PATH" \
  HELP_CAT_PATH_SHADOW_SENTINEL="$help_cat_path_shadow_sentinel" \
  HELP_CAT_PATH_SHADOW_MARKER="$help_cat_path_shadow_marker" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$notary_zip" \
  run_helper_capture "$output_file" --help; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  [[ ! -e "$notary_zip" ]] || fail "--help with PATH-shadowed cat created notary zip before failing: $notary_zip"
  fail "--help invoked PATH-shadowed cat"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage: sign_and_notarize.sh [--dry-run] [app-bundle]"
assert_not_contains "$helper_output" "$help_cat_path_shadow_sentinel"
assert_not_contains "$helper_output" "fake cat"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$help_cat_path_shadow_marker" ]] || fail "--help invoked PATH-shadowed cat: $(<"$help_cat_path_shadow_marker")"
[[ ! -e "$notary_zip" ]] || fail "--help with PATH-shadowed cat created notary zip: $notary_zip"

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

relative_entitlements_outside_cwd="$fixture_root/outside-repo-cwd"
relative_entitlements_notary_zip="$fixture_root/LithePG-relative-entitlements-notary.zip"
mkdir -p "$relative_entitlements_outside_cwd"
set +e
(
  cd "$relative_entitlements_outside_cwd"
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_ENTITLEMENTS=Sources/LithePGApp/LithePGApp.entitlements \
    LITHEPG_NOTARY_ZIP="$relative_entitlements_notary_zip" \
    /bin/bash "$HELPER" --dry-run "$app_bundle"
) >"$output_file" 2>&1
relative_entitlements_status=$?
set -e
helper_output="$(<"$output_file")"
if [[ "$relative_entitlements_status" -ne 0 ]]; then
  printf '%s\n' "$helper_output" >&2
  fail "dry run failed with relative entitlements from outside repo"
fi
assert_contains "$helper_output" "Signing/notarization dry run OK"
assert_contains "$helper_output" "Entitlements: configured (redacted)"
assert_contains "$helper_output" "Codesign identity: present (redacted)"
assert_contains "$helper_output" "Notary profile: present (redacted)"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
assert_not_contains "$helper_output" "$ROOT_DIR/Sources/LithePGApp/LithePGApp.entitlements"
assert_not_contains "$helper_output" "$relative_entitlements_notary_zip"
[[ ! -e "$relative_entitlements_notary_zip" ]] || fail "dry run with relative entitlements created notary zip: $relative_entitlements_notary_zip"

# Exported shell functions named like root/chdir helpers, plus PATH-shadowed
# root-resolution utilities, must not affect repository-root setup or the repo
# cwd used for package verification.
root_chdir_shadow_sentinel="SIGN_AND_NOTARIZE_ROOT_CHDIR_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_chdir_shadow_command_sentinel="SIGN_AND_NOTARIZE_COMMAND_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_chdir_shadow_builtin_sentinel="SIGN_AND_NOTARIZE_BUILTIN_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_chdir_shadow_cd_sentinel="SIGN_AND_NOTARIZE_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_chdir_shadow_pwd_sentinel="SIGN_AND_NOTARIZE_PWD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_chdir_shadow_fixture="$fixture_root/root-chdir-shadow"
root_chdir_shadow_app_bundle="$root_chdir_shadow_fixture/LithePG.app"
root_chdir_shadow_notary_zip="$root_chdir_shadow_fixture/LithePG-notary.zip"
root_chdir_shadow_fake_bin="$root_chdir_shadow_fixture/fake-bin"
root_chdir_shadow_marker_dir="$root_chdir_shadow_fixture/markers"
mkdir -p "$root_chdir_shadow_fake_bin" "$root_chdir_shadow_marker_dir"
make_minimal_app_bundle "$root_chdir_shadow_app_bundle"
for tool in realpath dirname; do
  cat >"$root_chdir_shadow_fake_bin/$tool" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
printf '%s fake $tool stdout\\n' "\${ROOT_CHDIR_SHADOW_SENTINEL:?}"
printf '%s fake $tool stderr\\n' "\${ROOT_CHDIR_SHADOW_SENTINEL:?}" >&2
printf '$tool\\n' >"\${ROOT_CHDIR_SHADOW_MARKER_DIR:?}/$tool"
exit 97
SHIM
  chmod +x "$root_chdir_shadow_fake_bin/$tool"
done

set +e
(
  cd "$ROOT_DIR"
  command() {
    /usr/bin/printf '%s command invoked\n' "${ROOT_CHDIR_SHADOW_COMMAND_SENTINEL:?}" >&2
    /usr/bin/printf 'command\n' >"${ROOT_CHDIR_SHADOW_MARKER_DIR:?}/command"
    exit 97
  }
  builtin() {
    /usr/bin/printf '%s builtin invoked\n' "${ROOT_CHDIR_SHADOW_BUILTIN_SENTINEL:?}" >&2
    /usr/bin/printf 'builtin\n' >"${ROOT_CHDIR_SHADOW_MARKER_DIR:?}/builtin"
    exit 97
  }
  cd() {
    /usr/bin/printf '%s cd invoked\n' "${ROOT_CHDIR_SHADOW_CD_SENTINEL:?}" >&2
    /usr/bin/printf 'cd\n' >"${ROOT_CHDIR_SHADOW_MARKER_DIR:?}/cd"
    exit 97
  }
  pwd() {
    /usr/bin/printf '%s pwd invoked\n' "${ROOT_CHDIR_SHADOW_PWD_SENTINEL:?}" >&2
    /usr/bin/printf 'pwd\n' >"${ROOT_CHDIR_SHADOW_MARKER_DIR:?}/pwd"
    /usr/bin/printf '%s\n' "${ROOT_CHDIR_SHADOW_FAKE_PWD:?}"
  }
  export -f command
  export -f builtin
  export -f cd
  export -f pwd
  PATH="$root_chdir_shadow_fake_bin:$PATH" \
    ROOT_CHDIR_SHADOW_SENTINEL="$root_chdir_shadow_sentinel" \
    ROOT_CHDIR_SHADOW_MARKER_DIR="$root_chdir_shadow_marker_dir" \
    ROOT_CHDIR_SHADOW_FAKE_PWD="$fixture_root/root-chdir-wrong-root" \
    ROOT_CHDIR_SHADOW_COMMAND_SENTINEL="$root_chdir_shadow_command_sentinel" \
    ROOT_CHDIR_SHADOW_BUILTIN_SENTINEL="$root_chdir_shadow_builtin_sentinel" \
    ROOT_CHDIR_SHADOW_CD_SENTINEL="$root_chdir_shadow_cd_sentinel" \
    ROOT_CHDIR_SHADOW_PWD_SENTINEL="$root_chdir_shadow_pwd_sentinel" \
    LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
    LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
    LITHEPG_ENTITLEMENTS="$ROOT_DIR/Sources/LithePGApp/LithePGApp.entitlements" \
    LITHEPG_NOTARY_ZIP="$root_chdir_shadow_notary_zip" \
    /bin/bash "$HELPER" --dry-run "$root_chdir_shadow_app_bundle"
) >"$output_file" 2>&1
root_chdir_shadow_status=$?
set -e
root_chdir_shadow_output="$(<"$output_file")"
if [[ "$root_chdir_shadow_status" -ne 0 ]]; then
  printf '%s\n' "$root_chdir_shadow_output" >&2
  fail "dry run failed under root/chdir function-shadowing"
fi
assert_contains "$root_chdir_shadow_output" "Signing/notarization dry run OK"
assert_contains "$root_chdir_shadow_output" "Codesign identity: present (redacted)"
assert_contains "$root_chdir_shadow_output" "Notary profile: present (redacted)"
assert_not_contains "$root_chdir_shadow_output" "$root_chdir_shadow_sentinel"
assert_not_contains "$root_chdir_shadow_output" "$root_chdir_shadow_command_sentinel"
assert_not_contains "$root_chdir_shadow_output" "$root_chdir_shadow_builtin_sentinel"
assert_not_contains "$root_chdir_shadow_output" "$root_chdir_shadow_cd_sentinel"
assert_not_contains "$root_chdir_shadow_output" "$root_chdir_shadow_pwd_sentinel"
assert_not_contains "$root_chdir_shadow_output" "$codesign_sentinel"
assert_not_contains "$root_chdir_shadow_output" "$notary_sentinel"
for tool in realpath dirname command builtin cd pwd; do
  [[ ! -e "$root_chdir_shadow_marker_dir/$tool" ]] || fail "dry run invoked shadowed $tool during root/chdir setup"
done
[[ ! -e "$root_chdir_shadow_notary_zip" ]] || fail "dry run with root/chdir shadowing created notary zip: $root_chdir_shadow_notary_zip"

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

publication_tool_path_shadow_sentinel="SIGN_PUBLICATION_TOOL_PATH_SHADOW_SHOULD_NOT_LEAK"
publication_tool_path_shadow_parent="$fixture_root/$publication_tool_path_shadow_sentinel-parent"
publication_tool_path_shadow_app="$publication_tool_path_shadow_parent/LithePG.app"
publication_tool_path_shadow_zip="$publication_tool_path_shadow_parent/LithePG-notary.zip"
publication_tool_path_shadow_entitlements="$publication_tool_path_shadow_parent/invalid.entitlements"
publication_tool_path_shadow_fake_bin="$fixture_root/publication-tool-path-shadow-fake-bin"
publication_tool_path_shadow_marker="$fixture_root/publication-tool-path-shadow-invoked"
mkdir -p "$publication_tool_path_shadow_parent" "$publication_tool_path_shadow_fake_bin"
make_minimal_app_bundle "$publication_tool_path_shadow_app"
printf 'not an entitlements plist\n' >"$publication_tool_path_shadow_entitlements"
for publication_tool_path_shadow_tool in codesign ditto xcrun spctl; do
  cat >"$publication_tool_path_shadow_fake_bin/$publication_tool_path_shadow_tool" <<'SHIM'
#!/usr/bin/env bash
tool="${0##*/}"
printf 'fake %s stdout sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$tool" "${PUBLICATION_TOOL_PATH_SHADOW_SENTINEL:-}" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake %s stderr sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$tool" "${PUBLICATION_TOOL_PATH_SHADOW_SENTINEL:-}" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
printf '%s\n' "$tool" >>"${PUBLICATION_TOOL_PATH_SHADOW_MARKER:?}"
if [[ "$tool" == "ditto" ]]; then
  printf 'FAKE_NOTARY_ZIP_FROM_PUBLICATION_TOOL_PATH_SHADOW\n' >"${!#}"
fi
exit 0
SHIM
done
chmod +x "$publication_tool_path_shadow_fake_bin"/*

if PATH="$publication_tool_path_shadow_fake_bin:$PATH" \
  PUBLICATION_TOOL_PATH_SHADOW_SENTINEL="$publication_tool_path_shadow_sentinel" \
  PUBLICATION_TOOL_PATH_SHADOW_MARKER="$publication_tool_path_shadow_marker" \
  LITHEPG_CODESIGN_IDENTITY=- \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_ENTITLEMENTS="$publication_tool_path_shadow_entitlements" \
  LITHEPG_NOTARY_ZIP="$publication_tool_path_shadow_zip" \
  run_helper_capture "$output_file" "$publication_tool_path_shadow_app"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly passed with PATH-shadowed publication tools"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "codesign failed"
assert_not_contains "$helper_output" "$publication_tool_path_shadow_sentinel"
assert_not_contains "$helper_output" "fake codesign"
assert_not_contains "$helper_output" "fake ditto"
assert_not_contains "$helper_output" "fake xcrun"
assert_not_contains "$helper_output" "fake spctl"
assert_not_contains "$helper_output" "$publication_tool_path_shadow_parent"
assert_not_contains "$helper_output" "$publication_tool_path_shadow_zip"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$publication_tool_path_shadow_marker" ]] || fail "PATH-shadowed publication tool was invoked: $(<"$publication_tool_path_shadow_marker")"
[[ ! -e "$publication_tool_path_shadow_zip" ]] || fail "real mode created notary zip through PATH-shadowed publication tools"

path_shadow_core_sentinel="SIGN_PATH_SHADOWED_CORE_UTILITY_SHOULD_NOT_LEAK"
path_shadow_core_parent="$fixture_root/$path_shadow_core_sentinel-parent"
path_shadow_core_zip="$path_shadow_core_parent/LithePG-notary.zip"
path_shadow_core_fake_bin="$fixture_root/path-shadow-core-fake-bin"
path_shadow_core_marker="$fixture_root/path-shadow-core-utility-invoked"
mkdir -p "$path_shadow_core_parent" "$path_shadow_core_fake_bin"
for path_shadow_core_utility in basename dirname mktemp chmod rm; do
  cat >"$path_shadow_core_fake_bin/$path_shadow_core_utility" <<'SHIM'
#!/usr/bin/env bash
utility="${0##*/}"
printf 'fake %s stdout sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$utility" "${PATH_SHADOW_CORE_SENTINEL:-}" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}"
printf 'fake %s stderr sentinel=%s args=%s identity=%s profile=%s zip=%s\n' \
  "$utility" "${PATH_SHADOW_CORE_SENTINEL:-}" "$*" "${LITHEPG_CODESIGN_IDENTITY:-}" "${LITHEPG_NOTARY_PROFILE:-}" "${LITHEPG_NOTARY_ZIP:-}" >&2
printf '%s\n' "$utility" >>"${PATH_SHADOW_CORE_MARKER:?}"
exit 71
SHIM
done
cat >"$path_shadow_core_fake_bin/codesign" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat >"$path_shadow_core_fake_bin/ditto" <<'SHIM'
#!/usr/bin/env bash
dest="${!#}"
printf 'FAKE_NOTARY_ZIP_FROM_PATH_SHADOW_TEST\n' >"$dest"
exit 0
SHIM
cat >"$path_shadow_core_fake_bin/xcrun" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat >"$path_shadow_core_fake_bin/spctl" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
chmod +x "$path_shadow_core_fake_bin"/*

if PATH="$path_shadow_core_fake_bin:$PATH" \
  PATH_SHADOW_CORE_SENTINEL="$path_shadow_core_sentinel" \
  PATH_SHADOW_CORE_MARKER="$path_shadow_core_marker" \
  LITHEPG_CODESIGN_IDENTITY="$codesign_sentinel" \
  LITHEPG_NOTARY_PROFILE="$notary_sentinel" \
  LITHEPG_NOTARY_ZIP="$path_shadow_core_zip" \
  run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "real mode unexpectedly passed with PATH-shadowed core utilities"
fi

helper_output="$(<"$output_file")"
assert_contains "$helper_output" "codesign failed"
assert_not_contains "$helper_output" "$path_shadow_core_sentinel"
assert_not_contains "$helper_output" "fake basename"
assert_not_contains "$helper_output" "fake dirname"
assert_not_contains "$helper_output" "fake mktemp"
assert_not_contains "$helper_output" "fake chmod"
assert_not_contains "$helper_output" "fake rm"
assert_not_contains "$helper_output" "$path_shadow_core_parent"
assert_not_contains "$helper_output" "$path_shadow_core_zip"
assert_not_contains "$helper_output" "$codesign_sentinel"
assert_not_contains "$helper_output" "$notary_sentinel"
[[ ! -e "$path_shadow_core_marker" ]] || fail "PATH-shadowed core utility was invoked: $(<"$path_shadow_core_marker")"
[[ ! -e "$path_shadow_core_zip" ]] || fail "real mode with PATH-shadowed core utilities created notary zip"

printf '%s\n' "$existing_notary_zip_marker" >"$notary_zip"
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
