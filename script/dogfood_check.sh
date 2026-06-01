#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

DOGFOOD_PORT="${LITHEPG_DOGFOOD_PORT:-55432}"
DOGFOOD_PASSWORD="${LITHEPG_DOGFOOD_PASSWORD:-postgres}"
DOGFOOD_DATABASE="${LITHEPG_DOGFOOD_DATABASE:-postgres}"
POSTGRES_TEST_URL="${POSTGRES_TEST_URL:-postgres://postgres:$DOGFOOD_PASSWORD@localhost:$DOGFOOD_PORT/$DOGFOOD_DATABASE?sslmode=disable}"
OUT_DIR="${LITHEPG_DOGFOOD_CHECK_OUT_DIR:-$ROOT_DIR/.build/dogfood-checks/$(/bin/date +%Y%m%d-%H%M%S)}"
/bin/mkdir -p "$OUT_DIR"

printf 'Starting dogfood Postgres...\n'
./script/dogfood_postgres.sh > "$OUT_DIR/dogfood-postgres.log"

printf 'Running default test suite...\n'
DEVELOPER_DIR="$DEVELOPER_DIR" swift test > "$OUT_DIR/swift-test.log" 2>&1

printf 'Running live dogfood test slice...\n'
POSTGRES_TEST_URL="$POSTGRES_TEST_URL" \
DEVELOPER_DIR="$DEVELOPER_DIR" \
swift test --filter 'saved connection flow|query history records|connects through AppState|refresh schema|reconnect|live|Live' \
  > "$OUT_DIR/live-swift-test.log" 2>&1

printf 'Running v0.4 measurement gate...\n'
LITHEPG_MEASURE_OUT_DIR="$OUT_DIR/v04-measure" \
POSTGRES_TEST_URL="$POSTGRES_TEST_URL" \
DEVELOPER_DIR="$DEVELOPER_DIR" \
./script/v04_measure.sh > "$OUT_DIR/v04-measure.log" 2>&1

COMMIT="$(git rev-parse --short HEAD)"
BRANCH="$(git branch --show-current)"
python3 - <<PY > "$OUT_DIR/status.json"
import json, pathlib, datetime
root = pathlib.Path("$OUT_DIR")
summary = json.loads((root / "v04-measure" / "summary.json").read_text())
status = {
    "timestampUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "branch": "$BRANCH",
    "commit": "$COMMIT",
    "postgresTestURLLabel": "postgres@localhost:$DOGFOOD_PORT/$DOGFOOD_DATABASE",
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

/bin/cat "$OUT_DIR/status.json"
echo
echo "Dogfood check written to $OUT_DIR"
