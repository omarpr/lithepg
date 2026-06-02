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
  local marker_dir="$6"
  local command_sentinel="$7"
  local builtin_sentinel="$8"
  local cd_sentinel="$9"
  local pwd_sentinel="${10}"
  local exec_sentinel="${11}"
  local startup_bash_env="${12:-}"
  local startup_perl_lib="${13:-}"
  local startup_perl_opt="${14:-}"
  local startup_sanitized_guard="${15:-}"

  set +e
  (
    cd "$fixture_root"
    command() {
      /usr/bin/printf '%s command invoked\n' "${DOGFOOD_CHECK_COMMAND_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'command\n' >"${DOGFOOD_CHECK_SHADOW_MARKER_DIR:?}/command"
      exit 97
    }
    builtin() {
      /usr/bin/printf '%s builtin invoked\n' "${DOGFOOD_CHECK_BUILTIN_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'builtin\n' >"${DOGFOOD_CHECK_SHADOW_MARKER_DIR:?}/builtin"
      exit 97
    }
    cd() {
      /usr/bin/printf '%s cd invoked\n' "${DOGFOOD_CHECK_CD_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'cd\n' >"${DOGFOOD_CHECK_SHADOW_MARKER_DIR:?}/cd"
      exit 97
    }
    pwd() {
      /usr/bin/printf '%s pwd invoked\n' "${DOGFOOD_CHECK_PWD_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'pwd\n' >"${DOGFOOD_CHECK_SHADOW_MARKER_DIR:?}/pwd"
      exit 97
    }
    exec() {
      /usr/bin/printf '%s exec invoked\n' "${DOGFOOD_CHECK_EXEC_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'exec\n' >"${DOGFOOD_CHECK_SHADOW_MARKER_DIR:?}/exec"
      exit 97
    }
    export -f command
    export -f builtin
    export -f cd
    export -f pwd
    export -f exec
    if [[ -n "$startup_bash_env" ]]; then
      export BASH_ENV="$startup_bash_env"
    else
      unset BASH_ENV
    fi
    if [[ -n "$startup_perl_lib" ]]; then
      export PERL5LIB="$startup_perl_lib"
      export PERLLIB="$startup_perl_lib"
      export PERL5OPT="$startup_perl_opt"
    else
      unset PERL5OPT PERL5LIB PERLLIB
    fi
    if [[ -n "$startup_sanitized_guard" ]]; then
      export LITHEPG_DOGFOOD_CHECK_STARTUP_ENV_SANITIZED="$startup_sanitized_guard"
    else
      unset LITHEPG_DOGFOOD_CHECK_STARTUP_ENV_SANITIZED
    fi
    /usr/bin/env -u POSTGRES_TEST_URL \
      PATH="$fake_bin:$PATH" \
      DEVELOPER_DIR="$developer_dir" \
      LITHEPG_DOGFOOD_PORT="55432" \
      "LITHEPG_DOGFOOD_PASSWORD=$fixture_database_credential" \
      LITHEPG_DOGFOOD_DATABASE="postgres" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      FAKE_MEASURE_LOG="$fake_measure_log" \
      DOGFOOD_CHECK_SHADOW_MARKER_DIR="$marker_dir" \
      DOGFOOD_CHECK_COMMAND_SHADOW_SENTINEL="$command_sentinel" \
      DOGFOOD_CHECK_BUILTIN_SHADOW_SENTINEL="$builtin_sentinel" \
      DOGFOOD_CHECK_CD_SHADOW_SENTINEL="$cd_sentinel" \
      DOGFOOD_CHECK_PWD_SHADOW_SENTINEL="$pwd_sentinel" \
      DOGFOOD_CHECK_EXEC_SHADOW_SENTINEL="$exec_sentinel" \
      DOGFOOD_CHECK_STARTUP_ENV_SHADOW_SENTINEL="$startup_env_shadow_sentinel" \
      DOGFOOD_CHECK_STARTUP_ENV_BASH_MARKER="$startup_env_bash_marker" \
      DOGFOOD_CHECK_STARTUP_ENV_PERL_MARKER="$startup_env_perl_marker" \
      DOGFOOD_CHECK_PERL_STARTUP_SHADOW_SENTINEL="$perl_startup_shadow_sentinel" \
      DOGFOOD_CHECK_PERL_STARTUP_MARKER="$perl_startup_perl_marker" \
      "$fixture_root/script/dogfood_check.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

run_helper_capture_empty_bash_env_guard() {
  local output_file="$1"
  local fixture_root="$2"
  local fake_bin="$3"
  local fake_swift_log="$4"
  local developer_dir="$5"

  set +e
  (
    cd "$fixture_root"
    export BASH_ENV=""
    export LITHEPG_DOGFOOD_CHECK_STARTUP_ENV_SANITIZED=1
    unset PERL5OPT PERL5LIB PERLLIB
    /usr/bin/env -u POSTGRES_TEST_URL \
      PATH="$fake_bin:$PATH" \
      DEVELOPER_DIR="$developer_dir" \
      LITHEPG_DOGFOOD_PORT="55432" \
      "LITHEPG_DOGFOOD_PASSWORD=$fixture_database_credential" \
      LITHEPG_DOGFOOD_DATABASE="postgres" \
      FAKE_SWIFT_LOG="$fake_swift_log" \
      FAKE_MEASURE_LOG="$fake_measure_log" \
      "$fixture_root/script/dogfood_check.sh"
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
  local expected_branch="$2"
  local expected_commit="$3"
  /usr/bin/python3 - "$status_file" "$expected_branch" "$expected_commit" <<'PY'
import json
import pathlib
import sys

status = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert status["branch"] == sys.argv[2], status
assert status["commit"] == sys.argv[3], status
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
git_sentinel="DOGFOOD_CHECK_GIT_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
command_sentinel="DOGFOOD_CHECK_COMMAND_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
builtin_sentinel="DOGFOOD_CHECK_BUILTIN_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
cd_sentinel="DOGFOOD_CHECK_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
pwd_sentinel="DOGFOOD_CHECK_PWD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
exec_sentinel="DOGFOOD_CHECK_EXEC_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
startup_env_shadow_sentinel="DOGFOOD_CHECK_STARTUP_ENV_SHADOW_SENTINEL_SHOULD_NOT_RUN"
perl_startup_shadow_sentinel="DOGFOOD_CHECK_PERL_STARTUP_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
fake_swift_log="$fixture_root/fake-swift.log"
fake_measure_log="$fixture_root/fake-measure.log"
marker_dir="$fixture_root/shadow-markers"
startup_env_bash_file="$fixture_root/dogfood-check-bash-env"
startup_env_bash_marker="$fixture_root/dogfood-check-bash-env-marker"
startup_env_perl_lib="$fixture_root/dogfood-check-startup-perl-lib"
startup_env_perl_marker="$fixture_root/dogfood-check-startup-perl-marker"
perl_startup_perl_lib="$fixture_root/dogfood-check-perl-only-lib"
perl_startup_perl_marker="$fixture_root/dogfood-check-perl-only-marker"
developer_dir="$(/usr/bin/xcode-select -p)"
fixture_database_credential="postgres"
/bin/mkdir -p "$fixture_root/script" "$fake_bin" "$marker_dir" "$startup_env_perl_lib" "$perl_startup_perl_lib"
/usr/bin/git -C "$fixture_root" init -q
/usr/bin/git -C "$fixture_root" config user.email dogfood-check-test@example.invalid
/usr/bin/git -C "$fixture_root" config user.name 'Dogfood Check Test'
/usr/bin/git -C "$fixture_root" checkout -q -b dogfood-check-test
/bin/cat >"$fixture_root/README.md" <<'README'
dogfood check fixture
README
/usr/bin/git -C "$fixture_root" add README.md
/usr/bin/git -C "$fixture_root" commit -q -m 'fixture commit'
expected_branch="$(/usr/bin/git -C "$fixture_root" branch --show-current)"
expected_commit="$(/usr/bin/git -C "$fixture_root" rev-parse --short HEAD)"
/bin/cp "$HELPER" "$fixture_root/script/dogfood_check.sh"
/bin/chmod +x "$fixture_root/script/dogfood_check.sh"

/bin/cat >"$startup_env_bash_file" <<'BASHENV'
set() {
  /usr/bin/printf '%s BASH_ENV set function invoked\n' "${DOGFOOD_CHECK_STARTUP_ENV_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'bash-env\n' >"${DOGFOOD_CHECK_STARTUP_ENV_BASH_MARKER:?}"
  exit 97
}
BASHENV

/bin/cat >"$startup_env_perl_lib/DogfoodCheckStartupPoison.pm" <<'PERLMOD'
package DogfoodCheckStartupPoison;
BEGIN {
  my $sentinel = $ENV{DOGFOOD_CHECK_STARTUP_ENV_SHADOW_SENTINEL} // '';
  my $marker = $ENV{DOGFOOD_CHECK_STARTUP_ENV_PERL_MARKER} // '';
  if ($marker ne '' && open(my $fh, '>', $marker)) {
    print {$fh} "perl\n";
    close $fh;
  }
  print STDERR "$sentinel Perl startup invoked\n";
  exit 97;
}
1;
PERLMOD

/bin/cat >"$perl_startup_perl_lib/DogfoodCheckPerlStartupPoison.pm" <<'PERLMOD'
package DogfoodCheckPerlStartupPoison;
BEGIN {
  my $sentinel = $ENV{DOGFOOD_CHECK_PERL_STARTUP_SHADOW_SENTINEL} // '';
  my $marker = $ENV{DOGFOOD_CHECK_PERL_STARTUP_MARKER} // '';
  if ($marker ne '' && open(my $fh, '>', $marker)) {
    print {$fh} "perl\n";
    close $fh;
  }
  print STDERR "$sentinel Perl startup invoked\n";
  exit 97;
}
1;
PERLMOD

for tool in dirname date mkdir cat realpath; do
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
check_no_exported_function_shadows() {
  /usr/bin/perl -e '
    use strict;
    use warnings;
    my %sentinel_for = (
      command => $ENV{DOGFOOD_CHECK_COMMAND_SHADOW_SENTINEL} // "",
      builtin => $ENV{DOGFOOD_CHECK_BUILTIN_SHADOW_SENTINEL} // "",
      cd => $ENV{DOGFOOD_CHECK_CD_SHADOW_SENTINEL} // "",
      pwd => $ENV{DOGFOOD_CHECK_PWD_SHADOW_SENTINEL} // "",
      exec => $ENV{DOGFOOD_CHECK_EXEC_SHADOW_SENTINEL} // "",
    );
    my $marker_dir = $ENV{DOGFOOD_CHECK_SHADOW_MARKER_DIR} // "";
    for my $key (keys %ENV) {
      next unless $key =~ /\ABASH_FUNC_(.*)%%\z/;
      my $name = $1;
      next unless exists $sentinel_for{$name};
      if ($marker_dir ne "") {
        open my $fh, ">", "$marker_dir/$name" or die "marker: $!\n";
        print {$fh} "$name\n";
      }
      print STDERR "$sentinel_for{$name} exported function inherited by fake swift\n";
      exit 97;
    }
  '
}
check_no_exported_function_shadows
/usr/bin/printf 'fake swift %s\n' "$*" >>"${FAKE_SWIFT_LOG:?}"
if [[ "${POSTGRES_TEST_URL+x}" == "x" ]]; then
  /usr/bin/printf 'fake swift POSTGRES_TEST_URL=%s\n' "$POSTGRES_TEST_URL" >>"${FAKE_SWIFT_LOG:?}"
else
  /usr/bin/printf 'fake swift POSTGRES_TEST_URL=<unset>\n' >>"${FAKE_SWIFT_LOG:?}"
fi
SWIFT
/bin/chmod +x "$fake_bin/swift"

/bin/cat >"$fake_bin/git" <<GIT
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s git invoked\\n' '$git_sentinel' >&2
/usr/bin/printf 'git\\n' >'$marker_dir/git'
if [[ "\${1:-}" == "-C" ]]; then
  shift 2
fi
case "\$*" in
  "rev-parse --short HEAD")
    /usr/bin/printf '%s\n' '$expected_commit'
    ;;
  "branch --show-current")
    /usr/bin/printf '%s\n' '$expected_branch'
    ;;
  *)
    /usr/bin/printf 'unexpected fake git invocation: %s\n' "\$*" >&2
    exit 98
    ;;
