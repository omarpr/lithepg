#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
HELPER="$ROOT_DIR/script/v04_measure.sh"

fail() {
  /usr/bin/printf 'test_v04_measure failed: %s\n' "$1" >&2
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
  local outside_cwd="$6"
  local marker_dir="$7"
  local command_sentinel="$8"
  local builtin_sentinel="$9"
  local cd_sentinel="${10}"
  local pwd_sentinel="${11}"
  local docker_sentinel="${12}"
  local kill_sentinel="${13}"
  local sleep_sentinel="${14}"

  set +e
  (
    cd "$outside_cwd"
    command() {
      /usr/bin/printf '%s command invoked\n' "${V04_MEASURE_COMMAND_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'command\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/command"
      exit 97
    }
    builtin() {
      /usr/bin/printf '%s builtin invoked\n' "${V04_MEASURE_BUILTIN_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'builtin\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/builtin"
      exit 97
    }
    cd() {
      /usr/bin/printf '%s cd invoked\n' "${V04_MEASURE_CD_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'cd\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/cd"
      exit 97
    }
    pwd() {
      /usr/bin/printf '%s pwd invoked\n' "${V04_MEASURE_PWD_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'pwd\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/pwd"
      exit 97
    }
    docker() {
      /usr/bin/printf '%s docker invoked\n' "${V04_MEASURE_DOCKER_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'docker\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/docker"
      exit 97
    }
    kill() {
      /usr/bin/printf '%s kill invoked\n' "${V04_MEASURE_KILL_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'kill\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/kill"
      exit 97
    }
    sleep() {
      /usr/bin/printf '%s sleep invoked\n' "${V04_MEASURE_SLEEP_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'sleep\n' >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/sleep"
      exit 97
    }
    export -f command
    export -f builtin
    export -f cd
    export -f pwd
    export -f docker
    export -f kill
    export -f sleep
      PATH="$fake_bin:$PATH" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      FAKE_DOGFOOD_LOG="$marker_dir/dogfood" \
      LITHEPG_MEASURE_OUT_DIR="$out_dir" \
      V04_MEASURE_SHADOW_MARKER_DIR="$marker_dir" \
      V04_MEASURE_SHADOW_ASSERT_HELPER="$fixture_root/assert_no_shadow_functions.sh" \
      V04_MEASURE_COMMAND_SHADOW_SENTINEL="$command_sentinel" \
      V04_MEASURE_BUILTIN_SHADOW_SENTINEL="$builtin_sentinel" \
      V04_MEASURE_CD_SHADOW_SENTINEL="$cd_sentinel" \
      V04_MEASURE_PWD_SHADOW_SENTINEL="$pwd_sentinel" \
      V04_MEASURE_DOCKER_SHADOW_SENTINEL="$docker_sentinel" \
      V04_MEASURE_KILL_SHADOW_SENTINEL="$kill_sentinel" \
      V04_MEASURE_SLEEP_SHADOW_SENTINEL="$sleep_sentinel" \
      /bin/bash "$fixture_root/script/v04_measure.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

assert_summary_json() {
  local summary_file="$1"
  local expected_out_dir="$2"
  local expected_app_path="$3"
  /usr/bin/python3 - "$summary_file" "$expected_out_dir" "$expected_app_path" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert pathlib.Path(summary["outDir"]).resolve() == pathlib.Path(sys.argv[2]).resolve(), summary
assert summary["binarySize"]["product"] == "LithePGApp", summary
assert pathlib.Path(summary["binarySize"]["path"]).resolve() == pathlib.Path(sys.argv[3]).resolve(), summary
assert summary["binarySize"]["bytes"] > 0, summary
assert summary["binarySize"]["stripXBytes"] > 0, summary
assert summary["shellStart"]["fixture"] == "fake-startup", summary
assert summary["coldStart"]["fixture"] == "fake-startup", summary
assert summary["lithepgSimple"]["tool"] == "lithepg-bench", summary
assert summary["lithepgDogfood"]["tool"] == "lithepg-bench", summary
assert summary["psqlSimple"]["tool"] == "psql", summary
assert summary["psqlDogfood"]["tool"] == "psql", summary
assert "queryOverheadSimpleMedianMs" in summary, summary
assert "queryOverheadDogfoodP95Ms" in summary, summary
PY
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

output_file="$(/usr/bin/mktemp)"
fixture_parent="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg v04 measure.XXXXXX")"
fixture_root="$fixture_parent/repo with spaces"
/bin/mkdir -p "$fixture_root"
trap '/bin/rm -f "$output_file"; /bin/rm -rf "$fixture_parent"' EXIT

sentinel="V04_MEASURE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
command_sentinel="V04_MEASURE_COMMAND_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
builtin_sentinel="V04_MEASURE_BUILTIN_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
cd_sentinel="V04_MEASURE_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
pwd_sentinel="V04_MEASURE_PWD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
docker_sentinel="V04_MEASURE_DOCKER_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
kill_sentinel="V04_MEASURE_KILL_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
sleep_sentinel="V04_MEASURE_SLEEP_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_swift_log="$fixture_root/fake-swift.log"
out_dir="$fixture_root/out/v04-measure"
outside_cwd="$fixture_root/outside-cwd"
marker_dir="$fixture_root/shadow-markers"
/bin/mkdir -p "$fixture_root/script" "$fake_bin" "$outside_cwd" "$marker_dir"
/bin/cp "$HELPER" "$fixture_root/script/v04_measure.sh"
/bin/chmod +x "$fixture_root/script/v04_measure.sh"

/bin/cat >"$fixture_root/assert_no_shadow_functions.sh" <<'SHADOW_ASSERT'
assert_no_shadow_functions() {
  local tool="$1"
  local safe_tool="${tool//[^A-Za-z0-9_.-]/_}"
  local fn sentinel
  for fn in command builtin cd pwd docker kill sleep; do
    case "$fn" in
      command) sentinel="${V04_MEASURE_COMMAND_SHADOW_SENTINEL:?}" ;;
      builtin) sentinel="${V04_MEASURE_BUILTIN_SHADOW_SENTINEL:?}" ;;
      cd) sentinel="${V04_MEASURE_CD_SHADOW_SENTINEL:?}" ;;
      pwd) sentinel="${V04_MEASURE_PWD_SHADOW_SENTINEL:?}" ;;
      docker) sentinel="${V04_MEASURE_DOCKER_SHADOW_SENTINEL:?}" ;;
      kill) sentinel="${V04_MEASURE_KILL_SHADOW_SENTINEL:?}" ;;
      sleep) sentinel="${V04_MEASURE_SLEEP_SHADOW_SENTINEL:?}" ;;
      *) exit 99 ;;
    esac
    if declare -F "$fn" >/dev/null; then
      /usr/bin/printf '%s %s inherited by %s\n' "$sentinel" "$fn" "$tool" >&2
      /usr/bin/printf '%s inherited by %s\n' "$fn" "$tool" >"${V04_MEASURE_SHADOW_MARKER_DIR:?}/inherited-$safe_tool-$fn"
      exit 97
    fi
  done
  /usr/bin/printf 'checked %s\n' "$tool" >>"${V04_MEASURE_SHADOW_MARKER_DIR:?}/shadow-function-checks"
}
SHADOW_ASSERT

