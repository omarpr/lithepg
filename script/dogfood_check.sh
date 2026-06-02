#!/bin/bash -p

BASH_BIN=/bin/bash
PERL_BIN=/usr/bin/perl
DIRNAME_BIN=/usr/bin/dirname
REALPATH_BIN=/bin/realpath
DATE_BIN=/bin/date
MKDIR_BIN=/bin/mkdir
CAT_BIN=/bin/cat
PYTHON3_BIN=/usr/bin/python3
GIT_BIN=/usr/bin/git

startup_env_sanitize_needed=0
if [[ "${BASH_ENV+x}" == x || "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
  startup_env_sanitize_needed=1
elif /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
  for my $key (keys %ENV) {
    exit 0 if $key =~ /\ABASH_FUNC_/;
  }
  exit 1;
'; then
  startup_env_sanitize_needed=1
fi

if [[ "$startup_env_sanitize_needed" == "1" ]]; then
  if [[ "${LITHEPG_DOGFOOD_CHECK_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after dogfood_check sanitizer\n' >&2
    exit 2
  fi
  /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
    use strict;
    use warnings;
    my $bash = shift @ARGV;
    for my $key (keys %ENV) {
      delete $ENV{$key} if $key =~ /\ABASH_FUNC_/;
    }
    delete $ENV{BASH_ENV};
    delete $ENV{PERL5OPT};
    delete $ENV{PERL5LIB};
    delete $ENV{PERLLIB};
    $ENV{LITHEPG_DOGFOOD_CHECK_STARTUP_ENV_SANITIZED} = "1";
    exec { $bash } $bash, "-p", @ARGV;
    die "exec $bash: $!\n";
  ' "$BASH_BIN" "${BASH_SOURCE[0]}" "$@"
  exit $?
fi

if [[ "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
  /usr/bin/printf 'unsanitized Perl startup environment remains\n' >&2
  exit 2
elif ! /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
  for my $key (keys %ENV) {
    die "unsanitized bash function environment key remains: $key\n" if $key =~ /\ABASH_FUNC_/;
  }
  die "unsanitized BASH_ENV remains\n" if exists $ENV{BASH_ENV};
  exit 0;
'; then
  exit 2
fi

set -euo pipefail

ROOT_DIR="$("$REALPATH_BIN" "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")/..")"

sanitized_exec() {
  "$PERL_BIN" -e '
    use strict;
    use warnings;
    for my $key (keys %ENV) {
      delete $ENV{$key} if $key =~ /\ABASH_FUNC_/;
    }
    @ARGV or die "exec: missing command\n";
    exec { $ARGV[0] } @ARGV;
    die "exec $ARGV[0]: $!\n";
  ' "$@"
}

run_from_root() {
  "$PERL_BIN" -e '
    use strict;
    use warnings;
    for my $key (keys %ENV) {
      delete $ENV{$key} if $key =~ /\ABASH_FUNC_/;
    }
    my $root = shift @ARGV;
    chdir($root) or die "chdir failed\n";
    $ENV{PWD} = $root;
    @ARGV or die "exec: missing command\n";
    exec { $ARGV[0] } @ARGV or die "exec failed\n";
  ' "$ROOT_DIR" "$@"
}

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

DOGFOOD_PORT="${LITHEPG_DOGFOOD_PORT:-55432}"
DOGFOOD_PASSWORD="${LITHEPG_DOGFOOD_PASSWORD:-postgres}"
DOGFOOD_DATABASE="${LITHEPG_DOGFOOD_DATABASE:-postgres}"
POSTGRES_TEST_URL="${POSTGRES_TEST_URL:-postgres://postgres:$DOGFOOD_PASSWORD@localhost:$DOGFOOD_PORT/$DOGFOOD_DATABASE?sslmode=disable}"
OUT_DIR="${LITHEPG_DOGFOOD_CHECK_OUT_DIR:-$ROOT_DIR/.build/dogfood-checks/$("$DATE_BIN" +%Y%m%d-%H%M%S)}"
"$MKDIR_BIN" -p "$OUT_DIR"

printf 'Starting dogfood Postgres...\n'
sanitized_exec "$ROOT_DIR/script/dogfood_postgres.sh" > "$OUT_DIR/dogfood-postgres.log"

printf 'Running default test suite...\n'
DEVELOPER_DIR="$DEVELOPER_DIR" run_from_root swift test > "$OUT_DIR/swift-test.log" 2>&1

printf 'Running live dogfood test slice...\n'
POSTGRES_TEST_URL="$POSTGRES_TEST_URL" \
DEVELOPER_DIR="$DEVELOPER_DIR" \
run_from_root swift test --filter 'saved connection flow|query history records|connects through AppState|refresh schema|reconnect|live|Live' \
  > "$OUT_DIR/live-swift-test.log" 2>&1

printf 'Running v0.4 measurement gate...\n'
LITHEPG_MEASURE_OUT_DIR="$OUT_DIR/v04-measure" \
POSTGRES_TEST_URL="$POSTGRES_TEST_URL" \
DEVELOPER_DIR="$DEVELOPER_DIR" \
sanitized_exec "$ROOT_DIR/script/v04_measure.sh" > "$OUT_DIR/v04-measure.log" 2>&1

COMMIT="$("$GIT_BIN" -C "$ROOT_DIR" rev-parse --short HEAD)"
BRANCH="$("$GIT_BIN" -C "$ROOT_DIR" branch --show-current)"
"$PYTHON3_BIN" - "$OUT_DIR" "$BRANCH" "$COMMIT" "$DOGFOOD_PORT" "$DOGFOOD_DATABASE" <<'PY' > "$OUT_DIR/status.json"
import json, pathlib, datetime, sys
out_dir, branch, commit, dogfood_port, dogfood_database = sys.argv[1:6]
root = pathlib.Path(out_dir)
summary = json.loads((root / "v04-measure" / "summary.json").read_text())
status = {
    "timestampUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "branch": branch,
    "commit": commit,
    "postgresTestURLLabel": f"postgres@localhost:{dogfood_port}/{dogfood_database}",
    "defaultSwiftTest": "passed",
    "liveSwiftTest": "passed",
    "v04Measure": "passed",
    "v04Summary": {
        "binaryMiB": summary["binarySize"]["mib"],
        "stripXMiB": summary["binarySize"].get("stripXMiB"),
        "shellStartMs": summary.get("shellStart", {}).get("elapsedMs"),
        "coldStartMs": summary["coldStart"].get("elapsedMs"),
        "simpleMedianOverheadMs": summary.get("queryOverheadSimpleMedianMs"),
        "dogfoodMedianOverheadMs": summary.get("queryOverheadDogfoodMedianMs"),
    },
    "artifacts": {
        "swiftTestLog": str(root / "swift-test.log"),
        "liveSwiftTestLog": str(root / "live-swift-test.log"),
        "v04MeasureLog": str(root / "v04-measure.log"),
        "v04Summary": str(root / "v04-measure" / "summary.json"),
    },
}
print(json.dumps(status, indent=2, sort_keys=True))
PY

"$CAT_BIN" "$OUT_DIR/status.json"
echo
echo "Dogfood check written to $OUT_DIR"