esac
GIT
/bin/chmod +x "$fake_bin/git"

/bin/cat >"$fake_bin/python3" <<PYTHON
#!/bin/bash
/usr/bin/printf '%s python3 invoked\\n' '$sentinel' >&2
/usr/bin/printf 'python3\\n' >'$marker_dir/python3'
exit 99
PYTHON
/bin/chmod +x "$fake_bin/python3"

/bin/cat >"$fixture_root/script/dogfood_postgres.sh" <<'DOGFOOD'
#!/bin/bash
set -euo pipefail
check_no_exported_function_shadows() {
  /usr/bin/perl -e '
    use strict;
    use warnings;
    my %sentinel_for = (
      command => $ENV{DOGFOOD_CHECK_COMMAND_SHADOW_SENTINEL} // "",
      builtin => $ENV{DOGFOOD_CHECK_BUILTIN_SHADOW_SENTINEL} // "",
      cd => $ENV{DOGFOOD_CHECK_CD_SHADOW_SENTINEL} // "",
      pwd => $ENV{DOGFOOD_CHECK_PWD_SHADOW_SENTINEL} // "",
      exec => $ENV{DOGFOOD_CHECK_EXEC_SHADOW_SENTINEL} // "",
    );
    my $marker_dir = $ENV{DOGFOOD_CHECK_SHADOW_MARKER_DIR} // "";
    for my $key (keys %ENV) {
      next unless $key =~ /\ABASH_FUNC_(.*)%%\z/;
      my $name = $1;
      next unless exists $sentinel_for{$name};
      if ($marker_dir ne "") {
        open my $fh, ">", "$marker_dir/$name" or die "marker: $!\n";
        print {$fh} "$name\n";
      }
      print STDERR "$sentinel_for{$name} exported function inherited by fake dogfood_postgres\n";
      exit 97;
    }
  '
}
check_no_exported_function_shadows
/usr/bin/printf 'fake dogfood postgres started\n'
DOGFOOD
/bin/chmod +x "$fixture_root/script/dogfood_postgres.sh"

