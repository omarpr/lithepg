#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/build_and_run.sh"
VERIFY_HELPER="$ROOT_DIR/script/package_verify.sh"

fail() {
  /usr/bin/printf 'test_build_and_run failed: %s\n' "$1" >&2
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

assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "$actual" == "$expected" ]] || fail "expected <$expected>, got <$actual>"
}

run_package_capture() {
  local output_file="$1"
  local fake_bin="$2"
  local fake_swift_bin_dir="$3"
  local fake_swift_marker="$4"
  set +e
  (
    cd "$ROOT_DIR"
    unset LITHEPG_NOTARY_PROFILE
    PATH="$fake_bin:$PATH" \
      FAKE_SWIFT_BIN_DIR="$fake_swift_bin_dir" \
      FAKE_SWIFT_MARKER="$fake_swift_marker" \
      LITHEPG_CODESIGN_IDENTITY="-" \
      LITHEPG_MARKETING_VERSION="1.0.0" \
      LITHEPG_BUILD_VERSION="100" \
      /bin/bash "$HELPER" --package
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"
[[ -f "$VERIFY_HELPER" ]] || fail "package verifier missing: $VERIFY_HELPER"
helper_contents="$(<"$HELPER")"
assert_contains "$helper_contents" '--scratch-path "$RELEASE_SCRATCH_DIR"'
assert_contains "$helper_contents" '/private/tmp/lithepg-release-build.XXXXXX'

output_file="$(/usr/bin/mktemp)"
verify_output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file" "$verify_output_file"; /bin/rm -rf "$fixture_root"' EXIT

help_sentinel="BUILD_AND_RUN_HELP_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
help_fake_bin="$fixture_root/help-fake-bin"
help_marker="$fixture_root/help-path-shadow-invoked"
/bin/mkdir -p "$help_fake_bin"
for tool in cat git pkill swift; do
  /bin/cat >"$help_fake_bin/$tool" <<SHIM
#!/bin/bash
/usr/bin/printf '%s %s invoked\\n' '$help_sentinel' '$tool' >&2
/usr/bin/printf '%s\\n' '$tool' >>'$help_marker'
exit 97
SHIM
  /bin/chmod +x "$help_fake_bin/$tool"
done

set +e
(
  cd "$ROOT_DIR"
  PATH="$help_fake_bin:$PATH" /bin/bash "$HELPER" --help
) >"$output_file" 2>&1
help_status=$?
set -e
help_output="$(<"$output_file")"
if [[ "$help_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$help_output" >&2
  fail "build_and_run --help did not exit 0 under PATH-shadowed tools"
fi
assert_contains "$help_output" "usage: script/build_and_run.sh"
assert_contains "$help_output" "--package"
assert_not_contains "$help_output" "$help_sentinel"
[[ ! -e "$help_marker" ]] || fail "build_and_run --help invoked PATH-shadowed tools: $(<"$help_marker")"

set +e
(
  cd "$ROOT_DIR"
  LITHEPG_BUILD_AND_RUN_PKILL="relative-pkill" /bin/bash "$HELPER" --help
) >"$output_file" 2>&1
relative_pkill_status=$?
set -e
relative_pkill_output="$(<"$output_file")"
assert_equals "$relative_pkill_status" "2"
assert_contains "$relative_pkill_output" "LITHEPG_BUILD_AND_RUN_PKILL must be an absolute path: relative-pkill"

root_shadow_sentinel="BUILD_AND_RUN_ROOT_REALPATH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_shadow_command_sentinel="BUILD_AND_RUN_ROOT_COMMAND_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_shadow_builtin_sentinel="BUILD_AND_RUN_ROOT_BUILTIN_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_shadow_cd_sentinel="BUILD_AND_RUN_ROOT_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_shadow_pwd_sentinel="BUILD_AND_RUN_ROOT_PWD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
root_shadow_fake_bin="$fixture_root/root-shadow-fake-bin"
root_shadow_swift_bin_dir="$fixture_root/root-shadow-swift-bin"
root_shadow_swift_marker="$fixture_root/root-shadow-fake-swift-used"
root_shadow_marker_dir="$fixture_root/root-shadow-markers"
root_shadow_safe_pkill="$fixture_root/root-shadow-safe-pkill"
root_shadow_safe_pkill_marker="$fixture_root/root-shadow-safe-pkill-invoked"
/bin/mkdir -p "$root_shadow_fake_bin" "$root_shadow_swift_bin_dir" "$root_shadow_marker_dir"

/bin/cat >"$root_shadow_fake_bin/realpath" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s realpath invoked\\n' '$root_shadow_sentinel' >&2
/usr/bin/printf 'realpath\\n' >'$root_shadow_marker_dir/realpath'
exit 97
SHIM
/bin/chmod +x "$root_shadow_fake_bin/realpath"

/bin/cat >"$root_shadow_fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake root-shadow swift used\n' >"${FAKE_SWIFT_MARKER:?}"
case "$*" in
  "build --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  "build --show-bin-path")
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BIN_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake root-shadow swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$root_shadow_fake_bin/swift"

/bin/cat >"$root_shadow_safe_pkill" <<SHIM
#!/bin/bash
set -euo pipefail
[[ "\$#" -eq 2 && "\$1" == "-x" && "\$2" == "LithePGApp" ]]
/usr/bin/printf 'safe pkill -x LithePGApp\\n' >'$root_shadow_safe_pkill_marker'
exit 0
SHIM
/bin/chmod +x "$root_shadow_safe_pkill"

set +e
(
  cd "$ROOT_DIR"
  command() {
    /usr/bin/printf '%s command invoked\n' "${ROOT_SHADOW_COMMAND_SENTINEL:?}" >&2
    /usr/bin/printf 'command\n' >"${ROOT_SHADOW_MARKER_DIR:?}/command"
    exit 97
  }
  builtin() {
    /usr/bin/printf '%s builtin invoked\n' "${ROOT_SHADOW_BUILTIN_SENTINEL:?}" >&2
    /usr/bin/printf 'builtin\n' >"${ROOT_SHADOW_MARKER_DIR:?}/builtin"
    exit 97
  }
  cd() {
    /usr/bin/printf '%s cd invoked\n' "${ROOT_SHADOW_CD_SENTINEL:?}" >&2
    /usr/bin/printf 'cd\n' >"${ROOT_SHADOW_MARKER_DIR:?}/cd"
    exit 97
  }
  pwd() {
    /usr/bin/printf '%s pwd invoked\n' "${ROOT_SHADOW_PWD_SENTINEL:?}" >&2
    /usr/bin/printf 'pwd\n' >"${ROOT_SHADOW_MARKER_DIR:?}/pwd"
    /usr/bin/printf '%s\n' "${ROOT_SHADOW_FAKE_PWD:?}"
  }
  export -f command
  export -f builtin
  export -f cd
  export -f pwd
  PATH="$root_shadow_fake_bin:$PATH" \
    FAKE_SWIFT_BIN_DIR="$root_shadow_swift_bin_dir" \
    FAKE_SWIFT_MARKER="$root_shadow_swift_marker" \
    LITHEPG_BUILD_AND_RUN_PKILL="$root_shadow_safe_pkill" \
    LITHEPG_MARKETING_VERSION="1.0.0" \
    LITHEPG_BUILD_VERSION="100" \
    ROOT_SHADOW_MARKER_DIR="$root_shadow_marker_dir" \
    ROOT_SHADOW_FAKE_PWD="$fixture_root/root-shadow-wrong-root" \
    ROOT_SHADOW_COMMAND_SENTINEL="$root_shadow_command_sentinel" \
    ROOT_SHADOW_BUILTIN_SENTINEL="$root_shadow_builtin_sentinel" \
    ROOT_SHADOW_CD_SENTINEL="$root_shadow_cd_sentinel" \
    ROOT_SHADOW_PWD_SENTINEL="$root_shadow_pwd_sentinel" \
    /bin/bash "$HELPER" --print-bundle-path
) >"$output_file" 2>&1
root_shadow_status=$?
set -e
root_shadow_output="$(<"$output_file")"
if [[ "$root_shadow_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$root_shadow_output" >&2
  fail "build_and_run root resolution was affected by function- or PATH-shadowed tools"
fi
[[ -f "$root_shadow_swift_marker" ]] || fail "fake root-shadow swift was not used"
assert_contains "$root_shadow_output" "$ROOT_DIR/dist/LithePG.app"
assert_not_contains "$root_shadow_output" "$root_shadow_sentinel"
assert_not_contains "$root_shadow_output" "$root_shadow_command_sentinel"
assert_not_contains "$root_shadow_output" "$root_shadow_builtin_sentinel"
assert_not_contains "$root_shadow_output" "$root_shadow_cd_sentinel"
assert_not_contains "$root_shadow_output" "$root_shadow_pwd_sentinel"
for tool in realpath command builtin cd pwd; do
  [[ ! -e "$root_shadow_marker_dir/$tool" ]] || fail "build_and_run root resolution invoked shadowed $tool"
done
[[ -f "$root_shadow_safe_pkill_marker" ]] || fail "build_and_run root-shadow fixture did not invoke safe pkill override"
assert_equals "$(<"$root_shadow_safe_pkill_marker")" "safe pkill -x LithePGApp"

root_shadow_icon="$ROOT_DIR/dist/LithePG.app/Contents/Resources/AppIcon.icns"
[[ -f "$root_shadow_icon" && ! -L "$root_shadow_icon" ]] || fail "build_and_run did not install Contents/Resources/AppIcon.icns"
assert_equals "$(/usr/bin/stat -f%Lp "$root_shadow_icon")" "644"
root_shadow_plist="$(<"$ROOT_DIR/dist/LithePG.app/Contents/Info.plist")"
assert_contains "$root_shadow_plist" "CFBundleIconFile"
assert_contains "$root_shadow_plist" "<string>AppIcon</string>"

startup_helper_repo="$fixture_root/startup-helper-repo"
startup_helper="$startup_helper_repo/script/build_and_run.sh"
startup_fake_bin="$fixture_root/startup-fake-bin"
startup_fake_bash_marker="$fixture_root/startup-fake-bash-invoked"
startup_fake_bash_sentinel="BUILD_AND_RUN_INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
/bin/mkdir -p "$startup_helper_repo/script" "$startup_fake_bin"
/bin/cp "$HELPER" "$startup_helper"
/bin/chmod +x "$startup_helper"
/bin/mkdir -p "$startup_helper_repo/packaging"
/bin/cp "$ROOT_DIR/packaging/AppIcon.icns" "$startup_helper_repo/packaging/AppIcon.icns"
/bin/cat >"$startup_fake_bin/bash" <<SHIM
#!/bin/bash
/usr/bin/printf '%s fake bash invoked\\n' '$startup_fake_bash_sentinel' >&2
/usr/bin/printf 'fake-bash\\n' >'$startup_fake_bash_marker'
exit 97
SHIM
/bin/chmod +x "$startup_fake_bin/bash"

set +e
(
  PATH="$startup_fake_bin:$PATH" "$startup_helper" --help
) >"$output_file" 2>&1
startup_fake_bash_status=$?
set -e
startup_fake_bash_output="$(<"$output_file")"
if [[ "$startup_fake_bash_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_fake_bash_output" >&2
  fail "build_and_run executable invocation used PATH-selected bash"
fi
assert_contains "$startup_fake_bash_output" "usage: script/build_and_run.sh"
assert_not_contains "$startup_fake_bash_output" "$startup_fake_bash_sentinel"
[[ ! -e "$startup_fake_bash_marker" ]] || fail "build_and_run executable invocation used fake PATH bash: $(<"$startup_fake_bash_marker")"

startup_env_shadow_sentinel="BUILD_AND_RUN_STARTUP_ENV_SHADOW_SENTINEL_SHOULD_NOT_RUN"
startup_env_bash_file="$fixture_root/build-and-run-bash-env"
startup_env_bash_marker="$fixture_root/build-and-run-bash-env-marker"
startup_env_export_marker="$fixture_root/build-and-run-exported-set-marker"
/bin/cat >"$startup_env_bash_file" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${BUILD_AND_RUN_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${BUILD_AND_RUN_STARTUP_ENV_BASH_MARKER:?}"
  exit 97
}
BASHENV

set +e
(
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${BUILD_AND_RUN_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${BUILD_AND_RUN_STARTUP_ENV_EXPORT_MARKER:?}"
    exit 97
  }
  export -f set
  BUILD_AND_RUN_STARTUP_ENV_SHADOW_SENTINEL="$startup_env_shadow_sentinel" \
    BUILD_AND_RUN_STARTUP_ENV_BASH_MARKER="$startup_env_bash_marker" \
    BUILD_AND_RUN_STARTUP_ENV_EXPORT_MARKER="$startup_env_export_marker" \
    BASH_ENV="$startup_env_bash_file" \
    "$startup_helper" --help
) >"$output_file" 2>&1
startup_env_shadow_status=$?
set -e
startup_env_shadow_output="$(<"$output_file")"
if [[ "$startup_env_shadow_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_env_shadow_output" >&2
  fail "build_and_run executable startup was affected by BASH_ENV or exported shell functions"
fi
assert_contains "$startup_env_shadow_output" "usage: script/build_and_run.sh"
assert_not_contains "$startup_env_shadow_output" "$startup_env_shadow_sentinel"
assert_not_contains "$startup_env_shadow_output" "set function invoked"
[[ ! -e "$startup_env_bash_marker" ]] || fail "build_and_run invoked BASH_ENV-defined set function: $(<"$startup_env_bash_marker")"
[[ ! -e "$startup_env_export_marker" ]] || fail "build_and_run invoked exported set function: $(<"$startup_env_export_marker")"

set +e
(
  LITHEPG_BUILD_AND_RUN_STARTUP_ENV_SANITIZED=1 \
    PERL5OPT=-MBuildAndRunSanitizerShouldFailClosed \
    "$startup_helper" --help
) >"$output_file" 2>&1
startup_fail_closed_status=$?
set -e
startup_fail_closed_output="$(<"$output_file")"
if [[ "$startup_fail_closed_status" -eq 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_fail_closed_output" >&2
  fail "build_and_run startup sanitizer did not fail closed when sanitized marker still had dirty env"
fi
assert_contains "$startup_fail_closed_output" "unsanitized startup environment remains after build_and_run sanitizer"
assert_not_contains "$startup_fail_closed_output" "usage: script/build_and_run.sh"

# If the sanitizer marker is already set, even an empty-but-present BASH_ENV is dirty.
startup_empty_bash_env_private="BUILD_AND_RUN_EMPTY_BASH_ENV_PRIVATE_SENTINEL_SHOULD_NOT_LEAK"
set +e
(
  LITHEPG_BUILD_AND_RUN_STARTUP_ENV_SANITIZED=1 \
    BUILD_AND_RUN_EMPTY_BASH_ENV_PRIVATE="$startup_empty_bash_env_private" \
    BASH_ENV="" \
    "$startup_helper" --help
) >"$output_file" 2>&1
startup_empty_bash_env_fail_closed_status=$?
set -e
startup_empty_bash_env_fail_closed_output="$(<"$output_file")"
if [[ "$startup_empty_bash_env_fail_closed_status" -ne 2 ]]; then
  /usr/bin/printf '%s\n' "$startup_empty_bash_env_fail_closed_output" >&2
  fail "build_and_run startup sanitizer did not fail closed with exit 2 for empty BASH_ENV after sanitizer marker"
fi
assert_contains "$startup_empty_bash_env_fail_closed_output" "unsanitized startup environment remains after build_and_run sanitizer"
assert_not_contains "$startup_empty_bash_env_fail_closed_output" "usage: script/build_and_run.sh"
assert_not_contains "$startup_empty_bash_env_fail_closed_output" "$startup_empty_bash_env_private"

startup_perl_sentinel="BUILD_AND_RUN_PERL_STARTUP_SHADOW_SENTINEL_SHOULD_NOT_RUN"
startup_perl_lib="$fixture_root/build-and-run-perl-lib"
startup_perl_marker="$fixture_root/build-and-run-perl-marker"
startup_perl_fake_bin="$fixture_root/build-and-run-perl-fake-bin"
startup_perl_swift_bin_dir="$fixture_root/build-and-run-perl-swift-bin"
startup_perl_swift_marker="$fixture_root/build-and-run-perl-swift-used"
startup_perl_safe_pkill="$fixture_root/build-and-run-perl-safe-pkill"
/bin/mkdir -p "$startup_perl_lib" "$startup_perl_fake_bin" "$startup_perl_swift_bin_dir"
/bin/cat >"$startup_perl_lib/BuildAndRunPerlStartupPoison.pm" <<'PERLPOISON'
BEGIN {
  open my $fh, '>', $ENV{BUILD_AND_RUN_PERL_STARTUP_MARKER} or die $!;
  print {$fh} "perl-startup\n";
  close $fh;
  die "$ENV{BUILD_AND_RUN_PERL_STARTUP_SHADOW_SENTINEL} Perl startup invoked\n";
}
1;
PERLPOISON
/bin/cat >"$startup_perl_fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake startup-perl swift used\n' >"${FAKE_SWIFT_MARKER:?}"
case "$*" in
  "build --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  "build --show-bin-path")
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BIN_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake startup-perl swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$startup_perl_fake_bin/swift"
/bin/cat >"$startup_perl_safe_pkill" <<'SHIM'
#!/bin/bash
exit 0
SHIM
/bin/chmod +x "$startup_perl_safe_pkill"

set +e
(
  PATH="$startup_perl_fake_bin:$PATH" \
    FAKE_SWIFT_BIN_DIR="$startup_perl_swift_bin_dir" \
    FAKE_SWIFT_MARKER="$startup_perl_swift_marker" \
    LITHEPG_BUILD_AND_RUN_PKILL="$startup_perl_safe_pkill" \
    LITHEPG_MARKETING_VERSION="1.0.0" \
    LITHEPG_BUILD_VERSION="100" \
    BUILD_AND_RUN_PERL_STARTUP_MARKER="$startup_perl_marker" \
    BUILD_AND_RUN_PERL_STARTUP_SHADOW_SENTINEL="$startup_perl_sentinel" \
    PERL5LIB="$startup_perl_lib" \
    PERLLIB="$startup_perl_lib" \
    PERL5OPT=-MBuildAndRunPerlStartupPoison \
    "$startup_helper" --print-bundle-path
) >"$output_file" 2>&1
startup_perl_status=$?
set -e
startup_perl_output="$(<"$output_file")"
if [[ "$startup_perl_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_perl_output" >&2
  fail "build_and_run executable startup left Perl startup environment unsanitized"
fi
[[ -f "$startup_perl_swift_marker" ]] || fail "fake startup-perl swift was not used"
assert_contains "$startup_perl_output" "$startup_helper_repo/dist/LithePG.app"
assert_not_contains "$startup_perl_output" "$startup_perl_sentinel"
assert_not_contains "$startup_perl_output" "Perl startup invoked"
[[ ! -e "$startup_perl_marker" ]] || fail "build_and_run invoked Perl startup env: $(<"$startup_perl_marker")"
[[ -f "$startup_helper_repo/dist/LithePG.app/Contents/Resources/AppIcon.icns" ]] || fail "build_and_run did not install AppIcon.icns in the fixture bundle"

icon_missing_repo="$fixture_root/icon-missing-repo"
icon_missing_helper="$icon_missing_repo/script/build_and_run.sh"
icon_missing_fake_bin="$fixture_root/icon-missing-fake-bin"
icon_missing_swift_bin_dir="$fixture_root/icon-missing-swift-bin"
icon_missing_swift_marker="$fixture_root/icon-missing-fake-swift-used"
icon_missing_safe_pkill="$fixture_root/icon-missing-safe-pkill"
/bin/mkdir -p "$icon_missing_repo/script" "$icon_missing_fake_bin" "$icon_missing_swift_bin_dir"
/bin/cp "$HELPER" "$icon_missing_helper"
/bin/chmod +x "$icon_missing_helper"
/bin/cat >"$icon_missing_fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake icon-missing swift used\n' >"${FAKE_SWIFT_MARKER:?}"
case "$*" in
  "build --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  "build --show-bin-path")
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BIN_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake icon-missing swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$icon_missing_fake_bin/swift"
/bin/cat >"$icon_missing_safe_pkill" <<'SHIM'
#!/bin/bash
exit 0
SHIM
/bin/chmod +x "$icon_missing_safe_pkill"

set +e
(
  PATH="$icon_missing_fake_bin:$PATH" \
    FAKE_SWIFT_BIN_DIR="$icon_missing_swift_bin_dir" \
    FAKE_SWIFT_MARKER="$icon_missing_swift_marker" \
    LITHEPG_BUILD_AND_RUN_PKILL="$icon_missing_safe_pkill" \
    LITHEPG_MARKETING_VERSION="1.0.0" \
    LITHEPG_BUILD_VERSION="100" \
    "$icon_missing_helper" --print-bundle-path
) >"$output_file" 2>&1
icon_missing_status=$?
set -e
icon_missing_output="$(<"$output_file")"
if [[ "$icon_missing_status" -eq 0 ]]; then
  /usr/bin/printf '%s\n' "$icon_missing_output" >&2
  fail "build_and_run unexpectedly succeeded without packaging/AppIcon.icns"
fi
assert_contains "$icon_missing_output" "build_and_run failed: app icon asset missing"

print_bundle_sentinel="BUILD_AND_RUN_FAKE_PKILL_SENTINEL_SHOULD_NOT_RUN"
print_bundle_fake_bin="$fixture_root/print-bundle-fake-bin"
print_bundle_swift_bin_dir="$fixture_root/print-bundle-swift-bin"
print_bundle_swift_marker="$fixture_root/print-bundle-fake-swift-used"
print_bundle_path_pkill_marker="$fixture_root/print-bundle-path-fake-pkill-invoked"
print_bundle_safe_pkill="$fixture_root/print-bundle-safe-pkill"
print_bundle_safe_pkill_marker="$fixture_root/print-bundle-safe-pkill-invoked"
/bin/mkdir -p "$print_bundle_fake_bin" "$print_bundle_swift_bin_dir"

/bin/cat >"$print_bundle_fake_bin/pkill" <<SHIM
#!/bin/bash
/usr/bin/printf '%s pkill invoked\\n' '$print_bundle_sentinel' >&2
/usr/bin/printf 'pkill %s\\n' "\$*" >'$print_bundle_path_pkill_marker'
exit 0
SHIM
/bin/chmod +x "$print_bundle_fake_bin/pkill"

/bin/cat >"$print_bundle_safe_pkill" <<SHIM
#!/bin/bash
set -euo pipefail
[[ "\$#" -eq 2 && "\$1" == "-x" && "\$2" == "LithePGApp" ]]
/usr/bin/printf 'safe pkill -x LithePGApp\\n' >'$print_bundle_safe_pkill_marker'
exit 0
SHIM
/bin/chmod +x "$print_bundle_safe_pkill"

/bin/cat >"$print_bundle_fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake debug swift used\n' >"${FAKE_SWIFT_MARKER:?}"
case "$*" in
  "build --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  "build --show-bin-path")
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BIN_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake debug swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$print_bundle_fake_bin/swift"

set +e
(
  cd "$ROOT_DIR"
  PATH="$print_bundle_fake_bin:$PATH" \
    FAKE_SWIFT_BIN_DIR="$print_bundle_swift_bin_dir" \
    FAKE_SWIFT_MARKER="$print_bundle_swift_marker" \
    LITHEPG_BUILD_AND_RUN_PKILL="$print_bundle_safe_pkill" \
    LITHEPG_MARKETING_VERSION="1.0.0" \
    LITHEPG_BUILD_VERSION="100" \
    /bin/bash "$HELPER" --print-bundle-path
) >"$output_file" 2>&1
print_bundle_status=$?
set -e
print_bundle_output="$(<"$output_file")"
if [[ "$print_bundle_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$print_bundle_output" >&2
  fail "build_and_run --print-bundle-path failed under fake swift"
fi
[[ -f "$print_bundle_swift_marker" ]] || fail "fake debug swift was not used"
assert_contains "$print_bundle_output" "$ROOT_DIR/dist/LithePG.app"
assert_not_contains "$print_bundle_output" "$print_bundle_sentinel"
[[ ! -e "$print_bundle_path_pkill_marker" ]] || fail "build_and_run --print-bundle-path invoked PATH-shadowed pkill: $(<"$print_bundle_path_pkill_marker")"
[[ -f "$print_bundle_safe_pkill_marker" ]] || fail "build_and_run --print-bundle-path did not invoke safe pkill override"
assert_equals "$(<"$print_bundle_safe_pkill_marker")" "safe pkill -x LithePGApp"

verify_sentinel="BUILD_AND_RUN_VERIFY_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
verify_fake_bin="$fixture_root/verify-fake-bin"
verify_swift_bin_dir="$fixture_root/verify-swift-bin"
verify_swift_marker="$fixture_root/verify-fake-swift-used"
verify_path_open_marker="$fixture_root/verify-path-open-invoked"
verify_path_sleep_marker="$fixture_root/verify-path-sleep-invoked"
verify_path_pgrep_marker="$fixture_root/verify-path-pgrep-invoked"
verify_safe_pkill="$fixture_root/verify-safe-pkill"
verify_safe_pkill_marker="$fixture_root/verify-safe-pkill-invoked"
verify_safe_sleep="$fixture_root/verify-safe-sleep"
verify_safe_sleep_marker="$fixture_root/verify-safe-sleep-invoked"
verify_safe_pgrep="$fixture_root/verify-safe-pgrep"
verify_safe_pgrep_marker="$fixture_root/verify-safe-pgrep-invoked"
verify_safe_open="$fixture_root/verify-safe-open"
verify_safe_open_marker="$fixture_root/verify-safe-open-invoked"
/bin/mkdir -p "$verify_fake_bin" "$verify_swift_bin_dir"

/bin/cat >"$verify_fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake verify swift used\n' >"${FAKE_SWIFT_MARKER:?}"
case "$*" in
  "build --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  "build --show-bin-path")
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BIN_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake verify swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$verify_fake_bin/swift"

/bin/cat >"$verify_fake_bin/open" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s open invoked\\n' '$verify_sentinel' >&2
/usr/bin/printf 'path open %s\\n' "\$*" >'$verify_path_open_marker'
exit 97
SHIM
/bin/chmod +x "$verify_fake_bin/open"

/bin/cat >"$verify_fake_bin/sleep" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s sleep invoked\\n' '$verify_sentinel' >&2
/usr/bin/printf 'path sleep %s\\n' "\$*" >'$verify_path_sleep_marker'
exit 97
SHIM
/bin/chmod +x "$verify_fake_bin/sleep"

/bin/cat >"$verify_fake_bin/pgrep" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s pgrep invoked\\n' '$verify_sentinel' >&2
/usr/bin/printf 'path pgrep %s\\n' "\$*" >'$verify_path_pgrep_marker'
exit 97
SHIM
/bin/chmod +x "$verify_fake_bin/pgrep"

/bin/cat >"$verify_safe_pkill" <<SHIM
#!/bin/bash
set -euo pipefail
[[ "\$#" -eq 2 && "\$1" == "-x" && "\$2" == "LithePGApp" ]]
/usr/bin/printf 'safe pkill -x LithePGApp\\n' >'$verify_safe_pkill_marker'
exit 0
SHIM
/bin/chmod +x "$verify_safe_pkill"

/bin/cat >"$verify_safe_sleep" <<SHIM
#!/bin/bash
set -euo pipefail
[[ "\$#" -eq 1 && "\$1" == "1" ]]
/usr/bin/printf 'safe sleep 1\\n' >'$verify_safe_sleep_marker'
exit 0
SHIM
/bin/chmod +x "$verify_safe_sleep"

/bin/cat >"$verify_safe_pgrep" <<SHIM
#!/bin/bash
set -euo pipefail
[[ "\$#" -eq 2 && "\$1" == "-x" && "\$2" == "LithePGApp" ]]
/usr/bin/printf 'safe pgrep -x LithePGApp\\n' >'$verify_safe_pgrep_marker'
exit 0
SHIM
/bin/chmod +x "$verify_safe_pgrep"

/bin/cat >"$verify_safe_open" <<SHIM
#!/bin/bash
set -euo pipefail
[[ "\$#" -eq 2 && "\$1" == "-n" && "\$2" == "$ROOT_DIR/dist/LithePG.app" ]]
/usr/bin/printf 'safe open -n $ROOT_DIR/dist/LithePG.app\\n' >'$verify_safe_open_marker'
exit 0
SHIM
/bin/chmod +x "$verify_safe_open"

set +e
(
  cd "$ROOT_DIR"
  PATH="$verify_fake_bin:$PATH" \
    FAKE_SWIFT_BIN_DIR="$verify_swift_bin_dir" \
    FAKE_SWIFT_MARKER="$verify_swift_marker" \
    LITHEPG_BUILD_AND_RUN_PKILL="$verify_safe_pkill" \
    LITHEPG_BUILD_AND_RUN_SLEEP="$verify_safe_sleep" \
    LITHEPG_BUILD_AND_RUN_PGREP="$verify_safe_pgrep" \
    LITHEPG_BUILD_AND_RUN_OPEN="$verify_safe_open" \
    LITHEPG_MARKETING_VERSION="1.0.0" \
    LITHEPG_BUILD_VERSION="100" \
    /bin/bash "$HELPER" --verify
) >"$output_file" 2>&1
verify_status=$?
set -e
verify_output="$(<"$output_file")"
if [[ "$verify_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$verify_output" >&2
  fail "build_and_run --verify failed under PATH-shadowed sleep/pgrep"
fi
[[ -f "$verify_swift_marker" ]] || fail "fake verify swift was not used"
assert_not_contains "$verify_output" "$verify_sentinel"
[[ ! -e "$verify_path_open_marker" ]] || fail "build_and_run --verify invoked PATH-shadowed open: $(<"$verify_path_open_marker")"
[[ ! -e "$verify_path_sleep_marker" ]] || fail "build_and_run --verify invoked PATH-shadowed sleep: $(<"$verify_path_sleep_marker")"
[[ ! -e "$verify_path_pgrep_marker" ]] || fail "build_and_run --verify invoked PATH-shadowed pgrep: $(<"$verify_path_pgrep_marker")"
[[ -f "$verify_safe_pkill_marker" ]] || fail "build_and_run --verify did not invoke safe pkill override"
[[ -f "$verify_safe_sleep_marker" ]] || fail "build_and_run --verify did not invoke safe sleep override"
[[ -f "$verify_safe_pgrep_marker" ]] || fail "build_and_run --verify did not invoke safe pgrep override"
[[ -f "$verify_safe_open_marker" ]] || fail "build_and_run --verify did not invoke safe open override"
assert_equals "$(<"$verify_safe_pkill_marker")" "safe pkill -x LithePGApp"
assert_equals "$(<"$verify_safe_sleep_marker")" "safe sleep 1"
assert_equals "$(<"$verify_safe_pgrep_marker")" "safe pgrep -x LithePGApp"
assert_equals "$(<"$verify_safe_open_marker")" "safe open -n $ROOT_DIR/dist/LithePG.app"

sentinel="BUILD_AND_RUN_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_swift_bin_dir="$fixture_root/swift-bin"
fake_swift_marker="$fixture_root/fake-swift-used"
/bin/mkdir -p "$fake_bin" "$fake_swift_bin_dir"

for tool in dirname rm mkdir chmod cp stat strip cat codesign ditto xcrun awk bash; do
  /bin/cat >"$fake_bin/$tool" <<SHIM
#!/bin/bash
/usr/bin/printf '%s %s invoked\\n' '$sentinel' '$tool' >&2
exit 97
SHIM
  /bin/chmod +x "$fake_bin/$tool"
done

/bin/cat >"$fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake swift used\n' >"${FAKE_SWIFT_MARKER:?}"
case "$*" in
  build\ --scratch-path\ /private/tmp/lithepg-release-build.*\ -c\ release\ --product\ LithePGApp)
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  build\ --scratch-path\ /private/tmp/lithepg-release-build.*\ -c\ release\ --show-bin-path)
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BIN_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$fake_bin/swift"

if ! run_package_capture "$output_file" "$fake_bin" "$fake_swift_bin_dir" "$fake_swift_marker"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "build_and_run --package was affected by PATH-shadowed core utilities"
fi

helper_output="$(<"$output_file")"
[[ -f "$fake_swift_marker" ]] || fail "fake swift was not used"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_contains "$helper_output" "Built $ROOT_DIR/dist/LithePG.app"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" "fake-tool"
assert_not_contains "$helper_output" " invoked"

[[ -d "$ROOT_DIR/dist/LithePG.app" ]] || fail "dist/LithePG.app was not created"
if ! "$VERIFY_HELPER" "$ROOT_DIR/dist/LithePG.app" >"$verify_output_file" 2>&1; then
  verify_output="$(<"$verify_output_file")"
  /usr/bin/printf '%s\n' "$verify_output" >&2
  fail "package verification failed for dist/LithePG.app"
fi
verify_output="$(<"$verify_output_file")"
assert_contains "$verify_output" "Package verified: LithePG.app"
assert_not_contains "$verify_output" "$sentinel"
assert_not_contains "$verify_output" "fake-tool"

/usr/bin/printf 'test_build_and_run passed\n'
