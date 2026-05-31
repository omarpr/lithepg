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
  output-zip   Zip path to create (default: dist/LithePG.app.zip)

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
    1|true|TRUE|True|yes|YES|Yes|approved|APPROVED|Approved)
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

absolute_lexical_path() {
  /usr/bin/perl -MFile::Spec -e 'print File::Spec->canonpath(File::Spec->rel2abs($ARGV[0], $ARGV[1]))' "$1" "$ROOT_DIR"
}

APP_BUNDLE_ABS="$(absolute_lexical_path "$APP_BUNDLE")"
OUTPUT_ZIP_ABS="$(absolute_lexical_path "$OUTPUT_ZIP")"
case "$OUTPUT_ZIP_ABS" in
  "$APP_BUNDLE_ABS"|"$APP_BUNDLE_ABS"/*)
    fail "output zip must not be inside the app bundle: $OUTPUT_ZIP"
    ;;
esac

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
