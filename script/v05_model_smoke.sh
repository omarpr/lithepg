#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
cd "$ROOT_DIR"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

OUT_DIR="${LITHEPG_MODEL_SMOKE_OUT_DIR:-$ROOT_DIR/.build/v05-model-smoke/$(/bin/date +%Y%m%d-%H%M%S)}"
/bin/mkdir -p "$OUT_DIR"

swift test --filter LocalModelAIQueryService | /usr/bin/tee "$OUT_DIR/local-model-tests.log"
swift build -c release --product LithePGApp | /usr/bin/tee "$OUT_DIR/release-build.log"

APP_BIN="$ROOT_DIR/.build/release/LithePGApp"
if [[ ! -x "$APP_BIN" ]]; then
  echo "missing app binary: $APP_BIN" >&2
  exit 1
fi

COREML_LINKED=0
if /usr/bin/otool -L "$APP_BIN" | /usr/bin/grep -q "CoreML.framework"; then
  COREML_LINKED=1
fi

python3 - <<PY > "$OUT_DIR/summary.json"
import json, os
path = "$APP_BIN"
size = os.path.getsize(path)
print(json.dumps({
  "product": "LithePGApp",
  "path": path,
  "bytes": size,
  "mib": size / 1024 / 1024,
  "coreMLFrameworkLinked": bool(int("$COREML_LINKED")),
  "modelArtifactBundled": False,
  "requiresPackageDependency": False,
  "gatedModelSmokeEnabled": os.environ.get("LITHEPG_ENABLE_LOCAL_MODEL") == "1" and bool(os.environ.get("LITHEPG_LOCAL_MODEL_PATH")),
  "modelPathProvided": bool(os.environ.get("LITHEPG_LOCAL_MODEL_PATH")),
}, indent=2, sort_keys=True))
PY

/bin/cat "$OUT_DIR/summary.json"
echo
echo "Model smoke measurements written to $OUT_DIR"