/bin/cat >"$fixture_root/script/v04_measure.sh" <<'MEASURE'
#!/bin/bash
set -euo pipefail
check_no_exported_function_shadows() {
  /usr/bin/perl -e '
    use strict;
    use warnings;
    my %sentinel_for = (
      command => $ENV{DOGFOOD_CHECK_COMMAND_SHADOW_SENTINEL} // "",
      builtin => $ENV{DOGFOOD_CHECK_BUILTIN_SHADOW_SENTINEL} // "",
      cd => $ENV{DOGFOOD_CHECK_CD_SHADOW_SENTINEL} // "",
      pwd => $ENV{DOGFOOD_CHECK_PWD_SHADOW_SENTINEL} // "",
      exec => $ENV{DOGFOOD_CHECK_EXEC_SHADOW_SENTINEL} // "",
    );
    my $marker_dir = $ENV{DOGFOOD_CHECK_SHADOW_MARKER_DIR} // "";
    for my $key (keys %ENV) {
      next unless $key =~ /\ABASH_FUNC_(.*)%%\z/;
      my $name = $1;
      next unless exists $sentinel_for{$name};
      if ($marker_dir ne "") {
        open my $fh, ">", "$marker_dir/$name" or die "marker: $!\n";
        print {$fh} "$name\n";
      }
      print STDERR "$sentinel_for{$name} exported function inherited by fake v04_measure\n";
      exit 97;
    }
  '
}
check_no_exported_function_shadows
/usr/bin/printf 'fake v04_measure POSTGRES_TEST_URL=%s\n' "${POSTGRES_TEST_URL-<unset>}" >>"${FAKE_MEASURE_LOG:?}"
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

