#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
URL="${POSTGRES_TEST_URL:-postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable}"
QUERY="${LITHEPG_STARTUP_QUERY:-SELECT * FROM lithepg_demo.customer_revenue ORDER BY revenue_cents DESC;}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

"$ROOT_DIR/script/dogfood_postgres.sh" >/dev/null
cd "$ROOT_DIR"
swift build --product LithePGApp >/dev/null
APP_BINARY="$(swift build --show-bin-path)/LithePGApp"

export LITHEPG_STARTUP_URL="$URL"
export LITHEPG_STARTUP_QUERY="$QUERY"
exec "$APP_BINARY"
