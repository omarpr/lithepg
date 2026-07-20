#!/bin/bash -p

set -euo pipefail

# ---------------------------------------------------------------------------
# EDIT THIS BLOCK ONCE BEFORE RUNNING A PUBLIC RELEASE.
#
# These values are identifiers and release approvals, not passwords. Keep Apple
# credentials in Keychain via `xcrun notarytool store-credentials`; never put an
# Apple password, app-specific password, private key, or GitHub token here.
# Existing environment variables override these defaults.
# ---------------------------------------------------------------------------
export LITHEPG_CODESIGN_IDENTITY="${LITHEPG_CODESIGN_IDENTITY:-Apple Development: omarpr@gmail.com (86XK7HVEUY)}"
export LITHEPG_NOTARY_PROFILE="${LITHEPG_NOTARY_PROFILE:-lithepg-notary}"
export LITHEPG_SECURITY_CONTACT="${LITHEPG_SECURITY_CONTACT:-https://github.com/omarpr/lithepg/security/advisories/new}"
export LITHEPG_HOMEBREW_TAP="${LITHEPG_HOMEBREW_TAP:-omarpr/tap}"
export LITHEPG_GITHUB_REPOSITORY="${LITHEPG_GITHUB_REPOSITORY:-omarpr/lithepg}"
export LITHEPG_RELEASE_BRANCH="${LITHEPG_RELEASE_BRANCH:-main}"
export LITHEPG_GITHUB_ACTIONS_READY="${LITHEPG_GITHUB_ACTIONS_READY:-true}"
export LITHEPG_RELEASE_COPY_APPROVED="${LITHEPG_RELEASE_COPY_APPROVED:-true}"
export LITHEPG_PUBLICATION_APPROVED="${LITHEPG_PUBLICATION_APPROVED:-true}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEFAULT_VERSION="1.0.1"
ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
CASK_PATH="$ROOT_DIR/packaging/homebrew/lithepg.rb"
APP_PATH="$ROOT_DIR/dist/LithePG.app"
ZIP_PATH="$ROOT_DIR/dist/LithePG.app.zip"

usage() {
  /bin/cat <<'USAGE'
Usage: ./script/release.sh

Prompt once for a stable SemVer version, then run the complete LithePG public
release workflow: test, package, sign, notarize, zip, validate, commit, tag,
publish a GitHub release, and update the configured Homebrew tap.

Edit the configuration block at the top of this script before the first run.
The script intentionally has no unsigned public-release mode.
USAGE
}

fail() {
  /usr/bin/printf 'release failed: %s\n' "$1" >&2
  exit 1
}

is_approved() {
  case "${1:-}" in
    1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Aa][Pp][Pp][Rr][Oo][Vv][Ee][Dd])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" && "$value" != *CHANGE_ME* ]] || fail "configure $name in script/release.sh"
}

require_approval() {
  local name="$1"
  is_approved "${!name:-}" || fail "set $name=approved in script/release.sh after reviewing that gate"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is not installed: $1"
}

run_at_root() {
  (
    cd "$ROOT_DIR"
    "$@"
  )
}

update_cask() {
  local source="$1"
  local destination="$2"
  local version="$3"
  local sha="$4"

  /usr/bin/perl -0 -e '
    use strict;
    use warnings;
    my ($source, $destination, $version, $sha) = @ARGV;
    open my $input, "<", $source or die "could not read cask template\n";
    local $/;
    my $contents = <$input>;
    close $input or die "could not close cask template\n";
    my $version_count = ($contents =~ s/^([ \t]*version[ \t]+)"[^"]+"/$1"$version"/mg);
    my $sha_count = ($contents =~ s/^([ \t]*sha256[ \t]+)"[^"]+"/$1"$sha"/mg);
    die "expected exactly one version stanza\n" unless $version_count == 1;
    die "expected exactly one sha256 stanza\n" unless $sha_count == 1;
    open my $output, ">", $destination or die "could not write prepared cask\n";
    print {$output} $contents or die "could not write prepared cask\n";
    close $output or die "could not close prepared cask\n";
  ' "$source" "$destination" "$version" "$sha"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ "$#" -eq 0 ]] || { usage >&2; fail "this script takes no arguments; enter the version at the prompt"; }

/usr/bin/printf 'Release version [%s]: ' "$DEFAULT_VERSION"
IFS= read -r VERSION
VERSION="${VERSION:-$DEFAULT_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must use stable SemVer major.minor.patch"
TAG="v$VERSION"

require_value LITHEPG_CODESIGN_IDENTITY
require_value LITHEPG_NOTARY_PROFILE
require_value LITHEPG_SECURITY_CONTACT
require_value LITHEPG_HOMEBREW_TAP
require_value LITHEPG_GITHUB_REPOSITORY
require_value LITHEPG_RELEASE_BRANCH
require_approval LITHEPG_GITHUB_ACTIONS_READY
require_approval LITHEPG_RELEASE_COPY_APPROVED
require_approval LITHEPG_PUBLICATION_APPROVED

for required_command in git swift gh brew xcrun codesign ditto shasum ruby; do
  require_command "$required_command"
done

[[ -d "$DEVELOPER_DIR" ]] || fail "DEVELOPER_DIR does not exist"
[[ -f "$CASK_PATH" ]] || fail "Homebrew cask template is missing"

CURRENT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
[[ "$CURRENT_BRANCH" == "$LITHEPG_RELEASE_BRANCH" ]] || fail "switch to $LITHEPG_RELEASE_BRANCH before releasing"
[[ -z "$(git -C "$ROOT_DIR" status --short)" ]] || fail "main repository must be clean before releasing"
git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && fail "local tag already exists: $TAG"
git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1 || fail "main repository has no origin remote"

set +e
git -C "$ROOT_DIR" ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1
REMOTE_TAG_STATUS=$?
set -e
case "$REMOTE_TAG_STATUS" in
  0)
    fail "remote tag already exists: $TAG"
    ;;
  2)
    ;;
  *)
    fail "could not verify whether remote tag exists: $TAG"
    ;;
