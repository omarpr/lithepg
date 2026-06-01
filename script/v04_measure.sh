#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN=/usr/bin/dirname
DATE_BIN=/bin/date
MKDIR_BIN=/bin/mkdir
CP_BIN=/bin/cp
STAT_BIN=/usr/bin/stat
MKTEMP_BIN=/usr/bin/mktemp
STRIP_BIN=/usr/bin/strip
RM_BIN=/bin/rm
CAT_BIN=/bin/cat
PWD_BIN=/bin/pwd

ROOT_DIR="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")"
cd "$ROOT_DIR"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

OUT_DIR="${LITHEPG_MEASURE_OUT_DIR:-$ROOT_DIR/.build/v04-measurements/$("$DATE_BIN" +%Y%m%d-%H%M%S)}"
DOGFOOD_PORT="${LITHEPG_DOGFOOD_PORT:-55432}"
DOGFOOD_PASSWORD="${LITHEPG_DOGFOOD_PASSWORD:-postgres}"
DOGFOOD_DATABASE="${LITHEPG_DOGFOOD_DATABASE:-postgres}"
BENCH_URL="${POSTGRES_TEST_URL:-postgres://postgres:$DOGFOOD_PASSWORD@localhost:$DOGFOOD_PORT/$DOGFOOD_DATABASE?sslmode=disable}"
WARMUP="${LITHEPG_BENCH_WARMUP:-5}"
ITERATIONS="${LITHEPG_BENCH_ITERATIONS:-30}"
SIMPLE_QUERY="${LITHEPG_BENCH_QUERY:-SELECT 1 AS lithepg_v04_bench}"
DOGFOOD_QUERY="${LITHEPG_DOGFOOD_QUERY:-SELECT * FROM lithepg_demo.customer_revenue ORDER BY revenue_cents DESC LIMIT 25}"
PSQL_BIN="${PSQL_BIN:-}"

"$MKDIR_BIN" -p "$OUT_DIR"

if [[ "${LITHEPG_SKIP_DOGFOOD_DB:-0}" != "1" ]]; then
  ./script/dogfood_postgres.sh >/tmp/lithepg-dogfood-postgres.log
  "$CP_BIN" /tmp/lithepg-dogfood-postgres.log "$OUT_DIR/dogfood-postgres.log"
fi

swift build -c release --product LithePGApp
swift build -c release --product lithepg-bench
APP_BIN="$ROOT_DIR/.build/release/LithePGApp"
BENCH_BIN="$ROOT_DIR/.build/release/lithepg-bench"

if [[ ! -x "$APP_BIN" ]]; then
  echo "missing app binary: $APP_BIN" >&2
  exit 1
fi
if [[ ! -x "$BENCH_BIN" ]]; then
  echo "missing bench binary: $BENCH_BIN" >&2
  exit 1
fi

APP_BYTES=$("$STAT_BIN" -f%z "$APP_BIN")
STRIP_PROBE=$("$MKTEMP_BIN" -t lithepg-strip.XXXXXX)
"$CP_BIN" "$APP_BIN" "$STRIP_PROBE"
"$STRIP_BIN" -x "$STRIP_PROBE" >/dev/null 2>&1 || true
APP_STRIP_X_BYTES=$("$STAT_BIN" -f%z "$STRIP_PROBE")
"$RM_BIN" -f "$STRIP_PROBE"
python3 - <<PY > "$OUT_DIR/binary-size.json"
import json
bytes_ = int("$APP_BYTES")
strip_x_bytes = int("$APP_STRIP_X_BYTES")
print(json.dumps({
  "product": "LithePGApp",
  "path": "$APP_BIN",
  "bytes": bytes_,
  "mib": bytes_ / 1024 / 1024,
  "stripXBytes": strip_x_bytes,
  "stripXMiB": strip_x_bytes / 1024 / 1024,
  "stripXSavingsBytes": bytes_ - strip_x_bytes,
  "stripXSavingsMiB": (bytes_ - strip_x_bytes) / 1024 / 1024,
  "stretchGoalMib": 30,
  "hardCapMib": 50,
  "underStretchGoal": bytes_ <= 30 * 1024 * 1024,
  "underHardCap": bytes_ <= 50 * 1024 * 1024,
}, indent=2, sort_keys=True))
PY

run_lithepg_bench() {
  local slug="$1"
  local query="$2"
  "$BENCH_BIN" \
    --url "$BENCH_URL" \
    --query "$query" \
    --warmup "$WARMUP" \
    --iterations "$ITERATIONS" \
    --json > "$OUT_DIR/lithepg-$slug.json"
}

find_psql() {
  if [[ -n "$PSQL_BIN" && -x "$PSQL_BIN" ]]; then
    printf '%s\n' "$PSQL_BIN"
  elif command -v psql >/dev/null 2>&1; then
    command -v psql
  elif [[ -x /opt/homebrew/opt/libpq/bin/psql ]]; then
    printf '%s\n' /opt/homebrew/opt/libpq/bin/psql
  else
    return 1
  fi
}

