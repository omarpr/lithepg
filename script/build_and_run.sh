#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LithePGApp"
BUNDLE_NAME="LithePG"
BUNDLE_ID="dev.omarpr.lithepg"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Sources/LithePGApp/LithePGApp.entitlements"
NOTARY_ZIP="$DIST_DIR/$BUNDLE_NAME-notary.zip"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$ROOT_DIR"

case "$MODE" in
  --package|package|release)
    BUILD_CONFIG="release"
    ;;
  *)
    BUILD_CONFIG="debug"
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    ;;
esac

if [[ "$BUILD_CONFIG" == "release" ]]; then
  swift build -c release --product "$APP_NAME"
  BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
else
  swift build --product "$APP_NAME"
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ "$BUILD_CONFIG" == "release" ]]; then
  BEFORE_BYTES=$(stat -f%z "$APP_BINARY")
  strip -x "$APP_BINARY" >/dev/null 2>&1 || true
  AFTER_BYTES=$(stat -f%z "$APP_BINARY")
fi

cat >"$INFO_PLIST" <<PLIST
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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

sign_release_bundle() {
  local identity="${LITHEPG_CODESIGN_IDENTITY:--}"
  local -a sign_args=(
    --force
    --options runtime
    --entitlements "$ENTITLEMENTS"
    --sign "$identity"
  )
  if [[ "$identity" != "-" ]]; then
    sign_args+=(--timestamp)
  fi
  codesign "${sign_args[@]}" "$APP_BUNDLE"
  codesign --verify --strict --deep "$APP_BUNDLE"
}

notarize_release_bundle() {
  [[ -n "${LITHEPG_NOTARY_PROFILE:-}" ]] || return 0
  ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$LITHEPG_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
}

if [[ "$BUILD_CONFIG" == "release" ]]; then
  sign_release_bundle
  notarize_release_bundle
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --print-bundle-path|print-bundle-path)
    printf '%s\n' "$APP_BUNDLE"
    ;;
  --package|package|release)
    BEFORE_MIB=$(awk "BEGIN { printf \"%.2f\", $BEFORE_BYTES / 1024 / 1024 }")
    AFTER_MIB=$(awk "BEGIN { printf \"%.2f\", $AFTER_BYTES / 1024 / 1024 }")
    printf 'Built %s (%s -> %s MiB after strip -x)\n' "$APP_BUNDLE" "$BEFORE_MIB" "$AFTER_MIB"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--print-bundle-path|--package]" >&2
    exit 2
    ;;
esac
