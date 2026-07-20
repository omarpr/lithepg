#!/bin/bash -p

set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
README_PATH="$ROOT_DIR/README.md"

usage() {
  /bin/cat <<'USAGE'
Usage: ./script/update_release_readme.sh <version> <stable|preview>

Update README.md's machine-managed release block with the tagged GitHub
release, versioned archive, Homebrew command and release channel.
USAGE
}

fail() {
  /usr/bin/printf 'update_release_readme failed: %s\n' "$1" >&2
  exit 1
}

[[ "$#" -eq 2 ]] || { usage >&2; fail "expected a version and release channel"; }

VERSION="$1"
CHANNEL="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] || \
  fail "version must use SemVer"

case "$CHANNEL" in
  stable)
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "stable releases require major.minor.patch"
    CHANNEL_LABEL="Signed and notarized release"
    ;;
  preview)
    [[ "$VERSION" == *-* ]] || fail "preview releases require a SemVer prerelease suffix"
    CHANNEL_LABEL="Unnotarized preview"
    ;;
  *)
    fail "channel must be stable or preview"
    ;;
esac

[[ -f "$README_PATH" ]] || fail "README.md is missing"

/usr/bin/perl -0 -e '
  use strict;
  use warnings;
  my ($path, $version, $channel_label) = @ARGV;
  open my $input, "<", $path or die "could not read README.md\n";
  local $/;
  my $contents = <$input>;
  close $input or die "could not close README.md\n";

  my $tag = "v$version";
  my $asset = "LithePG-$version.zip";
  my $release_url = "https://github.com/omarpr/lithepg/releases/tag/$tag";
  my $asset_url = "https://github.com/omarpr/lithepg/releases/download/$tag/$asset";
  my $block = join("\n",
    "<!-- release-download:start -->",
    "**Cask release:** [`$tag`]($release_url) · [Download `$asset`]($asset_url) · $channel_label",
    "",
    "Install: `brew install --cask omarpr/tap/lithepg`",
    "<!-- release-download:end -->"
  );

  my $count = ($contents =~ s{<!-- release-download:start -->.*?<!-- release-download:end -->}{$block}sg);
  die "expected exactly one managed release block\n" unless $count == 1;

  my $temporary = "$path.release-update.$$";
  open my $output, ">", $temporary or die "could not create README update\n";
  print {$output} $contents or die "could not write README update\n";
  close $output or die "could not close README update\n";
  rename $temporary, $path or die "could not replace README.md\n";
' "$README_PATH" "$VERSION" "$CHANNEL_LABEL"

/usr/bin/printf 'Updated README release metadata for v%s (%s).\n' "$VERSION" "$CHANNEL"
