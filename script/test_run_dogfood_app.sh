#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
HELPER="$ROOT_DIR/script/run_dogfood_app.sh"

fail() {
  /usr/bin/printf 'test_run_dogfood_app failed: %s\n' "$1" >&2
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

run_helper_capture() {
  local output_file="$1"
  local fixture_root="$2"
  local fake_bin="$3"
  local fake_swift_log="$4"
  local fake_swift_build_dir="$5"
  local fake_dogfood_log="$6"
  local fake_path_shadow_core_log="$7"
  local fake_function_shadow_log="$8"
  local fake_bash_env="$9"
  local fixture_url="${10}"
  local fixture_query="${11}"

  set +e
  (
    cd "$fixture_root"
    set() {
      /usr/bin/printf '%s shell function set invoked\n' "${RUN_DOGFOOD_APP_EXPORT_FUNC_SENTINEL:?}" >>"${FAKE_FUNCTION_SHADOW_LOG:?}"
      /usr/bin/printf '%s shell function set invoked\n' "${RUN_DOGFOOD_APP_EXPORT_FUNC_SENTINEL:?}" >&2
      return 97
    }
    export -f set
    PATH="$fake_bin:$PATH" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      FAKE_SWIFT_BUILD_DIR="$fake_swift_build_dir" \
      FAKE_DOGFOOD_LOG="$fake_dogfood_log" \
      FAKE_PATH_SHADOW_CORE_LOG="$fake_path_shadow_core_log" \
      FAKE_FUNCTION_SHADOW_LOG="$fake_function_shadow_log" \
      RUN_DOGFOOD_APP_EXPORT_FUNC_SENTINEL="$function_sentinel" \
      BASH_ENV="$fake_bash_env" \
      POSTGRES_TEST_URL="$fixture_url" \
      LITHEPG_STARTUP_QUERY="$fixture_query" \
      "$fixture_root/script/run_dogfood_app.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file"; /bin/rm -rf "$fixture_root"' EXIT

dirname_sentinel="RUN_DOGFOOD_APP_PATH_SHADOW_DIRNAME_SHOULD_NOT_RUN"
core_sentinel="RUN_DOGFOOD_APP_PATH_SHADOW_CORE_SHOULD_NOT_RUN"
function_sentinel="RUN_DOGFOOD_APP_EXPORTED_SHELL_FUNCTION_SHOULD_NOT_RUN"
initial_bash_sentinel="RUN_DOGFOOD_APP_INITIAL_BASH_PATH_SHADOW_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_dogfood_log="$fixture_root/fake-dogfood.log"
fake_path_shadow_core_log="$fixture_root/fake-path-shadow-core.log"
fake_function_shadow_log="$fixture_root/fake-function-shadow.log"
fake_bash_marker="$fixture_root/fake-path-bash.log"
fake_bash_env="$fixture_root/fake-bash-env"
fake_swift_log="$fixture_root/fake-swift.log"
fake_swift_build_dir="$fixture_root/fake swift build dir with spaces"
[[ "$fake_swift_build_dir" == *" "* ]] || fail "fake Swift build path must contain whitespace"
fixture_url="postgres://fixture-user@localhost:55432/postgres?sslmode=disable"
fixture_query="SELECT current_database() AS lithepg_run_dogfood_app_test;"
/bin/mkdir -p "$fixture_root/script" "$fake_bin"
/bin/cp "$HELPER" "$fixture_root/script/run_dogfood_app.sh"
/bin/chmod +x "$fixture_root/script/run_dogfood_app.sh"

/bin/cat >"$fake_bin/bash" <<SHIM
#!/bin/sh
/usr/bin/printf '%s fake PATH-selected bash invoked\\n' '$initial_bash_sentinel' >&2
/usr/bin/printf 'fake-bash\\n' >'$fake_bash_marker'
exit 97
SHIM
/bin/chmod +x "$fake_bin/bash"

/bin/cat >"$fake_bin/dirname" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s dirname invoked\\n' '$dirname_sentinel' >&2
exit 97
SHIM
/bin/chmod +x "$fake_bin/dirname"

/bin/cat >"$fake_bin/realpath" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s realpath invoked\\n' '$core_sentinel' >>"\${FAKE_PATH_SHADOW_CORE_LOG:?}"
/usr/bin/printf '%s realpath invoked\\n' '$core_sentinel' >&2
exit 97
SHIM
/bin/chmod +x "$fake_bin/realpath"

/bin/cat >"$fake_bin/pwd" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s pwd invoked\\n' '$core_sentinel' >>"\${FAKE_PATH_SHADOW_CORE_LOG:?}"
/usr/bin/printf '%s pwd invoked\\n' '$core_sentinel' >&2
exit 97
SHIM
/bin/chmod +x "$fake_bin/pwd"

/bin/cat >"$fake_bash_env" <<BASHENV
shadow_function() {
  /usr/bin/printf '%s shell function %s invoked\\n' '$function_sentinel' "\$1" >>"\${FAKE_FUNCTION_SHADOW_LOG:?}"
  /usr/bin/printf '%s shell function %s invoked\\n' '$function_sentinel' "\$1" >&2
  return 97
}
set() { shadow_function set "\$@"; }
command() { shadow_function command "\$@"; }
builtin() { shadow_function builtin "\$@"; }
cd() { shadow_function cd "\$@"; }
pwd() { shadow_function pwd "\$@"; }
export -f shadow_function set command builtin cd pwd
BASHENV

/bin/cat >"$fixture_root/script/dogfood_postgres.sh" <<'DOGFOOD'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake dogfood_postgres reached\n' >>"${FAKE_DOGFOOD_LOG:?}"
/usr/bin/printf 'fake dogfood_postgres reached\n'
DOGFOOD
/bin/chmod +x "$fixture_root/script/dogfood_postgres.sh"

/bin/cat >"$fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake swift %s\n' "$*" >>"${FAKE_SWIFT_LOG:?}"
case "$*" in
  "build --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BUILD_DIR:?}"
    /bin/cat >"$FAKE_SWIFT_BUILD_DIR/LithePGApp" <<'APP'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake LithePGApp reached\n'
/usr/bin/printf 'startup url=%s\n' "${LITHEPG_STARTUP_URL:?}"
/usr/bin/printf 'startup query=%s\n' "${LITHEPG_STARTUP_QUERY:?}"
APP
    /bin/chmod +x "$FAKE_SWIFT_BUILD_DIR/LithePGApp"
    ;;
  "build --show-bin-path")
    /usr/bin/printf '%s\n' "${FAKE_SWIFT_BUILD_DIR:?}"
    ;;
  *)
    /usr/bin/printf 'unexpected fake swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$fake_bin/swift"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$fake_swift_build_dir" "$fake_dogfood_log" "$fake_path_shadow_core_log" "$fake_function_shadow_log" "$fake_bash_env" "$fixture_url" "$fixture_query"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "run_dogfood_app.sh was affected by PATH-selected bash, PATH-shadowed core utility, BASH_ENV, or exported shell function"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$initial_bash_sentinel"
assert_not_contains "$helper_output" "$dirname_sentinel"
assert_not_contains "$helper_output" "$core_sentinel"
assert_not_contains "$helper_output" "$function_sentinel"
assert_not_contains "$helper_output" "fake PATH-selected bash invoked"
assert_not_contains "$helper_output" "dirname invoked"
assert_not_contains "$helper_output" "realpath invoked"
assert_not_contains "$helper_output" "pwd invoked"
assert_not_contains "$helper_output" "set invoked"
assert_not_contains "$helper_output" "shell function"
assert_not_contains "$helper_output" "fake dogfood_postgres reached"
assert_contains "$helper_output" "fake LithePGApp reached"
assert_contains "$helper_output" "startup url=$fixture_url"
assert_contains "$helper_output" "startup query=$fixture_query"

[[ ! -e "$fake_bash_marker" ]] || fail "fake PATH-selected bash was invoked: $(<"$fake_bash_marker")"
[[ ! -e "$fake_path_shadow_core_log" ]] || fail "fake PATH-shadowed core utility was invoked"
[[ ! -e "$fake_function_shadow_log" ]] || fail "exported shell function shadow was invoked"

[[ -s "$fake_dogfood_log" ]] || fail "fake dogfood_postgres was not used"
assert_contains "$(<"$fake_dogfood_log")" "fake dogfood_postgres reached"

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
fake_swift_output="$(<"$fake_swift_log")"
assert_contains "$fake_swift_output" "fake swift build --product LithePGApp"
assert_contains "$fake_swift_output" "fake swift build --show-bin-path"
assert_not_contains "$fake_swift_output" "$dirname_sentinel"
assert_not_contains "$fake_swift_output" "$core_sentinel"
assert_not_contains "$fake_swift_output" "$function_sentinel"

startup_perl_sentinel="RUN_DOGFOOD_APP_PERL_STARTUP_SHOULD_NOT_RUN"
startup_perl_lib="$fixture_root/perl-startup-lib"
startup_perl_marker="$fixture_root/perl-startup-marker"
/bin/mkdir -p "$startup_perl_lib"
/bin/cat >"$startup_perl_lib/RunDogfoodAppPerlStartupPoison.pm" <<'PERLPOISON'
BEGIN {
  open my $fh, '>', $ENV{RUN_DOGFOOD_APP_PERL_STARTUP_MARKER} or die $!;
  print {$fh} "perl-startup\n";
  close $fh;
  die "$ENV{RUN_DOGFOOD_APP_PERL_STARTUP_SENTINEL} Perl startup invoked\n";
}
1;
PERLPOISON

/bin/rm -f "$output_file" "$fake_dogfood_log" "$fake_swift_log" "$startup_perl_marker"
set +e
(
  cd "$fixture_root"
  PATH="$fake_bin:$PATH" \
    FAKE_SWIFT_LOG="$fake_swift_log" \
    FAKE_SWIFT_BUILD_DIR="$fake_swift_build_dir" \
    FAKE_DOGFOOD_LOG="$fake_dogfood_log" \
    RUN_DOGFOOD_APP_PERL_STARTUP_MARKER="$startup_perl_marker" \
    RUN_DOGFOOD_APP_PERL_STARTUP_SENTINEL="$startup_perl_sentinel" \
    PERL5LIB="$startup_perl_lib" \
    PERLLIB="$startup_perl_lib" \
    PERL5OPT=-MRunDogfoodAppPerlStartupPoison \
    POSTGRES_TEST_URL="$fixture_url" \
    LITHEPG_STARTUP_QUERY="$fixture_query" \
    "$fixture_root/script/run_dogfood_app.sh"
) >"$output_file" 2>&1
startup_perl_status=$?
set -e
startup_perl_output="$(<"$output_file")"
if [[ "$startup_perl_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_perl_output" >&2
  fail "run_dogfood_app.sh left Perl startup environment unsanitized"
fi
assert_contains "$startup_perl_output" "fake LithePGApp reached"
assert_not_contains "$startup_perl_output" "$startup_perl_sentinel"
assert_not_contains "$startup_perl_output" "Perl startup invoked"
[[ ! -e "$startup_perl_marker" ]] || fail "run_dogfood_app.sh invoked Perl startup env: $(<"$startup_perl_marker")"

/bin/rm -f "$output_file"
set +e
(
  cd "$fixture_root"
  LITHEPG_RUN_DOGFOOD_APP_STARTUP_ENV_SANITIZED=1 \
    PERL5OPT=-MRunDogfoodAppSanitizerShouldFailClosed \
    "$fixture_root/script/run_dogfood_app.sh"
) >"$output_file" 2>&1
startup_fail_closed_status=$?
set -e
startup_fail_closed_output="$(<"$output_file")"
if [[ "$startup_fail_closed_status" -ne 2 ]]; then
  /usr/bin/printf '%s\n' "$startup_fail_closed_output" >&2
  fail "run_dogfood_app.sh startup sanitizer did not fail closed with exit 2 when sanitized marker still had dirty env"
fi
assert_contains "$startup_fail_closed_output" "unsanitized startup environment remains after run_dogfood_app sanitizer"
assert_not_contains "$startup_fail_closed_output" "fake LithePGApp reached"

/bin/rm -f "$output_file" "$fake_dogfood_log" "$fake_swift_log"
empty_bash_env_private_sentinel="RUN_DOGFOOD_APP_EMPTY_BASH_ENV_PRIVATE_SENTINEL_SHOULD_NOT_LEAK"
set +e
(
  cd "$fixture_root"
  LITHEPG_RUN_DOGFOOD_APP_STARTUP_ENV_SANITIZED=1 \
    RUN_DOGFOOD_APP_EMPTY_BASH_ENV_PRIVATE="$empty_bash_env_private_sentinel" \
    BASH_ENV="" \
    PATH="$fake_bin:$PATH" \
    FAKE_SWIFT_LOG="$fake_swift_log" \
    FAKE_SWIFT_BUILD_DIR="$fake_swift_build_dir" \
    FAKE_DOGFOOD_LOG="$fake_dogfood_log" \
    POSTGRES_TEST_URL="$fixture_url" \
    LITHEPG_STARTUP_QUERY="$fixture_query" \
    "$fixture_root/script/run_dogfood_app.sh"
) >"$output_file" 2>&1
empty_bash_env_fail_closed_status=$?
set -e
empty_bash_env_fail_closed_output="$(<"$output_file")"
if [[ "$empty_bash_env_fail_closed_status" -ne 2 ]]; then
  /usr/bin/printf '%s\n' "$empty_bash_env_fail_closed_output" >&2
  fail "run_dogfood_app.sh startup sanitizer did not fail closed with exit 2 for empty BASH_ENV after sanitizer marker"
fi
assert_contains "$empty_bash_env_fail_closed_output" "unsanitized startup environment remains after run_dogfood_app sanitizer"
assert_not_contains "$empty_bash_env_fail_closed_output" "$empty_bash_env_private_sentinel"
assert_not_contains "$empty_bash_env_fail_closed_output" "fake LithePGApp reached"
assert_not_contains "$empty_bash_env_fail_closed_output" "fake dogfood_postgres reached"
[[ ! -s "$fake_dogfood_log" ]] || fail "run_dogfood_app.sh empty BASH_ENV fail-closed path started dogfood postgres: $(<"$fake_dogfood_log")"
[[ ! -s "$fake_swift_log" ]] || fail "run_dogfood_app.sh empty BASH_ENV fail-closed path invoked swift: $(<"$fake_swift_log")"

/usr/bin/printf 'test_run_dogfood_app passed\n'