if run_helper_capture_empty_bash_env_guard "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$developer_dir"; then
  empty_bash_env_fail_closed_status=0
else
  empty_bash_env_fail_closed_status=$?
fi
empty_bash_env_fail_closed_output="$(<"$output_file")"
if [[ "$empty_bash_env_fail_closed_status" -eq 0 ]]; then
  /usr/bin/printf '%s\n' "$empty_bash_env_fail_closed_output" >&2
  fail "dogfood_check.sh startup sanitizer did not fail closed when guard was set with exported empty BASH_ENV"
fi
assert_contains "$empty_bash_env_fail_closed_output" "unsanitized startup environment remains after dogfood_check sanitizer"
assert_not_contains "$empty_bash_env_fail_closed_output" "Starting dogfood Postgres"

if run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$developer_dir" "$marker_dir" "$command_sentinel" "$builtin_sentinel" "$cd_sentinel" "$pwd_sentinel" "$exec_sentinel" "" "" "" "1"; then
  startup_fail_closed_status=0
else
  startup_fail_closed_status=$?
fi
startup_fail_closed_output="$(<"$output_file")"
if [[ "$startup_fail_closed_status" -eq 0 ]]; then
  /usr/bin/printf '%s\n' "$startup_fail_closed_output" >&2
  fail "dogfood_check.sh startup sanitizer did not fail closed when guard was set with dirty env"
