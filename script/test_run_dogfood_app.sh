#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  local fixture_url="$7"
  local fixture_query="$8"

  set +e
  (
    cd "$fixture_root"
    PATH="$fake_bin:$PATH" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      FAKE_SWIFT_BUILD_DIR="$fake_swift_build_dir" \
      FAKE_DOGFOOD_LOG="$fake_dogfood_log" \
      POSTGRES_TEST_URL="$fixture_url" \
      LITHEPG_STARTUP_QUERY="$fixture_query" \
      /bin/bash "$fixture_root/script/run_dogfood_app.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file"; /bin/rm -rf "$fixture_root"' EXIT

sentinel="RUN_DOGFOOD_APP_PATH_SHADOW_DIRNAME_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_dogfood_log="$fixture_root/fake-dogfood.log"
fake_swift_log="$fixture_root/fake-swift.log"
fake_swift_build_dir="$fixture_root/fake-swift-build"
fixture_url="postgres://fixture-user@localhost:55432/postgres?sslmode=disable"
fixture_query="SELECT current_database() AS lithepg_run_dogfood_app_test;"
/bin/mkdir -p "$fixture_root/script" "$fake_bin"
/bin/cp "$HELPER" "$fixture_root/script/run_dogfood_app.sh"
/bin/chmod +x "$fixture_root/script/run_dogfood_app.sh"

/bin/cat >"$fake_bin/dirname" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s dirname invoked\\n' '$sentinel' >&2
exit 97
SHIM
/bin/chmod +x "$fake_bin/dirname"

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

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$fake_swift_build_dir" "$fake_dogfood_log" "$fixture_url" "$fixture_query"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "run_dogfood_app.sh was affected by PATH-shadowed dirname"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" "dirname invoked"
assert_not_contains "$helper_output" "fake dogfood_postgres reached"
assert_contains "$helper_output" "fake LithePGApp reached"
assert_contains "$helper_output" "startup url=$fixture_url"
assert_contains "$helper_output" "startup query=$fixture_query"

[[ -s "$fake_dogfood_log" ]] || fail "fake dogfood_postgres was not used"
assert_contains "$(<"$fake_dogfood_log")" "fake dogfood_postgres reached"

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
fake_swift_output="$(<"$fake_swift_log")"
assert_contains "$fake_swift_output" "fake swift build --product LithePGApp"
assert_contains "$fake_swift_output" "fake swift build --show-bin-path"
assert_not_contains "$fake_swift_output" "$sentinel"

/usr/bin/printf 'test_run_dogfood_app passed\n'