/bin/cat >"$fixture_root/script/dogfood_postgres.sh" <<'DOGFOOD'
#!/bin/bash
set -euo pipefail
. "${V04_MEASURE_SHADOW_ASSERT_HELPER:?}"
assert_no_shadow_functions "fake dogfood_postgres.sh"
/usr/bin/printf 'fake dogfood postgres invoked\n' >"${FAKE_DOGFOOD_LOG:?}"
/usr/bin/printf 'fake dogfood postgres ready\n'
DOGFOOD
/bin/chmod +x "$fixture_root/script/dogfood_postgres.sh"

for tool in dirname realpath date mkdir cp stat mktemp strip rm cat pwd python3; do
  /bin/cat >"$fake_bin/$tool" <<SHIM
#!/bin/bash
/usr/bin/printf '%s %s invoked\\n' '$sentinel' '$tool' >&2
/usr/bin/printf '%s\\n' '$tool' >'$marker_dir/$tool'
exit 97
SHIM
  /bin/chmod +x "$fake_bin/$tool"
done

/bin/cat >"$fake_bin/swift" <<'SWIFT'
#!/bin/bash
set -euo pipefail
. "${V04_MEASURE_SHADOW_ASSERT_HELPER:?}"
assert_no_shadow_functions "fake swift"
/usr/bin/printf 'fake swift %s\n' "$*" >>"${FAKE_SWIFT_LOG:?}"
case "$*" in
  "build -c release --product LithePGApp")
    /bin/mkdir -p .build/release
    /bin/cat > .build/release/LithePGApp <<'APP'
#!/bin/bash
set -euo pipefail
. "${V04_MEASURE_SHADOW_ASSERT_HELPER:?}"
assert_no_shadow_functions "fake LithePGApp"
/bin/cat >"${LITHEPG_STARTUP_METRICS_PATH:?}" <<'JSON'
{
  "fixture": "fake-startup",
  "readyMs": 1.25,
  "queryMs": 0.75
}
JSON
exit 0
APP
    /bin/chmod 755 .build/release/LithePGApp
    /usr/bin/printf 'fake app build passed\n'
    ;;
  "build -c release --product lithepg-bench")
    /bin/mkdir -p .build/release
    /bin/cat > .build/release/lithepg-bench <<'BENCH'
