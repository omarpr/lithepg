#!/bin/bash -p

set -euo pipefail

# Publish an explicitly ad-hoc-signed preview through the project-owned tap.
# This is not a substitute for the Developer ID + notarization release path.
export LITHEPG_HOMEBREW_TAP="${LITHEPG_HOMEBREW_TAP:-omarpr/tap}"
export LITHEPG_GITHUB_REPOSITORY="${LITHEPG_GITHUB_REPOSITORY:-omarpr/lithepg}"
export LITHEPG_RELEASE_BRANCH="${LITHEPG_RELEASE_BRANCH:-main}"
export LITHEPG_CASK_PREVIEW_NUMBER="${LITHEPG_CASK_PREVIEW_NUMBER:-1}"
export LITHEPG_CASK_PREVIEW_APPROVED="${LITHEPG_CASK_PREVIEW_APPROVED:-true}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEFAULT_VERSION="1.0.1"
ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
CASK_PATH="$ROOT_DIR/packaging/homebrew/lithepg.rb"
APP_PATH="$ROOT_DIR/dist/LithePG.app"
ZIP_PATH="$ROOT_DIR/dist/LithePG.app.zip"

usage() {
  /bin/cat <<'USAGE'
Usage: ./script/release_cask_preview.sh

Prompt once for a stable base SemVer, then publish an explicitly unnotarized
v<version>-preview.<number> GitHub prerelease and update the project-owned
Homebrew tap. The app is forced to use ad-hoc signing, and the tap cask warns
users that macOS requires manual approval in Privacy & Security.

This helper never uses an Apple signing identity or a notary profile. Use
script/release.sh for a trusted production release.
USAGE
}

