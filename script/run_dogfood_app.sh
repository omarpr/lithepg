#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
URL="${POSTGRES_TEST_URL:-postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable}"
QUERY="${LITHEPG_STARTUP_QUERY:-SELECT * FROM lithepg_demo.customer_revenue ORDER BY revenue_cents DESC;}"

run_from_root() {
  /usr/bin/perl -e '
    my $root = shift @ARGV;
    chdir($root) or die "chdir $root: $!\n";
    $ENV{PWD} = $root;
    exec { $ARGV[0] } @ARGV or die "exec $ARGV[0]: $!\n";
  ' "$ROOT_DIR" "$@"
}

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

"$ROOT_DIR/script/dogfood_postgres.sh" >/dev/null
run_from_root swift build --product LithePGApp >/dev/null
APP_BINARY="$(run_from_root swift build --show-bin-path)/LithePGApp"

export LITHEPG_STARTUP_URL="$URL"
export LITHEPG_STARTUP_QUERY="$QUERY"
exec /usr/bin/perl -e '
  my $root = shift @ARGV;
  chdir($root) or die "chdir $root: $!\n";
  $ENV{PWD} = $root;
  exec { $ARGV[0] } @ARGV or die "exec $ARGV[0]: $!\n";
' "$ROOT_DIR" "$APP_BINARY"
