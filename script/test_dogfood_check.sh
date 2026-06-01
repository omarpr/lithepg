#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/dogfood_check.sh"

fail() {
  /usr/bin/printf 'test_dogfood_check failed: %s\n' "$1" >&2
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
  local developer_dir="$5"

  set +e
  (
    cd "$fixture_root"
    PATH="$fake_bin:$PATH" \
      DEVELOPER_DIR="$developer_dir" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      /bin/bash "$fixture_root/script/dogfood_check.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

extract_out_dir() {
  local output_file="$1"
  /usr/bin/python3 - "$output_file" <<'PY'
import pathlib
import sys

prefix = "Dogfood check written to "
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if line.startswith(prefix):
        print(line[len(prefix):])
        raise SystemExit(0)
raise SystemExit(1)
PY
}

assert_status_json() {
  local status_file="$1"
  /usr/bin/python3 - "$status_file" <<'PY'
import json
import pathlib
import sys

status = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert status["branch"] == "dogfood-check-test", status
assert status["commit"] == "abc1234", status
assert status["defaultSwiftTest"] == "passed", status
assert status["liveSwiftTest"] == "passed", status
assert status["v04Measure"] == "passed", status
assert status["v04Summary"]["binaryMiB"] == 1.25, status
assert status["v04Summary"]["stripXMiB"] == 1.0, status
assert status["v04Summary"]["shellStartMs"] == 10, status
assert status["v04Summary"]["coldStartMs"] == 20, status
assert status["v04Summary"]["simpleMedianOverheadMs"] == 1.1, status
assert status["v04Summary"]["dogfoodMedianOverheadMs"] == 2.2, status
PY
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file"; /bin/rm -rf "$fixture_root"' EXIT

sentinel="DOGFOOD_CHECK_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_swift_log="$fixture_root/fake-swift.log"
developer_dir="$(/usr/bin/xcode-select -p)"
/bin/mkdir -p "$fixture_root/script" "$fake_bin"
/bin/cp "$HELPER" "$fixture_root/script/dogfood_check.sh"
/bin/chmod +x "$fixture_root/script/dogfood_check.sh"

for tool in dirname date mkdir cat; do
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
SWIFT
/bin/chmod +x "$fake_bin/swift"

/bin/cat >"$fake_bin/git" <<'GIT'
#!/bin/bash
set -euo pipefail
case "$*" in
  "rev-parse --short HEAD")
    /usr/bin/printf 'abc1234\n'
    ;;
  "branch --show-current")
    /usr/bin/printf 'dogfood-check-test\n'
    ;;
  *)
    /usr/bin/printf 'unexpected fake git invocation: %s\n' "$*" >&2
    exit 98
    ;;
esac
GIT
/bin/chmod +x "$fake_bin/git"

/bin/cat >"$fake_bin/python3" <<PYTHON
#!/bin/bash
/usr/bin/printf '%s python3 invoked\\n' '$sentinel' >&2
exit 99
PYTHON
/bin/chmod +x "$fake_bin/python3"

/bin/cat >"$fixture_root/script/dogfood_postgres.sh" <<'DOGFOOD'
#!/bin/bash
set -euo pipefail
/usr/bin/printf 'fake dogfood postgres started\n'
DOGFOOD
/bin/chmod +x "$fixture_root/script/dogfood_postgres.sh"

/bin/cat >"$fixture_root/script/v04_measure.sh" <<'MEASURE'
#!/bin/bash
set -euo pipefail
/bin/mkdir -p "${LITHEPG_MEASURE_OUT_DIR:?}"
/bin/cat >"$LITHEPG_MEASURE_OUT_DIR/summary.json" <<'JSON'
{
  "binarySize": {
    "mib": 1.25,
    "stripXMiB": 1.0
  },
  "shellStart": {
    "elapsedMs": 10
  },
  "coldStart": {
    "elapsedMs": 20
  },
  "queryOverheadSimpleMedianMs": 1.1,
  "queryOverheadDogfoodMedianMs": 2.2
}
JSON
MEASURE
/bin/chmod +x "$fixture_root/script/v04_measure.sh"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$developer_dir"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "dogfood_check.sh was affected by PATH-shadowed core utilities"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" " invoked"
assert_contains "$helper_output" '"defaultSwiftTest": "passed"'
assert_contains "$helper_output" '"liveSwiftTest": "passed"'
assert_contains "$helper_output" '"v04Measure": "passed"'

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
assert_contains "$(<"$fake_swift_log")" "fake swift test"
assert_contains "$(<"$fake_swift_log")" "fake swift test --filter"

out_dir="$(extract_out_dir "$output_file")" || fail "helper output did not include output directory"
status_file="$out_dir/status.json"
[[ -f "$status_file" ]] || fail "status.json missing: $status_file"
assert_status_json "$status_file"

/usr/bin/printf 'test_dogfood_check passed\n'
