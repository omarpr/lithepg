#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/update_release_readme.sh"

fail() {
  printf 'test_update_release_readme failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

[[ -x "$HELPER" ]] || fail "README release metadata helper is missing or not executable"

fixture="$(mktemp -d "${TMPDIR:-/tmp}/lithepg-readme-release-test.XXXXXX")"
cleanup() {
  rm -rf "$fixture"
}
trap cleanup EXIT

mkdir -p "$fixture/script"
cp "$HELPER" "$fixture/script/update_release_readme.sh"
chmod +x "$fixture/script/update_release_readme.sh"
cat >"$fixture/README.md" <<'README'
# LithePG

before
<!-- release-download:start -->
old release data
<!-- release-download:end -->
after
README

"$fixture/script/update_release_readme.sh" 1.2.3 stable >/dev/null
stable_contents="$(<"$fixture/README.md")"
assert_contains "$stable_contents" 'releases/tag/v1.2.3'
assert_contains "$stable_contents" 'LithePG-1.2.3.zip'
assert_contains "$stable_contents" 'Signed and notarized release'
assert_contains "$stable_contents" 'brew install --cask omarpr/tap/lithepg'

"$fixture/script/update_release_readme.sh" 1.2.4-preview.2 preview >/dev/null
preview_contents="$(<"$fixture/README.md")"
assert_contains "$preview_contents" 'releases/tag/v1.2.4-preview.2'
assert_contains "$preview_contents" 'LithePG-1.2.4-preview.2.zip'
assert_contains "$preview_contents" 'Unnotarized preview'

set +e
invalid_output="$("$fixture/script/update_release_readme.sh" 1.2 stable 2>&1)"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || fail "invalid SemVer unexpectedly passed"
assert_contains "$invalid_output" 'version must use SemVer'

set +e
wrong_channel_output="$("$fixture/script/update_release_readme.sh" 1.2.3 beta 2>&1)"
wrong_channel_status=$?
set -e
[[ "$wrong_channel_status" -ne 0 ]] || fail "invalid channel unexpectedly passed"
assert_contains "$wrong_channel_output" 'channel must be stable or preview'

/bin/cat >>"$fixture/README.md" <<'README'
<!-- release-download:start -->
duplicate release data
<!-- release-download:end -->
README
set +e
duplicate_output="$("$fixture/script/update_release_readme.sh" 1.2.5 stable 2>&1)"
duplicate_status=$?
set -e
[[ "$duplicate_status" -ne 0 ]] || fail "duplicate managed blocks unexpectedly passed"
assert_contains "$duplicate_output" 'expected exactly one managed release block'

printf 'test_update_release_readme passed\n'
