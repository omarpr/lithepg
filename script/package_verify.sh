#!/bin/bash -p

BASH_BIN=/bin/bash

if [[ "${BASH_ENV+x}" == x || "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]] || /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
  my $sanitize_needed = 0;
  for my $key (keys %ENV) {
    $sanitize_needed = 1 if $key =~ /\ABASH_FUNC_/;
  }
  exit 0 if $sanitize_needed;
  exit 1;
'; then
  if [[ "${LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'package verification failed: dirty startup environment remained after sanitization\n' >&2
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
    $ENV{LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED} = "1";
    exec { $bash } $bash, "-p", @ARGV;
    die "exec $bash: $!\n";
  ' "$BASH_BIN" "${BASH_SOURCE[0]}" "$@"
else
  if /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
    for my $key (keys %ENV) {
      die "unsanitized bash function environment key remains: $key\n" if $key =~ /\ABASH_FUNC_/;
    }
    die "unsanitized BASH_ENV remains\n" if exists $ENV{BASH_ENV};
    exit 0;
  '; then

set -euo pipefail

APP_NAME="LithePGApp"
BUNDLE_NAME="LithePG"
EXPECTED_BUNDLE_ID="dev.omarpr.lithepg"
EXPECTED_MIN_SYSTEM_VERSION="14.0"
HARD_CAP_BYTES=$((50 * 1024 * 1024))
ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"

fail() {
  printf 'package verification failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  /bin/cat <<'USAGE'
Usage: script/package_verify.sh [APP_BUNDLE]

Verify a LithePG.app bundle. APP_BUNDLE defaults to dist/LithePG.app.

Optional environment:
  LITHEPG_EXPECTED_MARKETING_VERSION  Expected CFBundleShortVersionString.
  LITHEPG_EXPECTED_BUILD_VERSION      Expected CFBundleVersion.
USAGE
}

[[ "$#" -le 1 ]] || fail "too many arguments"
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [[ "$#" -eq 0 ]]; then
  APP_BUNDLE="$ROOT_DIR/dist/LithePG.app"
else
  APP_BUNDLE="$1"
fi

if [[ "$#" -eq 1 && "$APP_BUNDLE" == */ && ! "$APP_BUNDLE" =~ ^/+$ ]]; then
  fail "app bundle path must not end with a slash"
fi

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true
}

while [[ "$APP_BUNDLE" != "/" && "$APP_BUNDLE" == */ ]]; do
  APP_BUNDLE="${APP_BUNDLE%/}"
done

[[ "${APP_BUNDLE##*.}" == "app" ]] || fail "bundle path must end in .app"
[[ "${APP_BUNDLE##*/}" == "LithePG.app" ]] || fail "app bundle basename must be LithePG.app"
[[ ! -L "$APP_BUNDLE" ]] || fail "app bundle path must not be a symlink"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found"
app_bundle_mode="$(/usr/bin/stat -f%p "$APP_BUNDLE")"
if (( (8#$app_bundle_mode & 07022) != 0 )); then
  fail "app bundle directory mode is unsafe"
fi

CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_BINARY="$MACOS_DIR/$APP_NAME"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

[[ -d "$CONTENTS_DIR" && ! -L "$CONTENTS_DIR" ]] || fail "Contents directory must be a non-symlink directory"
contents_dir_mode="$(/usr/bin/stat -f%p "$CONTENTS_DIR")"
if (( (8#$contents_dir_mode & 07022) != 0 )); then
  fail "Contents directory mode is unsafe"
fi
[[ -d "$MACOS_DIR" && ! -L "$MACOS_DIR" ]] || fail "Contents/MacOS directory must be a non-symlink directory"
macos_dir_mode="$(/usr/bin/stat -f%p "$MACOS_DIR")"
if (( (8#$macos_dir_mode & 07022) != 0 )); then
  fail "Contents/MacOS directory mode is unsafe"
fi
[[ -f "$APP_BINARY" && ! -L "$APP_BINARY" ]] || fail "app executable must be a regular file"
[[ -x "$APP_BINARY" ]] || fail "app executable is not executable"
app_binary_mode="$(/usr/bin/stat -f%p "$APP_BINARY")"
if (( (8#$app_binary_mode & 07022) != 0 )); then
  fail "app executable mode is unsafe"
fi
if ! app_binary_headers="$(/usr/bin/otool -hv "$APP_BINARY" 2>/dev/null)"; then
  fail "app executable format is invalid"
fi
if ! printf '%s\n' "$app_binary_headers" | /usr/bin/grep -Eq '^[[:space:]]*MH_MAGIC(_64)?[[:space:]].*[[:space:]]EXECUTE[[:space:]]'; then
  fail "app executable format is invalid"
fi
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]] || fail "Info.plist must be a regular file"
info_plist_mode="$(/usr/bin/stat -f%p "$INFO_PLIST")"
if (( (8#$info_plist_mode & 07022) != 0 )); then
  fail "Info.plist mode is unsafe"
fi
APP_ICON="$CONTENTS_DIR/Resources/AppIcon.icns"
[[ -f "$APP_ICON" && ! -L "$APP_ICON" ]] || fail "app icon must be a regular file"
app_icon_mode="$(/usr/bin/stat -f%p "$APP_ICON")"
if (( (8#$app_icon_mode & 07022) != 0 )); then
  fail "app icon mode is unsafe"
fi
if ! /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
  use strict;
  use warnings;

  my ($icon_path) = @ARGV;
  open my $icon_fh, "<:raw", $icon_path or exit 2;
  local $/;
  my $data = <$icon_fh>;
  defined $data or exit 2;

  my $total_length = length($data);
  exit 1 if $total_length < 16;
  exit 1 if substr($data, 0, 4) ne "icns";

  my $declared_length = unpack("N", substr($data, 4, 4));
  exit 1 if $declared_length != $total_length;

  my %image_element_types = map { $_ => 1 } (
    "ICON", "ICN#", "icm#", "icm4", "icm8", "ics#", "ics4", "ics8", "is32", "s8mk",
    "icl4", "icl8", "il32", "l8mk", "ich#", "ich4", "ich8", "ih32", "h8mk",
    "it32", "t8mk", "icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10", "ic11", "ic12", "ic13", "ic14",
  );
  my %high_resolution_image_types = map { $_ => 1 } ("ic10", "ic14");
  sub png_dimensions_are_valid {
    my ($payload, $minimum_dimension) = @_;
    return 0 unless length($payload) >= 33;
    return 0 unless substr($payload, 0, 8) eq "\x89PNG\r\n\x1a\n";
    return 0 unless unpack("N", substr($payload, 8, 4)) == 13;
    return 0 unless substr($payload, 12, 4) eq "IHDR";
    my $width = unpack("N", substr($payload, 16, 4));
    my $height = unpack("N", substr($payload, 20, 4));
    my $bit_depth = unpack("C", substr($payload, 24, 1));
    my $color_type = unpack("C", substr($payload, 25, 1));
    my $compression_method = unpack("C", substr($payload, 26, 1));
    my $filter_method = unpack("C", substr($payload, 27, 1));
    my $interlace_method = unpack("C", substr($payload, 28, 1));
    my $valid_bit_depth = 0;

    $valid_bit_depth = 1 if $color_type == 0 && ($bit_depth == 1 || $bit_depth == 2 || $bit_depth == 4 || $bit_depth == 8 || $bit_depth == 16);
    $valid_bit_depth = 1 if $color_type == 2 && ($bit_depth == 8 || $bit_depth == 16);
    $valid_bit_depth = 1 if $color_type == 3 && ($bit_depth == 1 || $bit_depth == 2 || $bit_depth == 4 || $bit_depth == 8);
    $valid_bit_depth = 1 if $color_type == 4 && ($bit_depth == 8 || $bit_depth == 16);
    $valid_bit_depth = 1 if $color_type == 6 && ($bit_depth == 8 || $bit_depth == 16);

    return 0 unless $valid_bit_depth;
    return 0 unless $compression_method == 0;
    return 0 unless $filter_method == 0;
    return 0 unless $interlace_method == 0 || $interlace_method == 1;
    return $width >= $minimum_dimension && $height >= $minimum_dimension;
  }

  sub has_high_resolution_encoded_image {
    my ($element_type, $payload) = @_;
    my $minimum_dimension = $element_type eq "ic10" ? 1024 : 512;
    return 1 if png_dimensions_are_valid($payload, $minimum_dimension);
    return 1 if length($payload) >= 12 && substr($payload, 0, 12) eq "\x00\x00\x00\x0cjP  \r\n\x87\n";
    return 1 if length($payload) >= 4 && substr($payload, 0, 4) eq "\xff\x4f\xff\x51";
    return 0;
  }
  my $has_image_payload = 0;
  my $has_high_resolution_image = 0;
  my $offset = 8;
  while ($offset < $total_length) {
    exit 1 if $offset + 8 > $total_length;
    my $element_type = substr($data, $offset, 4);
    my $element_length = unpack("N", substr($data, $offset + 4, 4));
    exit 1 if $element_type !~ /\A[\x20-\x7e]{4}\z/;
    exit 1 if $element_length < 8;
    exit 1 if $offset + $element_length > $total_length;
    if ($image_element_types{$element_type} && $element_length > 8) {
      my $payload = substr($data, $offset + 8, $element_length - 8);
      $has_image_payload = 1;
      $has_high_resolution_image = 1 if $high_resolution_image_types{$element_type} && has_high_resolution_encoded_image($element_type, $payload);
    }
    $offset += $element_length;
  }
  exit 1 unless $has_image_payload;
  exit 1 unless $has_high_resolution_image;

  exit 0;
' "$APP_ICON"; then
  fail "app icon format is invalid"
fi
symlink_match=""
if ! symlink_match="$(/usr/bin/find "$APP_BUNDLE" -type l -print -quit 2>/dev/null)"; then
  fail "app bundle must not contain symlinks"
fi
if [[ -n "$symlink_match" ]]; then
  fail "app bundle must not contain symlinks"
fi

special_file_match=""
if ! special_file_match="$(/usr/bin/find "$APP_BUNDLE" ! -type f ! -type d ! -type l -print -quit 2>/dev/null)"; then
  fail "app bundle must contain only regular files and directories"
fi
if [[ -n "$special_file_match" ]]; then
  fail "app bundle must contain only regular files and directories"
fi

hardlink_match=""
if ! hardlink_match="$(/usr/bin/find "$APP_BUNDLE" -type f -links +1 -print -quit 2>/dev/null)"; then
  fail "app bundle must not contain hard-linked files"
fi
if [[ -n "$hardlink_match" ]]; then
  fail "app bundle must not contain hard-linked files"
fi

if ! /usr/bin/find "$APP_BUNDLE" -type d -exec /bin/bash -c '
  for path do
    mode="$(/usr/bin/stat -f%p "$path")" || exit 2
    if (( (8#$mode & 07022) != 0 )); then
      exit 1
    fi
  done
' bash {} + >/dev/null 2>&1; then
  fail "app bundle contains unsafe directory mode"
fi

if ! /usr/bin/find "$APP_BUNDLE" -type f -exec /bin/bash -c '
  for path do
    mode="$(/usr/bin/stat -f%p "$path")" || exit 2
    if (( (8#$mode & 07022) != 0 )); then
      exit 1
    fi
  done
' bash {} + >/dev/null 2>&1; then
  fail "app bundle contains unsafe file mode"
fi

finder_metadata_match=""
if ! finder_metadata_match="$(/usr/bin/find "$APP_BUNDLE" \( -name '.DS_Store' -o -name '__MACOSX' -o -name '._*' \) -print -quit 2>/dev/null)"; then
  fail "app bundle must not contain Finder metadata files"
fi
if [[ -n "$finder_metadata_match" ]]; then
  fail "app bundle must not contain Finder metadata files"
fi

executable="$(plist_value CFBundleExecutable)"
icon_file="$(plist_value CFBundleIconFile)"
bundle_id="$(plist_value CFBundleIdentifier)"
bundle_name="$(plist_value CFBundleName)"
package_type="$(plist_value CFBundlePackageType)"
minimum_system="$(plist_value LSMinimumSystemVersion)"
principal_class="$(plist_value NSPrincipalClass)"
marketing_version="$(plist_value CFBundleShortVersionString)"
build_version="$(plist_value CFBundleVersion)"

[[ "$executable" == "$APP_NAME" ]] || fail "CFBundleExecutable mismatch"
[[ "$icon_file" == "AppIcon" ]] || fail "CFBundleIconFile mismatch"
[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "CFBundleIdentifier mismatch"
[[ "$bundle_name" == "$BUNDLE_NAME" ]] || fail "CFBundleName mismatch"
[[ "$package_type" == "APPL" ]] || fail "CFBundlePackageType mismatch"
[[ "$minimum_system" == "$EXPECTED_MIN_SYSTEM_VERSION" ]] || fail "LSMinimumSystemVersion mismatch"
[[ "$principal_class" == "NSApplication" ]] || fail "NSPrincipalClass mismatch"
[[ "$marketing_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "CFBundleShortVersionString is not a numeric release version"
[[ "$build_version" =~ ^[0-9]+$ ]] || fail "CFBundleVersion is not a numeric build version"

if [[ -n "${LITHEPG_EXPECTED_MARKETING_VERSION:-}" ]]; then
  [[ "$marketing_version" == "$LITHEPG_EXPECTED_MARKETING_VERSION" ]] || fail "CFBundleShortVersionString does not match LITHEPG_EXPECTED_MARKETING_VERSION"
fi

if [[ -n "${LITHEPG_EXPECTED_BUILD_VERSION:-}" ]]; then
  [[ "$build_version" == "$LITHEPG_EXPECTED_BUILD_VERSION" ]] || fail "CFBundleVersion does not match LITHEPG_EXPECTED_BUILD_VERSION"
fi

bytes=$(/usr/bin/stat -f%z "$APP_BINARY")
if [[ "$bytes" -gt "$HARD_CAP_BYTES" ]]; then
  mib=$(/usr/bin/awk "BEGIN { printf \"%.2f\", $bytes / 1024 / 1024 }")
  fail "app executable exceeds 50 MiB hard cap: ${mib} MiB"
fi

mib=$(/usr/bin/awk "BEGIN { printf \"%.2f\", $bytes / 1024 / 1024 }")
printf 'Package verified: %s\n' "${APP_BUNDLE##*/}"
printf 'Executable: Contents/MacOS/%s (%s bytes / %s MiB)\n' "$APP_NAME" "$bytes" "$mib"
printf 'Bundle ID: %s\n' "$bundle_id"
printf 'Version: %s (%s)\n' "$marketing_version" "$build_version"
if [[ -n "${LITHEPG_EXPECTED_MARKETING_VERSION:-}" ]]; then
  printf 'Expected marketing version: %s\n' "$LITHEPG_EXPECTED_MARKETING_VERSION"
fi
if [[ -n "${LITHEPG_EXPECTED_BUILD_VERSION:-}" ]]; then
  printf 'Expected build version: %s\n' "$LITHEPG_EXPECTED_BUILD_VERSION"
fi
printf 'Minimum system: %s\n' "$minimum_system"
  else
    /usr/bin/false
  fi
fi
