#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="${LITHEPG_DOGFOOD_CONTAINER:-lithepg-smoke}"
POSTGRES_IMAGE="${LITHEPG_DOGFOOD_IMAGE:-postgres:16}"
HOST_PORT="${LITHEPG_DOGFOOD_PORT:-55432}"
PASSWORD="${LITHEPG_DOGFOOD_PASSWORD:-postgres}"
DATABASE="${LITHEPG_DOGFOOD_DATABASE:-postgres}"
SEED_SQL="$ROOT_DIR/script/dogfood_seed.sql"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for LithePG dogfood Postgres" >&2
  exit 1
fi

if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
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
  sleep 1
done

docker exec -i "$CONTAINER_NAME" psql -v ON_ERROR_STOP=1 -U postgres -d "$DATABASE" < "$SEED_SQL" >/dev/null

echo "Dogfood database ready."
echo "POSTGRES_TEST_URL=postgres://postgres:$PASSWORD@localhost:$HOST_PORT/$DATABASE?sslmode=disable"
echo "Sample query: SELECT * FROM lithepg_demo.orders ORDER BY created_at DESC LIMIT 25;"
