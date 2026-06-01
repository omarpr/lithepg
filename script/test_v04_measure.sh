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

  set +e
  (
    cd "$fixture_root"
    env \
      PATH="$fake_bin:$PATH" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      LITHEPG_MEASURE_OUT_DIR="$out_dir" \
      LITHEPG_SKIP_DOGFOOD_DB=1 \
      PSQL_BIN="$fake_bin/psql" \
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
assert summary["outDir"] == sys.argv[2], summary
assert summary["binarySize"]["product"] == "LithePGApp", summary
assert summary["binarySize"]["path"] == sys.argv[3], summary
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
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file"; /bin/rm -rf "$fixture_root"' EXIT

sentinel="V04_MEASURE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_swift_log="$fixture_root/fake-swift.log"
out_dir="$fixture_root/out/v04-measure"
/bin/mkdir -p "$fixture_root/script" "$fake_bin"
/bin/cp "$HELPER" "$fixture_root/script/v04_measure.sh"
/bin/chmod +x "$fixture_root/script/v04_measure.sh"

/bin/cat >"$fixture_root/script/dogfood_postgres.sh" <<'DOGFOOD'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'dogfood fixture should be skipped when LITHEPG_SKIP_DOGFOOD_DB=1\n' >&2
exit 99
DOGFOOD
/bin/chmod +x "$fixture_root/script/dogfood_postgres.sh"

for tool in dirname date mkdir cp stat mktemp strip rm cat pwd python3; do
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
/usr/bin/printf 'fake swift %s\n' "$*" >>"${FAKE_SWIFT_LOG:?}"
case "$*" in
  "build -c release --product LithePGApp")
    /bin/mkdir -p .build/release
    /bin/cat > .build/release/LithePGApp <<'APP'
#!/bin/bash
set -euo pipefail
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
/usr/bin/printf 'Time: 0.20 ms\n'
/usr/bin/printf 'Time: 0.21 ms\n'
/usr/bin/printf 'Time: 0.22 ms\n'
/usr/bin/printf 'Time: 0.23 ms\n'
/usr/bin/printf 'Time: 0.24 ms\n'
/usr/bin/printf 'Time: 0.25 ms\n'
/usr/bin/printf 'Time: 0.26 ms\n'
PSQL
/bin/chmod +x "$fake_bin/psql"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$out_dir"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "v04_measure.sh was affected by PATH-shadowed core utilities"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" " invoked"
assert_contains "$helper_output" "fake app build passed"
assert_contains "$helper_output" "fake bench build passed"
assert_contains "$helper_output" '"outDir":'
assert_contains "$helper_output" "Measurements written to $out_dir"

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
fake_swift_output="$(<"$fake_swift_log")"
assert_contains "$fake_swift_output" "fake swift build -c release --product LithePGApp"
assert_contains "$fake_swift_output" "fake swift build -c release --product lithepg-bench"

summary_file="$out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "summary.json missing: $summary_file"
assert_summary_json "$summary_file" "$out_dir" "$fixture_root/.build/release/LithePGApp"

for artifact in binary-size.json lithepg-simple.json lithepg-dogfood.json psql-simple.json psql-dogfood.json shell-start.json cold-start.json; do
  [[ -s "$out_dir/$artifact" ]] || fail "artifact missing or empty: $artifact"
done

/usr/bin/printf 'test_v04_measure passed\n'
