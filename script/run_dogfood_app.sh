#!/bin/bash -p

BASH_BIN=/bin/bash

startup_env_sanitize_needed=0
if [[ -n "${BASH_ENV:-}" || "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
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
  if [[ "${LITHEPG_RUN_DOGFOOD_APP_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after run_dogfood_app sanitizer\n' >&2
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
    $ENV{LITHEPG_RUN_DOGFOOD_APP_STARTUP_ENV_SANITIZED} = "1";
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
  die "unsanitized BASH_ENV remains\n" if exists $ENV{BASH_ENV} && $ENV{BASH_ENV} ne "";
  exit 0;
'; then
  exit 2
fi

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
