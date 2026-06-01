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
      LITHEPG_MARKETING_VERSION="1.0" \
      LITHEPG_BUILD_VERSION="100" \
      /bin/bash "$HELPER" --package
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"
[[ -f "$VERIFY_HELPER" ]] || fail "package verifier missing: $VERIFY_HELPER"

output_file="$(/usr/bin/mktemp)"
verify_output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file" "$verify_output_file"; /bin/rm -rf "$fixture_root"' EXIT

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
  "build -c release --product LithePGApp")
    /bin/mkdir -p "${FAKE_SWIFT_BIN_DIR:?}"
    /bin/cp /usr/bin/true "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    /bin/chmod 755 "$FAKE_SWIFT_BIN_DIR/LithePGApp"
    ;;
  "build -c release --show-bin-path")
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
