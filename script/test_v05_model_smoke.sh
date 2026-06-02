#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/v05_model_smoke.sh"

fail() {
  /usr/bin/printf 'test_v05_model_smoke failed: %s\n' "$1" >&2
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
  local out_dir="$5"

  set +e
  (
    cd "$fixture_root"
    env \
      -u LITHEPG_ENABLE_LOCAL_MODEL \
      -u LITHEPG_LOCAL_MODEL_PATH \
      PATH="$fake_bin:$PATH" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      LITHEPG_MODEL_SMOKE_OUT_DIR="$out_dir" \
      /bin/bash "$fixture_root/script/v05_model_smoke.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

assert_summary_json() {
  local summary_file="$1"
  local expected_path="$2"
  /usr/bin/python3 - "$summary_file" "$expected_path" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["product"] == "LithePGApp", summary
assert summary["path"] == sys.argv[2], summary
assert summary["bytes"] > 0, summary
assert summary["mib"] > 0, summary
assert summary["coreMLFrameworkLinked"] is False, summary
assert summary["modelArtifactBundled"] is False, summary
assert summary["requiresPackageDependency"] is False, summary
assert summary["gatedModelSmokeEnabled"] is False, summary
assert summary["modelPathProvided"] is False, summary
PY
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file" "${function_shadow_output_file:-}"; /bin/rm -rf "$fixture_root"' EXIT

sentinel="V05_MODEL_SMOKE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_swift_log="$fixture_root/fake-swift.log"
out_dir="$fixture_root/out/model-smoke"
/bin/mkdir -p "$fixture_root/script" "$fake_bin"
/bin/cp "$HELPER" "$fixture_root/script/v05_model_smoke.sh"
/bin/chmod +x "$fixture_root/script/v05_model_smoke.sh"

for tool in realpath dirname date mkdir tee otool grep cat pwd; do
  /bin/cat >"$fake_bin/$tool" <<SHIM
#!/bin/bash
/usr/bin/printf '%s %s invoked\\n' '$sentinel' '$tool' >&2
exit 97
SHIM
  /bin/chmod +x "$fake_bin/$tool"
done

/bin/cat >"$fake_bin/python3" <<SHIM
#!/bin/bash
/usr/bin/printf '%s python3 invoked\\n' '$sentinel' >&2
exit 97
SHIM
/bin/chmod +x "$fake_bin/python3"

/bin/cat >"$fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake swift %s\n' "$*" >>"${FAKE_SWIFT_LOG:?}"
case "$*" in
  "test --filter LocalModelAIQueryService")
    /usr/bin/printf 'fake local model tests passed\n'
    ;;
  "build -c release --product LithePGApp")
    /bin/mkdir -p .build/release
    /bin/cp /usr/bin/true .build/release/LithePGApp
    /bin/chmod 755 .build/release/LithePGApp
    /usr/bin/printf 'fake release build passed\n'
    ;;
  *)
    /usr/bin/printf 'unexpected fake swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$fake_bin/swift"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$out_dir"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "v05_model_smoke.sh was affected by PATH-shadowed core utilities"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" " invoked"
assert_contains "$helper_output" "fake local model tests passed"
assert_contains "$helper_output" "fake release build passed"
assert_contains "$helper_output" '"product": "LithePGApp"'
assert_contains "$helper_output" "Model smoke measurements written to $out_dir"

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
fake_swift_output="$(<"$fake_swift_log")"
assert_contains "$fake_swift_output" "fake swift test --filter LocalModelAIQueryService"
assert_contains "$fake_swift_output" "fake swift build -c release --product LithePGApp"

summary_file="$out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "summary.json missing: $summary_file"
expected_app_bin="$(/bin/realpath "$fixture_root")/.build/release/LithePGApp"
assert_summary_json "$summary_file" "$expected_app_bin"

[[ -s "$out_dir/local-model-tests.log" ]] || fail "local-model-tests.log missing"
[[ -s "$out_dir/release-build.log" ]] || fail "release-build.log missing"

function_shadow_output_file="$(/usr/bin/mktemp)"
function_shadow_out_dir="$fixture_root/out/function-shadow-model-smoke"
function_shadow_marker_dir="$fixture_root/function-shadow-markers"
outside_cwd="$fixture_root/outside-cwd"
/bin/mkdir -p "$function_shadow_marker_dir" "$outside_cwd"

set +e
(
  cd "$outside_cwd"

  command() {
    /usr/bin/printf '%s command function invoked\n' "${V05_FUNCTION_SENTINEL:?}" >&2
    /usr/bin/touch "${V05_SENTINEL_MARKER_DIR:?}/command"
    return 97
  }

  builtin() {
    /usr/bin/printf '%s builtin function invoked\n' "${V05_FUNCTION_SENTINEL:?}" >&2
    /usr/bin/touch "${V05_SENTINEL_MARKER_DIR:?}/builtin"
    return 97
  }

  cd() {
    /usr/bin/printf '%s cd function invoked\n' "${V05_FUNCTION_SENTINEL:?}" >&2
    /usr/bin/touch "${V05_SENTINEL_MARKER_DIR:?}/cd"
    return 97
  }

  pwd() {
    /usr/bin/printf '%s pwd function invoked\n' "${V05_FUNCTION_SENTINEL:?}" >&2
    /usr/bin/touch "${V05_SENTINEL_MARKER_DIR:?}/pwd"
    return 97
  }

  export -f command builtin cd pwd
  env \
    -u LITHEPG_ENABLE_LOCAL_MODEL \
    -u LITHEPG_LOCAL_MODEL_PATH \
    PATH="$fake_bin:$PATH" \
    FAKE_SWIFT_LOG="$fake_swift_log" \
    LITHEPG_MODEL_SMOKE_OUT_DIR="$function_shadow_out_dir" \
    V05_FUNCTION_SENTINEL="$sentinel" \
    V05_SENTINEL_MARKER_DIR="$function_shadow_marker_dir" \
    /bin/bash "$fixture_root/script/v05_model_smoke.sh"
) >"$function_shadow_output_file" 2>&1
function_shadow_status=$?
set -e

if [[ "$function_shadow_status" -ne 0 ]]; then
  helper_output="$(<"$function_shadow_output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "v05_model_smoke.sh was affected by function-shadowed shell builtins during root/chdir setup"
fi

function_shadow_output="$(<"$function_shadow_output_file")"
assert_not_contains "$function_shadow_output" "$sentinel"
assert_not_contains "$function_shadow_output" "function invoked"
assert_contains "$function_shadow_output" "fake local model tests passed"
assert_contains "$function_shadow_output" "fake release build passed"
assert_contains "$function_shadow_output" '"product": "LithePGApp"'
assert_contains "$function_shadow_output" "Model smoke measurements written to $function_shadow_out_dir"

for marker in command builtin cd pwd; do
  [[ ! -e "$function_shadow_marker_dir/$marker" ]] || fail "function-shadowed $marker was invoked"
done

summary_file="$function_shadow_out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "function-shadow summary.json missing: $summary_file"
expected_app_bin="$(/bin/realpath "$fixture_root")/.build/release/LithePGApp"
assert_summary_json "$summary_file" "$expected_app_bin"

[[ -s "$function_shadow_out_dir/local-model-tests.log" ]] || fail "function-shadow local-model-tests.log missing"
[[ -s "$function_shadow_out_dir/release-build.log" ]] || fail "function-shadow release-build.log missing"

/bin/rm -f "$function_shadow_output_file"

/usr/bin/printf 'test_v05_model_smoke passed\n'
