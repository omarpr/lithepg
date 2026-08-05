#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/release_cask_notarized.sh"

fail() {
  printf 'test_release_cask_notarized failed: %s\n' "$1" >&2
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

[[ -x "$HELPER" ]] || fail "notarized cask release helper is missing or not executable"

help_output="$($HELPER --help)"
assert_contains "$help_output" "Usage: ./script/release_cask_notarized.sh"
assert_contains "$help_output" "Developer ID-signed and Apple-notarized"
assert_contains "$help_output" "10-character Apple Developer Team ID"
assert_contains "$help_output" "never printed"
assert_contains "$help_output" "creates commits, tags, releases, and Homebrew tap updates"

set +e
missing_output="$(/usr/bin/env \
  -u LITHEPG_APPLE_TEAM_ID \
  -u LITHEPG_NOTARY_PROFILE \
  -u LITHEPG_CODESIGN_IDENTITY \
  "$HELPER" 2>&1)"
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]] || fail "missing organization configuration unexpectedly passed"
assert_contains "$missing_output" "missing required LITHEPG_APPLE_TEAM_ID"

team_id_sentinel="TEAM-ID-SHOULD-NOT-PRINT"
profile_sentinel="PROFILE-SHOULD-NOT-PRINT"
identity_sentinel="IDENTITY-SHOULD-NOT-PRINT"
set +e
invalid_team_output="$(/usr/bin/env \
  LITHEPG_APPLE_TEAM_ID="$team_id_sentinel" \
  LITHEPG_NOTARY_PROFILE="$profile_sentinel" \
  LITHEPG_CODESIGN_IDENTITY="$identity_sentinel" \
  "$HELPER" 2>&1)"
invalid_team_status=$?
set -e
[[ "$invalid_team_status" -ne 0 ]] || fail "invalid Team ID unexpectedly passed"
assert_contains "$invalid_team_output" "must be a 10-character uppercase alphanumeric Team ID"
assert_not_contains "$invalid_team_output" "$team_id_sentinel"
assert_not_contains "$invalid_team_output" "$profile_sentinel"
assert_not_contains "$invalid_team_output" "$identity_sentinel"

script_contents="$(<"$HELPER")"
assert_contains "$script_contents" '/usr/bin/security find-identity -v -p codesigning'
assert_contains "$script_contents" '"Developer ID Application:'
assert_contains "$script_contents" '/usr/bin/xcrun notarytool history'
assert_contains "$script_contents" '--keychain-profile "$LITHEPG_NOTARY_PROFILE"'
assert_contains "$script_contents" 'export LITHEPG_CODESIGN_IDENTITY="$SELECTED_IDENTITY"'
assert_contains "$script_contents" 'exec "$RELEASE_HELPER"'
assert_not_contains "$script_contents" '--apple-id'
assert_not_contains "$script_contents" '--password'
assert_not_contains "$script_contents" 'notarytool submit'

printf 'test_release_cask_notarized passed\n'