fail() {
  /usr/bin/printf 'cask preview release failed: %s\n' "$1" >&2
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
  [[ -n "$value" && "$value" != *CHANGE_ME* ]] || fail "configure $name in script/release_cask_preview.sh"
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

is_lithepg_placeholder_cask() {
  local path="$1"
  /usr/bin/perl -0 -e '
    use strict;
    use warnings;
    my $path = shift @ARGV;
    open my $input, "<", $path or exit 1;
    local $/;
    my $contents = <$input>;
    close $input or exit 1;
    exit(($contents =~ /^cask "lithepg" do$/m
      && $contents =~ /^\s*sha256 "REPLACE_WITH_SHA256"$/m
      && $contents =~ m{github\.com/omarpr/lithepg/releases/download/v#\{version\}/LithePG\.app\.zip}) ? 0 : 1);
  ' "$path"
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

add_preview_caveat() {
  local source="$1"
  local destination="$2"

  /usr/bin/perl -0 -e '
    use strict;
    use warnings;
    my ($source, $destination) = @ARGV;
    open my $input, "<", $source or die "could not read prepared cask\n";
    local $/;
    my $contents = <$input>;
    close $input or die "could not close prepared cask\n";
    die "preview caveat already exists\n" if $contents =~ /This preview build uses ad-hoc signing/;
    my $block = <<"CAVEAT";
  caveats <<~EOS
    This preview build uses ad-hoc signing and is not notarized by Apple.
    After the first blocked launch, open:
      System Settings -> Privacy & Security -> Open Anyway
  EOS
CAVEAT
    my $end_count = ($contents =~ s/\nend\s*\z/\n\n$block\nend\n/);
    die "expected one final cask end\n" unless $end_count == 1;
    open my $output, ">", $destination or die "could not write tap cask\n";
    print {$output} $contents or die "could not write tap cask\n";
    close $output or die "could not close tap cask\n";
  ' "$source" "$destination"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ "$#" -eq 0 ]] || { usage >&2; fail "this script takes no arguments; enter the version at the prompt"; }

/usr/bin/printf 'Cask preview base version [%s]: ' "$DEFAULT_VERSION"
IFS= read -r VERSION
VERSION="${VERSION:-$DEFAULT_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must use stable SemVer major.minor.patch"
[[ "$LITHEPG_CASK_PREVIEW_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "LITHEPG_CASK_PREVIEW_NUMBER must be a positive integer"
is_approved "$LITHEPG_CASK_PREVIEW_APPROVED" || \
  fail "set LITHEPG_CASK_PREVIEW_APPROVED=approved after accepting the Gatekeeper limitation"

CASK_VERSION="$VERSION-preview.$LITHEPG_CASK_PREVIEW_NUMBER"
TAG="v$CASK_VERSION"

require_value LITHEPG_HOMEBREW_TAP
require_value LITHEPG_GITHUB_REPOSITORY
require_value LITHEPG_RELEASE_BRANCH

for required_command in git swift gh brew codesign shasum ruby; do
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
    { ! /usr/bin/cmp -s "$CASK_PATH" "$TAP_DIR/Casks/lithepg.rb" \
      && ! is_lithepg_placeholder_cask "$TAP_DIR/Casks/lithepg.rb"; }; then
    fail "Homebrew tap has changes other than the recognized draft Casks/lithepg.rb"
  fi
  /usr/bin/printf 'Homebrew tap contains the recognized draft cask; it will be finalized during this preview release.\n'
fi
git -C "$TAP_DIR" remote get-url origin >/dev/null 2>&1 || fail "Homebrew tap has no origin remote"

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-cask-preview.XXXXXX")"
cleanup() {
  [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]] && /bin/rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT
PREPARED_CASK="$TEMP_DIR/lithepg.rb"
TAP_CASK="$TEMP_DIR/lithepg-tap.rb"
DOWNLOADED_ZIP="$TEMP_DIR/download/LithePG.app.zip"

/usr/bin/printf '\n[1/7] Running Swift tests…\n'
run_at_root /usr/bin/env DEVELOPER_DIR="$DEVELOPER_DIR" swift test

/usr/bin/printf '\n[2/7] Building ad-hoc-signed LithePG %s…\n' "$VERSION"
run_at_root /usr/bin/env \
  -u LITHEPG_NOTARY_PROFILE \
  DEVELOPER_DIR="$DEVELOPER_DIR" \
  LITHEPG_CODESIGN_IDENTITY=- \
  LITHEPG_FORCE_ADHOC_CODESIGN=1 \
  LITHEPG_MARKETING_VERSION="$VERSION" \
  ./script/build_and_run.sh --package
run_at_root /usr/bin/env \
  LITHEPG_EXPECTED_MARKETING_VERSION="$VERSION" \
  ./script/package_verify.sh "$APP_PATH"
SIGNATURE_DETAILS="$(/usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1)"
[[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]] || fail "packaged app is not ad-hoc signed"

/usr/bin/printf '\n[3/7] Creating and hashing the preview archive…\n'
run_at_root /usr/bin/env \
  LITHEPG_EXPECTED_MARKETING_VERSION="$VERSION" \
  LITHEPG_RELEASE_ZIP_OVERWRITE=approved \
  ./script/create_release_zip.sh "$APP_PATH" "$ZIP_PATH"
ZIP_SHA="$(/usr/bin/shasum -a 256 "$ZIP_PATH")"
ZIP_SHA="${ZIP_SHA%%[[:space:]]*}"
[[ "$ZIP_SHA" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute release archive SHA-256"
update_cask "$CASK_PATH" "$PREPARED_CASK" "$CASK_VERSION" "$ZIP_SHA"
add_preview_caveat "$PREPARED_CASK" "$TAP_CASK"
/usr/bin/ruby -c "$PREPARED_CASK" >/dev/null
/usr/bin/ruby -c "$TAP_CASK" >/dev/null

/usr/bin/printf '\n[4/7] Creating the preview commit and tag…\n'
/bin/cp "$PREPARED_CASK" "$CASK_PATH"
git -C "$ROOT_DIR" add -- packaging/homebrew/lithepg.rb
git -C "$ROOT_DIR" diff --cached --quiet && fail "the prepared cask did not change"
git -C "$ROOT_DIR" commit -m "chore(release): prepare $TAG"
git -C "$ROOT_DIR" tag -a "$TAG" -m "LithePG $TAG"
git -C "$ROOT_DIR" push --atomic origin "$LITHEPG_RELEASE_BRANCH" "$TAG"

/usr/bin/printf '\n[5/7] Creating and verifying the GitHub prerelease…\n'
gh release create "$TAG" "$ZIP_PATH#LithePG for macOS (unnotarized preview)" \
  --repo "$LITHEPG_GITHUB_REPOSITORY" \
  --verify-tag \
  --draft \
  --prerelease \
  --latest=false \
  --title "LithePG $TAG" \
  --generate-notes \
  --notes "Unsigned preview: this artifact is ad-hoc signed and is not notarized by Apple. \
macOS requires manual approval in System Settings -> Privacy & Security."
/bin/mkdir -p "$(/usr/bin/dirname "$DOWNLOADED_ZIP")"
gh release download "$TAG" \
  --repo "$LITHEPG_GITHUB_REPOSITORY" \
  --pattern LithePG.app.zip \
  --dir "$(/usr/bin/dirname "$DOWNLOADED_ZIP")"
DOWNLOADED_SHA="$(/usr/bin/shasum -a 256 "$DOWNLOADED_ZIP")"
DOWNLOADED_SHA="${DOWNLOADED_SHA%%[[:space:]]*}"
[[ "$DOWNLOADED_SHA" == "$ZIP_SHA" ]] || fail "uploaded preview artifact SHA-256 does not match"
gh release edit "$TAG" \
  --repo "$LITHEPG_GITHUB_REPOSITORY" \
  --draft=false \
  --prerelease \
  --latest=false

/usr/bin/printf '\n[6/7] Validating and updating the Homebrew tap…\n'
/bin/mkdir -p "$TAP_DIR/Casks"
/bin/cp "$TAP_CASK" "$TAP_DIR/Casks/lithepg.rb"
(
  cd "$TAP_DIR"
  brew style --cask Casks/lithepg.rb
  brew audit --cask --skip-style Casks/lithepg.rb
)
git -C "$TAP_DIR" add -- Casks/lithepg.rb
git -C "$TAP_DIR" diff --cached --quiet && fail "the Homebrew tap cask did not change"
git -C "$TAP_DIR" commit -m "lithepg $CASK_VERSION"
git -C "$TAP_DIR" push origin HEAD

/usr/bin/printf '\n[7/7] Cask preview published.\n'
/usr/bin/printf 'Install with: brew install --cask %s/lithepg\n' "$LITHEPG_HOMEBREW_TAP"
/usr/bin/printf 'This preview requires manual Gatekeeper approval after its first launch.\n'