run_psql_bench() {
  local slug="$1"
  local query="$2"
  local psql
  if ! psql="$(find_psql)"; then
    printf '{"skipped": true, "reason": "psql not found"}\n' > "$OUT_DIR/psql-$slug.json"
    return 0
  fi
  local sql_file raw_file
  sql_file="$OUT_DIR/psql-$slug.sql"
  raw_file="$OUT_DIR/psql-$slug.raw.txt"
  python3 - <<PY > "$sql_file"
warmup = int("$WARMUP")
iterations = int("$ITERATIONS")
query = """$query""".strip()
if not query.endswith(';'):
    query += ';'
print(r'\pset pager off')
print(r'\timing on')
for _ in range(warmup + iterations):
    print(query)
PY
  "$psql" "$BENCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$sql_file" > "$raw_file" 2>&1
  python3 - <<PY > "$OUT_DIR/psql-$slug.json"
import json, math, re, statistics
raw = open("$raw_file", encoding="utf-8", errors="replace").read()
times = [float(x) for x in re.findall(r"Time:\\s+([0-9.]+)\\s+ms", raw)]
warmup = int("$WARMUP")
iterations = int("$ITERATIONS")
samples = times[warmup:warmup + iterations]
def pctl(vals, pct):
    if not vals:
        return 0
    vals = sorted(vals)
    idx = max(0, min(len(vals) - 1, math.ceil(pct * len(vals)) - 1))
    return vals[idx]
print(json.dumps({
    "tool": "psql",
    "query": """$query""",
    "warmup": warmup,
    "iterations": len(samples),
    "samplesMs": samples,
    "medianMs": statistics.median(samples) if samples else 0,
    "p95Ms": pctl(samples, 0.95),
    "minMs": min(samples) if samples else 0,
    "maxMs": max(samples) if samples else 0,
    "rawTimingCount": len(times),
}, indent=2, sort_keys=True))
PY
}

run_lithepg_bench simple "$SIMPLE_QUERY"
run_lithepg_bench dogfood "$DOGFOOD_QUERY"
run_psql_bench simple "$SIMPLE_QUERY"
run_psql_bench dogfood "$DOGFOOD_QUERY"

capture_app_metrics() {
  local metrics_path="$1"
  local log_path="$2"
  shift 2
  "$RM_BIN" -f "$metrics_path"
  env \
    -u LITHEPG_STARTUP_URL \
    -u LITHEPG_UI_SMOKE_URL \
    -u LITHEPG_STARTUP_QUERY \
    -u LITHEPG_UI_SMOKE_QUERY \
    -u LITHEPG_STARTUP_TLS \
    -u LITHEPG_UI_SMOKE_TLS \
    -u LITHEPG_STARTUP_TLS_CA_PATH \
    -u LITHEPG_UI_SMOKE_TLS_CA_PATH \
    -u LITHEPG_STARTUP_SSH_TARGET \
    -u LITHEPG_UI_SMOKE_SSH_TARGET \
    -u LITHEPG_STARTUP_METRICS_PATH \
    -u LITHEPG_UI_SMOKE_METRICS_PATH \
    "$@" "$APP_BIN" > "$log_path" 2>&1 &
  local app_pid=$!
  for _ in {1..200}; do
    if [[ -s "$metrics_path" ]]; then
      break
    fi
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$app_pid" >/dev/null 2>&1; then
    kill "$app_pid" >/dev/null 2>&1 || true
    wait "$app_pid" >/dev/null 2>&1 || true
  fi
  if [[ ! -s "$metrics_path" ]]; then
    printf '{"error":"startup metrics were not written"}\n' > "$metrics_path"
  fi
}

SHELL_METRICS_PATH="$OUT_DIR/shell-start.json"
capture_app_metrics \
  "$SHELL_METRICS_PATH" \
  "$OUT_DIR/shell-start-app.log" \
  LITHEPG_STARTUP_METRICS_PATH="$SHELL_METRICS_PATH"

METRICS_PATH="$OUT_DIR/cold-start.json"
capture_app_metrics \
  "$METRICS_PATH" \
  "$OUT_DIR/cold-start-app.log" \
  LITHEPG_STARTUP_URL="$BENCH_URL" \
  LITHEPG_STARTUP_QUERY="$SIMPLE_QUERY" \
  LITHEPG_STARTUP_METRICS_PATH="$METRICS_PATH"

python3 - <<PY > "$OUT_DIR/summary.json"
import json, pathlib
root = pathlib.Path("$OUT_DIR")
def load(name):
    with open(root / name) as f:
        return json.load(f)
summary = {
    "outDir": str(root),
    "binarySize": load("binary-size.json"),
    "shellStart": load("shell-start.json"),
    "coldStart": load("cold-start.json"),
    "lithepgSimple": load("lithepg-simple.json"),
    "psqlSimple": load("psql-simple.json"),
    "lithepgDogfood": load("lithepg-dogfood.json"),
    "psqlDogfood": load("psql-dogfood.json"),
}
for key in [("Simple", "lithepgSimple", "psqlSimple"), ("Dogfood", "lithepgDogfood", "psqlDogfood")]:
    label, lhs, rhs = key
    psql = summary[rhs]
    if not psql.get("skipped") and psql.get("medianMs", 0) > 0:
        summary[f"queryOverhead{label}MedianMs"] = summary[lhs]["medianMs"] - psql["medianMs"]
        summary[f"queryOverhead{label}P95Ms"] = summary[lhs]["p95Ms"] - psql["p95Ms"]
print(json.dumps(summary, indent=2, sort_keys=True))
PY

"$CAT_BIN" "$OUT_DIR/summary.json"
echo
echo "Measurements written to $OUT_DIR"