fi
assert_contains "$startup_fail_closed_output" "unsanitized startup environment remains after dogfood_check sanitizer"
assert_not_contains "$startup_fail_closed_output" "Starting dogfood Postgres"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$developer_dir" "$marker_dir" "$command_sentinel" "$builtin_sentinel" "$cd_sentinel" "$pwd_sentinel" "$exec_sentinel" "" "$perl_startup_perl_lib" "-MDogfoodCheckPerlStartupPoison"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "dogfood_check.sh left Perl startup environment unsanitized"
fi

perl_startup_output="$(<"$output_file")"
assert_not_contains "$perl_startup_output" "$perl_startup_shadow_sentinel"
assert_not_contains "$perl_startup_output" "Perl startup invoked"
[[ ! -e "$perl_startup_perl_marker" ]] || fail "dogfood_check.sh honored Perl startup environment: $(<"$perl_startup_perl_marker")"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$developer_dir" "$marker_dir" "$command_sentinel" "$builtin_sentinel" "$cd_sentinel" "$pwd_sentinel" "$exec_sentinel" "$startup_env_bash_file" "$startup_env_perl_lib" "-MDogfoodCheckStartupPoison"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "dogfood_check.sh was affected by PATH-shadowed core utilities or startup environment"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" "$git_sentinel"
assert_not_contains "$helper_output" "$command_sentinel"
assert_not_contains "$helper_output" "$builtin_sentinel"
assert_not_contains "$helper_output" "$cd_sentinel"
assert_not_contains "$helper_output" "$pwd_sentinel"
assert_not_contains "$helper_output" "$exec_sentinel"
assert_not_contains "$helper_output" "$startup_env_shadow_sentinel"
assert_not_contains "$helper_output" "BASH_ENV set function invoked"
assert_not_contains "$helper_output" "Perl startup invoked"
assert_not_contains "$helper_output" " invoked"
assert_contains "$helper_output" '"defaultSwiftTest": "passed"'
assert_contains "$helper_output" '"liveSwiftTest": "passed"'
assert_contains "$helper_output" '"v04Measure": "passed"'
assert_contains "$helper_output" '"postgresTestURLLabel": "postgres@localhost:55432/postgres"'
assert_not_contains "$helper_output" "postgres:postgres@"

