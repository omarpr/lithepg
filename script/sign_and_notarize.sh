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
  if [[ "${LITHEPG_SIGN_AND_NOTARIZE_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after sign_and_notarize sanitizer\n' >&2
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
    $ENV{LITHEPG_SIGN_AND_NOTARIZE_STARTUP_ENV_SANITIZED} = "1";
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

usage() {
  /bin/cat <<'USAGE'
Usage: sign_and_notarize.sh [--dry-run] [app-bundle]

Sign, zip for notarization, submit to Apple notarization, staple, and validate
the LithePG macOS app bundle. This helper is credential-gated and reads
configuration from environment variables; it never stores credentials.

Arguments:
  app-bundle   App bundle to sign/notarize (default: dist/LithePG.app)

Options:
  --dry-run    Validate inputs/configuration and print planned actions without
               signing, zipping, submitting, stapling, or assessing.
  -h, --help   Show this help.

Environment:
  LITHEPG_CODESIGN_IDENTITY     Apple Developer Application signing identity.
  LITHEPG_NOTARY_PROFILE        xcrun notarytool keychain profile name.
  LITHEPG_ENTITLEMENTS          Entitlements path.
  LITHEPG_NOTARY_ZIP            Intermediate notary zip path.
  LITHEPG_NOTARY_ZIP_OVERWRITE  Set to 1, true, yes, or approved to replace an
                                existing notary zip.
USAGE
}

MODE="sign"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
  MODE="dry-run"
  shift
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

APP_BUNDLE="${1:-dist/LithePG.app}"
ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
APP_BUNDLE_ABS="$APP_BUNDLE"
if [[ "$APP_BUNDLE_ABS" != /* ]]; then
  APP_BUNDLE_ABS="$ROOT_DIR/$APP_BUNDLE_ABS"
fi

BUNDLE_NAME="$(/usr/bin/basename "$APP_BUNDLE_ABS" .app)"
DIST_DIR="$(/usr/bin/dirname "$APP_BUNDLE_ABS")"
ZIP_PATH="${LITHEPG_NOTARY_ZIP:-$DIST_DIR/$BUNDLE_NAME-notary.zip}"
ENTITLEMENTS="${LITHEPG_ENTITLEMENTS:-$ROOT_DIR/Sources/LithePGApp/LithePGApp.entitlements}"
CODESIGN_IDENTITY="${LITHEPG_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${LITHEPG_NOTARY_PROFILE:-}"

fail() {
  printf 'sign/notarize failed: %s\n' "$1" >&2
  exit 1
}

run_quiet() {
  local failure_message="$1"
  shift
  "$@" >/dev/null 2>&1 || fail "$failure_message"
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

[[ "$#" -le 1 ]] || fail "too many arguments"

make_absolute_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

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

require_config() {
  [[ -n "$CODESIGN_IDENTITY" ]] || fail "missing LITHEPG_CODESIGN_IDENTITY (Apple Developer Application signing identity)"
  [[ -n "$NOTARY_PROFILE" ]] || fail "missing LITHEPG_NOTARY_PROFILE (xcrun notarytool keychain profile name)"
  [[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements file"
}

normalize_app_bundle_path() {
  local normalized_app_bundle_path="$APP_BUNDLE_ABS"
  while [[ "$normalized_app_bundle_path" != "/" && "$normalized_app_bundle_path" == */ ]]; do
    normalized_app_bundle_path="${normalized_app_bundle_path%/}"
  done
  printf '%s\n' "$normalized_app_bundle_path"
}

validate_app_bundle_canonical_basename() {
  local normalized_app_bundle_path
  normalized_app_bundle_path="$(normalize_app_bundle_path)"
  [[ "$(/usr/bin/basename "$normalized_app_bundle_path")" == "LithePG.app" ]] || fail "app bundle basename must be LithePG.app"
}

validate_app_bundle_not_symlink() {
  local normalized_app_bundle_path
  normalized_app_bundle_path="$(normalize_app_bundle_path)"

  # Reject a symlink at the final .app path before package verification or signing.
  # Parent components may include platform-level aliases such as /var -> /private/var
  # on macOS; later physical-location checks still guard notary zip placement.
  [[ ! -L "$normalized_app_bundle_path" ]] || fail "app bundle path must not be a symlink"
}

validate_notary_zip_location() {
  local app_bundle_check_path
  local zip_check_path
  if ! app_bundle_check_path="$(canonicalize_path_for_location_check "$APP_BUNDLE_ABS" 2>/dev/null)"; then
    fail "could not validate app bundle path"
  fi
  if ! zip_check_path="$(canonicalize_path_for_location_check "$ZIP_PATH" preserve-final-symlink 2>/dev/null)"; then
    fail "could not validate notary zip path"
  fi

  if [[ "$zip_check_path" == "$app_bundle_check_path" || "$zip_check_path" == "$app_bundle_check_path/"* ]]; then
    fail "notary zip must not be inside app bundle"
  fi
}

validate_notary_zip_no_trailing_slash() {
  [[ "$ZIP_PATH" != */ ]] || fail "notary zip path must not end with a slash"
}

validate_notary_zip_public_release_name() {
  local zip_basename
  local zip_basename_lower
  zip_basename="$(/usr/bin/basename "$ZIP_PATH")"
  zip_basename_lower="$(printf '%s' "$zip_basename" | LC_ALL=C /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$zip_basename_lower" != "lithepg.app.zip" ]] || fail "notary zip must not use public release artifact name"
}

