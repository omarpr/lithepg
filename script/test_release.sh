#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/release.sh"

fail() {
  printf 'test_release failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "output unexpectedly contained: $needle"
}

[[ -x "$HELPER" ]] || fail "release helper is missing or not executable"

help_output="$($HELPER --help)"
assert_contains "$help_output" "Usage: ./script/release.sh"
assert_contains "$help_output" "The script intentionally has no unsigned public-release mode."

set +e
invalid_output="$(printf '1.0\n' | /usr/bin/env \
  LITHEPG_CODESIGN_IDENTITY=CHANGE_ME \
  LITHEPG_NOTARY_PROFILE=CHANGE_ME \
  LITHEPG_GITHUB_ACTIONS_READY=CHANGE_ME \
  LITHEPG_RELEASE_COPY_APPROVED=CHANGE_ME \
  LITHEPG_PUBLICATION_APPROVED=CHANGE_ME \
  "$HELPER" 2>&1)"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || fail "invalid SemVer unexpectedly passed"
assert_contains "$invalid_output" "version must use stable SemVer major.minor.patch"

set +e
config_output="$(printf '1.0.3\n' | /usr/bin/env \
  LITHEPG_CODESIGN_IDENTITY=CHANGE_ME \
  LITHEPG_NOTARY_PROFILE=CHANGE_ME \
  LITHEPG_GITHUB_ACTIONS_READY=CHANGE_ME \
  LITHEPG_RELEASE_COPY_APPROVED=CHANGE_ME \
  LITHEPG_PUBLICATION_APPROVED=CHANGE_ME \
  "$HELPER" 2>&1)"
config_status=$?
set -e
[[ "$config_status" -ne 0 ]] || fail "placeholder configuration unexpectedly passed"
assert_contains "$config_output" "configure LITHEPG_CODESIGN_IDENTITY"
assert_contains "$config_output" "Release version:"

set +e
approval_output="$(printf '1.0.3\n' | /usr/bin/env \
  -u LITHEPG_GITHUB_ACTIONS_READY \
  -u LITHEPG_RELEASE_COPY_APPROVED \
  -u LITHEPG_PUBLICATION_APPROVED \
  LITHEPG_CODESIGN_IDENTITY=configured \
  LITHEPG_NOTARY_PROFILE=configured \
  "$HELPER" 2>&1)"
approval_status=$?
set -e
[[ "$approval_status" -ne 0 ]] || fail "unset release approvals unexpectedly passed"
assert_contains "$approval_output" "set LITHEPG_GITHUB_ACTIONS_READY=approved"

script_contents="$(<"$HELPER")"
assert_not_contains "$script_contents" 'LITHEPG_GITHUB_ACTIONS_READY:-true'
assert_not_contains "$script_contents" 'LITHEPG_RELEASE_COPY_APPROVED:-true'
assert_not_contains "$script_contents" 'LITHEPG_PUBLICATION_APPROVED:-true'
assert_contains "$script_contents" 'LITHEPG_MARKETING_VERSION="$VERSION"'
assert_contains "$script_contents" 'LITHEPG_EXPECTED_MARKETING_VERSION="$VERSION"'
assert_contains "$script_contents" 'ASSET_NAME="LithePG-$VERSION.zip"'
assert_contains "$script_contents" 'CHECKSUM_NAME="$ASSET_NAME.sha256"'
assert_contains "$script_contents" './script/update_release_readme.sh "$VERSION" stable'
assert_contains "$script_contents" 'git -C "$ROOT_DIR" add -- README.md packaging/homebrew/lithepg.rb'
assert_contains "$script_contents" 'CHANGELOG.md must contain a ## [v$VERSION] release entry before releasing'
assert_contains "$script_contents" 'LithePG-#{version}.zip'
assert_contains "$script_contents" '/usr/bin/shasum -a 256 -c "$CHECKSUM_NAME"'
assert_contains "$script_contents" 'README release metadata helper is missing or not executable'
assert_contains "$script_contents" '--notes-file "$RELEASE_COPY"'
assert_contains "$script_contents" 'git -C "$ROOT_DIR" commit -s -m'
assert_contains "$script_contents" './script/sign_and_notarize.sh "$APP_PATH"'
assert_contains "$script_contents" './script/v10_release_gate.sh --version "$VERSION" --check-remote'
assert_contains "$script_contents" 'git -C "$ROOT_DIR" push --atomic origin'
assert_contains "$script_contents" 'gh release create "$TAG"'
assert_contains "$script_contents" 'Homebrew tap contains the recognized draft cask; it will be finalized during this release.'
assert_contains "$script_contents" 'is_lithepg_placeholder_cask "$TAP_DIR/Casks/lithepg.rb"'
assert_contains "$script_contents" '/bin/mkdir -p "$TAP_DIR/Casks"'
assert_contains "$script_contents" 'brew audit --new --strict --cask Casks/lithepg.rb'

printf 'test_release passed\n'