esac
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated"
if gh release view "$TAG" --repo "$LITHEPG_GITHUB_REPOSITORY" >/dev/null 2>&1; then
  fail "GitHub release already exists: $TAG"
fi

TAP_DIR="$(brew --repository "$LITHEPG_HOMEBREW_TAP" 2>/dev/null)" || \
  fail "Homebrew tap is unavailable; run: brew tap $LITHEPG_HOMEBREW_TAP"
[[ -d "$TAP_DIR/.git" ]] || fail "Homebrew tap is not a Git repository"
TAP_STATUS="$(git -C "$TAP_DIR" status --short --untracked-files=all)"
if [[ -n "$TAP_STATUS" ]]; then
  tap_has_only_matching_cask=1
  while IFS= read -r status_line; do
    [[ "${status_line:3}" == "Casks/lithepg.rb" ]] || tap_has_only_matching_cask=0
  done <<<"$TAP_STATUS"

  if [[ "$tap_has_only_matching_cask" -ne 1 || ! -f "$TAP_DIR/Casks/lithepg.rb" ]] || \
    ! /usr/bin/cmp -s "$CASK_PATH" "$TAP_DIR/Casks/lithepg.rb"; then
    fail "Homebrew tap has changes other than the matching draft Casks/lithepg.rb"
  fi
  /usr/bin/printf 'Homebrew tap contains the matching draft cask; it will be finalized during this release.\n'
fi
git -C "$TAP_DIR" remote get-url origin >/dev/null 2>&1 || fail "Homebrew tap has no origin remote"

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-release.XXXXXX")"
cleanup() {
  [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]] && /bin/rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT
PREPARED_CASK="$TEMP_DIR/lithepg.rb"
RELEASE_COPY="$TEMP_DIR/release-notes.md"
DOWNLOADED_ZIP="$TEMP_DIR/download/LithePG.app.zip"

/usr/bin/printf '\n[1/9] Running Swift tests…\n'
run_at_root /usr/bin/env DEVELOPER_DIR="$DEVELOPER_DIR" swift test

/usr/bin/printf '\n[2/9] Building and verifying LithePG %s…\n' "$VERSION"
run_at_root /usr/bin/env \
  DEVELOPER_DIR="$DEVELOPER_DIR" \
  LITHEPG_MARKETING_VERSION="$VERSION" \
  ./script/build_and_run.sh --package
run_at_root /usr/bin/env \
  LITHEPG_EXPECTED_MARKETING_VERSION="$VERSION" \
  ./script/package_verify.sh "$APP_PATH"

/usr/bin/printf '\n[3/9] Signing, notarizing, and stapling…\n'
run_at_root /usr/bin/env \
  LITHEPG_CODESIGN_IDENTITY="$LITHEPG_CODESIGN_IDENTITY" \
  LITHEPG_NOTARY_PROFILE="$LITHEPG_NOTARY_PROFILE" \
  LITHEPG_NOTARY_ZIP_OVERWRITE=approved \
  ./script/sign_and_notarize.sh "$APP_PATH"

/usr/bin/printf '\n[4/9] Creating the public release archive…\n'
run_at_root /usr/bin/env \
  LITHEPG_RELEASE_ZIP_OVERWRITE=approved \
  ./script/create_release_zip.sh "$APP_PATH" "$ZIP_PATH"
