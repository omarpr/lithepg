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
  if [[ "${LITHEPG_BUILD_AND_RUN_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after build_and_run sanitizer\n' >&2
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
    $ENV{LITHEPG_BUILD_AND_RUN_STARTUP_ENV_SANITIZED} = "1";
    exec { $bash } $bash, "-p", @ARGV;
    die "exec $bash: $!\n";
  ' "$BASH_BIN" "${BASH_SOURCE[0]}" "$@"
  exit $?
fi

if [[ "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
  /usr/bin/printf 'unsanitized Perl startup environment remains\n' >&2
  exit 2
elif ! /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl -e '
  for my $key (keys %ENV) {
    die "unsanitized bash function environment key remains: $key\n" if $key =~ /\ABASH_FUNC_/;
  }
  die "unsanitized BASH_ENV remains\n" if exists $ENV{BASH_ENV};
  exit 0;
'; then
  exit 2
fi

set -euo pipefail

MODE="${1:-run}"
APP_NAME="LithePGApp"
BUNDLE_NAME="LithePG"
BUNDLE_ID="dev.omarpr.lithepg"
MIN_SYSTEM_VERSION="14.0"
AWK=/usr/bin/awk
CAT=/bin/cat
CHMOD=/bin/chmod
CODESIGN=/usr/bin/codesign
CP=/bin/cp
DITTO=/usr/bin/ditto
MKDIR=/bin/mkdir
PERL=/usr/bin/perl
OPEN="${LITHEPG_BUILD_AND_RUN_OPEN:-/usr/bin/open}"
PGREP="${LITHEPG_BUILD_AND_RUN_PGREP:-/usr/bin/pgrep}"
PKILL="${LITHEPG_BUILD_AND_RUN_PKILL:-/usr/bin/pkill}"
RM=/bin/rm
SLEEP="${LITHEPG_BUILD_AND_RUN_SLEEP:-/bin/sleep}"
STAT=/usr/bin/stat
STRIP=/usr/bin/strip
XCRUN=/usr/bin/xcrun

require_absolute_tool_path() {
  local name="$1"
  local value="$2"
  if [[ "$value" != /* ]]; then
    printf '%s must be an absolute path: %s\n' "$name" "$value" >&2
    exit 2
  fi
}

require_absolute_tool_path LITHEPG_BUILD_AND_RUN_OPEN "$OPEN"
require_absolute_tool_path LITHEPG_BUILD_AND_RUN_PGREP "$PGREP"
require_absolute_tool_path LITHEPG_BUILD_AND_RUN_PKILL "$PKILL"
require_absolute_tool_path LITHEPG_BUILD_AND_RUN_SLEEP "$SLEEP"

usage() {
  "$CAT" <<'USAGE'
usage: script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify|--print-bundle-path|--package]

Build and run, inspect, or package the LithePG macOS app.

Modes:
  run                  Build debug app and open it (default)
  --debug              Build debug app and start lldb
  --logs               Build debug app, open it, and stream app process logs
  --telemetry          Build debug app, open it, and stream subsystem logs
  --verify             Build debug app, open it, and verify the process starts
  --print-bundle-path  Print the generated app bundle path
  --package            Build release app bundle under dist/LithePG.app and verify it
USAGE
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Sources/LithePGApp/LithePGApp.entitlements"
ICON_SOURCE="$ROOT_DIR/packaging/AppIcon.icns"
NOTARY_ZIP="$DIST_DIR/$BUNDLE_NAME-notary.zip"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

run_from_root() {
  "$PERL" -e '
    use strict;
    use warnings;
    my $root = shift @ARGV;
    chdir $root or die "chdir $root: $!\n";
    $ENV{PWD} = $root;
    @ARGV or die "exec: missing command\n";
    exec { $ARGV[0] } @ARGV;
    die "exec $ARGV[0]: $!\n";
  ' "$ROOT_DIR" "$@"
}

LATEST_TAG="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
TAG_VERSION="${LATEST_TAG#v}"
TAG_VERSION="${TAG_VERSION%%-*}"
if [[ "$TAG_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  TAG_VERSION="${TAG_VERSION}.0"
fi
MARKETING_VERSION="${LITHEPG_MARKETING_VERSION:-$TAG_VERSION}"
MARKETING_VERSION="${MARKETING_VERSION:-0.0.0}"
BUILD_VERSION="${LITHEPG_BUILD_VERSION:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '0')}"

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'build failed: LITHEPG_MARKETING_VERSION must use SemVer major.minor.patch\n' >&2
  exit 2
fi

case "$MODE" in
  --package|package|release)
    BUILD_CONFIG="release"
    ;;
  *)
    BUILD_CONFIG="debug"
    "$PKILL" -x "$APP_NAME" >/dev/null 2>&1 || true
    ;;
esac

if [[ "$BUILD_CONFIG" == "release" ]]; then
  run_from_root swift build -c release --product "$APP_NAME"
  BUILD_BINARY="$(run_from_root swift build -c release --show-bin-path)/$APP_NAME"
else
  run_from_root swift build --product "$APP_NAME"
  BUILD_BINARY="$(run_from_root swift build --show-bin-path)/$APP_NAME"
fi

if [[ ! -f "$ICON_SOURCE" || -L "$ICON_SOURCE" ]]; then
  /usr/bin/printf 'build_and_run failed: app icon asset missing\n' >&2
  exit 2
fi

"$RM" -rf "$APP_BUNDLE"
"$MKDIR" -p "$APP_MACOS"
"$CHMOD" 755 "$APP_BUNDLE" "$APP_CONTENTS" "$APP_MACOS"
"$CP" "$BUILD_BINARY" "$APP_BINARY"
"$CHMOD" 755 "$APP_BINARY"
"$MKDIR" -p "$APP_RESOURCES"
"$CHMOD" 755 "$APP_RESOURCES"
"$CP" "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
"$CHMOD" 644 "$APP_RESOURCES/AppIcon.icns"
if [[ "$BUILD_CONFIG" == "release" ]]; then
  BEFORE_BYTES=$("$STAT" -f%z "$APP_BINARY")
  "$STRIP" -x "$APP_BINARY" >/dev/null 2>&1 || true
  AFTER_BYTES=$("$STAT" -f%z "$APP_BINARY")
fi

"$CAT" >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
"$CHMOD" 644 "$INFO_PLIST"

sign_release_bundle() {
  local identity="${LITHEPG_CODESIGN_IDENTITY:--}"
  # Prefer an existing persistent local dev identity over ad-hoc signing so
  # Keychain "Always Allow" choices survive rebuilds.
  if [[ "$identity" == "-" ]] \
    && /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "LithePG Local Dev"; then
    identity="LithePG Local Dev"
  fi
  local -a sign_args=(
    --force
    --options runtime
    --entitlements "$ENTITLEMENTS"
    --sign "$identity"
  )
  if [[ "$identity" != "-" ]]; then
    sign_args+=(--timestamp)
  fi
  "$CODESIGN" "${sign_args[@]}" "$APP_BUNDLE"
  "$CODESIGN" --verify --strict --deep "$APP_BUNDLE"
}

notarize_release_bundle() {
  [[ -n "${LITHEPG_NOTARY_PROFILE:-}" ]] || return 0
  "$DITTO" -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  "$XCRUN" notarytool submit "$NOTARY_ZIP" --keychain-profile "$LITHEPG_NOTARY_PROFILE" --wait
  "$XCRUN" stapler staple "$APP_BUNDLE"
}

if [[ "$BUILD_CONFIG" == "release" ]]; then
  sign_release_bundle
  notarize_release_bundle
fi

open_app() {
  "$OPEN" -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    "$SLEEP" 1
    "$PGREP" -x "$APP_NAME" >/dev/null
    ;;
  --print-bundle-path|print-bundle-path)
    printf '%s\n' "$APP_BUNDLE"
    ;;
  --package|package|release)
    BEFORE_MIB=$("$AWK" "BEGIN { printf \"%.2f\", $BEFORE_BYTES / 1024 / 1024 }")
    AFTER_MIB=$("$AWK" "BEGIN { printf \"%.2f\", $AFTER_BYTES / 1024 / 1024 }")
    /bin/bash "$ROOT_DIR/script/package_verify.sh" "$APP_BUNDLE"
    printf 'Built %s (%s -> %s MiB after strip -x)\n' "$APP_BUNDLE" "$BEFORE_MIB" "$AFTER_MIB"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--print-bundle-path|--package]" >&2
    exit 2
    ;;
esac
