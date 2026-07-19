#!/bin/bash -p

set -euo pipefail

CAT=/bin/cat
DITTO=/usr/bin/ditto
MKTEMP=/usr/bin/mktemp
MV=/bin/mv
OPEN=/usr/bin/open
PKILL=/usr/bin/pkill
PLIST_BUDDY=/usr/libexec/PlistBuddy
RM=/bin/rm
SUDO=/usr/bin/sudo

usage() {
  "$CAT" <<'USAGE'
usage: script/rebuild_and_install.sh [--no-open]

Build a fresh release bundle, verify it, replace /Applications/LithePG.app,
verify the installed copy, and open it. Use --no-open to leave it closed.

Environment:
  LITHEPG_MARKETING_VERSION  App version to build (default: 1.0)
USAGE
}

open_after_install=1
case "${1:-}" in
  "") ;;
  --no-open) open_after_install=0 ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
SOURCE_APP="$ROOT_DIR/dist/LithePG.app"
EXPECTED_BUNDLE_ID="dev.omarpr.lithepg"

# The override is a narrow test seam. Normal runs always use /Applications.
APPLICATIONS_DIR="${LITHEPG_INSTALL_APPLICATIONS_DIR:-/Applications}"
if [[ "$APPLICATIONS_DIR" != /* || ! -d "$APPLICATIONS_DIR" || -L "$APPLICATIONS_DIR" ]]; then
  /usr/bin/printf 'install failed: applications directory must be an absolute, real directory: %s\n' \
    "$APPLICATIONS_DIR" >&2
  exit 2
fi
DESTINATION="$APPLICATIONS_DIR/LithePG.app"

bundle_identifier() {
  local app="$1"
  "$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true
}

if [[ -L "$DESTINATION" ]]; then
  /usr/bin/printf 'install failed: refusing to replace a symlink at %s\n' "$DESTINATION" >&2
  exit 2
fi
if [[ -e "$DESTINATION" ]]; then
  if [[ ! -d "$DESTINATION" ]]; then
    /usr/bin/printf 'install failed: destination is not an app directory: %s\n' "$DESTINATION" >&2
    exit 2
  fi
  installed_bundle_id="$(bundle_identifier "$DESTINATION")"
  if [[ "$installed_bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
    /usr/bin/printf \
      'install failed: refusing to replace an app whose bundle identifier is %s\n' \
      "${installed_bundle_id:-missing}" >&2
    exit 2
  fi
fi

MARKETING_VERSION="${LITHEPG_MARKETING_VERSION:-1.0}"
(
  cd "$ROOT_DIR"
  LITHEPG_MARKETING_VERSION="$MARKETING_VERSION" \
    "$ROOT_DIR/script/build_and_run.sh" --package
)
"$ROOT_DIR/script/package_verify.sh" "$SOURCE_APP"

if [[ "$(bundle_identifier "$SOURCE_APP")" != "$EXPECTED_BUNDLE_ID" ]]; then
  /usr/bin/printf 'install failed: built app has an unexpected bundle identifier\n' >&2
  exit 2
fi

if [[ "${LITHEPG_INSTALL_SKIP_QUIT:-0}" != "1" ]]; then
  "$PKILL" -x LithePGApp >/dev/null 2>&1 || true
fi

needs_sudo=0
if [[ ! -w "$APPLICATIONS_DIR" ]]; then
  needs_sudo=1
fi

run_install_command() {
  if [[ "$needs_sudo" == "1" ]]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
}

backup_root="$($MKTEMP -d /private/tmp/lithepg-install.XXXXXX)"
backup_app="$backup_root/LithePG.app"
previous_saved=0
install_complete=0

cleanup() {
  local status=$?
  trap - EXIT INT TERM

  if [[ "$status" != "0" && "$install_complete" != "1" ]]; then
    if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
      run_install_command "$RM" -rf -- "$DESTINATION" || true
    fi
    if [[ "$previous_saved" == "1" && -d "$backup_app" ]]; then
      run_install_command "$MV" "$backup_app" "$DESTINATION" || true
      /usr/bin/printf 'Previous LithePG.app restored after install failure.\n' >&2
    fi
  fi

  if [[ -d "$backup_root" ]]; then
    run_install_command "$RM" -rf -- "$backup_root" || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -d "$DESTINATION" ]]; then
  run_install_command "$MV" "$DESTINATION" "$backup_app"
  previous_saved=1
fi

run_install_command "$DITTO" --norsrc --noextattr --noqtn --noacl \
  "$SOURCE_APP" "$DESTINATION"
"$ROOT_DIR/script/package_verify.sh" "$DESTINATION"

install_complete=1
/usr/bin/printf 'Installed LithePG %s at %s\n' "$MARKETING_VERSION" "$DESTINATION"

if [[ "$open_after_install" == "1" ]]; then
  "$OPEN" "$DESTINATION"
fi