#!/bin/bash
set -euo pipefail
. "${V04_MEASURE_SHADOW_ASSERT_HELPER:?}"
assert_no_shadow_functions "fake lithepg-bench"
/usr/bin/printf '{"tool":"lithepg-bench","query":"fixture","warmup":1,"iterations":2,"samplesMs":[1.0,2.0],"medianMs":1.5,"p95Ms":2.0,"minMs":1.0,"maxMs":2.0}\n'
BENCH
    /bin/chmod 755 .build/release/lithepg-bench
    /usr/bin/printf 'fake bench build passed\n'
    ;;
  *)
    /usr/bin/printf 'unexpected fake swift invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
SWIFT
/bin/chmod +x "$fake_bin/swift"

/bin/cat >"$fake_bin/psql" <<'PSQL'
#!/bin/bash
set -euo pipefail
. "${V04_MEASURE_SHADOW_ASSERT_HELPER:?}"
assert_no_shadow_functions "fake psql"
/usr/bin/printf 'Time: 0.20 ms\n'
/usr/bin/printf 'Time: 0.21 ms\n'
/usr/bin/printf 'Time: 0.22 ms\n'
/usr/bin/printf 'Time: 0.23 ms\n'
/usr/bin/printf 'Time: 0.24 ms\n'
/usr/bin/printf 'Time: 0.25 ms\n'
/usr/bin/printf 'Time: 0.26 ms\n'
PSQL
/bin/chmod +x "$fake_bin/psql"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$out_dir" "$outside_cwd" "$marker_dir" "$command_sentinel" "$builtin_sentinel" "$cd_sentinel" "$pwd_sentinel" "$docker_sentinel" "$kill_sentinel" "$sleep_sentinel"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "v04_measure.sh was affected by PATH-shadowed core utilities or exported shell functions"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" "$command_sentinel"
assert_not_contains "$helper_output" "$builtin_sentinel"
assert_not_contains "$helper_output" "$cd_sentinel"
assert_not_contains "$helper_output" "$pwd_sentinel"
assert_not_contains "$helper_output" "$docker_sentinel"
assert_not_contains "$helper_output" "$kill_sentinel"
assert_not_contains "$helper_output" "$sleep_sentinel"
assert_not_contains "$helper_output" " invoked"
assert_contains "$helper_output" "fake app build passed"
assert_contains "$helper_output" "fake bench build passed"
assert_contains "$helper_output" '"outDir":'
assert_contains "$helper_output" "Measurements written to $out_dir"

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
fake_swift_output="$(<"$fake_swift_log")"
assert_contains "$fake_swift_output" "fake swift build -c release --product LithePGApp"
assert_contains "$fake_swift_output" "fake swift build -c release --product lithepg-bench"

[[ -s "$marker_dir/dogfood" ]] || fail "fake dogfood postgres was not invoked"
assert_contains "$(<"$marker_dir/dogfood")" "fake dogfood postgres invoked"
[[ -s "$out_dir/dogfood-postgres.log" ]] || fail "dogfood-postgres.log missing"
assert_contains "$(<"$out_dir/dogfood-postgres.log")" "fake dogfood postgres ready"

[[ -s "$marker_dir/shadow-function-checks" ]] || fail "child bash shadow-function checks were not run"
shadow_checks="$(<"$marker_dir/shadow-function-checks")"
assert_contains "$shadow_checks" "checked fake dogfood_postgres.sh"
assert_contains "$shadow_checks" "checked fake swift"
assert_contains "$shadow_checks" "checked fake LithePGApp"
assert_contains "$shadow_checks" "checked fake lithepg-bench"
assert_contains "$shadow_checks" "checked fake psql"
/usr/bin/python3 - "$marker_dir" <<'PY'
import pathlib
import sys

leaks = sorted(path.name for path in pathlib.Path(sys.argv[1]).glob("inherited-*"))
if leaks:
    raise SystemExit("exported shell functions leaked into child bash tools: " + ", ".join(leaks))
PY

for tool in dirname realpath pwd command builtin cd docker kill sleep; do
  [[ ! -e "$marker_dir/$tool" ]] || fail "v04_measure.sh invoked shadowed $tool"
done

summary_file="$out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "summary.json missing: $summary_file"
expected_root="$(/bin/realpath "$fixture_root")"
assert_summary_json "$summary_file" "$out_dir" "$expected_root/.build/release/LithePGApp"

for artifact in binary-size.json lithepg-simple.json lithepg-dogfood.json psql-simple.json psql-dogfood.json shell-start.json cold-start.json; do
  [[ -s "$out_dir/$artifact" ]] || fail "artifact missing or empty: $artifact"
done

/usr/bin/printf 'test_v04_measure passed\n'
