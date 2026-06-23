#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/package_verify.sh"

fail() {
  printf 'test_package_verify failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "output leaked forbidden value: $needle"
}

write_valid_app_icon_fixture() {
  local output_path="$1"

  /usr/bin/python3 - "$output_path" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024


def png_chunk(chunk_type, data):
    return (
        len(data).to_bytes(4, "big")
        + chunk_type
        + data
        + (binascii.crc32(chunk_type + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


raw_scanlines = b"".join(b"\x00" + (b"\x00" * width * 4) for _ in range(height))
png_payload = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(raw_scanlines, 9))
    + png_chunk(b"IEND", b"")
)
icns_element = b"ic10" + (len(png_payload) + 8).to_bytes(4, "big") + png_payload
icns = b"icns" + (len(icns_element) + 8).to_bytes(4, "big") + icns_element

with open(output_path, "wb") as icon_file:
    icon_file.write(icns)
PY
}

write_invalid_filter_app_icon_fixture() {
  local output_path="$1"

  /usr/bin/python3 - "$output_path" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024


def png_chunk(chunk_type, data):
    return (
        len(data).to_bytes(4, "big")
        + chunk_type
        + data
        + (binascii.crc32(chunk_type + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


# Keep the inflated IDAT length exactly correct, but use filter byte 5 on every
# scanline. PNG filter methods only define per-row filter bytes 0 through 4.
raw_scanlines = b"".join(b"\x05" + (b"\x00" * width * 4) for _ in range(height))
png_payload = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(raw_scanlines, 9))
    + png_chunk(b"IEND", b"")
)
icns_element = b"ic10" + (len(png_payload) + 8).to_bytes(4, "big") + png_payload
icns = b"icns" + (len(icns_element) + 8).to_bytes(4, "big") + icns_element

with open(output_path, "wb") as icon_file:
    icon_file.write(icns)
PY
}

write_split_idat_app_icon_fixture() {
  local output_path="$1"

  /usr/bin/python3 - "$output_path" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024


def png_chunk(chunk_type, data):
    return (
        len(data).to_bytes(4, "big")
        + chunk_type
        + data
        + (binascii.crc32(chunk_type + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


raw_scanlines = b"".join(b"\x00" + (b"\x00" * width * 4) for _ in range(height))
compressed = zlib.compress(raw_scanlines, 9)
split_at = max(1, len(compressed) // 2)
png_payload = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", compressed[:split_at])
    + png_chunk(b"tEXt", b"lithepg=nonconsecutive-idat")
    + png_chunk(b"IDAT", compressed[split_at:])
    + png_chunk(b"IEND", b"")
)
icns_element = b"ic10" + (len(png_payload) + 8).to_bytes(4, "big") + png_payload
icns = b"icns" + (len(icns_element) + 8).to_bytes(4, "big") + icns_element

with open(output_path, "wb") as icon_file:
    icon_file.write(icns)
PY
}

write_indexed_png_without_plte_app_icon_fixture() {
  local output_path="$1"

  /usr/bin/python3 - "$output_path" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024


def png_chunk(chunk_type, data):
    return (
        len(data).to_bytes(4, "big")
        + chunk_type
        + data
        + (binascii.crc32(chunk_type + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


# Color type 3 is indexed-color PNG. It is invalid unless a PLTE chunk appears
# before IDAT, even if the scanline data length and CRCs are otherwise valid.
raw_scanlines = b"".join(b"\x00" + (b"\x00" * width) for _ in range(height))
png_payload = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(raw_scanlines, 9))
    + png_chunk(b"IEND", b"")
)
icns_element = b"ic10" + (len(png_payload) + 8).to_bytes(4, "big") + png_payload
icns = b"icns" + (len(icns_element) + 8).to_bytes(4, "big") + icns_element

with open(output_path, "wb") as icon_file:
    icon_file.write(icns)
PY
}

write_indexed_png_empty_plte_app_icon_fixture() {
  local output_path="$1"

  /usr/bin/python3 - "$output_path" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024


def png_chunk(chunk_type, data):
    return (
        len(data).to_bytes(4, "big")
        + chunk_type
        + data
        + (binascii.crc32(chunk_type + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


# Indexed-color PNG requires a non-empty PLTE whose length is a multiple of 3.
# An empty palette before IDAT is still malformed and must not satisfy the gate.
raw_scanlines = b"".join(b"\x00" + (b"\x00" * width) for _ in range(height))
png_payload = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
    + png_chunk(b"PLTE", b"")
    + png_chunk(b"IDAT", zlib.compress(raw_scanlines, 9))
    + png_chunk(b"IEND", b"")
)
icns_element = b"ic10" + (len(png_payload) + 8).to_bytes(4, "big") + png_payload
icns = b"icns" + (len(icns_element) + 8).to_bytes(4, "big") + icns_element

with open(output_path, "wb") as icon_file:
    icon_file.write(icns)
PY
}

write_indexed_png_duplicate_plte_app_icon_fixture() {
  local output_path="$1"

  /usr/bin/python3 - "$output_path" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024


def png_chunk(chunk_type, data):
    return (
        len(data).to_bytes(4, "big")
        + chunk_type
        + data
        + (binascii.crc32(chunk_type + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


# PNG permits at most one PLTE chunk. This fixture is otherwise valid indexed
# PNG data, but repeats the palette before IDAT and must be rejected.
palette = b"\x00\x00\x00"
raw_scanlines = b"".join(b"\x00" + (b"\x00" * width) for _ in range(height))
png_payload = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
    + png_chunk(b"PLTE", palette)
    + png_chunk(b"PLTE", palette)
    + png_chunk(b"IDAT", zlib.compress(raw_scanlines, 9))
    + png_chunk(b"IEND", b"")
)
icns_element = b"ic10" + (len(png_payload) + 8).to_bytes(4, "big") + png_payload
icns = b"icns" + (len(icns_element) + 8).to_bytes(4, "big") + icns_element

with open(output_path, "wb") as icon_file:
    icon_file.write(icns)
PY
}

make_minimal_app_bundle() {
  local app_bundle="$1"
  mkdir -p "$app_bundle/Contents/MacOS"
  chmod 755 "$app_bundle" "$app_bundle/Contents" "$app_bundle/Contents/MacOS"

  cat >"$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>LithePGApp</string>
  <key>CFBundleIdentifier</key>
  <string>dev.omarpr.lithepg</string>
  <key>CFBundleName</key>
  <string>LithePG</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>100</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  chmod 644 "$app_bundle/Contents/Info.plist"

  cp /usr/bin/true "$app_bundle/Contents/MacOS/LithePGApp"
  chmod 755 "$app_bundle/Contents/MacOS/LithePGApp"

  mkdir -p "$app_bundle/Contents/Resources"
  chmod 755 "$app_bundle/Contents/Resources"
  write_valid_app_icon_fixture "$app_bundle/Contents/Resources/AppIcon.icns"
  chmod 644 "$app_bundle/Contents/Resources/AppIcon.icns"
}

make_text_executable_app_bundle() {
  local app_bundle="$1"
  local executable_sentinel="$2"
  make_minimal_app_bundle "$app_bundle"

  cat >"$app_bundle/Contents/MacOS/LithePGApp" <<APP
#!/usr/bin/env bash
printf '%s\\n' '$executable_sentinel'
APP
  chmod 755 "$app_bundle/Contents/MacOS/LithePGApp"
}

run_helper_capture() {
  local output_file="$1"
  shift
  set +e
  (
    cd "$ROOT_DIR"
    unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
    "$HELPER" "$@"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

run_helper_capture_with_expected_marketing_version() {
  local output_file="$1"
  local expected_marketing_version="$2"
  shift 2
  set +e
  (
    cd "$ROOT_DIR"
    unset LITHEPG_EXPECTED_BUILD_VERSION
    LITHEPG_EXPECTED_MARKETING_VERSION="$expected_marketing_version" "$HELPER" "$@"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

run_helper_capture_with_expected_build_version() {
  local output_file="$1"
  local expected_build_version="$2"
  shift 2
  set +e
  (
    cd "$ROOT_DIR"
    unset LITHEPG_EXPECTED_MARKETING_VERSION
    LITHEPG_EXPECTED_BUILD_VERSION="$expected_build_version" "$HELPER" "$@"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"
helper_contents="$(<"$HELPER")"
assert_contains "$helper_contents" 'exec { $bash } $bash, "-p", @ARGV;'

output_file="$(mktemp)"
fixture_root="$(mktemp -d)"
trap 'rm -f "$output_file"; rm -rf "$fixture_root"' EXIT

app_bundle="$fixture_root/LithePG.app"
make_minimal_app_bundle "$app_bundle"

default_root_sentinel="PACKAGE_VERIFY_DEFAULT_ROOT_SHADOW_SHOULD_NOT_RUN"
default_root_repo="$fixture_root/default-root-repo"
default_root_outside_cwd="$fixture_root/default-root-outside-cwd"
default_root_fake_bin="$fixture_root/default-root-fake-bin"
default_root_marker_dir="$fixture_root/default-root-shadow-markers"
/bin/mkdir -p "$default_root_repo/script" "$default_root_repo/dist" "$default_root_outside_cwd" "$default_root_fake_bin" "$default_root_marker_dir"
/bin/cp "$HELPER" "$default_root_repo/script/package_verify.sh"
/bin/chmod +x "$default_root_repo/script/package_verify.sh"
make_minimal_app_bundle "$default_root_repo/dist/LithePG.app"
for tool in dirname realpath; do
  /bin/cat >"$default_root_fake_bin/$tool" <<SHIM
#!/usr/bin/env bash
/usr/bin/printf '%s %s invoked\\n' "$default_root_sentinel" "$tool" >&2
/usr/bin/printf '%s\\n' "$tool" >"$default_root_marker_dir/$tool"
exit 97
SHIM
  /bin/chmod +x "$default_root_fake_bin/$tool"
done
set +e
(
  cd "$default_root_outside_cwd"
  command() {
    /usr/bin/printf '%s command function invoked\\n' "${DEFAULT_ROOT_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'command\\n' >"${DEFAULT_ROOT_MARKER_DIR:?}/command"
    exit 97
  }
  builtin() {
    /usr/bin/printf '%s builtin function invoked\\n' "${DEFAULT_ROOT_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'builtin\\n' >"${DEFAULT_ROOT_MARKER_DIR:?}/builtin"
    exit 97
  }
  cd() {
    /usr/bin/printf '%s cd function invoked\\n' "${DEFAULT_ROOT_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'cd\\n' >"${DEFAULT_ROOT_MARKER_DIR:?}/cd"
    exit 97
  }
  pwd() {
    /usr/bin/printf '%s pwd function invoked\\n' "${DEFAULT_ROOT_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'pwd\\n' >"${DEFAULT_ROOT_MARKER_DIR:?}/pwd"
    exit 97
  }
  export -f command
  export -f builtin
  export -f cd
  export -f pwd
  DEFAULT_ROOT_SHADOW_SENTINEL="$default_root_sentinel" \
    DEFAULT_ROOT_MARKER_DIR="$default_root_marker_dir" \
    PATH="$default_root_fake_bin:$PATH" \
    "$default_root_repo/script/package_verify.sh"
) >"$output_file" 2>&1
default_root_status=$?
set -e
if [[ "$default_root_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier default app path did not resolve from the helper repo root"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$default_root_sentinel"
assert_not_contains "$helper_output" "function invoked"
for tool in dirname realpath command builtin cd pwd; do
  [[ ! -e "$default_root_marker_dir/$tool" ]] || fail "package verifier default root handling invoked shadowed $tool"
done

help_cat_path_shadow_sentinel="PACKAGE_VERIFY_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN"
help_cat_path_shadow_fake_bin="$fixture_root/help-cat-path-shadow-fake-bin"
help_cat_path_shadow_marker="$fixture_root/help-cat-path-shadow-invoked"
mkdir -p "$help_cat_path_shadow_fake_bin"
cat >"$help_cat_path_shadow_fake_bin/cat" <<'SHIM'
#!/usr/bin/env bash
printf 'fake cat stdout sentinel=%s args=%s\n' "${HELP_CAT_PATH_SHADOW_SENTINEL:-}" "$*"
printf 'fake cat stderr sentinel=%s args=%s\n' "${HELP_CAT_PATH_SHADOW_SENTINEL:-}" "$*" >&2
printf 'cat\n' >"${HELP_CAT_PATH_SHADOW_MARKER:?}"
exit 73
SHIM
chmod +x "$help_cat_path_shadow_fake_bin/cat"
if ! HELP_CAT_PATH_SHADOW_SENTINEL="$help_cat_path_shadow_sentinel" \
  HELP_CAT_PATH_SHADOW_MARKER="$help_cat_path_shadow_marker" \
  PATH="$help_cat_path_shadow_fake_bin:$PATH" \
  run_helper_capture "$output_file" --help; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier --help invoked PATH-shadowed cat"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage:"
assert_contains "$helper_output" "LITHEPG_EXPECTED_MARKETING_VERSION"
assert_contains "$helper_output" "LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$help_cat_path_shadow_sentinel"
assert_not_contains "$helper_output" "fake cat"
[[ ! -e "$help_cat_path_shadow_marker" ]] || fail "package verifier --help invoked PATH-shadowed cat: $(<"$help_cat_path_shadow_marker")"

if ! run_helper_capture "$output_file" --help; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier --help unexpectedly failed"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage:"
assert_contains "$helper_output" "LITHEPG_EXPECTED_MARKETING_VERSION"
assert_contains "$helper_output" "LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"

if ! run_helper_capture "$output_file" -h; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier -h unexpectedly failed"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Usage:"
assert_contains "$helper_output" "LITHEPG_EXPECTED_MARKETING_VERSION"
assert_contains "$helper_output" "LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"

text_executable_sentinel="TEXT_EXECUTABLE_SENTINEL_SHOULD_NOT_LEAK"
text_executable_bundle="$fixture_root/text-executable-$text_executable_sentinel/LithePG.app"
make_text_executable_app_bundle "$text_executable_bundle" "$text_executable_sentinel"
if run_helper_capture "$output_file" "$text_executable_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a text app executable"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app executable format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$text_executable_bundle"
assert_not_contains "$helper_output" "$text_executable_sentinel"
assert_not_contains "$helper_output" "shell script"
assert_not_contains "$helper_output" "ASCII text"

mach_o_non_executable_sentinel="MACH_O_NON_EXECUTABLE_SENTINEL_SHOULD_NOT_LEAK"
mach_o_non_executable_bundle="$fixture_root/mach-o-non-executable-$mach_o_non_executable_sentinel/LithePG.app"
make_minimal_app_bundle "$mach_o_non_executable_bundle"
cp /usr/lib/dyld "$mach_o_non_executable_bundle/Contents/MacOS/LithePGApp"
chmod 755 "$mach_o_non_executable_bundle/Contents/MacOS/LithePGApp"
if run_helper_capture "$output_file" "$mach_o_non_executable_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a Mach-O non-executable app binary"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app executable format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$mach_o_non_executable_bundle"
assert_not_contains "$helper_output" "$mach_o_non_executable_sentinel"
assert_not_contains "$helper_output" "dynamic linker"
assert_not_contains "$helper_output" "Mach-O"

mach_o_path_contamination_sentinel="MACH_O_PATH_CONTAMINATION_SENTINEL_SHOULD_NOT_LEAK"
mach_o_path_contamination_dir="$fixture_root/Mach-O 64-bit executable path $mach_o_path_contamination_sentinel"
mach_o_path_contamination_bundle="$mach_o_path_contamination_dir/LithePG.app"
make_minimal_app_bundle "$mach_o_path_contamination_bundle"
cp /usr/lib/dyld "$mach_o_path_contamination_bundle/Contents/MacOS/LithePGApp"
chmod 755 "$mach_o_path_contamination_bundle/Contents/MacOS/LithePGApp"
if run_helper_capture "$output_file" "$mach_o_path_contamination_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a Mach-O non-executable app binary from a misleading path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app executable format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$mach_o_path_contamination_dir"
assert_not_contains "$helper_output" "$mach_o_path_contamination_sentinel"
assert_not_contains "$helper_output" "dynamic linker"
assert_not_contains "$helper_output" "Mach-O"

success_path_sentinel="SUCCESS_PATH_SENTINEL_SHOULD_NOT_LEAK"
success_path_bundle="$fixture_root/success-path-$success_path_sentinel/LithePG.app"
make_minimal_app_bundle "$success_path_bundle"
if ! run_helper_capture "$output_file" "$success_path_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verification unexpectedly failed for a valid fixture under a sentinel path"
fi
helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$success_path_bundle"
assert_not_contains "$helper_output" "$success_path_sentinel"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_contains "$helper_output" "Bundle ID: dev.omarpr.lithepg"
assert_contains "$helper_output" "Version: 1.0 (100)"

icon_missing_sentinel="ICON_MISSING_SENTINEL_SHOULD_NOT_LEAK"
icon_missing_bundle="$fixture_root/icon-missing-$icon_missing_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_missing_bundle"
rm "$icon_missing_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_missing_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a bundle without AppIcon.icns"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon must be a regular file"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_missing_sentinel"

icon_format_sentinel="ICON_FORMAT_SENTINEL_SHOULD_NOT_LEAK"
icon_format_bundle="$fixture_root/icon-format-$icon_format_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_format_bundle"
printf '%s\n' "$icon_format_sentinel" >"$icon_format_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_format_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_format_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a malformed AppIcon.icns"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_format_sentinel"
assert_not_contains "$helper_output" "$icon_format_bundle"

icon_length_sentinel="ICON_LENGTH_SENTINEL_SHOULD_NOT_LEAK"
icon_length_bundle="$fixture_root/icon-length-$icon_length_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_length_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\xff%s\n' "$icon_length_sentinel" >"$icon_length_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_length_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_length_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns with mismatched header length"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_length_sentinel"
assert_not_contains "$helper_output" "$icon_length_bundle"

icon_element_sentinel="ICON_ELEMENT_SENTINEL_SHOULD_NOT_LEAK"
icon_element_bundle="$fixture_root/icon-element-$icon_element_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_element_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x0cBAD!' >"$icon_element_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_element_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_element_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns with a malformed element table"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_element_sentinel"
assert_not_contains "$helper_output" "$icon_element_bundle"

icon_empty_image_sentinel="ICON_EMPTY_IMAGE_SENTINEL_SHOULD_NOT_LEAK"
icon_empty_image_bundle="$fixture_root/icon-empty-image-$icon_empty_image_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_empty_image_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x10icp4\x00\x00\x00\x08' >"$icon_empty_image_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_empty_image_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_empty_image_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns without image payload data"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_empty_image_sentinel"
assert_not_contains "$helper_output" "$icon_empty_image_bundle"

icon_low_resolution_sentinel="ICON_LOW_RESOLUTION_SENTINEL_SHOULD_NOT_LEAK"
icon_low_resolution_bundle="$fixture_root/icon-low-resolution-$icon_low_resolution_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_low_resolution_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x11icp4\x00\x00\x00\x09\x00' >"$icon_low_resolution_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_low_resolution_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_low_resolution_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns without a high-resolution image element"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_low_resolution_sentinel"
assert_not_contains "$helper_output" "$icon_low_resolution_bundle"

icon_high_resolution_payload_sentinel="ICON_HIGH_RESOLUTION_PAYLOAD_SENTINEL_SHOULD_NOT_LEAK"
icon_high_resolution_payload_bundle="$fixture_root/icon-high-resolution-payload-$icon_high_resolution_payload_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_high_resolution_payload_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x11ic10\x00\x00\x00\x09\x00' >"$icon_high_resolution_payload_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_high_resolution_payload_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_high_resolution_payload_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution image payload has no encoded image signature"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_high_resolution_payload_sentinel"
assert_not_contains "$helper_output" "$icon_high_resolution_payload_bundle"

icon_jpeg2000_magic_sentinel="ICON_JPEG2000_MAGIC_SENTINEL_SHOULD_NOT_LEAK"
icon_jpeg2000_magic_bundle="$fixture_root/icon-jpeg2000-magic-$icon_jpeg2000_magic_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_jpeg2000_magic_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x1cic10\x00\x00\x00\x14\x00\x00\x00\x0cjP  \x0d\x0a\x87\x0a' >"$icon_jpeg2000_magic_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_jpeg2000_magic_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_jpeg2000_magic_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution image payload only has a JPEG 2000 magic header"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_jpeg2000_magic_sentinel"
assert_not_contains "$helper_output" "$icon_jpeg2000_magic_bundle"

icon_png_header_sentinel="ICON_PNG_HEADER_SENTINEL_SHOULD_NOT_LEAK"
icon_png_header_bundle="$fixture_root/icon-png-header-$icon_png_header_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_header_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x18ic10\x00\x00\x00\x10\x89\x50\x4e\x47\x0d\x0a\x1a\x0a' >"$icon_png_header_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_header_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_header_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG payload has no dimensions"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_header_sentinel"
assert_not_contains "$helper_output" "$icon_png_header_bundle"

icon_png_ihdr_metadata_sentinel="ICON_PNG_IHDR_METADATA_SENTINEL_SHOULD_NOT_LEAK"
icon_png_ihdr_metadata_bundle="$fixture_root/icon-png-ihdr-metadata-$icon_png_ihdr_metadata_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_ihdr_metadata_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x31ic10\x00\x00\x00\x29\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0dIHDR\x00\x00\x04\x00\x00\x00\x04\x00\x00\x06\x00\x00\x00\x00\x00\x00\x00' >"$icon_png_ihdr_metadata_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_ihdr_metadata_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_ihdr_metadata_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IHDR metadata is invalid"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_ihdr_metadata_sentinel"
assert_not_contains "$helper_output" "$icon_png_ihdr_metadata_bundle"

icon_png_ihdr_crc_sentinel="ICON_PNG_IHDR_CRC_SENTINEL_SHOULD_NOT_LEAK"
icon_png_ihdr_crc_bundle="$fixture_root/icon-png-ihdr-crc-$icon_png_ihdr_crc_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_ihdr_crc_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x31ic10\x00\x00\x00\x29\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0dIHDR\x00\x00\x04\x00\x00\x00\x04\x00\x08\x06\x00\x00\x00\x00\x00\x00\x00' >"$icon_png_ihdr_crc_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_ihdr_crc_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_ihdr_crc_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IHDR CRC is invalid"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_ihdr_crc_sentinel"
assert_not_contains "$helper_output" "$icon_png_ihdr_crc_bundle"

icon_png_iend_sentinel="ICON_PNG_IEND_SENTINEL_SHOULD_NOT_LEAK"
icon_png_iend_bundle="$fixture_root/icon-png-iend-$icon_png_iend_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_iend_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x31ic10\x00\x00\x00\x29\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0dIHDR\x00\x00\x04\x00\x00\x00\x04\x00\x08\x06\x00\x00\x00\x7f\x1d\x2b\x83' >"$icon_png_iend_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_iend_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_iend_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG payload has no IEND chunk"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_iend_sentinel"
assert_not_contains "$helper_output" "$icon_png_iend_bundle"

icon_png_idat_sentinel="ICON_PNG_IDAT_SENTINEL_SHOULD_NOT_LEAK"
icon_png_idat_bundle="$fixture_root/icon-png-idat-$icon_png_idat_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_idat_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x3dic10\x00\x00\x00\x35\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0dIHDR\x00\x00\x04\x00\x00\x00\x04\x00\x08\x06\x00\x00\x00\x7f\x1d\x2b\x83\x00\x00\x00\x00IEND\xae\x42\x60\x82' >"$icon_png_idat_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_idat_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_idat_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG payload has no IDAT image data"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_idat_sentinel"
assert_not_contains "$helper_output" "$icon_png_idat_bundle"

icon_png_idat_zlib_sentinel="ICON_PNG_IDAT_ZLIB_SENTINEL_SHOULD_NOT_LEAK"
icon_png_idat_zlib_bundle="$fixture_root/icon-png-idat-zlib-$icon_png_idat_zlib_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_idat_zlib_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x4a\x69\x63\x31\x30\x00\x00\x00\x42\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x04\x00\x00\x00\x04\x00\x08\x06\x00\x00\x00\x7f\x1d\x2b\x83\x00\x00\x00\x01\x49\x44\x41\x54\x78\x76\xe6\x84\xe6\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' >"$icon_png_idat_zlib_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_idat_zlib_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_idat_zlib_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT stream is not valid zlib data"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_idat_zlib_sentinel"
assert_not_contains "$helper_output" "$icon_png_idat_zlib_bundle"

icon_png_idat_length_sentinel="ICON_PNG_IDAT_LENGTH_SENTINEL_SHOULD_NOT_LEAK"
icon_png_idat_length_bundle="$fixture_root/icon-png-idat-length-$icon_png_idat_length_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_idat_length_bundle"
printf '\x69\x63\x6e\x73\x00\x00\x00\x52\x69\x63\x31\x30\x00\x00\x00\x4a\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x04\x00\x00\x00\x04\x00\x08\x06\x00\x00\x00\x7f\x1d\x2b\x83\x00\x00\x00\x09\x49\x44\x41\x54\x78\x9c\x63\x00\x00\x00\x01\x00\x01\x5e\xff\x7d\xf9\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' >"$icon_png_idat_length_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_idat_length_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_idat_length_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT stream is too short for the declared dimensions"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_idat_length_sentinel"
assert_not_contains "$helper_output" "$icon_png_idat_length_bundle"

icon_png_filter_byte_sentinel="ICON_PNG_FILTER_BYTE_SENTINEL_SHOULD_NOT_LEAK"
icon_png_filter_byte_bundle="$fixture_root/icon-png-filter-byte-$icon_png_filter_byte_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_filter_byte_bundle"
write_invalid_filter_app_icon_fixture "$icon_png_filter_byte_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_filter_byte_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_filter_byte_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT scanlines use an invalid filter byte"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_filter_byte_sentinel"
assert_not_contains "$helper_output" "$icon_png_filter_byte_bundle"

icon_png_split_idat_sentinel="ICON_PNG_SPLIT_IDAT_SENTINEL_SHOULD_NOT_LEAK"
icon_png_split_idat_bundle="$fixture_root/icon-png-split-idat-$icon_png_split_idat_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_split_idat_bundle"
write_split_idat_app_icon_fixture "$icon_png_split_idat_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_split_idat_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_split_idat_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT chunks are not consecutive"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_split_idat_sentinel"
assert_not_contains "$helper_output" "$icon_png_split_idat_bundle"

icon_png_missing_plte_sentinel="ICON_PNG_MISSING_PLTE_SENTINEL_SHOULD_NOT_LEAK"
icon_png_missing_plte_bundle="$fixture_root/icon-png-missing-plte-$icon_png_missing_plte_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_missing_plte_bundle"
write_indexed_png_without_plte_app_icon_fixture "$icon_png_missing_plte_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_missing_plte_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_missing_plte_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose indexed PNG payload has no PLTE chunk"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_missing_plte_sentinel"
assert_not_contains "$helper_output" "$icon_png_missing_plte_bundle"

icon_png_empty_plte_sentinel="ICON_PNG_EMPTY_PLTE_SENTINEL_SHOULD_NOT_LEAK"
icon_png_empty_plte_bundle="$fixture_root/icon-png-empty-plte-$icon_png_empty_plte_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_empty_plte_bundle"
write_indexed_png_empty_plte_app_icon_fixture "$icon_png_empty_plte_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_empty_plte_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_empty_plte_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose indexed PNG payload has an empty PLTE chunk"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_empty_plte_sentinel"
assert_not_contains "$helper_output" "$icon_png_empty_plte_bundle"

icon_png_duplicate_plte_sentinel="ICON_PNG_DUPLICATE_PLTE_SENTINEL_SHOULD_NOT_LEAK"
icon_png_duplicate_plte_bundle="$fixture_root/icon-png-duplicate-plte-$icon_png_duplicate_plte_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_png_duplicate_plte_bundle"
write_indexed_png_duplicate_plte_app_icon_fixture "$icon_png_duplicate_plte_bundle/Contents/Resources/AppIcon.icns"
chmod 644 "$icon_png_duplicate_plte_bundle/Contents/Resources/AppIcon.icns"
if run_helper_capture "$output_file" "$icon_png_duplicate_plte_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an AppIcon.icns whose indexed PNG payload has duplicate PLTE chunks"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "app icon format is invalid"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_png_duplicate_plte_sentinel"
assert_not_contains "$helper_output" "$icon_png_duplicate_plte_bundle"

icon_name_sentinel="ICON_NAME_SENTINEL_SHOULD_NOT_LEAK"
icon_name_bundle="$fixture_root/icon-name-$icon_name_sentinel/LithePG.app"
make_minimal_app_bundle "$icon_name_bundle"
/usr/bin/sed -i '' 's|<string>AppIcon</string>|<string>WrongIcon</string>|' "$icon_name_bundle/Contents/Info.plist"
if run_helper_capture "$output_file" "$icon_name_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a mismatched CFBundleIconFile"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "CFBundleIconFile mismatch"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$icon_name_sentinel"

path_shadow_sentinel="PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
path_shadow_fake_bin="$fixture_root/path-shadow-fake-bin"
path_shadow_bundle="$fixture_root/path-shadow-$path_shadow_sentinel/LithePG.app"
mkdir -p "$path_shadow_fake_bin"
make_minimal_app_bundle "$path_shadow_bundle"
cat >"$path_shadow_fake_bin/stat" <<SHIM
#!/usr/bin/env bash
printf '%s stat invoked\\n' "$path_shadow_sentinel" >&2
exit 97
SHIM
cat >"$path_shadow_fake_bin/awk" <<SHIM
#!/usr/bin/env bash
printf '%s awk invoked\\n' "$path_shadow_sentinel" >&2
exit 97
SHIM
chmod +x "$path_shadow_fake_bin/stat" "$path_shadow_fake_bin/awk"
if ! PATH="$path_shadow_fake_bin:$PATH" run_helper_capture "$output_file" "$path_shadow_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier was affected by PATH-shadowed stat/awk"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$path_shadow_bundle"
assert_not_contains "$helper_output" "$path_shadow_sentinel"
assert_not_contains "$helper_output" "stat invoked"
assert_not_contains "$helper_output" "awk invoked"

initial_bash_path_shadow_sentinel="INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
initial_bash_path_shadow_fake_bin="$fixture_root/initial-bash-path-shadow-fake-bin"
initial_bash_path_shadow_bundle="$fixture_root/initial-bash-path-shadow-$initial_bash_path_shadow_sentinel/LithePG.app"
initial_bash_path_shadow_marker="$fixture_root/initial-bash-path-shadow-invoked"
mkdir -p "$initial_bash_path_shadow_fake_bin"
make_minimal_app_bundle "$initial_bash_path_shadow_bundle"
cat >"$initial_bash_path_shadow_fake_bin/bash" <<'SHIM'
#!/bin/sh
/usr/bin/printf '%s fake bash invoked\n' "${INITIAL_BASH_PATH_SHADOW_SENTINEL:-}" >&2
/usr/bin/printf 'bash\n' >"${INITIAL_BASH_PATH_SHADOW_MARKER:?}"
exit 97
SHIM
chmod +x "$initial_bash_path_shadow_fake_bin/bash"
if ! INITIAL_BASH_PATH_SHADOW_SENTINEL="$initial_bash_path_shadow_sentinel" \
  INITIAL_BASH_PATH_SHADOW_MARKER="$initial_bash_path_shadow_marker" \
  PATH="$initial_bash_path_shadow_fake_bin:$PATH" \
  run_helper_capture "$output_file" "$initial_bash_path_shadow_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier executable invocation used PATH-selected bash"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$initial_bash_path_shadow_bundle"
assert_not_contains "$helper_output" "$initial_bash_path_shadow_sentinel"
assert_not_contains "$helper_output" "fake bash invoked"
[[ ! -e "$initial_bash_path_shadow_marker" ]] || fail "package verifier executable invocation used PATH-selected bash: $(<"$initial_bash_path_shadow_marker")"

printf_function_shadow_sentinel="PRINTF_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
printf_function_shadow_bundle="$fixture_root/printf-function-shadow-$printf_function_shadow_sentinel/LithePG.app"
printf_function_shadow_marker="$fixture_root/printf-function-shadow-invoked"
make_minimal_app_bundle "$printf_function_shadow_bundle"
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  printf() {
    /usr/bin/printf '%s printf function invoked\n' "${PRINTF_FUNCTION_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'printf\n' >"${PRINTF_FUNCTION_SHADOW_MARKER:?}"
    exit 97
  }
  export -f printf
  PRINTF_FUNCTION_SHADOW_SENTINEL="$printf_function_shadow_sentinel" \
    PRINTF_FUNCTION_SHADOW_MARKER="$printf_function_shadow_marker" \
    "$HELPER" "$printf_function_shadow_bundle"
) >"$output_file" 2>&1
printf_function_shadow_status=$?
set -e
if [[ "$printf_function_shadow_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier was affected by an exported printf function"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$printf_function_shadow_bundle"
assert_not_contains "$helper_output" "$printf_function_shadow_sentinel"
assert_not_contains "$helper_output" "printf function invoked"
[[ ! -e "$printf_function_shadow_marker" ]] || fail "package verifier invoked exported printf function: $(<"$printf_function_shadow_marker")"

exec_function_shadow_sentinel="EXEC_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
exec_function_shadow_bundle="$fixture_root/exec-function-shadow-$exec_function_shadow_sentinel/LithePG.app"
exec_function_shadow_marker="$fixture_root/exec-function-shadow-invoked"
make_minimal_app_bundle "$exec_function_shadow_bundle"
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  exec() {
    /usr/bin/printf '%s exec function invoked\n' "${EXEC_FUNCTION_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'exec\n' >"${EXEC_FUNCTION_SHADOW_MARKER:?}"
    exit 97
  }
  export -f exec
  EXEC_FUNCTION_SHADOW_SENTINEL="$exec_function_shadow_sentinel" \
    EXEC_FUNCTION_SHADOW_MARKER="$exec_function_shadow_marker" \
    "$HELPER" "$exec_function_shadow_bundle"
) >"$output_file" 2>&1
exec_function_shadow_status=$?
set -e
if [[ "$exec_function_shadow_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier was affected by an exported exec function"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$exec_function_shadow_bundle"
assert_not_contains "$helper_output" "$exec_function_shadow_sentinel"
assert_not_contains "$helper_output" "exec function invoked"
[[ ! -e "$exec_function_shadow_marker" ]] || fail "package verifier invoked exported exec function: $(<"$exec_function_shadow_marker")"

set_function_shadow_sentinel="SET_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
set_function_shadow_bundle="$fixture_root/set-function-shadow-$set_function_shadow_sentinel/LithePG.app"
set_function_shadow_marker="$fixture_root/set-function-shadow-invoked"
make_minimal_app_bundle "$set_function_shadow_bundle"
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  set() {
    /usr/bin/printf '%s set function invoked\n' "${SET_FUNCTION_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'set\n' >"${SET_FUNCTION_SHADOW_MARKER:?}"
    exit 97
  }
  export -f set
  SET_FUNCTION_SHADOW_SENTINEL="$set_function_shadow_sentinel" \
    SET_FUNCTION_SHADOW_MARKER="$set_function_shadow_marker" \
    "$HELPER" "$set_function_shadow_bundle"
) >"$output_file" 2>&1
set_function_shadow_status=$?
set -e
if [[ "$set_function_shadow_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier was affected by an exported set function"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$set_function_shadow_bundle"
assert_not_contains "$helper_output" "$set_function_shadow_sentinel"
assert_not_contains "$helper_output" "set function invoked"
[[ ! -e "$set_function_shadow_marker" ]] || fail "package verifier invoked exported set function: $(<"$set_function_shadow_marker")"

bash_env_set_shadow_sentinel="BASH_ENV_SET_SHADOW_SENTINEL_SHOULD_NOT_RUN"
bash_env_set_shadow_bundle="$fixture_root/bash-env-set-shadow-$bash_env_set_shadow_sentinel/LithePG.app"
bash_env_set_shadow_marker="$fixture_root/bash-env-set-shadow-invoked"
bash_env_set_shadow_fixture="$fixture_root/bash-env-set-shadow.bash_env"
make_minimal_app_bundle "$bash_env_set_shadow_bundle"
cat >"$bash_env_set_shadow_fixture" <<'BASHENV'
set() {
  /usr/bin/printf '%s set function invoked\n' "${BASH_ENV_SET_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'set\n' >"${BASH_ENV_SET_SHADOW_MARKER:?}"
  exit 97
}
BASHENV
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  BASH_ENV_SET_SHADOW_SENTINEL="$bash_env_set_shadow_sentinel" \
    BASH_ENV_SET_SHADOW_MARKER="$bash_env_set_shadow_marker" \
    BASH_ENV="$bash_env_set_shadow_fixture" \
    "$HELPER" "$bash_env_set_shadow_bundle"
) >"$output_file" 2>&1
bash_env_set_shadow_status=$?
set -e
if [[ "$bash_env_set_shadow_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier was affected by a BASH_ENV-defined set function"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$bash_env_set_shadow_bundle"
assert_not_contains "$helper_output" "$bash_env_set_shadow_sentinel"
assert_not_contains "$helper_output" "set function invoked"
[[ ! -e "$bash_env_set_shadow_marker" ]] || fail "package verifier invoked BASH_ENV-defined set function: $(<"$bash_env_set_shadow_marker")"

bash_env_unset_then_set_shadow_sentinel="BASH_ENV_UNSET_THEN_SET_SHADOW_SENTINEL_SHOULD_NOT_RUN"
bash_env_unset_then_set_shadow_bundle="$fixture_root/bash-env-unset-then-set-shadow-$bash_env_unset_then_set_shadow_sentinel/LithePG.app"
bash_env_unset_then_set_shadow_marker="$fixture_root/bash-env-unset-then-set-shadow-invoked"
bash_env_unset_then_set_shadow_fixture="$fixture_root/bash-env-unset-then-set-shadow.bash_env"
make_minimal_app_bundle "$bash_env_unset_then_set_shadow_bundle"
cat >"$bash_env_unset_then_set_shadow_fixture" <<'BASHENV'
unset BASH_ENV
set() {
  /usr/bin/printf '%s set function invoked\n' "${BASH_ENV_UNSET_THEN_SET_SHADOW_SENTINEL:?}" >&2
  /usr/bin/printf 'set\n' >"${BASH_ENV_UNSET_THEN_SET_SHADOW_MARKER:?}"
  exit 97
}
BASHENV
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  BASH_ENV_UNSET_THEN_SET_SHADOW_SENTINEL="$bash_env_unset_then_set_shadow_sentinel" \
    BASH_ENV_UNSET_THEN_SET_SHADOW_MARKER="$bash_env_unset_then_set_shadow_marker" \
    BASH_ENV="$bash_env_unset_then_set_shadow_fixture" \
    "$HELPER" "$bash_env_unset_then_set_shadow_bundle"
) >"$output_file" 2>&1
bash_env_unset_then_set_shadow_status=$?
set -e
if [[ "$bash_env_unset_then_set_shadow_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier was affected by a BASH_ENV file that unset BASH_ENV before defining set"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$bash_env_unset_then_set_shadow_bundle"
assert_not_contains "$helper_output" "$bash_env_unset_then_set_shadow_sentinel"
assert_not_contains "$helper_output" "set function invoked"
[[ ! -e "$bash_env_unset_then_set_shadow_marker" ]] || fail "package verifier invoked BASH_ENV-defined set function after BASH_ENV was unset: $(<"$bash_env_unset_then_set_shadow_marker")"

perl_startup_hide_function_sentinel="PERL_STARTUP_HIDE_FUNCTION_SENTINEL_SHOULD_NOT_RUN"
perl_startup_hide_function_bundle="$fixture_root/perl-startup-hide-function-$perl_startup_hide_function_sentinel/LithePG.app"
perl_startup_hide_function_marker="$fixture_root/perl-startup-hide-function-invoked"
perl_startup_hide_function_lib="$fixture_root/perl-startup-hide-function-lib"
make_minimal_app_bundle "$perl_startup_hide_function_bundle"
mkdir -p "$perl_startup_hide_function_lib"
cat >"$perl_startup_hide_function_lib/HideBashFunc.pm" <<'PERLMOD'
package HideBashFunc;
BEGIN {
  for my $key (keys %ENV) {
    delete $ENV{$key} if $key =~ /\ABASH_FUNC_/;
  }
}
1;
PERLMOD
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  set() {
    /usr/bin/printf '%s set function invoked\n' "${PERL_STARTUP_HIDE_FUNCTION_SENTINEL:?}" >&2
    /usr/bin/printf 'set\n' >"${PERL_STARTUP_HIDE_FUNCTION_MARKER:?}"
    exit 97
  }
  export -f set
  PERL_STARTUP_HIDE_FUNCTION_SENTINEL="$perl_startup_hide_function_sentinel" \
    PERL_STARTUP_HIDE_FUNCTION_MARKER="$perl_startup_hide_function_marker" \
    PERL5LIB="$perl_startup_hide_function_lib" \
    PERL5OPT=-MHideBashFunc \
    "$HELPER" "$perl_startup_hide_function_bundle"
) >"$output_file" 2>&1
perl_startup_hide_function_status=$?
set -e
if [[ "$perl_startup_hide_function_status" -ne 0 ]]; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier let Perl startup env hide an exported set function"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_not_contains "$helper_output" "$perl_startup_hide_function_bundle"
assert_not_contains "$helper_output" "$perl_startup_hide_function_sentinel"
assert_not_contains "$helper_output" "set function invoked"
[[ ! -e "$perl_startup_hide_function_marker" ]] || fail "package verifier invoked exported set function hidden by Perl startup env: $(<"$perl_startup_hide_function_marker")"

perl_startup_env_set_shadow_sentinel="PERL_STARTUP_ENV_SET_SHADOW_SENTINEL_SHOULD_NOT_RUN"
perl_startup_env_set_shadow_marker="$fixture_root/perl-startup-env-set-shadow-invoked"
set +e
(
  cd "$ROOT_DIR"
  unset LITHEPG_EXPECTED_MARKETING_VERSION LITHEPG_EXPECTED_BUILD_VERSION
  set() {
    /usr/bin/printf '%s set function invoked\n' "${PERL_STARTUP_ENV_SET_SHADOW_SENTINEL:?}" >&2
    /usr/bin/printf 'set\n' >"${PERL_STARTUP_ENV_SET_SHADOW_MARKER:?}"
    exit 97
  }
  export -f set
  PERL_STARTUP_ENV_SET_SHADOW_SENTINEL="$perl_startup_env_set_shadow_sentinel" \
    PERL_STARTUP_ENV_SET_SHADOW_MARKER="$perl_startup_env_set_shadow_marker" \
    PERL5OPT=-Mdoesnotexist \
    "$HELPER" --help
) >"$output_file" 2>&1
perl_startup_env_set_shadow_status=$?
set -e
helper_output="$(<"$output_file")"
if [[ "$perl_startup_env_set_shadow_status" -ne 0 ]]; then
  printf '%s\n' "$helper_output" >&2
  fail "package verifier honored PERL5OPT before sanitizer detection"
fi
assert_contains "$helper_output" "Usage:"
assert_not_contains "$helper_output" "$perl_startup_env_set_shadow_sentinel"
assert_not_contains "$helper_output" "set function invoked"
[[ ! -e "$perl_startup_env_set_shadow_marker" ]] || fail "package verifier invoked exported set function under PERL5OPT: $(<"$perl_startup_env_set_shadow_marker")"

startup_env_sanitizer_fail_closed_sentinel="PACKAGE_VERIFY_STARTUP_ENV_FAIL_CLOSED_SHOULD_NOT_LEAK"
startup_env_sanitizer_fail_closed_fixture="$fixture_root/startup-env-sanitizer-fail-closed"
startup_env_sanitizer_fail_closed_bash_env="$fixture_root/startup-env-sanitizer-fail-closed.bash_env"
startup_env_sanitizer_fail_closed_marker="$fixture_root/startup-env-sanitizer-fail-closed-marker"
/bin/mkdir -p "$startup_env_sanitizer_fail_closed_fixture/script" "$startup_env_sanitizer_fail_closed_fixture/dist"
/bin/cp "$HELPER" "$startup_env_sanitizer_fail_closed_fixture/script/package_verify.sh"
/bin/chmod +x "$startup_env_sanitizer_fail_closed_fixture/script/package_verify.sh"
make_minimal_app_bundle "$startup_env_sanitizer_fail_closed_fixture/dist/LithePG.app"
/bin/cat >"$startup_env_sanitizer_fail_closed_bash_env" <<'BASHENV'
set() {
  /usr/bin/printf '%s set function invoked\n' "${STARTUP_ENV_SANITIZER_FAIL_CLOSED_SENTINEL:?}" >&2
  /usr/bin/printf 'set\n' >"${STARTUP_ENV_SANITIZER_FAIL_CLOSED_MARKER:?}"
  exit 97
}
BASHENV
set +e
(
  cd "$fixture_root"
  set() {
    /usr/bin/printf '%s exported set function invoked\n' "${STARTUP_ENV_SANITIZER_FAIL_CLOSED_SENTINEL:?}" >&2
    /usr/bin/printf 'exported-set\n' >"${STARTUP_ENV_SANITIZER_FAIL_CLOSED_MARKER:?}"
    exit 97
  }
  export -f set
  STARTUP_ENV_SANITIZER_FAIL_CLOSED_SENTINEL="$startup_env_sanitizer_fail_closed_sentinel" \
    STARTUP_ENV_SANITIZER_FAIL_CLOSED_MARKER="$startup_env_sanitizer_fail_closed_marker" \
    BASH_ENV="$startup_env_sanitizer_fail_closed_bash_env" \
    LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1 \
    "$startup_env_sanitizer_fail_closed_fixture/script/package_verify.sh"
) >"$output_file" 2>&1
startup_env_sanitizer_fail_closed_status=$?
set -e
helper_output="$(<"$output_file")"
if [[ "$startup_env_sanitizer_fail_closed_status" -ne 2 ]]; then
  printf '%s\n' "$helper_output" >&2
  fail "package verifier sanitizer marker with dirty startup env should exit 2, got $startup_env_sanitizer_fail_closed_status"
fi
assert_contains "$helper_output" "package verification failed: dirty startup environment remained after sanitization"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$startup_env_sanitizer_fail_closed_fixture"
assert_not_contains "$helper_output" "$startup_env_sanitizer_fail_closed_sentinel"
assert_not_contains "$helper_output" "set function invoked"
[[ ! -e "$startup_env_sanitizer_fail_closed_marker" ]] || fail "package verifier sanitizer fail-closed invoked startup shadow: $(<"$startup_env_sanitizer_fail_closed_marker")"

startup_env_sanitizer_empty_bash_env_fail_closed_sentinel="PACKAGE_VERIFY_EMPTY_BASH_ENV_FAIL_CLOSED_SHOULD_NOT_LEAK"
startup_env_sanitizer_empty_bash_env_fail_closed_private_value="synthetic-package-verify-empty-bash-env-private-value-SHOULD_NOT_LEAK"
startup_env_sanitizer_empty_bash_env_fail_closed_fixture="$fixture_root/startup-env-sanitizer-empty-bash-env-fail-closed-$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel"
/bin/mkdir -p "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/script" "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/dist"
/bin/cp "$HELPER" "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/script/package_verify.sh"
/bin/chmod +x "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/script/package_verify.sh"
make_minimal_app_bundle "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/dist/LithePG.app"
set +e
(
  cd "$fixture_root"
  STARTUP_ENV_SANITIZER_EMPTY_BASH_ENV_FAIL_CLOSED_SENTINEL="$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel" \
    LITHEPG_TEST_AMBIENT_PRIVATE_VALUE="$startup_env_sanitizer_empty_bash_env_fail_closed_private_value" \
    BASH_ENV= \
    LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1 \
    "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture/script/package_verify.sh"
) >"$output_file" 2>&1
startup_env_sanitizer_empty_bash_env_fail_closed_status=$?
set -e
helper_output="$(<"$output_file")"
if [[ "$startup_env_sanitizer_empty_bash_env_fail_closed_status" -ne 2 ]]; then
  printf '%s\n' "$helper_output" >&2
  fail "package verifier sanitizer marker with empty BASH_ENV should exit 2, got $startup_env_sanitizer_empty_bash_env_fail_closed_status"
fi
assert_contains "$helper_output" "package verification failed: dirty startup environment remained after sanitization"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "Usage:"
assert_not_contains "$helper_output" "$startup_env_sanitizer_empty_bash_env_fail_closed_fixture"
assert_not_contains "$helper_output" "$startup_env_sanitizer_empty_bash_env_fail_closed_sentinel"
assert_not_contains "$helper_output" "$startup_env_sanitizer_empty_bash_env_fail_closed_private_value"

startup_env_sanitizer_fail_closed_perl_sentinel="PACKAGE_VERIFY_STARTUP_ENV_FAIL_CLOSED_PERL_SHOULD_NOT_LEAK"
startup_env_sanitizer_fail_closed_perl_fixture="$fixture_root/startup-env-sanitizer-fail-closed-perl"
/bin/mkdir -p "$startup_env_sanitizer_fail_closed_perl_fixture/script" "$startup_env_sanitizer_fail_closed_perl_fixture/dist"
/bin/cp "$HELPER" "$startup_env_sanitizer_fail_closed_perl_fixture/script/package_verify.sh"
/bin/chmod +x "$startup_env_sanitizer_fail_closed_perl_fixture/script/package_verify.sh"
make_minimal_app_bundle "$startup_env_sanitizer_fail_closed_perl_fixture/dist/LithePG.app"
set +e
(
  cd "$fixture_root"
  STARTUP_ENV_SANITIZER_FAIL_CLOSED_PERL_SENTINEL="$startup_env_sanitizer_fail_closed_perl_sentinel" \
    PERL5OPT=-Mdoesnotexist \
    LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1 \
    "$startup_env_sanitizer_fail_closed_perl_fixture/script/package_verify.sh"
) >"$output_file" 2>&1
startup_env_sanitizer_fail_closed_perl_status=$?
set -e
helper_output="$(<"$output_file")"
if [[ "$startup_env_sanitizer_fail_closed_perl_status" -ne 2 ]]; then
  printf '%s\n' "$helper_output" >&2
  fail "package verifier sanitizer marker with dirty Perl startup env should exit 2, got $startup_env_sanitizer_fail_closed_perl_status"
fi
assert_contains "$helper_output" "package verification failed: dirty startup environment remained after sanitization"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$startup_env_sanitizer_fail_closed_perl_fixture"
assert_not_contains "$helper_output" "$startup_env_sanitizer_fail_closed_perl_sentinel"
assert_not_contains "$helper_output" "doesnotexist"

for empty_perl_env_name in PERL5OPT PERL5LIB PERLLIB; do
  startup_env_sanitizer_empty_perl_fail_closed_sentinel="PACKAGE_VERIFY_EMPTY_${empty_perl_env_name}_FAIL_CLOSED_SHOULD_NOT_LEAK"
  startup_env_sanitizer_empty_perl_fail_closed_private_value="synthetic-package-verify-empty-${empty_perl_env_name}-private-value-SHOULD_NOT_LEAK"
  startup_env_sanitizer_empty_perl_fail_closed_fixture="$fixture_root/startup-env-sanitizer-empty-${empty_perl_env_name}-fail-closed-$startup_env_sanitizer_empty_perl_fail_closed_sentinel"
  /bin/mkdir -p "$startup_env_sanitizer_empty_perl_fail_closed_fixture/script" "$startup_env_sanitizer_empty_perl_fail_closed_fixture/dist"
  /bin/cp "$HELPER" "$startup_env_sanitizer_empty_perl_fail_closed_fixture/script/package_verify.sh"
  /bin/chmod +x "$startup_env_sanitizer_empty_perl_fail_closed_fixture/script/package_verify.sh"
  make_minimal_app_bundle "$startup_env_sanitizer_empty_perl_fail_closed_fixture/dist/LithePG.app"

  set +e
  (
    cd "$fixture_root"
    env \
      "STARTUP_ENV_SANITIZER_EMPTY_PERL_FAIL_CLOSED_SENTINEL=$startup_env_sanitizer_empty_perl_fail_closed_sentinel" \
      "LITHEPG_TEST_AMBIENT_PRIVATE_VALUE=$startup_env_sanitizer_empty_perl_fail_closed_private_value" \
      "$empty_perl_env_name=" \
      LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1 \
      "$startup_env_sanitizer_empty_perl_fail_closed_fixture/script/package_verify.sh"
  ) >"$output_file" 2>&1
  startup_env_sanitizer_empty_perl_fail_closed_status=$?
  set -e

  helper_output="$(<"$output_file")"
  if [[ "$startup_env_sanitizer_empty_perl_fail_closed_status" -ne 2 ]]; then
    printf '%s\n' "$helper_output" >&2
    fail "package verifier sanitizer marker with empty $empty_perl_env_name should exit 2, got $startup_env_sanitizer_empty_perl_fail_closed_status"
  fi
  assert_contains "$helper_output" "package verification failed: dirty startup environment remained after sanitization"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "Usage:"
  assert_not_contains "$helper_output" "$startup_env_sanitizer_empty_perl_fail_closed_fixture"
  assert_not_contains "$helper_output" "$startup_env_sanitizer_empty_perl_fail_closed_sentinel"
  assert_not_contains "$helper_output" "$startup_env_sanitizer_empty_perl_fail_closed_private_value"
done

if ! run_helper_capture "$output_file" "$app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verification unexpectedly failed for a valid fixture"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "Package verified: LithePG.app"
assert_contains "$helper_output" "Bundle ID: dev.omarpr.lithepg"
assert_contains "$helper_output" "Version: 1.0 (100)"

finder_metadata_failure="package verification failed: app bundle must not contain Finder metadata files"

ds_store_metadata_sentinel="DS_STORE_METADATA_SENTINEL_SHOULD_NOT_LEAK"
ds_store_metadata_bundle="$fixture_root/finder-metadata-ds-store-$ds_store_metadata_sentinel/LithePG.app"
make_minimal_app_bundle "$ds_store_metadata_bundle"
mkdir -p "$ds_store_metadata_bundle/Contents/Resources"
printf '%s\n' "$ds_store_metadata_sentinel" >"$ds_store_metadata_bundle/Contents/Resources/.DS_Store"
if run_helper_capture "$output_file" "$ds_store_metadata_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted Finder metadata .DS_Store inside the app bundle"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "$finder_metadata_failure"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$ds_store_metadata_bundle"
assert_not_contains "$helper_output" "$ds_store_metadata_sentinel"
assert_not_contains "$helper_output" ".DS_Store"

macosx_metadata_sentinel="MACOSX_METADATA_SENTINEL_SHOULD_NOT_LEAK"
macosx_metadata_bundle="$fixture_root/finder-metadata-macosx-$macosx_metadata_sentinel/LithePG.app"
make_minimal_app_bundle "$macosx_metadata_bundle"
mkdir -p "$macosx_metadata_bundle/Contents/Resources/__MACOSX"
printf '%s\n' "$macosx_metadata_sentinel" >"$macosx_metadata_bundle/Contents/Resources/__MACOSX/._manifest"
if run_helper_capture "$output_file" "$macosx_metadata_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted Finder metadata __MACOSX directory inside the app bundle"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "$finder_metadata_failure"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$macosx_metadata_bundle"
assert_not_contains "$helper_output" "$macosx_metadata_sentinel"
assert_not_contains "$helper_output" "__MACOSX"
assert_not_contains "$helper_output" "._manifest"

appledouble_metadata_sentinel="APPLEDOUBLE_METADATA_SENTINEL_SHOULD_NOT_LEAK"
appledouble_metadata_bundle="$fixture_root/finder-metadata-appledouble-$appledouble_metadata_sentinel/LithePG.app"
make_minimal_app_bundle "$appledouble_metadata_bundle"
mkdir -p "$appledouble_metadata_bundle/Contents/Resources"
printf '%s\n' "$appledouble_metadata_sentinel" >"$appledouble_metadata_bundle/Contents/Resources/._Icon"
if run_helper_capture "$output_file" "$appledouble_metadata_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted AppleDouble Finder metadata inside the app bundle"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "$finder_metadata_failure"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$appledouble_metadata_bundle"
assert_not_contains "$helper_output" "$appledouble_metadata_sentinel"
assert_not_contains "$helper_output" "._Icon"

metadata_cases=(
  "CFBundleExecutable|CFBundleExecutable mismatch"
  "CFBundleIdentifier|CFBundleIdentifier mismatch"
  "CFBundleName|CFBundleName mismatch"
  "CFBundlePackageType|CFBundlePackageType mismatch"
  "LSMinimumSystemVersion|LSMinimumSystemVersion mismatch"
  "NSPrincipalClass|NSPrincipalClass mismatch"
  "CFBundleShortVersionString|CFBundleShortVersionString is not a numeric release version"
  "CFBundleVersion|CFBundleVersion is not a numeric build version"
)
for metadata_case in "${metadata_cases[@]}"; do
  IFS='|' read -r metadata_key expected_failure <<<"$metadata_case"
  metadata_sentinel="${metadata_key}_METADATA_SENTINEL_SHOULD_NOT_LEAK"
  metadata_bundle="$fixture_root/metadata-$metadata_key/LithePG.app"
  make_minimal_app_bundle "$metadata_bundle"
  /usr/libexec/PlistBuddy -c "Set :$metadata_key $metadata_sentinel" "$metadata_bundle/Contents/Info.plist" >/dev/null
  if run_helper_capture "$output_file" "$metadata_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted invalid $metadata_key metadata"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: $expected_failure"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$metadata_sentinel"
  assert_not_contains "$helper_output" "$metadata_bundle"
done

expected_marketing_sentinel="EXPECTED_MARKETING_VERSION_SENTINEL_SHOULD_NOT_LEAK"
expected_marketing_bundle="$fixture_root/expected-marketing/LithePG.app"
make_minimal_app_bundle "$expected_marketing_bundle"
if run_helper_capture_with_expected_marketing_version "$output_file" "$expected_marketing_sentinel" "$expected_marketing_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted mismatched expected marketing version"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: CFBundleShortVersionString does not match LITHEPG_EXPECTED_MARKETING_VERSION"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$expected_marketing_sentinel"
assert_not_contains "$helper_output" "$expected_marketing_bundle"

expected_build_sentinel="EXPECTED_BUILD_VERSION_SENTINEL_SHOULD_NOT_LEAK"
expected_build_bundle="$fixture_root/expected-build/LithePG.app"
make_minimal_app_bundle "$expected_build_bundle"
if run_helper_capture_with_expected_build_version "$output_file" "$expected_build_sentinel" "$expected_build_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted mismatched expected build version"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: CFBundleVersion does not match LITHEPG_EXPECTED_BUILD_VERSION"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$expected_build_sentinel"
assert_not_contains "$helper_output" "$expected_build_bundle"

missing_app_sentinel="MISSING_APP_SENTINEL_SHOULD_NOT_LEAK"
missing_app_bundle="$fixture_root/$missing_app_sentinel/LithePG.app"
if run_helper_capture "$output_file" "$missing_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a nonexistent LithePG.app path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle not found"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$missing_app_bundle"
assert_not_contains "$helper_output" "$missing_app_sentinel"

trailing_slash_sentinel="TRAILING_SLASH_SENTINEL_SHOULD_NOT_LEAK"
trailing_slash_app_bundle="$fixture_root/$trailing_slash_sentinel/LithePG.app"
make_minimal_app_bundle "$trailing_slash_app_bundle"
if run_helper_capture "$output_file" "$trailing_slash_app_bundle/"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an app bundle path with a trailing slash"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not end with a slash"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$trailing_slash_sentinel"

symlink_sentinel="SYMLINK_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlink_target_bundle="$fixture_root/$symlink_sentinel/LithePG.app"
make_minimal_app_bundle "$symlink_target_bundle"
symlink_parent="$fixture_root/symlink-input"
mkdir -p "$symlink_parent"
symlinked_app_bundle="$symlink_parent/LithePG.app"
ln -s "$symlink_target_bundle" "$symlinked_app_bundle"
if run_helper_capture "$output_file" "$symlinked_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked app bundle path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not be a symlink"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlink_sentinel"

if run_helper_capture "$output_file" "$symlinked_app_bundle/"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked app bundle path with a trailing slash"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not end with a slash"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlink_sentinel"

dangling_symlink_sentinel="DANGLING_SYMLINK_TARGET_SENTINEL_SHOULD_NOT_LEAK"
dangling_symlink_parent="$fixture_root/dangling-symlink-input"
mkdir -p "$dangling_symlink_parent"
dangling_symlinked_app_bundle="$dangling_symlink_parent/LithePG.app"
dangling_symlink_target="$fixture_root/$dangling_symlink_sentinel/LithePG.app"
ln -s "$dangling_symlink_target" "$dangling_symlinked_app_bundle"
if run_helper_capture "$output_file" "$dangling_symlinked_app_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a dangling symlinked app bundle path"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle path must not be a symlink"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$dangling_symlink_sentinel"
assert_not_contains "$helper_output" "$dangling_symlinked_app_bundle"

for unsafe_mode in 4755 2755 1755; do
  app_bundle_mode_sentinel="APP_BUNDLE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  app_bundle_mode_path="$fixture_root/app-bundle-mode-$unsafe_mode-$app_bundle_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$app_bundle_mode_path"
  chmod "$unsafe_mode" "$app_bundle_mode_path"
  if run_helper_capture "$output_file" "$app_bundle_mode_path"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on LithePG.app"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app bundle directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$app_bundle_mode_path"
  assert_not_contains "$helper_output" "$app_bundle_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 775 757; do
  app_bundle_mode_sentinel="APP_BUNDLE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  app_bundle_mode_path="$fixture_root/app-bundle-mode-$unsafe_mode-$app_bundle_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$app_bundle_mode_path"
  chmod "$unsafe_mode" "$app_bundle_mode_path"
  if run_helper_capture "$output_file" "$app_bundle_mode_path"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on LithePG.app"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app bundle directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$app_bundle_mode_path"
  assert_not_contains "$helper_output" "$app_bundle_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

symlinked_contents_sentinel="SYMLINKED_CONTENTS_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_contents_bundle="$fixture_root/symlinked-contents/LithePG.app"
make_minimal_app_bundle "$symlinked_contents_bundle"
symlinked_contents_target="$fixture_root/$symlinked_contents_sentinel/Contents-target"
mkdir -p "${symlinked_contents_target%/*}"
mv "$symlinked_contents_bundle/Contents" "$symlinked_contents_target"
ln -s "$symlinked_contents_target" "$symlinked_contents_bundle/Contents"
if run_helper_capture "$output_file" "$symlinked_contents_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked Contents directory"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: Contents directory must be a non-symlink directory"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_contents_sentinel"
assert_not_contains "$helper_output" "Contents-target"

symlinked_macos_sentinel="SYMLINKED_MACOS_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_macos_bundle="$fixture_root/symlinked-macos/LithePG.app"
make_minimal_app_bundle "$symlinked_macos_bundle"
symlinked_macos_target="$fixture_root/$symlinked_macos_sentinel/MacOS-target"
mkdir -p "${symlinked_macos_target%/*}"
mv "$symlinked_macos_bundle/Contents/MacOS" "$symlinked_macos_target"
ln -s "$symlinked_macos_target" "$symlinked_macos_bundle/Contents/MacOS"
if run_helper_capture "$output_file" "$symlinked_macos_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked Contents/MacOS directory"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: Contents/MacOS directory must be a non-symlink directory"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_macos_sentinel"
assert_not_contains "$helper_output" "MacOS-target"

for unsafe_mode in 4755 2755 1755; do
  contents_mode_sentinel="CONTENTS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  contents_mode_bundle="$fixture_root/contents-mode-$unsafe_mode-$contents_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$contents_mode_bundle"
  chmod "$unsafe_mode" "$contents_mode_bundle/Contents"
  if run_helper_capture "$output_file" "$contents_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$contents_mode_bundle"
  assert_not_contains "$helper_output" "$contents_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 775 757; do
  contents_mode_sentinel="CONTENTS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  contents_mode_bundle="$fixture_root/contents-mode-$unsafe_mode-$contents_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$contents_mode_bundle"
  chmod "$unsafe_mode" "$contents_mode_bundle/Contents"
  if run_helper_capture "$output_file" "$contents_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$contents_mode_bundle"
  assert_not_contains "$helper_output" "$contents_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 4755 2755 1755; do
  macos_mode_sentinel="MACOS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  macos_mode_bundle="$fixture_root/macos-mode-$unsafe_mode-$macos_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$macos_mode_bundle"
  chmod "$unsafe_mode" "$macos_mode_bundle/Contents/MacOS"
  if run_helper_capture "$output_file" "$macos_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents/MacOS"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents/MacOS directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$macos_mode_bundle"
  assert_not_contains "$helper_output" "$macos_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 775 757; do
  macos_mode_sentinel="MACOS_MODE_SENTINEL_SHOULD_NOT_LEAK"
  macos_mode_bundle="$fixture_root/macos-mode-$unsafe_mode-$macos_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$macos_mode_bundle"
  chmod "$unsafe_mode" "$macos_mode_bundle/Contents/MacOS"
  if run_helper_capture "$output_file" "$macos_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on Contents/MacOS"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Contents/MacOS directory mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$macos_mode_bundle"
  assert_not_contains "$helper_output" "$macos_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

symlinked_executable_sentinel="SYMLINKED_EXECUTABLE_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_executable_bundle="$fixture_root/symlinked-executable/LithePG.app"
make_minimal_app_bundle "$symlinked_executable_bundle"
symlinked_executable_target_dir="$fixture_root/$symlinked_executable_sentinel"
symlinked_executable_target="$symlinked_executable_target_dir/LithePGApp-target"
mkdir -p "$symlinked_executable_target_dir"
cat >"$symlinked_executable_target" <<'APP'
#!/usr/bin/env bash
printf 'LithePG symlink executable target fixture\n'
APP
chmod +x "$symlinked_executable_target"
rm "$symlinked_executable_bundle/Contents/MacOS/LithePGApp"
ln -s "$symlinked_executable_target" "$symlinked_executable_bundle/Contents/MacOS/LithePGApp"
if run_helper_capture "$output_file" "$symlinked_executable_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked app executable"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app executable must be a regular file"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_executable_sentinel"
assert_not_contains "$helper_output" "LithePGApp-target"

symlinked_plist_sentinel="SYMLINKED_INFO_PLIST_TARGET_SENTINEL_SHOULD_NOT_LEAK"
symlinked_plist_bundle="$fixture_root/symlinked-info-plist/LithePG.app"
make_minimal_app_bundle "$symlinked_plist_bundle"
symlinked_plist_target_dir="$fixture_root/$symlinked_plist_sentinel"
symlinked_plist_target="$symlinked_plist_target_dir/Info-target.plist"
mkdir -p "$symlinked_plist_target_dir"
cp "$symlinked_plist_bundle/Contents/Info.plist" "$symlinked_plist_target"
rm "$symlinked_plist_bundle/Contents/Info.plist"
ln -s "$symlinked_plist_target" "$symlinked_plist_bundle/Contents/Info.plist"
if run_helper_capture "$output_file" "$symlinked_plist_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a symlinked Info.plist"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: Info.plist must be a regular file"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$symlinked_plist_sentinel"
assert_not_contains "$helper_output" "Info-target.plist"

resource_symlink_sentinel="RESOURCE_SYMLINK_SENTINEL_SHOULD_NOT_LEAK"
resource_symlink_bundle="$fixture_root/resource-symlink/LithePG.app"
make_minimal_app_bundle "$resource_symlink_bundle"
mkdir -p "$resource_symlink_bundle/Contents/Resources"
printf '%s\n' "$resource_symlink_sentinel" >"$resource_symlink_bundle/Contents/Resources/target.txt"
ln -s target.txt "$resource_symlink_bundle/Contents/Resources/resource-link"
if run_helper_capture "$output_file" "$resource_symlink_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a resource symlink inside the app bundle"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle must not contain symlinks"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$resource_symlink_bundle"
assert_not_contains "$helper_output" "$resource_symlink_sentinel"
assert_not_contains "$helper_output" "target.txt"
assert_not_contains "$helper_output" "resource-link"

special_file_sentinel="SPECIAL_FILE_FIFO_SENTINEL_SHOULD_NOT_LEAK"
special_file_bundle="$fixture_root/special-file-$special_file_sentinel/LithePG.app"
special_file_fifo_name="special-fifo-should-not-leak"
make_minimal_app_bundle "$special_file_bundle"
mkdir -p "$special_file_bundle/Contents/Resources"
/usr/bin/mkfifo "$special_file_bundle/Contents/Resources/$special_file_fifo_name"
if run_helper_capture "$output_file" "$special_file_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a special file inside the app bundle"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle must contain only regular files and directories"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$special_file_bundle"
assert_not_contains "$helper_output" "$special_file_sentinel"
assert_not_contains "$helper_output" "$special_file_fifo_name"

hardlinked_file_sentinel="HARDLINKED_FILE_SENTINEL_SHOULD_NOT_LEAK"
hardlinked_file_bundle="$fixture_root/hardlinked-file-$hardlinked_file_sentinel/LithePG.app"
hardlinked_external_target="$fixture_root/hardlinked-external-target"
make_minimal_app_bundle "$hardlinked_file_bundle"
rm "$hardlinked_file_bundle/Contents/MacOS/LithePGApp"
cp /usr/bin/true "$hardlinked_external_target"
ln "$hardlinked_external_target" "$hardlinked_file_bundle/Contents/MacOS/LithePGApp"
chmod 755 "$hardlinked_file_bundle/Contents/MacOS/LithePGApp"
if run_helper_capture "$output_file" "$hardlinked_file_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted a hard-linked file inside the app bundle"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle must not contain hard-linked files"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$hardlinked_file_bundle"
assert_not_contains "$helper_output" "$hardlinked_file_sentinel"
assert_not_contains "$helper_output" "hardlinked-external-target"

unreadable_symlink_sentinel="UNREADABLE_SYMLINK_SENTINEL_SHOULD_NOT_LEAK"
unreadable_symlink_bundle="$fixture_root/unreadable-symlink/LithePG.app"
make_minimal_app_bundle "$unreadable_symlink_bundle"
unreadable_symlink_dir="$unreadable_symlink_bundle/Contents/Resources/sealed"
mkdir -p "$unreadable_symlink_dir"
printf '%s\n' "$unreadable_symlink_sentinel" >"$unreadable_symlink_dir/target.txt"
ln -s target.txt "$unreadable_symlink_dir/hidden-link"
chmod 000 "$unreadable_symlink_dir"
if run_helper_capture "$output_file" "$unreadable_symlink_bundle"; then
  chmod u+rwx "$unreadable_symlink_dir"
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an uninspectable bundle tree"
fi
chmod u+rwx "$unreadable_symlink_dir"
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle must not contain symlinks"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$unreadable_symlink_bundle"
assert_not_contains "$helper_output" "$unreadable_symlink_sentinel"
assert_not_contains "$helper_output" "target.txt"
assert_not_contains "$helper_output" "hidden-link"
assert_not_contains "$helper_output" "sealed"

for unsafe_mode in 775 1755; do
  nested_directory_mode_sentinel="NESTED_DIRECTORY_MODE_SENTINEL_SHOULD_NOT_LEAK"
  nested_directory_mode_bundle="$fixture_root/nested-directory-mode-$unsafe_mode-$nested_directory_mode_sentinel/LithePG.app"
  nested_directory_name="nested-directory-mode-name-should-not-leak"
  make_minimal_app_bundle "$nested_directory_mode_bundle"
  mkdir -p "$nested_directory_mode_bundle/Contents/Resources/$nested_directory_name"
  chmod "$unsafe_mode" "$nested_directory_mode_bundle/Contents/Resources/$nested_directory_name"
  if run_helper_capture "$output_file" "$nested_directory_mode_bundle"; then
    chmod u+rwx "$nested_directory_mode_bundle/Contents/Resources/$nested_directory_name"
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on a nested app-bundle directory"
  fi
  chmod u+rwx "$nested_directory_mode_bundle/Contents/Resources/$nested_directory_name"
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app bundle contains unsafe directory mode"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$nested_directory_mode_bundle"
  assert_not_contains "$helper_output" "$nested_directory_mode_sentinel"
  assert_not_contains "$helper_output" "$nested_directory_name"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 664 4755; do
  nested_file_mode_sentinel="NESTED_FILE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  nested_file_mode_bundle="$fixture_root/nested-file-mode-$unsafe_mode-$nested_file_mode_sentinel/LithePG.app"
  nested_file_name="nested-file-mode-name-should-not-leak.txt"
  make_minimal_app_bundle "$nested_file_mode_bundle"
  mkdir -p "$nested_file_mode_bundle/Contents/Resources"
  printf '%s\n' "$nested_file_mode_sentinel" >"$nested_file_mode_bundle/Contents/Resources/$nested_file_name"
  chmod "$unsafe_mode" "$nested_file_mode_bundle/Contents/Resources/$nested_file_name"
  if run_helper_capture "$output_file" "$nested_file_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted unsafe mode $unsafe_mode on a nested app-bundle file"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app bundle contains unsafe file mode"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$nested_file_mode_bundle"
  assert_not_contains "$helper_output" "$nested_file_mode_sentinel"
  assert_not_contains "$helper_output" "$nested_file_name"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 4755 2755 1755; do
  info_plist_special_mode_sentinel="INFO_PLIST_SPECIAL_MODE_SENTINEL_SHOULD_NOT_LEAK"
  info_plist_special_mode_bundle="$fixture_root/info-plist-special-mode-$unsafe_mode-$info_plist_special_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$info_plist_special_mode_bundle"
  chmod "$unsafe_mode" "$info_plist_special_mode_bundle/Contents/Info.plist"
  if run_helper_capture "$output_file" "$info_plist_special_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted special mode $unsafe_mode on Info.plist"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Info.plist mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$info_plist_special_mode_bundle"
  assert_not_contains "$helper_output" "$info_plist_special_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

for unsafe_mode in 664 646; do
  info_plist_writable_mode_sentinel="INFO_PLIST_WRITABLE_MODE_SENTINEL_SHOULD_NOT_LEAK"
  info_plist_writable_mode_bundle="$fixture_root/info-plist-writable-mode-$unsafe_mode-$info_plist_writable_mode_sentinel/LithePG.app"
  make_minimal_app_bundle "$info_plist_writable_mode_bundle"
  chmod "$unsafe_mode" "$info_plist_writable_mode_bundle/Contents/Info.plist"
  if run_helper_capture "$output_file" "$info_plist_writable_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted mode $unsafe_mode on Info.plist"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: Info.plist mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
  assert_not_contains "$helper_output" "$info_plist_writable_mode_bundle"
  assert_not_contains "$helper_output" "$info_plist_writable_mode_sentinel"
  assert_not_contains "$helper_output" "$unsafe_mode"
done

wrong_basename_bundle="$fixture_root/NotLithePG.app"
make_minimal_app_bundle "$wrong_basename_bundle"
if run_helper_capture "$output_file" "$wrong_basename_bundle"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an app bundle with the wrong basename"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "package verification failed: app bundle basename must be LithePG.app"
assert_not_contains "$helper_output" "Package verified:"

for unsafe_mode in 4755 2755 1755; do
  special_mode_bundle="$fixture_root/special-mode-$unsafe_mode/LithePG.app"
  make_minimal_app_bundle "$special_mode_bundle"
  chmod "$unsafe_mode" "$special_mode_bundle/Contents/MacOS/LithePGApp"
  if run_helper_capture "$output_file" "$special_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted special mode $unsafe_mode on the app executable"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app executable mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
done

for unsafe_mode in 775 757; do
  writable_mode_bundle="$fixture_root/writable-mode-$unsafe_mode/LithePG.app"
  make_minimal_app_bundle "$writable_mode_bundle"
  chmod "$unsafe_mode" "$writable_mode_bundle/Contents/MacOS/LithePGApp"
  if run_helper_capture "$output_file" "$writable_mode_bundle"; then
    helper_output="$(<"$output_file")"
    printf '%s\n' "$helper_output" >&2
    fail "package verifier unexpectedly accepted mode $unsafe_mode on the app executable"
  fi
  helper_output="$(<"$output_file")"
  assert_contains "$helper_output" "package verification failed: app executable mode is unsafe"
  assert_not_contains "$helper_output" "Package verified:"
done

extra_arg_sentinel="EXTRA_ARG_SHOULD_NOT_BE_USED_OR_LEAKED"
if run_helper_capture "$output_file" "$app_bundle" "$extra_arg_sentinel"; then
  helper_output="$(<"$output_file")"
  printf '%s\n' "$helper_output" >&2
  fail "package verifier unexpectedly accepted an extra positional argument"
fi
helper_output="$(<"$output_file")"
assert_contains "$helper_output" "too many arguments"
assert_not_contains "$helper_output" "Package verified:"
assert_not_contains "$helper_output" "$extra_arg_sentinel"

printf 'test_package_verify passed\n'
