#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ROOT_DIR"
npm run build >/dev/null

python3 - "$ROOT_DIR" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

root = Path(sys.argv[1])
dist = root / "dist"
index = dist / "index.html"

required = [
    index,
    dist / "robots.txt",
    dist / "sitemap.xml",
    dist / "site.webmanifest",
    dist / "assets" / "lithepg-icon.png",
    dist / "assets" / "lithepg-app-snapshot.png",
]
for path in required:
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"missing or empty built web asset: {path}")


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.local_assets = []
        self.has_description = False
        self.has_title = False
        self.in_title = False

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        self.in_title = tag == "title"
        for attr in ("href", "src"):
            value = values.get(attr, "")
            if value.startswith("/"):
                self.local_assets.append(value.split("?", 1)[0])
        if tag == "meta" and values.get("name") == "description":
            self.has_description = bool(values.get("content"))

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title and data.strip():
            self.has_title = True


parser = SiteParser()
parser.feed(index.read_text())

for asset in sorted(set(parser.local_assets)):
    candidate = dist / asset.removeprefix("/")
    if not candidate.is_file():
        raise SystemExit(f"built HTML references missing local asset: {asset}")

source = "\n".join(
    path.read_text()
    for path in [root / "index.html", root / "src" / "App.jsx", root / "src" / "styles.css"]
)
required_copy = [
    "brew install --cask lithepg",
    "https://github.com/omarpr/lithepg",
    "Latest source tag",
    "Install the latest release",
    "Build the latest tagged source",
    "Cask coming soon",
]
for value in required_copy:
    if value not in source:
        raise SystemExit(f"required page copy is missing: {value}")

for stale_version in ("v1.0.0", "Build v1", "git checkout v1"):
    if stale_version in source:
        raise SystemExit(f"version-specific copy remains in the webapp: {stale_version}")

if not parser.has_description:
    raise SystemExit("page is missing a meta description")
if not parser.has_title:
    raise SystemExit("page is missing a title")

scripts = list((dist / "assets").glob("*.js"))
styles = list((dist / "assets").glob("*.css"))
if not scripts or not styles:
    raise SystemExit("Vite did not emit JavaScript and CSS assets")

print("webapp checks passed")
PY
