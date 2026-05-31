#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_APP_BUNDLE="dist/LithePG.app"
DEFAULT_OUTPUT_ZIP="dist/LithePG.app.zip"

usage() {
  cat <<'USAGE'
Usage: create_release_zip.sh [app-bundle] [output-zip]

Create the public LithePG.app.zip from an already-built app bundle and print
its SHA-256 digest and byte size. This local helper verifies the app bundle first; it does
not upload, tag, sign, notarize, push, or contact the network.

Arguments:
  app-bundle   App bundle to package (default: dist/LithePG.app)
  output-zip   Zip path to create; basename must be LithePG.app.zip (default: dist/LithePG.app.zip)

Set LITHEPG_RELEASE_ZIP_OVERWRITE=1 (also true/yes/approved) to replace an
existing output zip.
USAGE
}

fail() {
  printf 'create_release_zip failed: %s\n' "$1" >&2
  exit 1
}

is_approved() {
  case "${1:-}" in
    1|true|yes|approved)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -gt 2 ]]; then
  usage >&2
  fail "too many arguments"
fi

APP_BUNDLE="${1:-$DEFAULT_APP_BUNDLE}"
OUTPUT_ZIP="${2:-$DEFAULT_OUTPUT_ZIP}"

cd "$ROOT_DIR"

"$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE"

if [[ "$(basename "$APP_BUNDLE")" != "LithePG.app" ]]; then
  fail "app bundle basename must be LithePG.app"
fi

app_bundle_symlink_check="$APP_BUNDLE"
while [[ "$app_bundle_symlink_check" != "/" && "$app_bundle_symlink_check" == */ ]]; do
  app_bundle_symlink_check="${app_bundle_symlink_check%/}"
done
if [[ -L "$app_bundle_symlink_check" ]]; then
  fail "app bundle path must not be a symlink"
fi

if [[ "$(basename "$OUTPUT_ZIP")" != "LithePG.app.zip" ]]; then
  fail "output zip basename must be LithePG.app.zip"
fi

absolute_lexical_path() {
  /usr/bin/perl -MFile::Spec -e 'print File::Spec->canonpath(File::Spec->rel2abs($ARGV[0], $ARGV[1]))' "$1" "$ROOT_DIR"
}

canonicalize_path_for_location_check() {
  local path="$1"
  /usr/bin/perl -MCwd=abs_path -e '
use strict;
use warnings;

sub path_parts {
  my ($path) = @_;
  return grep { length($_) && $_ ne "." } split m{/+}, $path;
}

my ($path, $root_dir) = @ARGV;
my @parts;
my @queue;

if ($path =~ m{\A/}) {
  @parts = ();
  @queue = path_parts($path);
} else {
  my $physical_root = abs_path($root_dir);
  die "could not resolve repository root: $root_dir\n" unless defined $physical_root;
  @parts = path_parts($physical_root);
  @queue = path_parts($path);
}

my $symlink_count = 0;
while (@queue) {
  my $part = shift @queue;
  next if $part eq "" || $part eq ".";
  if ($part eq "..") {
    pop @parts if @parts;
    next;
  }

  my $parent = "/" . join("/", @parts);
  my $candidate = "/" . join("/", @parts, $part);
  if ((-e $candidate || -l $candidate) && opendir(my $dh, $parent)) {
    my $case_insensitive_match;
    while (defined(my $entry = readdir($dh))) {
      next if $entry eq "." || $entry eq "..";
      if ($entry eq $part) {
        $part = $entry;
        undef $case_insensitive_match;
        last;
      }
      $case_insensitive_match = $entry if !defined($case_insensitive_match) && lc($entry) eq lc($part);
    }
    closedir($dh);
    $part = $case_insensitive_match if defined($case_insensitive_match);
    $candidate = "/" . join("/", @parts, $part);
  }

  if (-l $candidate) {
    die "too many symlinks while resolving path: $path\n" if ++$symlink_count > 40;
    my $target = readlink($candidate);
    die "could not read symlink: $candidate\n" unless defined $target;
    if ($target =~ m{\A/}) {
      @parts = ();
      unshift @queue, path_parts($target);
    } else {
      unshift @queue, path_parts($target);
    }
    next;
  }

  push @parts, $part;
}

print "/" . join("/", @parts) . "\n";
' "$path" "$ROOT_DIR"
}

APP_BUNDLE_ABS="$(absolute_lexical_path "$APP_BUNDLE")"
OUTPUT_ZIP_ABS="$(absolute_lexical_path "$OUTPUT_ZIP")"
case "$OUTPUT_ZIP_ABS" in
  "$APP_BUNDLE_ABS"|"$APP_BUNDLE_ABS"/*)
    fail "output zip must not be inside the app bundle: $OUTPUT_ZIP"
    ;;
esac

APP_BUNDLE_PHYSICAL="$(canonicalize_path_for_location_check "$APP_BUNDLE")"
OUTPUT_ZIP_PHYSICAL="$(canonicalize_path_for_location_check "$OUTPUT_ZIP")"
case "$OUTPUT_ZIP_PHYSICAL" in
  "$APP_BUNDLE_PHYSICAL"|"$APP_BUNDLE_PHYSICAL"/*)
    fail "output zip must not be inside the app bundle: $OUTPUT_ZIP"
    ;;
esac

if [[ -d "$OUTPUT_ZIP" && ! -L "$OUTPUT_ZIP" ]]; then
  fail "output zip path must not be a directory"
fi

if [[ ( -e "$OUTPUT_ZIP" || -L "$OUTPUT_ZIP" ) ]] && ! is_approved "${LITHEPG_RELEASE_ZIP_OVERWRITE:-}"; then
  fail "Refusing to overwrite existing output zip: $OUTPUT_ZIP (set LITHEPG_RELEASE_ZIP_OVERWRITE=1 to replace it)"
fi

output_parent="$(dirname "$OUTPUT_ZIP")"
mkdir -p "$output_parent"

temp_dir=""
cleanup_temp_dir() {
  if [[ -n "$temp_dir" ]]; then
    rm -rf -- "$temp_dir"
  fi
}
trap cleanup_temp_dir EXIT

temp_dir="$(mktemp -d "${output_parent%/}/.release-zip.XXXXXX")" || fail "could not create temporary output directory under $output_parent"
temp_zip="$temp_dir/LithePG.app.zip"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$temp_zip"

sha_line="$(/usr/bin/shasum -a 256 "$temp_zip")"
sha_digest="${sha_line%%[[:space:]]*}"
[[ -n "$sha_digest" ]] || fail "could not compute SHA-256 for $OUTPUT_ZIP"

if ! zip_size_bytes="$(/usr/bin/stat -f%z "$temp_zip" 2>/dev/null)"; then
  fail "could not compute byte size for $OUTPUT_ZIP"
fi
[[ "$zip_size_bytes" =~ ^[0-9]+$ ]] || fail "computed byte size for $OUTPUT_ZIP was empty or non-numeric"

/usr/bin/perl -e 'use strict; use warnings; rename($ARGV[0], $ARGV[1]) or die "rename failed: $!\n";' "$temp_zip" "$OUTPUT_ZIP" || fail "could not replace output zip: $OUTPUT_ZIP"

printf 'Created release zip: %s\n' "$OUTPUT_ZIP"
printf 'SHA-256: %s\n' "$sha_digest"
printf 'Size bytes: %s\n' "$zip_size_bytes"