[[ -s "$fake_swift_log" ]] || fail "fake swift was not used"
fake_swift_output="$(<"$fake_swift_log")"
expected_default_postgres_test_url="postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable"
redacted_default_postgres_test_url="postgres://postgres:***@localhost:55432/postgres?sslmode=disable"
assert_contains "$fake_swift_output" "fake swift test"
assert_contains "$fake_swift_output" "fake swift POSTGRES_TEST_URL=<unset>"
assert_contains "$fake_swift_output" "fake swift test --filter"
[[ "$fake_swift_output" == *"fake swift POSTGRES_TEST_URL=$expected_default_postgres_test_url"* ]] || fail "live Swift did not receive default POSTGRES_TEST_URL with real password"
assert_not_contains "$fake_swift_output" "$redacted_default_postgres_test_url"

[[ -s "$fake_measure_log" ]] || fail "fake v04_measure was not used"
fake_measure_output="$(<"$fake_measure_log")"
[[ "$fake_measure_output" == *"fake v04_measure POSTGRES_TEST_URL=$expected_default_postgres_test_url"* ]] || fail "v04_measure did not receive default POSTGRES_TEST_URL with real password"
assert_not_contains "$fake_measure_output" "$redacted_default_postgres_test_url"

out_dir="$(extract_out_dir "$output_file")" || fail "helper output did not include output directory"
status_file="$out_dir/status.json"
[[ -f "$status_file" ]] || fail "status.json missing: $status_file"
assert_status_json "$status_file" "$expected_branch" "$expected_commit"
status_json="$(<"$status_file")"
assert_contains "$status_json" '"postgresTestURLLabel": "postgres@localhost:55432/postgres"'
assert_not_contains "$status_json" "postgres:postgres@"

quoted_branch='dogfood-check-quote"branch'
/usr/bin/git -C "$fixture_root" checkout -q -b "$quoted_branch"
if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$fake_swift_log" "$developer_dir" "$marker_dir" "$command_sentinel" "$builtin_sentinel" "$cd_sentinel" "$pwd_sentinel" "$exec_sentinel" "$startup_env_bash_file" "$startup_env_perl_lib" "-MDogfoodCheckStartupPoison"; then
  helper_output="$(<"$output_file")"
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "dogfood_check.sh could not write valid status.json for quoted git branch"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" "$git_sentinel"
assert_not_contains "$helper_output" "$startup_env_shadow_sentinel"
assert_not_contains "$helper_output" "Perl startup invoked"
assert_not_contains "$helper_output" " invoked"
assert_not_contains "$helper_output" "postgres:postgres@"
quoted_out_dir="$(extract_out_dir "$output_file")" || fail "helper output did not include output directory for quoted branch run"
quoted_status_file="$quoted_out_dir/status.json"
[[ -f "$quoted_status_file" ]] || fail "status.json missing for quoted branch run: $quoted_status_file"
assert_status_json "$quoted_status_file" "$quoted_branch" "$expected_commit"
quoted_status_json="$(<"$quoted_status_file")"
assert_contains "$quoted_status_json" 'dogfood-check-quote\"branch'
assert_contains "$quoted_status_json" '"postgresTestURLLabel": "postgres@localhost:55432/postgres"'
assert_not_contains "$quoted_status_json" "postgres:postgres@"

for tool in dirname date mkdir cat realpath python3 git command builtin cd pwd exec; do
  [[ ! -e "$marker_dir/$tool" ]] || fail "dogfood_check.sh invoked shadowed $tool"
done
[[ ! -e "$startup_env_bash_marker" ]] || fail "dogfood_check.sh invoked BASH_ENV-defined set function: $(<"$startup_env_bash_marker")"
[[ ! -e "$startup_env_perl_marker" ]] || fail "dogfood_check.sh honored startup Perl environment: $(<"$startup_env_perl_marker")"

/usr/bin/printf 'test_dogfood_check passed\n'
