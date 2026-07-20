#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/release_cask_preview.sh"

fail() {
  printf 'test_release_cask_preview failed: %s\n' "$1" >&2
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
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

[[ -x "$HELPER" ]] || fail "cask preview release helper is missing or not executable"

help_output="$($HELPER --help)"
assert_contains "$help_output" "Usage: ./script/release_cask_preview.sh"
assert_contains "$help_output" "explicitly unnotarized"
assert_contains "$help_output" "never uses an Apple signing identity or a notary profile"

set +e
invalid_output="$(printf '1.0\n' | "$HELPER" 2>&1)"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || fail "invalid SemVer unexpectedly passed"
assert_contains "$invalid_output" "version must use stable SemVer major.minor.patch"

set +e
preview_number_output="$(printf '1.0.1\n' | /usr/bin/env LITHEPG_CASK_PREVIEW_NUMBER=zero "$HELPER" 2>&1)"
preview_number_status=$?
set -e
[[ "$preview_number_status" -ne 0 ]] || fail "invalid preview number unexpectedly passed"
assert_contains "$preview_number_output" "LITHEPG_CASK_PREVIEW_NUMBER must be a positive integer"

script_contents="$(<"$HELPER")"
assert_contains "$script_contents" 'LITHEPG_CODESIGN_IDENTITY=-'
assert_contains "$script_contents" 'LITHEPG_FORCE_ADHOC_CODESIGN=1'
assert_contains "$script_contents" 'LITHEPG_EXPECTED_MARKETING_VERSION="$VERSION"'
assert_contains "$script_contents" 'ASSET_NAME="LithePG-$CASK_VERSION.zip"'
assert_contains "$script_contents" 'CHECKSUM_NAME="$ASSET_NAME.sha256"'
assert_contains "$script_contents" './script/update_release_readme.sh "$CASK_VERSION" preview'
assert_contains "$script_contents" 'git -C "$ROOT_DIR" add -- README.md packaging/homebrew/lithepg.rb'
assert_contains "$script_contents" 'LithePG-#{version}.zip'
assert_contains "$script_contents" '/usr/bin/shasum -a 256 -c "$CHECKSUM_NAME"'
assert_contains "$script_contents" 'README release metadata helper is missing or not executable'
assert_contains "$script_contents" '--notes-file "$RELEASE_NOTES"'
assert_contains "$script_contents" 'git -C "$ROOT_DIR" commit -s -m'
assert_contains "$script_contents" 'Signature=adhoc'
assert_contains "$script_contents" '--prerelease'
assert_contains "$script_contents" '--latest=false'
assert_contains "$script_contents" 'This preview build uses ad-hoc signing and is not notarized by Apple.'
assert_contains "$script_contents" 'System Settings -> Privacy & Security -> Open Anyway'
assert_contains "$script_contents" 's/\nend\s*\z/\n\n${block}end\n/'
assert_contains "$script_contents" '/usr/bin/ruby -c Casks/lithepg.rb'
assert_not_contains "$script_contents" 'brew audit'
assert_contains "$script_contents" 'git -C "$TAP_DIR" push origin HEAD'
assert_contains "$script_contents" 'is_lithepg_placeholder_cask "$TAP_DIR/Casks/lithepg.rb"'
assert_not_contains "$script_contents" 'sign_and_notarize.sh'
assert_not_contains "$script_contents" 'notarytool submit'

printf 'test_release_cask_preview passed\n'
