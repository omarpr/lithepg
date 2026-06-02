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

run_executable_helper_capture() {
  local output_file="$1"
  local fixture_root="$2"
  local path_bin="$3"
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
    PATH="$path_bin:$PATH" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      FAKE_DOGFOOD_LOG="$marker_dir/dogfood-executable" \
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
      "$fixture_root/script/v04_measure.sh"
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

startup_fake_bash_sentinel="V04_MEASURE_INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
startup_fake_bash_marker="$fixture_root/startup-fake-bash-invoked"
/bin/cat >"$fake_bin/bash" <<SHIM
#!/bin/bash
/usr/bin/printf '%s fake bash invoked\\n' '$startup_fake_bash_sentinel' >&2
/usr/bin/printf 'fake-bash\\n' >'$startup_fake_bash_marker'
exit 97
SHIM
/bin/chmod +x "$fake_bin/bash"

executable_out_dir="$fixture_root/out/executable-v04-measure"
if ! run_executable_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$executable_out_dir" "$outside_cwd" "$marker_dir" "$command_sentinel" "$builtin_sentinel" "$cd_sentinel" "$pwd_sentinel" "$docker_sentinel" "$kill_sentinel" "$sleep_sentinel"; then
  executable_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$executable_output" >&2
  fail "v04_measure.sh executable invocation used PATH-selected bash"
fi

executable_output="$(<"$output_file")"
assert_not_contains "$executable_output" "$startup_fake_bash_sentinel"
assert_not_contains "$executable_output" "fake bash invoked"
assert_contains "$executable_output" "fake app build passed"
assert_contains "$executable_output" "fake bench build passed"
assert_contains "$executable_output" "Measurements written to $executable_out_dir"
[[ ! -e "$startup_fake_bash_marker" ]] || fail "v04_measure.sh executable invocation used fake PATH bash: $(<"$startup_fake_bash_marker")"
summary_file="$executable_out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "executable summary.json missing: $summary_file"
expected_root="$(/bin/realpath "$fixture_root")"
assert_summary_json "$summary_file" "$executable_out_dir" "$expected_root/.build/release/LithePGApp"

startup_clean_bin="$fixture_root/startup-clean-bin"
/bin/mkdir -p "$startup_clean_bin"
/bin/cp "$fake_bin/swift" "$startup_clean_bin/swift"
/bin/cp "$fake_bin/psql" "$startup_clean_bin/psql"
/bin/chmod +x "$startup_clean_bin/swift" "$startup_clean_bin/psql"

startup_env_shadow_sentinel="V04_MEASURE_STARTUP_ENV_SHADOW_SENTINEL_SHOULD_NOT_RUN"
startup_env_bash_file="$fixture_root/v04-measure-bash-env"
startup_env_bash_marker="$fixture_root/v04-measure-bash-env-marker"
startup_env_export_marker="$fixture_root/v04-measure-exported-set-marker"
startup_env_out_dir="$fixture_root/out/startup-env-v04-measure"
/bin/cat >"$startup_env_bash_file" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${V04_MEASURE_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${V04_MEASURE_STARTUP_ENV_BASH_MARKER:?}"
  exit 97
}
BASHENV

set +e
(
  cd "$fixture_root"
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${V04_MEASURE_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${V04_MEASURE_STARTUP_ENV_EXPORT_MARKER:?}"
    exit 97
  }
  export -f set
  PATH="$startup_clean_bin:$PATH" \
    FAKE_SWIFT_LOG="$fake_swift_log" \
    FAKE_DOGFOOD_LOG="$marker_dir/dogfood-startup-env" \
    LITHEPG_MEASURE_OUT_DIR="$startup_env_out_dir" \
    V04_MEASURE_SHADOW_MARKER_DIR="$marker_dir" \
    V04_MEASURE_SHADOW_ASSERT_HELPER="$fixture_root/assert_no_shadow_functions.sh" \
    V04_MEASURE_COMMAND_SHADOW_SENTINEL="$command_sentinel" \
    V04_MEASURE_BUILTIN_SHADOW_SENTINEL="$builtin_sentinel" \
    V04_MEASURE_CD_SHADOW_SENTINEL="$cd_sentinel" \
    V04_MEASURE_PWD_SHADOW_SENTINEL="$pwd_sentinel" \
    V04_MEASURE_DOCKER_SHADOW_SENTINEL="$docker_sentinel" \
    V04_MEASURE_KILL_SHADOW_SENTINEL="$kill_sentinel" \
    V04_MEASURE_SLEEP_SHADOW_SENTINEL="$sleep_sentinel" \
    V04_MEASURE_STARTUP_ENV_SHADOW_SENTINEL="$startup_env_shadow_sentinel" \
    V04_MEASURE_STARTUP_ENV_BASH_MARKER="$startup_env_bash_marker" \
    V04_MEASURE_STARTUP_ENV_EXPORT_MARKER="$startup_env_export_marker" \
    BASH_ENV="$startup_env_bash_file" \
    "$fixture_root/script/v04_measure.sh"
) >"$output_file" 2>&1
startup_env_shadow_status=$?
set -e
startup_env_shadow_output="$(<"$output_file")"
if [[ "$startup_env_shadow_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_env_shadow_output" >&2
  fail "v04_measure.sh executable startup was affected by BASH_ENV or exported shell functions"
fi
assert_not_contains "$startup_env_shadow_output" "$startup_env_shadow_sentinel"
assert_not_contains "$startup_env_shadow_output" "set function invoked"
assert_contains "$startup_env_shadow_output" "fake app build passed"
assert_contains "$startup_env_shadow_output" "fake bench build passed"
assert_contains "$startup_env_shadow_output" "Measurements written to $startup_env_out_dir"
[[ ! -e "$startup_env_bash_marker" ]] || fail "v04_measure.sh invoked BASH_ENV-defined set function: $(<"$startup_env_bash_marker")"
[[ ! -e "$startup_env_export_marker" ]] || fail "v04_measure.sh invoked exported set function: $(<"$startup_env_export_marker")"
summary_file="$startup_env_out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "startup-env summary.json missing: $summary_file"
assert_summary_json "$summary_file" "$startup_env_out_dir" "$expected_root/.build/release/LithePGApp"

startup_perl_sentinel="V04_MEASURE_PERL_STARTUP_SHADOW_SENTINEL_SHOULD_NOT_RUN"
startup_perl_lib="$fixture_root/v04-measure-perl-lib"
startup_perl_marker="$fixture_root/v04-measure-perl-marker"
startup_perl_out_dir="$fixture_root/out/startup-perl-v04-measure"
/bin/mkdir -p "$startup_perl_lib"
/bin/cat >"$startup_perl_lib/V04MeasurePerlStartupPoison.pm" <<'PERLPOISON'
BEGIN {
  open my $fh, '>', $ENV{V04_MEASURE_PERL_STARTUP_MARKER} or die $!;
  print {$fh} "perl-startup\n";
  close $fh;
  die "$ENV{V04_MEASURE_PERL_STARTUP_SHADOW_SENTINEL} Perl startup invoked\n";
}
1;
PERLPOISON

set +e
(
  cd "$fixture_root"
  PATH="$startup_clean_bin:$PATH" \
    FAKE_SWIFT_LOG="$fake_swift_log" \
    FAKE_DOGFOOD_LOG="$marker_dir/dogfood-startup-perl" \
    LITHEPG_MEASURE_OUT_DIR="$startup_perl_out_dir" \
    V04_MEASURE_SHADOW_MARKER_DIR="$marker_dir" \
    V04_MEASURE_SHADOW_ASSERT_HELPER="$fixture_root/assert_no_shadow_functions.sh" \
    V04_MEASURE_COMMAND_SHADOW_SENTINEL="$command_sentinel" \
    V04_MEASURE_BUILTIN_SHADOW_SENTINEL="$builtin_sentinel" \
    V04_MEASURE_CD_SHADOW_SENTINEL="$cd_sentinel" \
    V04_MEASURE_PWD_SHADOW_SENTINEL="$pwd_sentinel" \
    V04_MEASURE_DOCKER_SHADOW_SENTINEL="$docker_sentinel" \
    V04_MEASURE_KILL_SHADOW_SENTINEL="$kill_sentinel" \
    V04_MEASURE_SLEEP_SHADOW_SENTINEL="$sleep_sentinel" \
    V04_MEASURE_PERL_STARTUP_MARKER="$startup_perl_marker" \
    V04_MEASURE_PERL_STARTUP_SHADOW_SENTINEL="$startup_perl_sentinel" \
    PERL5LIB="$startup_perl_lib" \
    PERLLIB="$startup_perl_lib" \
    PERL5OPT=-MV04MeasurePerlStartupPoison \
    "$fixture_root/script/v04_measure.sh"
) >"$output_file" 2>&1
startup_perl_status=$?
set -e
startup_perl_output="$(<"$output_file")"
if [[ "$startup_perl_status" -ne 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_perl_output" >&2
  fail "v04_measure.sh executable startup left Perl startup environment unsanitized"
fi
assert_not_contains "$startup_perl_output" "$startup_perl_sentinel"
assert_not_contains "$startup_perl_output" "Perl startup invoked"
assert_contains "$startup_perl_output" "fake app build passed"
assert_contains "$startup_perl_output" "fake bench build passed"
assert_contains "$startup_perl_output" "Measurements written to $startup_perl_out_dir"
[[ ! -e "$startup_perl_marker" ]] || fail "v04_measure.sh honored Perl startup environment: $(<"$startup_perl_marker")"
summary_file="$startup_perl_out_dir/summary.json"
[[ -f "$summary_file" ]] || fail "startup-perl summary.json missing: $summary_file"
assert_summary_json "$summary_file" "$startup_perl_out_dir" "$expected_root/.build/release/LithePGApp"

startup_fail_closed_out_dir="$fixture_root/out/startup-fail-closed-v04-measure"
set +e
(
  cd "$fixture_root"
  PATH="$startup_clean_bin:$PATH" \
    FAKE_SWIFT_LOG="$fake_swift_log" \
    LITHEPG_MEASURE_OUT_DIR="$startup_fail_closed_out_dir" \
    LITHEPG_V04_MEASURE_STARTUP_ENV_SANITIZED=1 \
    PERL5OPT=-MV04MeasureSanitizerShouldFailClosed \
    "$fixture_root/script/v04_measure.sh"
) >"$output_file" 2>&1
startup_fail_closed_status=$?
set -e
startup_fail_closed_output="$(<"$output_file")"
if [[ "$startup_fail_closed_status" -eq 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_fail_closed_output" >&2
  fail "v04_measure.sh startup sanitizer did not fail closed when sanitized marker still had dirty env"
elif [[ "$startup_fail_closed_status" -ne 2 ]]; then
  /usr/bin/printf '%s\n' "$startup_fail_closed_output" >&2
  fail "v04_measure.sh startup sanitizer fail-closed exit was $startup_fail_closed_status, expected 2"
fi
assert_contains "$startup_fail_closed_output" "unsanitized startup environment remains after v04_measure sanitizer"
assert_not_contains "$startup_fail_closed_output" "fake app build passed"
assert_not_contains "$startup_fail_closed_output" '"outDir":'

empty_bash_env_fail_closed_private_sentinel="V04_MEASURE_EMPTY_BASH_ENV_PRIVATE_SENTINEL_SHOULD_NOT_LEAK"
empty_bash_env_fail_closed_out_dir="$fixture_root/out/empty-bash-env-fail-closed-v04-measure"
empty_bash_env_fail_closed_swift_log="$fixture_root/empty-bash-env-fail-closed-swift.log"
set +e
(
  cd "$fixture_root"
  PATH="$startup_clean_bin:$PATH" \
    FAKE_SWIFT_LOG="$empty_bash_env_fail_closed_swift_log" \
    FAKE_DOGFOOD_LOG="$marker_dir/dogfood-empty-bash-env-fail-closed" \
    LITHEPG_MEASURE_OUT_DIR="$empty_bash_env_fail_closed_out_dir" \
    LITHEPG_V04_MEASURE_STARTUP_ENV_SANITIZED=1 \
    V04_MEASURE_EMPTY_BASH_ENV_PRIVATE_SENTINEL="$empty_bash_env_fail_closed_private_sentinel" \
    BASH_ENV="" \
    "$fixture_root/script/v04_measure.sh"
) >"$output_file" 2>&1
empty_bash_env_fail_closed_status=$?
set -e
empty_bash_env_fail_closed_output="$(<"$output_file")"
if [[ "$empty_bash_env_fail_closed_status" -ne 2 ]]; then
  /usr/bin/printf '%s\n' "$empty_bash_env_fail_closed_output" >&2
  fail "v04_measure.sh sanitizer marker with exported empty BASH_ENV should exit 2, got $empty_bash_env_fail_closed_status"
fi
if [[ "$empty_bash_env_fail_closed_output" != "unsanitized startup environment remains after v04_measure sanitizer" ]]; then
  /usr/bin/printf '%s\n' "$empty_bash_env_fail_closed_output" >&2
  fail "v04_measure.sh sanitizer empty BASH_ENV fail-closed output was not generic and redacted"
fi
assert_not_contains "$empty_bash_env_fail_closed_output" "$empty_bash_env_fail_closed_private_sentinel"
assert_not_contains "$empty_bash_env_fail_closed_output" "fake dogfood postgres ready"
assert_not_contains "$empty_bash_env_fail_closed_output" "fake app build passed"
assert_not_contains "$empty_bash_env_fail_closed_output" "fake bench build passed"
assert_not_contains "$empty_bash_env_fail_closed_output" '"outDir":'
[[ ! -s "$empty_bash_env_fail_closed_swift_log" ]] || fail "sanitizer empty BASH_ENV fail-closed invoked fake swift: $(<"$empty_bash_env_fail_closed_swift_log")"
[[ ! -s "$marker_dir/dogfood-empty-bash-env-fail-closed" ]] || fail "sanitizer empty BASH_ENV fail-closed invoked fake dogfood: $(<"$marker_dir/dogfood-empty-bash-env-fail-closed")"
[[ ! -e "$empty_bash_env_fail_closed_out_dir" ]] || fail "sanitizer empty BASH_ENV fail-closed created out dir: $empty_bash_env_fail_closed_out_dir"
[[ ! -e "$empty_bash_env_fail_closed_out_dir/summary.json" ]] || fail "sanitizer empty BASH_ENV fail-closed wrote summary.json"

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
