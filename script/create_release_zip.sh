#!/bin/bash -p

BASH_BIN=/bin/bash

startup_env_sanitize_needed=0
if [[ "${BASH_ENV+x}" == x || "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
  startup_env_sanitize_needed=1
elif /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
  for my $key (keys %ENV) {
    exit 0 if $key =~ /\ABASH_FUNC_/;
  }
  exit 1;
'; then
  startup_env_sanitize_needed=1
fi

if [[ "$startup_env_sanitize_needed" == "1" ]]; then
  if [[ "${LITHEPG_CREATE_RELEASE_ZIP_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after create_release_zip sanitizer\n' >&2
    exit 2
  fi
  /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
    use strict;
    use warnings;
    my $bash = shift @ARGV;
    for my $key (keys %ENV) {
      delete $ENV{$key} if $key =~ /\ABASH_FUNC_/;
    }
    delete $ENV{BASH_ENV};
    delete $ENV{PERL5OPT};
    delete $ENV{PERL5LIB};
    delete $ENV{PERLLIB};
    $ENV{LITHEPG_CREATE_RELEASE_ZIP_STARTUP_ENV_SANITIZED} = "1";
    exec { $bash } $bash, "-p", @ARGV;
    die "exec $bash: $!\n";
  ' "$BASH_BIN" "${BASH_SOURCE[0]}" "$@"
else
  if [[ "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
    /usr/bin/printf 'unsanitized Perl startup environment remains\n' >&2
    /usr/bin/false
  elif /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
    for my $key (keys %ENV) {
      die "unsanitized bash function environment key remains: $key\n" if $key =~ /\ABASH_FUNC_/;
    }
    die "unsanitized BASH_ENV remains\n" if exists $ENV{BASH_ENV};
    exit 0;
  '; then

set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
DEFAULT_APP_BUNDLE="dist/LithePG.app"
DEFAULT_OUTPUT_ZIP="dist/LithePG.app.zip"

usage() {
  /bin/cat <<'USAGE'
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

absolute_lexical_path() {
  /usr/bin/perl -MFile::Spec -e 'print File::Spec->canonpath(File::Spec->rel2abs($ARGV[0], $ARGV[1]))' "$1" "$ROOT_DIR"
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
APP_BUNDLE_ABS="$(absolute_lexical_path "$APP_BUNDLE")"
OUTPUT_ZIP_ABS="$(absolute_lexical_path "$OUTPUT_ZIP")"

/usr/bin/perl -e '
use strict;
use warnings;
my ($root_dir, @cmd) = @ARGV;
chdir $root_dir or exit 126;
exec @cmd;
exit 127;
' "$ROOT_DIR" "$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE"

if [[ "$(/usr/bin/basename "$APP_BUNDLE")" != "LithePG.app" ]]; then
  fail "app bundle basename must be LithePG.app"
fi

app_bundle_symlink_check="$APP_BUNDLE_ABS"
while [[ "$app_bundle_symlink_check" != "/" && "$app_bundle_symlink_check" == */ ]]; do
  app_bundle_symlink_check="${app_bundle_symlink_check%/}"
done
if [[ -L "$app_bundle_symlink_check" ]]; then
  fail "app bundle path must not be a symlink"
fi

case "$OUTPUT_ZIP" in
  */)
    fail "output zip path must not end with a slash"
    ;;
esac

if [[ "$(/usr/bin/basename "$OUTPUT_ZIP")" != "LithePG.app.zip" ]]; then
  fail "output zip basename must be LithePG.app.zip"
fi

canonicalize_path_for_location_check() {
  local path="$1"
  local final_symlink_mode="${2:-follow-final-symlink}"
  /usr/bin/perl -MCwd=abs_path -e '
use strict;
use warnings;

sub path_parts {
  my ($path) = @_;
  return grep { length($_) && $_ ne "." } split m{/+}, $path;
}

my ($path, $root_dir, $final_symlink_mode) = @ARGV;
my $follow_final_symlink = $final_symlink_mode ne "preserve-final-symlink";
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
  my $is_final_part = !@queue;
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

  if ($follow_final_symlink || !$is_final_part) {
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
  }

  push @parts, $part;
}

print "/" . join("/", @parts) . "\n";
' "$path" "$ROOT_DIR" "$final_symlink_mode"
}

case "$OUTPUT_ZIP_ABS" in
  "$APP_BUNDLE_ABS"|"$APP_BUNDLE_ABS"/*)
    fail "output zip must not be inside the app bundle"
    ;;
esac

APP_BUNDLE_PHYSICAL="$(canonicalize_path_for_location_check "$APP_BUNDLE_ABS")"
OUTPUT_ZIP_PHYSICAL="$(canonicalize_path_for_location_check "$OUTPUT_ZIP_ABS" preserve-final-symlink)"
case "$OUTPUT_ZIP_PHYSICAL" in
  "$APP_BUNDLE_PHYSICAL"|"$APP_BUNDLE_PHYSICAL"/*)
    fail "output zip must not be inside the app bundle"
    ;;
esac

if [[ -d "$OUTPUT_ZIP_ABS" && ! -L "$OUTPUT_ZIP_ABS" ]]; then
  fail "output zip path must not be a directory"
fi

if [[ ( -e "$OUTPUT_ZIP_ABS" || -L "$OUTPUT_ZIP_ABS" ) ]] && ! is_approved "${LITHEPG_RELEASE_ZIP_OVERWRITE:-}"; then
  fail "Refusing to overwrite existing output zip (set LITHEPG_RELEASE_ZIP_OVERWRITE=1 to replace it)"
fi

output_parent="$(/usr/bin/dirname "$OUTPUT_ZIP_ABS")"
if [[ ( -e "$output_parent" || -L "$output_parent" ) && ! -d "$output_parent" ]]; then
  fail "output zip parent path must be a directory"
fi
if ! /bin/mkdir -p "$output_parent" 2>/dev/null; then
  fail "could not create output zip parent directory"
fi

temp_dir=""
cleanup_temp_dir() {
  if [[ -n "$temp_dir" ]]; then
    /bin/rm -rf -- "$temp_dir" >/dev/null 2>&1 || true
  fi
}
trap cleanup_temp_dir EXIT

temp_dir="$(/usr/bin/mktemp -d "${output_parent%/}/.release-zip.XXXXXX" 2>/dev/null)" || fail "could not create temporary output directory"
temp_zip="$temp_dir/LithePG.app.zip"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE_ABS" "$temp_zip"

if ! sha_line="$(/usr/bin/shasum -a 256 "$temp_zip" 2>/dev/null)"; then
  fail "could not compute SHA-256 for output zip"
fi
sha_digest="${sha_line%%[[:space:]]*}"
[[ -n "$sha_digest" ]] || fail "could not compute SHA-256 for output zip"

if ! zip_size_bytes="$(/usr/bin/stat -f%z "$temp_zip" 2>/dev/null)"; then
  fail "could not compute byte size for output zip"
fi
[[ "$zip_size_bytes" =~ ^[0-9]+$ ]] || fail "computed byte size for output zip was empty or non-numeric"

/usr/bin/perl -e 'use strict; use warnings; rename($ARGV[0], $ARGV[1]) or die "rename failed: $!\n";' "$temp_zip" "$OUTPUT_ZIP_ABS" 2>/dev/null || fail "could not replace output zip"

printf 'Created release zip: %s\n' "$(/usr/bin/basename "$OUTPUT_ZIP")"
printf 'SHA-256: %s\n' "$sha_digest"
printf 'Size bytes: %s\n' "$zip_size_bytes"
  else
    /usr/bin/false
  fi
fi