ZIP_SHA="$(/usr/bin/shasum -a 256 "$ZIP_PATH")"
ZIP_SHA="${ZIP_SHA%%[[:space:]]*}"
[[ "$ZIP_SHA" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute release archive SHA-256"

update_cask "$CASK_PATH" "$PREPARED_CASK" "$VERSION" "$ZIP_SHA"
/usr/bin/printf '# LithePG %s\n\nSHA-256: `%s`\n' "$TAG" "$ZIP_SHA" >"$RELEASE_COPY"

/usr/bin/printf '\n[5/9] Running the publication gate…\n'
run_at_root /usr/bin/env \
  LITHEPG_RELEASE_COPY_PATH="$RELEASE_COPY" \
  LITHEPG_HOMEBREW_CASK_PATH="$PREPARED_CASK" \
  LITHEPG_RELEASE_ZIP_PATH="$ZIP_PATH" \
  LITHEPG_RELEASE_ZIP_SHA256="$ZIP_SHA" \
  LITHEPG_CODESIGN_IDENTITY="$LITHEPG_CODESIGN_IDENTITY" \
  LITHEPG_NOTARY_PROFILE="$LITHEPG_NOTARY_PROFILE" \
  LITHEPG_SECURITY_CONTACT="$LITHEPG_SECURITY_CONTACT" \
  LITHEPG_HOMEBREW_TAP="$LITHEPG_HOMEBREW_TAP" \
  LITHEPG_GITHUB_ACTIONS_READY="$LITHEPG_GITHUB_ACTIONS_READY" \
  LITHEPG_RELEASE_COPY_APPROVED="$LITHEPG_RELEASE_COPY_APPROVED" \
  LITHEPG_PUBLICATION_APPROVED="$LITHEPG_PUBLICATION_APPROVED" \
  ./script/v10_release_gate.sh --version "$VERSION" --check-remote

/usr/bin/printf '\n[6/9] Creating the release commit and tag…\n'
/bin/cp "$PREPARED_CASK" "$CASK_PATH"
git -C "$ROOT_DIR" add -- packaging/homebrew/lithepg.rb
git -C "$ROOT_DIR" diff --cached --quiet && fail "the prepared cask did not change"
git -C "$ROOT_DIR" commit -m "chore(release): prepare $TAG"
git -C "$ROOT_DIR" tag -a "$TAG" -m "LithePG $TAG"

/usr/bin/printf '\n[7/9] Pushing and creating the GitHub release…\n'
git -C "$ROOT_DIR" push --atomic origin "$LITHEPG_RELEASE_BRANCH" "$TAG"
gh release create "$TAG" "$ZIP_PATH#LithePG for macOS" \
  --repo "$LITHEPG_GITHUB_REPOSITORY" \
  --verify-tag \
  --draft \
  --title "LithePG $TAG" \
  --generate-notes \
  --notes "SHA-256: \`$ZIP_SHA\`" \
  --fail-on-no-commits

/usr/bin/printf '\n[8/9] Verifying the uploaded artifact and publishing…\n'
/bin/mkdir -p "$(/usr/bin/dirname "$DOWNLOADED_ZIP")"
gh release download "$TAG" \
  --repo "$LITHEPG_GITHUB_REPOSITORY" \
  --pattern LithePG.app.zip \
  --dir "$(/usr/bin/dirname "$DOWNLOADED_ZIP")"
DOWNLOADED_SHA="$(/usr/bin/shasum -a 256 "$DOWNLOADED_ZIP")"
DOWNLOADED_SHA="${DOWNLOADED_SHA%%[[:space:]]*}"
[[ "$DOWNLOADED_SHA" == "$ZIP_SHA" ]] || fail "uploaded release artifact SHA-256 does not match"
gh release edit "$TAG" --repo "$LITHEPG_GITHUB_REPOSITORY" --draft=false --latest

/usr/bin/printf '\n[9/9] Updating the Homebrew tap…\n'
/bin/mkdir -p "$TAP_DIR/Casks"
/bin/cp "$CASK_PATH" "$TAP_DIR/Casks/lithepg.rb"
(
  cd "$TAP_DIR"
  brew style --cask Casks/lithepg.rb
  brew audit --new --strict --cask Casks/lithepg.rb
)
git -C "$TAP_DIR" add -- Casks/lithepg.rb
git -C "$TAP_DIR" diff --cached --quiet && fail "the Homebrew tap cask did not change"
git -C "$TAP_DIR" commit -m "lithepg $VERSION"
git -C "$TAP_DIR" push origin HEAD

/usr/bin/printf '\nLithePG %s is released.\n' "$TAG"
/usr/bin/printf 'Install with: brew install --cask %s/lithepg\n' "$LITHEPG_HOMEBREW_TAP"
