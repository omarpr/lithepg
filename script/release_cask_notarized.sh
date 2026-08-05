#!/bin/bash -p

set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
RELEASE_HELPER="$ROOT_DIR/script/release.sh"

usage() {
  /bin/cat <<'USAGE'
Usage: ./script/release_cask_notarized.sh

Publish a stable, Developer ID-signed and Apple-notarized LithePG release
through the project-owned Homebrew tap. This organization-aware entry point
selects an installed Developer ID Application certificate by Apple Team ID,
validates the configured notarytool Keychain profile, and then runs the full
script/release.sh workflow.

Required environment:
  LITHEPG_APPLE_TEAM_ID   Organization's 10-character Apple Developer Team ID.
  LITHEPG_NOTARY_PROFILE  notarytool Keychain profile for that organization.

Optional environment:
  LITHEPG_CODESIGN_IDENTITY  SHA-1 fingerprint of the organization's Developer
                            ID Application certificate. Required only when the
                            keychain contains more than one matching identity.

The signing identity, Team ID, profile name, and credentials are never printed.
The notary profile must contain credentials stored with `xcrun notarytool
store-credentials`; do not put credentials in this script or the repository.

All publication approvals and configuration required by script/release.sh still
apply. This helper performs authenticated Apple and GitHub operations and
creates commits, tags, releases, and Homebrew tap updates.
USAGE
}

fail() {
  /usr/bin/printf 'notarized cask release failed: %s\n' "$1" >&2
  exit 1
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" && "$value" != *CHANGE_ME* ]] || fail "missing required $name"
}

filter_team_identities() {
  local team_id="$1"
  /usr/bin/perl -e '
      use strict;
      use warnings;
      my $team_id = shift @ARGV;
      while (my $line = <STDIN>) {
        if ($line =~ /^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"Developer ID Application:.*\(\Q$team_id\E\)"\s*$/) {
          print uc($1), "\n";
        }
      }
    ' "$team_id"
}

find_team_identities() {
  local team_id="$1"
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | \
    filter_team_identities "$team_id"
}

main() {
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ "$#" -eq 0 ]] || { usage >&2; fail "this script takes no arguments; enter the version at the release prompt"; }

require_value LITHEPG_APPLE_TEAM_ID
require_value LITHEPG_NOTARY_PROFILE
[[ "$LITHEPG_APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || \
  fail "LITHEPG_APPLE_TEAM_ID must be a 10-character uppercase alphanumeric Team ID"
[[ -x "$RELEASE_HELPER" ]] || fail "script/release.sh is missing or not executable"
[[ -x /usr/bin/security ]] || fail "macOS security tool is unavailable"
[[ -x /usr/bin/xcrun ]] || fail "Xcode command-line tools are unavailable"

TEAM_IDENTITIES=()
while IFS= read -r identity; do
  [[ -n "$identity" ]] && TEAM_IDENTITIES+=("$identity")
done < <(find_team_identities "$LITHEPG_APPLE_TEAM_ID")

SELECTED_IDENTITY="${LITHEPG_CODESIGN_IDENTITY:-}"
if [[ -n "$SELECTED_IDENTITY" ]]; then
  [[ "$SELECTED_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] || \
    fail "LITHEPG_CODESIGN_IDENTITY must be a 40-character certificate fingerprint"
  SELECTED_IDENTITY="$(/usr/bin/printf '%s' "$SELECTED_IDENTITY" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  identity_matches_team=0
  for identity in "${TEAM_IDENTITIES[@]}"; do
    [[ "$identity" == "$SELECTED_IDENTITY" ]] && identity_matches_team=1
  done
  [[ "$identity_matches_team" -eq 1 ]] || \
    fail "configured signing fingerprint is not a valid Developer ID Application identity for the configured Team ID"
else
  case "${#TEAM_IDENTITIES[@]}" in
    0)
      fail "no valid Developer ID Application identity was found for the configured Team ID"
      ;;
    1)
      SELECTED_IDENTITY="${TEAM_IDENTITIES[0]}"
      ;;
    *)
      fail "multiple Developer ID Application identities match; set LITHEPG_CODESIGN_IDENTITY to the chosen certificate fingerprint"
      ;;
  esac
fi

if ! /usr/bin/xcrun notarytool history \
  --keychain-profile "$LITHEPG_NOTARY_PROFILE" \
  --output-format json >/dev/null 2>&1; then
  fail "the configured notarytool Keychain profile could not authenticate"
fi

/usr/bin/printf 'Organization signing/notarization preflight passed (identifiers redacted).\n'
export LITHEPG_CODESIGN_IDENTITY="$SELECTED_IDENTITY"
export LITHEPG_NOTARY_PROFILE
exec "$RELEASE_HELPER"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
