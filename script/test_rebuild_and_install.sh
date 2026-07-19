#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

fail() {
  printf 'test_rebuild_and_install failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

mkdir -p "$FIXTURE/script" "$FIXTURE/Applications"
cp "$ROOT_DIR/script/rebuild_and_install.sh" "$FIXTURE/script/rebuild_and_install.sh"
chmod +x "$FIXTURE/script/rebuild_and_install.sh"

cat >"$FIXTURE/script/build_and_run.sh" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "${1:-}" == "--package" ]]
printf '%s\n' "${LITHEPG_MARKETING_VERSION:-missing}" >"$(dirname "$0")/../build-version.log"
app="$(dirname "$0")/../dist/LithePG.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.omarpr.lithepg</string>
</dict></plist>
PLIST
printf 'fresh build\n' >"$app/Contents/MacOS/LithePGApp"
SH
chmod +x "$FIXTURE/script/build_and_run.sh"

cat >"$FIXTURE/script/package_verify.sh" <<'SH'
#!/bin/bash
set -euo pipefail
app="${1:?missing app}"
[[ -d "$app" ]]
[[ -f "$app/Contents/MacOS/LithePGApp" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "dev.omarpr.lithepg" ]]
SH
chmod +x "$FIXTURE/script/package_verify.sh"

run_installer() {
  LITHEPG_INSTALL_APPLICATIONS_DIR="$1" \
  LITHEPG_INSTALL_SKIP_QUIT=1 \
    "$FIXTURE/script/rebuild_and_install.sh" --no-open
}

output="$(run_installer "$FIXTURE/Applications")"
assert_contains "$output" "Installed LithePG 1.0"
[[ "$(cat "$FIXTURE/build-version.log")" == "1.0" ]] || fail "default version was not 1.0"
[[ "$(cat "$FIXTURE/Applications/LithePG.app/Contents/MacOS/LithePGApp")" == "fresh build" ]] \
  || fail "fresh app was not installed"

printf 'old build\n' >"$FIXTURE/Applications/LithePG.app/Contents/MacOS/LithePGApp"
run_installer "$FIXTURE/Applications" >/dev/null
[[ "$(cat "$FIXTURE/Applications/LithePG.app/Contents/MacOS/LithePGApp")" == "fresh build" ]] \
  || fail "existing LithePG app was not replaced"

wrong_applications="$FIXTURE/WrongApplications"
mkdir -p "$wrong_applications/LithePG.app/Contents"
cat >"$wrong_applications/LithePG.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.some-other-app</string>
</dict></plist>
PLIST
if wrong_output="$(run_installer "$wrong_applications" 2>&1)"; then
  fail "installer replaced an app with a different bundle identifier"
fi
assert_contains "$wrong_output" "refusing to replace an app whose bundle identifier is com.example.some-other-app"
[[ -d "$wrong_applications/LithePG.app" ]] || fail "wrong-bundle app was not preserved"

symlink_applications="$FIXTURE/SymlinkApplications"
mkdir -p "$symlink_applications" "$FIXTURE/symlink-target"
ln -s "$FIXTURE/symlink-target" "$symlink_applications/LithePG.app"
if symlink_output="$(run_installer "$symlink_applications" 2>&1)"; then
  fail "installer followed a destination symlink"
fi
assert_contains "$symlink_output" "refusing to replace a symlink"
[[ -L "$symlink_applications/LithePG.app" ]] || fail "destination symlink was not preserved"

help_output="$($FIXTURE/script/rebuild_and_install.sh --help)"
assert_contains "$help_output" "usage: script/rebuild_and_install.sh [--no-open]"

printf 'test_rebuild_and_install passed\n'
