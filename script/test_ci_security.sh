#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
workflows = sorted((root / ".github" / "workflows").glob("*.y*ml"))
if not workflows:
    raise SystemExit("test_ci_security failed: no GitHub Actions workflows found")

uses_pattern = re.compile(r"^\s*uses:\s*([^\s#]+)", re.MULTILINE)
sha_pattern = re.compile(r"^[^@]+@[0-9a-f]{40}$")
unpinned = []
for workflow in workflows:
    contents = workflow.read_text()
    for action in uses_pattern.findall(contents):
        if action.startswith("./"):
            continue
        if not sha_pattern.fullmatch(action):
            unpinned.append(f"{workflow.relative_to(root)}: {action}")

if unpinned:
    raise SystemExit(
        "test_ci_security failed: actions must use immutable 40-character SHAs:\n"
        + "\n".join(unpinned)
    )

ci = (root / ".github" / "workflows" / "ci.yml").read_text()
if "pipx install semgrep==1.170.0" not in ci:
    raise SystemExit("test_ci_security failed: Semgrep must be pinned to 1.170.0")

codeql = (root / ".github" / "workflows" / "codeql.yml").read_text()
codeql_sha = "7188fc363630916deb702c7fdcf4e481b751f97a"
for action in ("init", "analyze"):
    expected = f"github/codeql-action/{action}@{codeql_sha}"
    if expected not in codeql:
        raise SystemExit(f"test_ci_security failed: missing pinned {expected}")

if "github/codeql-action/autobuild@" in codeql:
    raise SystemExit(
        "test_ci_security failed: Swift CodeQL must use the explicit SwiftPM build, not autobuild"
    )

setup_xcode = (
    "maxim-lobanov/setup-xcode@60606e260d2fc5762a71e64e74b2174e8ea3c8bd"
)
if setup_xcode not in codeql:
    raise SystemExit("test_ci_security failed: CodeQL must select the pinned Xcode toolchain")
if codeql.index(setup_xcode) > codeql.index(f"github/codeql-action/init@{codeql_sha}"):
    raise SystemExit("test_ci_security failed: CodeQL must select Xcode before initialization")

for command in ("run: swift package resolve", "run: swift build"):
    if command not in codeql:
        raise SystemExit(f"test_ci_security failed: CodeQL is missing `{command}`")

print("test_ci_security passed")
PY
