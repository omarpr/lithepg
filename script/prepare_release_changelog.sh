#!/bin/bash -p

set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"

usage() {
  /bin/cat <<'USAGE'
Usage: ./script/prepare_release_changelog.sh VERSION OUTPUT [REPOSITORY]

Prepare a CHANGELOG.md for a stable VERSION without modifying the source file.
If the version section is absent, add a dated section containing commit subjects
from the latest reachable release tag through HEAD. OUTPUT must not exist.

REPOSITORY defaults to the LithePG repository root.

Optional environment:
  LITHEPG_RELEASE_DATE       Release date as YYYY-MM-DD (defaults to today).
  LITHEPG_GITHUB_REPOSITORY GitHub owner/repository used by compare links.
USAGE
}

fail() {
  /usr/bin/printf 'prepare release changelog failed: %s\n' "$1" >&2
  exit 1
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac
[[ "$#" -eq 2 || "$#" -eq 3 ]] || { usage >&2; fail "expected VERSION, OUTPUT, and optional REPOSITORY"; }

VERSION="$1"
OUTPUT_PATH="$2"
REPOSITORY="${3:-$ROOT_DIR}"
CHANGELOG_PATH="$REPOSITORY/CHANGELOG.md"
RELEASE_DATE="${LITHEPG_RELEASE_DATE:-$(/bin/date +%F)}"
GITHUB_REPOSITORY="${LITHEPG_GITHUB_REPOSITORY:-omarpr/lithepg}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must use stable SemVer major.minor.patch"
[[ "$RELEASE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "LITHEPG_RELEASE_DATE must use YYYY-MM-DD"
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
  fail "LITHEPG_GITHUB_REPOSITORY must use owner/repository form"
[[ -d "$REPOSITORY/.git" ]] || fail "REPOSITORY must be a Git repository"
[[ -f "$CHANGELOG_PATH" && ! -L "$CHANGELOG_PATH" ]] || fail "CHANGELOG.md must be a regular file"

if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PWD/$OUTPUT_PATH"
fi
[[ ! -e "$OUTPUT_PATH" && ! -L "$OUTPUT_PATH" ]] || fail "OUTPUT must not already exist"
OUTPUT_PARENT="$(/usr/bin/dirname "$OUTPUT_PATH")"
[[ -d "$OUTPUT_PARENT" && -w "$OUTPUT_PARENT" ]] || fail "OUTPUT parent must be a writable directory"

PREVIOUS_TAG="$(git -C "$REPOSITORY" describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
[[ -n "$PREVIOUS_TAG" ]] || fail "no previous release tag is reachable from HEAD"
[[ "$PREVIOUS_TAG" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?([.-][0-9A-Za-z.-]+)?$ ]] || \
  fail "previous release tag has an unsupported format"
[[ "$PREVIOUS_TAG" != "v$VERSION" ]] || fail "release tag already points at or precedes HEAD"

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-changelog.XXXXXX")"
cleanup() {
  [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]] && /bin/rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT
/bin/chmod 700 "$TEMP_DIR"
COMMITS_PATH="$TEMP_DIR/commits.tsv"
PREPARED_PATH="$TEMP_DIR/CHANGELOG.md"

git -C "$REPOSITORY" log \
  --reverse \
  --no-merges \
  --format='%h%x09%s' \
  "$PREVIOUS_TAG..HEAD" >"$COMMITS_PATH"
[[ -s "$COMMITS_PATH" ]] || fail "no commits exist after the previous release tag"

/usr/bin/perl -e '
  use strict;
  use warnings;

  my ($source, $commits_path, $output, $version, $date, $previous_tag, $repository) = @ARGV;
  open my $input, "<", $source or die "could not read CHANGELOG.md\n";
  my $contents;
  {
    local $/;
    $contents = <$input>;
  }
  close $input or die "could not close CHANGELOG.md\n";

  open my $commits, "<", $commits_path or die "could not read commit range\n";
  my @changes;
  while (my $line = <$commits>) {
    chomp $line;
    my ($short_hash, $subject) = split /\t/, $line, 2;
    next unless defined $short_hash && defined $subject;
    $subject =~ s/[\x00-\x1f\x7f]+/ /g;
    $subject =~ s/\s+/ /g;
    $subject =~ s/^\s+|\s+$//g;
    next unless length $subject;
    push @changes, "- $subject (`$short_hash`)";
  }
  close $commits or die "could not close commit range\n";
  die "commit range contained no usable subjects\n" unless @changes;

  my $section_pattern = qr/^## \[v\Q$version\E\](?:\s|$)/m;
  if ($contents !~ $section_pattern) {
    my $section = "## [v$version] — $date\n\n"
      . "### Changes since `$previous_tag`\n\n"
      . join("\n", @changes) . "\n";
    my $unreleased_count = ($contents =~ s/^## \[Unreleased\]\s*$/## [Unreleased]\n\n$section/m);
    die "expected exactly one Unreleased section\n" unless $unreleased_count == 1;
  }

  my $link = "[v$version]: https://github.com/$repository/compare/$previous_tag...v$version";
  if ($contents =~ /^\[v\Q$version\E\]:.*$/m) {
    $contents =~ s/^\[v\Q$version\E\]:.*$/$link/m;
  } elsif ($contents =~ /^\[v[^\]]+\]:/m) {
    $contents =~ s/^(\[v[^\]]+\]:)/$link\n$1/m;
  } else {
    $contents =~ s/\s*\z/\n\n$link\n/;
  }

  open my $prepared, ">", $output or die "could not create prepared CHANGELOG.md\n";
  print {$prepared} $contents or die "could not write prepared CHANGELOG.md\n";
  close $prepared or die "could not close prepared CHANGELOG.md\n";
' "$CHANGELOG_PATH" "$COMMITS_PATH" "$PREPARED_PATH" "$VERSION" "$RELEASE_DATE" "$PREVIOUS_TAG" "$GITHUB_REPOSITORY"

/bin/mv "$PREPARED_PATH" "$OUTPUT_PATH"
/usr/bin/printf 'Prepared CHANGELOG.md for v%s from %s..HEAD.\n' "$VERSION" "$PREVIOUS_TAG"