validate_notary_zip_parent_dir() {
  local zip_parent
  zip_parent="$(/usr/bin/dirname "$ZIP_PATH")"
  if [[ ! -d "$zip_parent" ]]; then
    if [[ -e "$zip_parent" || -L "$zip_parent" ]]; then
      fail "notary zip parent path must be a directory"
    fi
    fail "notary zip parent directory does not exist"
  fi
  [[ -w "$zip_parent" ]] || fail "notary zip parent directory is not writable"
}

validate_notary_zip_not_directory() {
  [[ ! -d "$ZIP_PATH" ]] || fail "notary zip path must not be a directory"
}

validate_notary_zip_overwrite() {
  if [[ ( -e "$ZIP_PATH" || -L "$ZIP_PATH" ) ]] && ! is_approved "${LITHEPG_NOTARY_ZIP_OVERWRITE:-}"; then
    fail "notary zip already exists; set LITHEPG_NOTARY_ZIP_OVERWRITE=approved to replace it"
  fi
}

ZIP_PATH="$(make_absolute_path "$ZIP_PATH")"
ENTITLEMENTS="$(make_absolute_path "$ENTITLEMENTS")"
validate_app_bundle_canonical_basename
validate_app_bundle_not_symlink
/usr/bin/perl -e '
use strict;
use warnings;
my ($root_dir, @cmd) = @ARGV;
chdir $root_dir or exit 126;
exec @cmd;
exit 127;
' "$ROOT_DIR" "$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE_ABS"
require_config
validate_notary_zip_no_trailing_slash
validate_notary_zip_location
validate_notary_zip_public_release_name
validate_notary_zip_parent_dir
validate_notary_zip_not_directory
validate_notary_zip_overwrite

if [[ "$MODE" == "dry-run" ]]; then
  printf 'Signing/notarization dry run OK. No changes made.\n'
  printf 'App bundle: LithePG.app\n'
  printf 'Codesign identity: present (redacted)\n'
  printf 'Notary profile: present (redacted)\n'
  printf 'Entitlements: configured (redacted)\n'
  printf 'Notary zip: configured (redacted)\n'
  printf 'Planned commands: codesign -> zip -> notarytool submit --wait -> stapler -> spctl/stapler validation\n'
  exit 0
fi

STAGED_ZIP_DIR=""
cleanup_staged_zip() {
  if [[ -n "$STAGED_ZIP_DIR" ]]; then
    /bin/rm -rf -- "$STAGED_ZIP_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup_staged_zip EXIT

ZIP_PARENT="$(/usr/bin/dirname "$ZIP_PATH")"
staged_zip_dir=""
if ! staged_zip_dir="$(/usr/bin/mktemp -d "$ZIP_PARENT/.lithepg-notary.XXXXXX" 2>/dev/null)"; then
  fail "could not create notary zip staging directory"
fi
STAGED_ZIP_DIR="$staged_zip_dir"
if ! /bin/chmod 700 "$STAGED_ZIP_DIR" >/dev/null 2>&1; then
  fail "could not secure notary zip staging directory"
fi
STAGED_ZIP="$STAGED_ZIP_DIR/$(/usr/bin/basename "$ZIP_PATH")"

CODESIGN_BIN=/usr/bin/codesign
DITTO_BIN=/usr/bin/ditto
XCRUN_BIN=/usr/bin/xcrun
SPCTL_BIN=/usr/sbin/spctl

run_quiet "codesign failed" "$CODESIGN_BIN" \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_BUNDLE_ABS"

run_quiet "codesign verification failed" "$CODESIGN_BIN" --verify --strict --deep "$APP_BUNDLE_ABS"
run_quiet "notary zip creation failed" "$DITTO_BIN" -c -k --keepParent "$APP_BUNDLE_ABS" "$STAGED_ZIP"
run_quiet "could not replace notary zip" /usr/bin/perl -e 'use strict; use warnings; rename($ARGV[0], $ARGV[1]) or die "rename failed: $!\n";' "$STAGED_ZIP" "$ZIP_PATH"
run_quiet "notary submission failed" "$XCRUN_BIN" notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
run_quiet "staple failed" "$XCRUN_BIN" stapler staple "$APP_BUNDLE_ABS"
run_quiet "staple validation failed" "$XCRUN_BIN" stapler validate "$APP_BUNDLE_ABS"
run_quiet "spctl assessment failed" "$SPCTL_BIN" --assess --type execute --verbose=4 "$APP_BUNDLE_ABS"

printf 'Signed and notarized: LithePG.app\n'
printf 'Notary zip: created (redacted)\n'
  else
    /usr/bin/false
  fi
fi
