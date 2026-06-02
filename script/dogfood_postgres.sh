#!/bin/bash -p

BASH_BIN=/bin/bash

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
  if [[ "${LITHEPG_DOGFOOD_POSTGRES_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after dogfood_postgres sanitizer\n' >&2
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
    $ENV{LITHEPG_DOGFOOD_POSTGRES_STARTUP_ENV_SANITIZED} = "1";
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

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
CONTAINER_NAME="${LITHEPG_DOGFOOD_CONTAINER:-lithepg-smoke}"
POSTGRES_IMAGE="${LITHEPG_DOGFOOD_IMAGE:-postgres:16}"
HOST_PORT="${LITHEPG_DOGFOOD_PORT:-55432}"
PASSWORD="${LITHEPG_DOGFOOD_PASSWORD:-postgres}"
DATABASE="${LITHEPG_DOGFOOD_DATABASE:-postgres}"
SEED_SQL="$ROOT_DIR/script/dogfood_seed.sql"

if ! /usr/bin/which docker >/dev/null 2>&1; then
  echo "docker is required for LithePG dogfood Postgres" >&2
  exit 1
fi

if ! docker ps -a --format '{{.Names}}' | /usr/bin/grep -Fqx -- "$CONTAINER_NAME"; then
  docker run \
    --name "$CONTAINER_NAME" \
    -e POSTGRES_PASSWORD="$PASSWORD" \
    -p "$HOST_PORT:5432" \
    -d "$POSTGRES_IMAGE" >/dev/null
elif [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
  docker start "$CONTAINER_NAME" >/dev/null
fi

printf 'Waiting for %s to accept connections' "$CONTAINER_NAME"
for _ in {1..60}; do
  if docker exec "$CONTAINER_NAME" pg_isready -U postgres -d "$DATABASE" >/dev/null 2>&1; then
    echo
    break
  fi
  printf '.'
  /bin/sleep 1
done

docker exec -i "$CONTAINER_NAME" psql -v ON_ERROR_STOP=1 -U postgres -d "$DATABASE" < "$SEED_SQL" >/dev/null

echo "Dogfood database ready."
echo "POSTGRES_TEST_URL=postgres://postgres:"'***'"@localhost:$HOST_PORT/$DATABASE?sslmode=disable"
echo "Sample query: SELECT * FROM lithepg_demo.orders ORDER BY created_at DESC LIMIT 25;"
