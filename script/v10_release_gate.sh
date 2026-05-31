#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0"
CHECK_REMOTE_TAGS="${LITHEPG_CHECK_REMOTE_TAGS:-0}"
RELEASE_COPY_PATH="${LITHEPG_RELEASE_COPY_PATH:-docs/releases/v1.0-draft.md}"
HOMEBREW_CASK_PATH="${LITHEPG_HOMEBREW_CASK_PATH:-packaging/homebrew/lithepg.rb}"
SECURITY_DOC_PATH="${LITHEPG_SECURITY_DOC_PATH:-}"
RELEASE_ZIP_PATH="${LITHEPG_RELEASE_ZIP_PATH:-dist/LithePG.app.zip}"
RELEASE_ZIP_SHA256="${LITHEPG_RELEASE_ZIP_SHA256:-}"

usage() {
  cat <<'USAGE'
Usage: script/v10_release_gate.sh [--version <version>] [--check-remote]

Fast v1.0 publication preflight. Summarizes local tag readiness and required
external release inputs without running long build/test/dogfood gates, contacting
origin by default, or printing secret/contact/tap environment values.

Pass --check-remote or set LITHEPG_CHECK_REMOTE_TAGS=1 to opt into a non-fatal
origin tag lookup. Set LITHEPG_RELEASE_COPY_PATH or LITHEPG_HOMEBREW_CASK_PATH
to scan non-default release copy or Homebrew cask files. Set
LITHEPG_SECURITY_DOC_PATH to scan one alternate security policy file instead of
the default SECURITY.md and docs/SECURITY.md files (paths may be relative to the
repository root or absolute). Set LITHEPG_RELEASE_ZIP_PATH to the final public
release zip artifact path (default: dist/LithePG.app.zip; basename must be
LithePG.app.zip) and LITHEPG_RELEASE_ZIP_SHA256 to the approved expected
64-hex SHA-256 digest.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { printf 'v1.0 release gate failed: --version requires a value\n' >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --check-remote)
      CHECK_REMOTE_TAGS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'v1.0 release gate failed: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "$SECURITY_DOC_PATH" ]]; then
  SECURITY_DOC_PATHS=("$SECURITY_DOC_PATH")
else
  SECURITY_DOC_PATHS=("SECURITY.md" "docs/SECURITY.md")
fi
TAG="v$VERSION"
BLOCKERS=0

mark_blocker() {
  BLOCKERS=$((BLOCKERS + 1))
}

is_placeholder_value() {
  local value="${1:-}"

  case "$value" in
    *[Rr][Ee][Pp][Ll][Aa][Cc][Ee]_[Ww][Ii][Tt][Hh]_*|\
    *[Pp][Ll][Aa][Cc][Ee][Hh][Oo][Ll][Dd][Ee][Rr]*|\
    *[Tt][Oo][Dd][Oo]*|\
    *[Tt][Bb][Dd]*|\
    *[Pp][Ee][Nn][Dd][Ii][Nn][Gg]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

print_config_status() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    printf '%s: missing\n' "$name"
    mark_blocker
  elif is_placeholder_value "$value"; then
    printf '%s: placeholder\n' "$name"
    mark_blocker
  else
    printf '%s: configured\n' "$name"
  fi
}

is_approved_value() {
  case "${1:-}" in
    1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Aa][Pp][Pp][Rr][Oo][Vv][Ee][Dd])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

print_approval_status() {
  local name="$1"
  if is_approved_value "${!name:-}"; then
    printf '%s: approved\n' "$name"
  else
    printf '%s: not approved\n' "$name"
    mark_blocker
  fi
}

release_copy_full_path() {
  case "$RELEASE_COPY_PATH" in
    /*)
      printf '%s\n' "$RELEASE_COPY_PATH"
      ;;
    *)
      printf '%s/%s\n' "$ROOT_DIR" "$RELEASE_COPY_PATH"
      ;;
  esac
}

homebrew_cask_full_path() {
  case "$HOMEBREW_CASK_PATH" in
    /*)
      printf '%s\n' "$HOMEBREW_CASK_PATH"
      ;;
    *)
      printf '%s/%s\n' "$ROOT_DIR" "$HOMEBREW_CASK_PATH"
      ;;
  esac
}

extract_homebrew_cask_token() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*cask[[:space:]]+\"([^\"]+)\"[[:space:]]+do([[:space:]]|$) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_name() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*name[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_desc() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*desc[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_sha256() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*sha256[[:space:]]+\"([[:xdigit:]]{64})\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_version() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*version[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_url() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*url[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_verified_url() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*verified:[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_homepage() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*homepage[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_uninstall_quit_bundle_id() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*uninstall[[:space:]]+quit:[[:space:]]*\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_app_stanza() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*app[[:space:]]+\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

extract_homebrew_cask_macos_requirement() {
  local cask_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*depends_on[[:space:]]+macos:[[:space:]]*\"([^\"]+)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
    if [[ "$line" =~ ^[[:space:]]*depends_on[[:space:]]+macos:[[:space:]]*([^[:space:]#]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$cask_file"

  return 1
}

strip_ruby_inline_comment() {
  local input="$1"
  local output=""
  local char=""
  local escaped=0
  local in_double=0
  local i=0
  local length=${#input}

  while [[ "$i" -lt "$length" ]]; do
    char="${input:$i:1}"
    if [[ "$in_double" -eq 1 ]]; then
      output="${output}${char}"
      if [[ "$escaped" -eq 1 ]]; then
        escaped=0
      elif [[ "$char" == "\\" ]]; then
        escaped=1
      elif [[ "$char" == "\"" ]]; then
        in_double=0
      fi
    else
      case "$char" in
        '#')
          break
          ;;
        '"')
          in_double=1
          escaped=0
          output="${output}${char}"
          ;;
        *)
          output="${output}${char}"
          ;;
      esac
    fi
    i=$((i + 1))
  done

  printf '%s\n' "$output"
}

extract_homebrew_cask_zap_trash_paths() {
  local cask_file="$1"
  local line=""
  local remaining=""
  local in_zap=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(strip_ruby_inline_comment "$line")"

    if [[ "$in_zap" -eq 0 ]]; then
      if [[ "$line" =~ ^[[:space:]]*zap[[:space:]]+trash:[[:space:]]*\[ ]]; then
        in_zap=1
      else
        continue
      fi
    fi

    remaining="$line"
    while [[ "$remaining" =~ \"([^\"]+)\" ]]; do
      printf '%s\n' "${BASH_REMATCH[1]}"
      remaining="${remaining#*\"${BASH_REMATCH[1]}\"}"
    done

    if [[ "$line" =~ \] ]]; then
      return 0
    fi
  done <"$cask_file"

  return 1
}

security_doc_full_path() {
  local security_doc_path="$1"
  case "$security_doc_path" in
    /*)
      printf '%s\n' "$security_doc_path"
      ;;
    *)
      printf '%s/%s\n' "$ROOT_DIR" "$security_doc_path"
      ;;
  esac
}

release_zip_full_path() {
  case "$RELEASE_ZIP_PATH" in
    /*)
      printf '%s\n' "$RELEASE_ZIP_PATH"
      ;;
    *)
      printf '%s/%s\n' "$ROOT_DIR" "$RELEASE_ZIP_PATH"
      ;;
  esac
}

release_zip_app_bundle_structure_status() {
  local zip_file="$1"
  local zip_entries=""
  local entry=""
  local has_app_wrapper=0
  local has_info_plist=0
  local has_app_executable=0

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_entries="$(/usr/bin/zipinfo -1 "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r entry || [[ -n "$entry" ]]; do
    case "$entry" in
      LithePG.app|LithePG.app/*)
        has_app_wrapper=1
        ;;
    esac

    if [[ "$entry" == "LithePG.app/Contents/Info.plist" ]]; then
      has_info_plist=1
    elif [[ "$entry" == "LithePG.app/Contents/MacOS/LithePGApp" ]]; then
      has_app_executable=1
    fi
  done <<<"$zip_entries"

  if [[ "$has_app_wrapper" -ne 1 ]]; then
    return 1
  fi

  if [[ "$has_info_plist" -ne 1 || "$has_app_executable" -ne 1 ]]; then
    return 3
  fi

  return 0
}

release_zip_bundle_file_types_status() {
  local zip_file="$1"
  local zip_listing=""
  local line=""
  local mode=""
  local entry_rest=""
  local entry_name=""
  local has_info_plist=0
  local has_app_executable=0
  local invalid_bundle_file_type=0

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_listing="$(/usr/bin/zipinfo -l "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    mode=""
    entry_rest=""
    read -r mode _zip_version _zip_system _uncompressed_size _entry_type _compressed_size _method _date _time entry_rest <<<"$line" || true
    entry_name="${entry_rest%% -> *}"

    if [[ "$entry_name" == "LithePG.app/Contents/Info.plist" ]]; then
      has_info_plist=1
      if [[ "$mode" != -* ]]; then
        invalid_bundle_file_type=1
      fi
    elif [[ "$entry_name" == "LithePG.app/Contents/MacOS/LithePGApp" ]]; then
      has_app_executable=1
      if [[ "$mode" != -* ]]; then
        invalid_bundle_file_type=1
      fi
    fi
  done <<<"$zip_listing"

  if [[ "$invalid_bundle_file_type" -eq 1 ]]; then
    return 1
  fi

  if [[ "$has_info_plist" -ne 1 || "$has_app_executable" -ne 1 ]]; then
    return 2
  fi

  return 0
}

release_zip_symlinks_status() {
  local zip_file="$1"
  local zip_listing=""
  local line=""
  local mode=""

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_listing="$(/usr/bin/zipinfo -l "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    mode=""
    read -r mode _rest <<<"$line" || true
    case "$mode" in
      l*)
        return 1
        ;;
    esac
  done <<<"$zip_listing"

  return 0
}

release_zip_essential_entries_unique_status() {
  local zip_file="$1"
  local zip_entries=""
  local entry=""
  local info_plist_count=0
  local app_executable_count=0
  local code_resources_count=0

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_entries="$(/usr/bin/zipinfo -1 "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r entry || [[ -n "$entry" ]]; do
    case "$entry" in
      LithePG.app/Contents/Info.plist)
        info_plist_count=$((info_plist_count + 1))
        ;;
      LithePG.app/Contents/MacOS/LithePGApp)
        app_executable_count=$((app_executable_count + 1))
        ;;
      LithePG.app/Contents/_CodeSignature/CodeResources)
        code_resources_count=$((code_resources_count + 1))
        ;;
    esac
  done <<<"$zip_entries"

  if [[ "$info_plist_count" -gt 1 || "$app_executable_count" -gt 1 || "$code_resources_count" -gt 1 ]]; then
    return 1
  fi

  return 0
}

release_zip_entry_path_is_canonical() {
  local entry="$1"
  local entry_without_trailing_slash=""

  if [[ -z "$entry" ]]; then
    return 1
  fi

  if ! printf '%s' "$entry" | LC_ALL=C /usr/bin/awk '/[^ -~]/ { found = 1 } END { exit found ? 1 : 0 }'; then
    return 1
  fi

  case "$entry" in
    /*|./*|../*|.|..|*//*|*\\*)
      return 1
      ;;
  esac

  entry_without_trailing_slash="${entry%/}"
  case "$entry_without_trailing_slash" in
    ""|*/.|*/..|*/./*|*/../*)
      return 1
      ;;
  esac

  return 0
}

release_zip_entry_paths_ascii_status() {
  local zip_file="$1"

  if [[ ! -x /usr/bin/python3 ]]; then
    return 2
  fi

  /usr/bin/python3 - "$zip_file" <<'PY'
import sys
import zipfile

zip_path = sys.argv[1]

try:
    with zipfile.ZipFile(zip_path) as archive:
        for entry in archive.infolist():
            if any(ord(character) < 0x20 or ord(character) > 0x7E for character in entry.filename):
                sys.exit(1)
except (zipfile.BadZipFile, OSError):
    sys.exit(2)
except UnicodeDecodeError:
    sys.exit(1)

sys.exit(0)
PY
}

release_zip_entry_paths_status() {
  local zip_file="$1"
  local zip_entries=""
  local entry=""
  local duplicate_entry_path_count=""
  local ascii_status=0

  if [[ ! -x /usr/bin/zipinfo || ! -x /usr/bin/awk || ! -x /usr/bin/sort || ! -x /usr/bin/uniq || ! -x /usr/bin/wc ]]; then
    return 2
  fi

  if release_zip_entry_paths_ascii_status "$zip_file" 2>/dev/null; then
    :
  else
    ascii_status=$?
    case "$ascii_status" in
      1)
        return 1
        ;;
      *)
        return 2
        ;;
    esac
  fi

  if ! zip_entries="$(/usr/bin/zipinfo -1 "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r entry || [[ -n "$entry" ]]; do
    if ! release_zip_entry_path_is_canonical "$entry"; then
      return 1
    fi
  done <<<"$zip_entries"

  if ! duplicate_entry_path_count="$(printf '%s\n' "$zip_entries" | LC_ALL=C /usr/bin/awk '{ key = $0; sub(/\/$/, "", key); print tolower(key) }' | /usr/bin/sort | /usr/bin/uniq -d | /usr/bin/wc -l)"; then
    return 2
  fi
  duplicate_entry_path_count="${duplicate_entry_path_count//[[:space:]]/}"
  if [[ "$duplicate_entry_path_count" != "0" ]]; then
    return 3
  fi

  return 0
}

release_zip_metadata_files_status() {
  local zip_file="$1"
  local zip_entries=""
  local entry=""
  local entry_without_trailing_slash=""
  local entry_basename=""

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_entries="$(/usr/bin/zipinfo -1 "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r entry || [[ -n "$entry" ]]; do
    case "$entry" in
      __MACOSX|__MACOSX/*|*/__MACOSX|*/__MACOSX/*)
        return 1
        ;;
    esac

    entry_without_trailing_slash="${entry%/}"
    entry_basename="${entry_without_trailing_slash##*/}"
    case "$entry_basename" in
      .DS_Store|._*)
        return 1
        ;;
    esac
  done <<<"$zip_entries"

  return 0
}

plist_key_matches() {
  local plist_file="$1"
  local key="$2"
  local expected_value="$3"
  local actual_value=""

  if ! actual_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_file" 2>/dev/null)"; then
    return 1
  fi

  [[ "$actual_value" == "$expected_value" ]]
}

plist_key_is_numeric() {
  local plist_file="$1"
  local key="$2"
  local actual_value=""

  if ! actual_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_file" 2>/dev/null)"; then
    return 1
  fi

  [[ "$actual_value" =~ ^[0-9]+$ ]]
}

release_zip_info_plist_metadata_status() {
  local zip_file="$1"
  local expected_version="$2"
  local plist_file=""

  if [[ ! -x /usr/bin/unzip || ! -x /usr/libexec/PlistBuddy || ! -x /usr/bin/mktemp || ! -x /usr/bin/plutil ]]; then
    return 2
  fi

  if ! plist_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lithepg-info-plist.XXXXXX")"; then
    return 2
  fi

  if ! /usr/bin/unzip -p "$zip_file" "LithePG.app/Contents/Info.plist" >"$plist_file" 2>/dev/null; then
    rm -f "$plist_file"
    return 2
  fi

  if ! /usr/bin/plutil -lint "$plist_file" >/dev/null 2>&1; then
    rm -f "$plist_file"
    return 2
  fi

  if plist_key_matches "$plist_file" CFBundleExecutable "LithePGApp" && \
    plist_key_matches "$plist_file" CFBundleIdentifier "dev.omarpr.lithepg" && \
    plist_key_matches "$plist_file" CFBundleName "LithePG" && \
    plist_key_matches "$plist_file" CFBundlePackageType "APPL" && \
    plist_key_matches "$plist_file" CFBundleShortVersionString "$expected_version" && \
    plist_key_is_numeric "$plist_file" CFBundleVersion && \
    plist_key_matches "$plist_file" LSMinimumSystemVersion "14.0" && \
    plist_key_matches "$plist_file" NSPrincipalClass "NSApplication"; then
    rm -f "$plist_file"
    return 0
  fi

  rm -f "$plist_file"
  return 1
}

release_zip_bundle_executable_permission_status() {
  local zip_file="$1"
  local zip_listing=""
  local line=""
  local mode=""
  local entry_rest=""
  local entry_name=""
  local executable_mode=""

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_listing="$(/usr/bin/zipinfo -l "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    mode=""
    entry_rest=""
    read -r mode _zip_version _zip_system _uncompressed_size _entry_type _compressed_size _method _date _time entry_rest <<<"$line" || true
    entry_name="${entry_rest%% -> *}"

    if [[ "$entry_name" == "LithePG.app/Contents/MacOS/LithePGApp" ]]; then
      executable_mode="$mode"
      break
    fi
  done <<<"$zip_listing"

  if [[ -z "$executable_mode" || "$executable_mode" != -* ]]; then
    return 2
  fi

  if [[ "${executable_mode:3:1}" == "x" ]]; then
    return 0
  fi

  return 1
}

release_zip_app_executable_format_status() {
  local zip_file="$1"
  local executable_temp_dir=""
  local executable_file=""
  local file_output=""

  if [[ ! -x /usr/bin/unzip || ! -x /usr/bin/file || ! -x /usr/bin/mktemp || ! -x /bin/rm ]]; then
    return 2
  fi

  if ! executable_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-app-executable.XXXXXX")"; then
    return 2
  fi
  executable_file="$executable_temp_dir/LithePGApp"

  if ! /usr/bin/unzip -p "$zip_file" "LithePG.app/Contents/MacOS/LithePGApp" >"$executable_file" 2>/dev/null; then
    /bin/rm -rf "$executable_temp_dir"
    return 2
  fi

  if ! file_output="$(/usr/bin/file -b "$executable_file" 2>/dev/null)"; then
    /bin/rm -rf "$executable_temp_dir"
    return 2
  fi

  /bin/rm -rf "$executable_temp_dir"

  case "$file_output" in
    *Mach-O*executable*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

release_zip_code_signature_resources_status() {
  local zip_file="$1"
  local zip_listing=""
  local line=""
  local mode=""
  local entry_rest=""
  local entry_name=""
  local has_code_resources=0
  local invalid_code_resources=0

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_listing="$(/usr/bin/zipinfo -l "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    mode=""
    entry_rest=""
    read -r mode _zip_version _zip_system _uncompressed_size _entry_type _compressed_size _method _date _time entry_rest <<<"$line" || true
    entry_name="${entry_rest%% -> *}"

    if [[ "$entry_name" == "LithePG.app/Contents/_CodeSignature/CodeResources" ]]; then
      has_code_resources=1
      if [[ "$mode" != -* ]]; then
        invalid_code_resources=1
      fi
    fi
  done <<<"$zip_listing"

  if [[ "$invalid_code_resources" -eq 1 ]]; then
    return 3
  fi

  if [[ "$has_code_resources" -ne 1 ]]; then
    return 1
  fi

  return 0
}

release_zip_code_signature_verification_status() {
  local zip_file="$1"
  local extract_temp_dir=""
  local app_bundle_path=""

  if [[ ! -x /usr/bin/unzip || ! -x /usr/bin/codesign || ! -x /usr/bin/mktemp || ! -x /bin/rm ]]; then
    return 2
  fi

  if ! extract_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-code-signature.XXXXXX")"; then
    return 2
  fi
  app_bundle_path="$extract_temp_dir/LithePG.app"

  if ! /usr/bin/unzip -q "$zip_file" "LithePG.app/*" -d "$extract_temp_dir" >/dev/null 2>&1; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  if [[ ! -d "$app_bundle_path" ]]; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  if /usr/bin/codesign --verify --strict --deep "$app_bundle_path" >/dev/null 2>&1; then
    /bin/rm -rf "$extract_temp_dir"
    return 0
  fi

  /bin/rm -rf "$extract_temp_dir"
  return 1
}

release_zip_code_signature_identifier_status() {
  local zip_file="$1"
  local extract_temp_dir=""
  local app_bundle_path=""
  local codesign_display_output=""

  if [[ ! -x /usr/bin/unzip || ! -x /usr/bin/codesign || ! -x /usr/bin/mktemp || ! -x /bin/rm ]]; then
    return 2
  fi

  if ! extract_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-code-signature-identifier.XXXXXX")"; then
    return 2
  fi
  app_bundle_path="$extract_temp_dir/LithePG.app"

  if ! /usr/bin/unzip -q "$zip_file" "LithePG.app/*" -d "$extract_temp_dir" >/dev/null 2>&1; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  if [[ ! -d "$app_bundle_path" ]]; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  if ! codesign_display_output="$(/usr/bin/codesign --display --verbose=4 "$app_bundle_path" 2>&1)"; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  /bin/rm -rf "$extract_temp_dir"
  case $'\n'"$codesign_display_output"$'\n' in
    *$'\nIdentifier=dev.omarpr.lithepg\n'*)
      return 0
      ;;
  esac

  return 1
}

release_zip_code_signature_runtime_status() {
  local zip_file="$1"
  local extract_temp_dir=""
  local app_bundle_path=""
  local codesign_display_output=""

  if [[ ! -x /usr/bin/unzip || ! -x /usr/bin/codesign || ! -x /usr/bin/mktemp || ! -x /bin/rm ]]; then
    return 2
  fi

  if ! extract_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lithepg-code-signature-runtime.XXXXXX")"; then
    return 2
  fi
  app_bundle_path="$extract_temp_dir/LithePG.app"

  if ! /usr/bin/unzip -q "$zip_file" "LithePG.app/*" -d "$extract_temp_dir" >/dev/null 2>&1; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  if [[ ! -d "$app_bundle_path" ]]; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  if ! codesign_display_output="$(/usr/bin/codesign --display --verbose=4 "$app_bundle_path" 2>&1)"; then
    /bin/rm -rf "$extract_temp_dir"
    return 2
  fi

  /bin/rm -rf "$extract_temp_dir"
  if [[ "$codesign_display_output" == *"flags="*"runtime"* ]]; then
    return 0
  fi

  return 1
}

release_zip_top_level_entries_status() {
  local zip_file="$1"
  local zip_entries=""
  local entry=""
  local unexpected_top_level_entry=0

  if [[ ! -x /usr/bin/zipinfo ]]; then
    return 2
  fi

  if ! zip_entries="$(/usr/bin/zipinfo -1 "$zip_file" 2>/dev/null)"; then
    return 2
  fi

  while IFS= read -r entry || [[ -n "$entry" ]]; do
    case "$entry" in
      LithePG.app|LithePG.app/*)
        case "$entry" in
          ..|../*|*/..|*/../*|.|./*|*/.|*/./*)
            unexpected_top_level_entry=1
            ;;
        esac
        ;;
      *)
        unexpected_top_level_entry=1
        ;;
    esac
  done <<<"$zip_entries"

  if [[ "$unexpected_top_level_entry" -eq 1 ]]; then
    return 1
  fi

  return 0
}

cd "$ROOT_DIR"

printf 'LithePG %s fast publication preflight\n' "$TAG"
printf 'Repository: %s\n' "$ROOT_DIR"
printf '\nLocal git/tag readiness:\n'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null || true)"
  if [[ -n "$branch" ]]; then
    printf 'Git branch: %s\n' "$branch"
  else
    printf 'Git branch: detached at %s\n' "$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  fi

  if status_output="$(git status --short 2>/dev/null)"; then
    if [[ -z "$status_output" ]]; then
      printf 'Git status: clean\n'
    else
      printf 'Git status: changes present (expected clean before tagging/publishing)\n'
      mark_blocker
    fi
  else
    printf 'Git status: unknown (git status failed; expected clean before tagging/publishing)\n'
    mark_blocker
  fi

  if git rev-parse -q --verify refs/tags/v0.5 >/dev/null 2>&1; then
    printf 'Local tag v0.5: present\n'
  else
    printf 'Local tag v0.5: missing\n'
    mark_blocker
  fi

  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    printf 'Local tag %s: present (expected absent before publication)\n' "$TAG"
    mark_blocker
  else
    printf 'Local tag %s: absent\n' "$TAG"
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    if is_approved_value "$CHECK_REMOTE_TAGS"; then
      set +e
      GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --tags origin refs/tags/v0.5 >/dev/null 2>&1
      remote_v05_status=$?
      set -e
      case "$remote_v05_status" in
        0)
          printf 'Remote origin tag v0.5: present\n'
          ;;
        2)
          printf 'Remote origin tag v0.5: missing\n'
          mark_blocker
          ;;
        *)
          printf 'Remote origin tag v0.5: unknown (remote/network unavailable; not blocking this fast check)\n'
          ;;
      esac

      set +e
      GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1
      remote_status=$?
      set -e
      case "$remote_status" in
        0)
          printf 'Remote origin tag %s: present (expected absent before publication)\n' "$TAG"
          mark_blocker
          ;;
        2)
          printf 'Remote origin tag %s: absent\n' "$TAG"
          ;;
        *)
          printf 'Remote origin tag %s: unknown (remote/network unavailable; not blocking this fast check)\n' "$TAG"
          ;;
      esac
    else
      printf 'Remote origin tag v0.5: not checked (set LITHEPG_CHECK_REMOTE_TAGS=1 or pass --check-remote)\n'
      printf 'Remote origin tag %s: not checked (set LITHEPG_CHECK_REMOTE_TAGS=1 or pass --check-remote)\n' "$TAG"
    fi
  else
    printf 'Remote origin tag v0.5: unknown (no origin remote; not blocking this fast check)\n'
    printf 'Remote origin tag %s: unknown (no origin remote; not blocking this fast check)\n' "$TAG"
  fi
else
  printf 'Git repository: unavailable\n'
  mark_blocker
fi

printf '\nRelease copy readiness:\n'
release_copy_file="$(release_copy_full_path)"
release_copy_check_ready=0
if [[ ! -f "$release_copy_file" ]]; then
  printf 'Release copy placeholders: missing release copy at %s\n' "$RELEASE_COPY_PATH"
  mark_blocker
else
  set +e
  grep -q 'REPLACE_WITH_' "$release_copy_file"
  grep_status=$?
  set -e
  case "$grep_status" in
    0)
      printf 'Release copy placeholders: present in %s\n' "$RELEASE_COPY_PATH"
      mark_blocker
      ;;
    1)
      printf 'Release copy placeholders: none found\n'
      release_copy_check_ready=1
      ;;
    *)
      printf 'Release copy placeholders: could not scan %s\n' "$RELEASE_COPY_PATH"
      mark_blocker
      ;;
  esac
fi

if [[ "$release_copy_check_ready" -eq 1 ]]; then
  set +e
  grep -Eq '^[[:space:]]*-[[:space:]]\[[[:space:]]\]' "$release_copy_file"
  grep_status=$?
  set -e
  case "$grep_status" in
    0)
      printf 'Release copy checklist: unchecked items present\n'
      mark_blocker
      ;;
    1)
      printf 'Release copy checklist: none unchecked\n'
      ;;
    *)
      printf 'Release copy checklist: could not scan %s\n' "$RELEASE_COPY_PATH"
      mark_blocker
      ;;
  esac
fi

if [[ "$release_copy_check_ready" -eq 1 && "$RELEASE_ZIP_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
  expected_sha="$(printf '%s' "$RELEASE_ZIP_SHA256" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  set +e
  grep -Eiq -- "(^|[^[:xdigit:]])${expected_sha}([^[:xdigit:]]|$)" "$release_copy_file"
  grep_status=$?
  set -e
  case "$grep_status" in
    0)
      printf 'Release copy SHA-256: matches\n'
      ;;
    1)
      printf 'Release copy SHA-256: mismatch\n'
      mark_blocker
      ;;
    *)
      printf 'Release copy SHA-256: could not scan %s\n' "$RELEASE_COPY_PATH"
      mark_blocker
      ;;
  esac
fi

printf '\nHomebrew cask readiness:\n'
homebrew_cask_file="$(homebrew_cask_full_path)"
homebrew_cask_check_ready=0
if [[ ! -f "$homebrew_cask_file" ]]; then
  printf 'Homebrew cask placeholders: missing cask at %s\n' "$HOMEBREW_CASK_PATH"
  mark_blocker
else
  set +e
  grep -q 'REPLACE_WITH_' "$homebrew_cask_file"
  grep_status=$?
  set -e
  case "$grep_status" in
    0)
      printf 'Homebrew cask placeholders: present in %s\n' "$HOMEBREW_CASK_PATH"
      mark_blocker
      ;;
    1)
      printf 'Homebrew cask placeholders: none found\n'
      homebrew_cask_check_ready=1
      ;;
    *)
      printf 'Homebrew cask placeholders: could not scan %s\n' "$HOMEBREW_CASK_PATH"
      mark_blocker
      ;;
  esac
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_token="$(extract_homebrew_cask_token "$homebrew_cask_file")"; then
    if [[ "$cask_token" == "lithepg" ]]; then
      printf 'Homebrew cask token: matches\n'
    else
      printf 'Homebrew cask token: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask token: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_name="$(extract_homebrew_cask_name "$homebrew_cask_file")"; then
    if [[ "$cask_name" == "LithePG" ]]; then
      printf 'Homebrew cask name: matches\n'
    else
      printf 'Homebrew cask name: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask name: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_desc="$(extract_homebrew_cask_desc "$homebrew_cask_file")"; then
    if [[ "$cask_desc" == "Lean PostgreSQL client with local-first AI" ]]; then
      printf 'Homebrew cask desc: matches\n'
    else
      printf 'Homebrew cask desc: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask desc: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_version="$(extract_homebrew_cask_version "$homebrew_cask_file")"; then
    if [[ "$cask_version" == "$VERSION" ]]; then
      printf 'Homebrew cask version: matches\n'
    else
      printf 'Homebrew cask version: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask version: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_url="$(extract_homebrew_cask_url "$homebrew_cask_file")"; then
    expected_cask_url_template='https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip'
    expected_cask_url_concrete="https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG.app.zip"
    if [[ "$cask_url" == "$expected_cask_url_template" || "$cask_url" == "$expected_cask_url_concrete" ]]; then
      printf 'Homebrew cask URL: matches\n'
    else
      printf 'Homebrew cask URL: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask URL: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_verified_url="$(extract_homebrew_cask_verified_url "$homebrew_cask_file")"; then
    if [[ "$cask_verified_url" == "github.com/omarpr/lithepg/" ]]; then
      printf 'Homebrew cask verified URL: matches\n'
    else
      printf 'Homebrew cask verified URL: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask verified URL: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_homepage="$(extract_homebrew_cask_homepage "$homebrew_cask_file")"; then
    if [[ "$cask_homepage" == "https://github.com/omarpr/lithepg" ]]; then
      printf 'Homebrew cask homepage: matches\n'
    else
      printf 'Homebrew cask homepage: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask homepage: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_bundle_id="$(extract_homebrew_cask_uninstall_quit_bundle_id "$homebrew_cask_file")"; then
    if [[ "$cask_bundle_id" == "dev.omarpr.lithepg" ]]; then
      printf 'Homebrew cask uninstall quit bundle ID: matches\n'
    else
      printf 'Homebrew cask uninstall quit bundle ID: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask uninstall quit bundle ID: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_app="$(extract_homebrew_cask_app_stanza "$homebrew_cask_file")"; then
    if [[ "$cask_app" == "LithePG.app" ]]; then
      printf 'Homebrew cask app stanza: matches\n'
    else
      printf 'Homebrew cask app stanza: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask app stanza: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_macos_requirement="$(extract_homebrew_cask_macos_requirement "$homebrew_cask_file")"; then
    if [[ "$cask_macos_requirement" == ">= :sonoma" ]]; then
      printf 'Homebrew cask macOS requirement: matches\n'
    else
      printf 'Homebrew cask macOS requirement: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask macOS requirement: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if cask_zap_paths="$(extract_homebrew_cask_zap_trash_paths "$homebrew_cask_file")"; then
    cask_zap_has_app_support=0
    cask_zap_has_preferences=0
    while IFS= read -r cask_zap_path || [[ -n "$cask_zap_path" ]]; do
      case "$cask_zap_path" in
        "~/Library/Application Support/LithePG")
          cask_zap_has_app_support=1
          ;;
        "~/Library/Preferences/dev.omarpr.lithepg.plist")
          cask_zap_has_preferences=1
          ;;
      esac
    done <<<"$cask_zap_paths"

    if [[ "$cask_zap_has_app_support" -eq 1 && "$cask_zap_has_preferences" -eq 1 ]]; then
      printf 'Homebrew cask zap stanza: matches\n'
    else
      printf 'Homebrew cask zap stanza: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask zap stanza: missing\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 ]]; then
  if [[ ! -x /usr/bin/ruby ]]; then
    printf 'Homebrew cask Ruby syntax: ruby unavailable\n'
    mark_blocker
  elif /usr/bin/ruby -c "$homebrew_cask_file" >/dev/null 2>&1; then
    printf 'Homebrew cask Ruby syntax: valid\n'
  else
    printf 'Homebrew cask Ruby syntax: invalid\n'
    mark_blocker
  fi
fi

if [[ "$homebrew_cask_check_ready" -eq 1 && "$RELEASE_ZIP_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
  if cask_sha="$(extract_homebrew_cask_sha256 "$homebrew_cask_file")"; then
    expected_sha="$(printf '%s' "$RELEASE_ZIP_SHA256" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    cask_sha="$(printf '%s' "$cask_sha" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    if [[ "$cask_sha" == "$expected_sha" ]]; then
      printf 'Homebrew cask SHA-256: matches\n'
    else
      printf 'Homebrew cask SHA-256: mismatch\n'
      mark_blocker
    fi
  else
    printf 'Homebrew cask SHA-256: missing\n'
    mark_blocker
  fi
fi

printf '\nSecurity policy readiness:\n'
for security_doc_path in "${SECURITY_DOC_PATHS[@]}"; do
  security_doc_file="$(security_doc_full_path "$security_doc_path")"
  if [[ ! -f "$security_doc_file" ]]; then
    printf 'Security policy placeholders: missing policy at %s\n' "$security_doc_path"
    mark_blocker
  else
    set +e
    grep -Eiq '\[security contact pending\]|REPLACE_WITH_|PLACEHOLDER|TODO|TBD' "$security_doc_file"
    grep_status=$?
    set -e
    case "$grep_status" in
      0)
        printf 'Security policy placeholders: present in %s\n' "$security_doc_path"
        mark_blocker
        ;;
      1)
        printf 'Security policy placeholders: none found in %s\n' "$security_doc_path"
        ;;
      *)
        printf 'Security policy placeholders: could not scan %s\n' "$security_doc_path"
        mark_blocker
        ;;
    esac
  fi
done

printf '\nRelease artifact readiness:\n'
release_zip_file="$(release_zip_full_path)"
release_zip_present=0
if [[ "${RELEASE_ZIP_PATH##*/}" == "LithePG.app.zip" ]]; then
  printf 'Release artifact filename: matches\n'
else
  printf 'Release artifact filename: mismatch\n'
  mark_blocker
fi

if [[ ! -f "$release_zip_file" ]]; then
  printf 'Release artifact zip: missing at %s\n' "$RELEASE_ZIP_PATH"
  mark_blocker
else
  printf 'Release artifact zip: present\n'
  release_zip_present=1
fi

if [[ "$release_zip_present" -eq 1 ]]; then
  if release_zip_symlinks_status "$release_zip_file"; then
    printf 'Release artifact symlinks: absent\n'
  else
    release_zip_symlinks_status=$?
    case "$release_zip_symlinks_status" in
      1)
        printf 'Release artifact symlinks: present\n'
        ;;
      *)
        printf 'Release artifact symlinks: could not inspect\n'
        ;;
    esac
    mark_blocker
  fi

  if release_zip_metadata_files_status "$release_zip_file"; then
    printf 'Release artifact metadata files: absent\n'
  else
    release_zip_metadata_files_status=$?
    case "$release_zip_metadata_files_status" in
      1)
        printf 'Release artifact metadata files: present\n'
        ;;
      *)
        printf 'Release artifact metadata files: could not inspect\n'
        ;;
    esac
    mark_blocker
  fi

  release_zip_structure_ready=0
  if release_zip_app_bundle_structure_status "$release_zip_file"; then
    printf 'Release artifact app wrapper: present\n'
    printf 'Release artifact bundle contents: present\n'
    release_zip_structure_ready=1
  else
    release_zip_structure_status=$?
    case "$release_zip_structure_status" in
      1)
        printf 'Release artifact app wrapper: missing\n'
        ;;
      3)
        printf 'Release artifact app wrapper: present\n'
        printf 'Release artifact bundle contents: missing\n'
        ;;
      *)
        printf 'Release artifact app wrapper: could not inspect\n'
        printf 'Release artifact bundle file types: could not inspect\n'
        ;;
    esac
    mark_blocker
  fi

  if [[ "$release_zip_structure_ready" -eq 1 ]]; then
    release_zip_file_types_ready=0
    if release_zip_bundle_file_types_status "$release_zip_file"; then
      printf 'Release artifact bundle file types: regular\n'
      release_zip_file_types_ready=1
    else
      release_zip_file_types_status=$?
      case "$release_zip_file_types_status" in
        1)
          printf 'Release artifact bundle file types: invalid\n'
          ;;
        *)
          printf 'Release artifact bundle file types: could not inspect\n'
          ;;
      esac
      mark_blocker
    fi

    release_zip_essential_entries_ready=0
    release_zip_entry_paths_ready=0
    if [[ "$release_zip_file_types_ready" -eq 1 ]]; then
      if release_zip_entry_paths_status "$release_zip_file"; then
        printf 'Release artifact entry paths: canonical\n'
        release_zip_entry_paths_ready=1
      else
        release_zip_entry_paths_status=$?
        case "$release_zip_entry_paths_status" in
          1)
            printf 'Release artifact entry paths: non-canonical\n'
            ;;
          3)
            printf 'Release artifact entry paths: collision\n'
            ;;
          *)
            printf 'Release artifact entry paths: could not inspect\n'
            ;;
        esac
        mark_blocker
      fi
    fi

    if [[ "$release_zip_file_types_ready" -eq 1 && "$release_zip_entry_paths_ready" -eq 1 ]]; then
      if release_zip_essential_entries_unique_status "$release_zip_file"; then
        printf 'Release artifact essential entries: unique\n'
        release_zip_essential_entries_ready=1
      else
        release_zip_essential_entries_status=$?
        case "$release_zip_essential_entries_status" in
          1)
            printf 'Release artifact essential entries: duplicate\n'
            ;;
          *)
            printf 'Release artifact essential entries: could not inspect\n'
            ;;
        esac
        mark_blocker
      fi
    fi

    if [[ "$release_zip_file_types_ready" -eq 1 && "$release_zip_essential_entries_ready" -eq 1 ]]; then
      if release_zip_info_plist_metadata_status "$release_zip_file" "$VERSION"; then
        printf 'Release artifact Info.plist metadata: matches\n'
      else
        release_zip_info_plist_metadata_status=$?
        case "$release_zip_info_plist_metadata_status" in
          1)
            printf 'Release artifact Info.plist metadata: mismatch\n'
            ;;
          *)
            printf 'Release artifact Info.plist metadata: could not inspect\n'
            ;;
        esac
        mark_blocker
      fi

      if release_zip_bundle_executable_permission_status "$release_zip_file"; then
        printf 'Release artifact bundle executable: executable\n'
        release_zip_executable_permission_ready=1
      else
        release_zip_executable_status=$?
        release_zip_executable_permission_ready=0
        case "$release_zip_executable_status" in
          1)
            printf 'Release artifact bundle executable: not executable\n'
            ;;
          *)
            printf 'Release artifact bundle executable: could not inspect\n'
            ;;
        esac
        mark_blocker
      fi

      if [[ "$release_zip_executable_permission_ready" -eq 1 ]]; then
        if release_zip_app_executable_format_status "$release_zip_file"; then
          printf 'Release artifact executable format: Mach-O\n'
        else
          release_zip_executable_format_status=$?
          case "$release_zip_executable_format_status" in
            1)
              printf 'Release artifact executable format: invalid\n'
              ;;
            *)
              printf 'Release artifact executable format: could not inspect\n'
              ;;
          esac
          mark_blocker
        fi
      fi

      release_zip_code_signature_resources_ready=0
      if release_zip_code_signature_resources_status "$release_zip_file"; then
        printf 'Release artifact code signature resources: present\n'
        release_zip_code_signature_resources_ready=1
      else
        release_zip_code_signature_resources_status=$?
        case "$release_zip_code_signature_resources_status" in
          1)
            printf 'Release artifact code signature resources: missing\n'
            ;;
          3)
            printf 'Release artifact code signature resources: invalid\n'
            ;;
          *)
            printf 'Release artifact code signature resources: could not inspect\n'
            ;;
        esac
        mark_blocker
      fi

      if [[ "$release_zip_code_signature_resources_ready" -eq 1 ]]; then
        release_zip_code_signature_verification_ready=0
        if release_zip_code_signature_verification_status "$release_zip_file"; then
          printf 'Release artifact code signature verification: valid\n'
          release_zip_code_signature_verification_ready=1
        else
          release_zip_code_signature_verification_status=$?
          case "$release_zip_code_signature_verification_status" in
            1)
              printf 'Release artifact code signature verification: invalid\n'
              ;;
            *)
              printf 'Release artifact code signature verification: could not inspect\n'
              ;;
          esac
          mark_blocker
        fi

        if [[ "$release_zip_code_signature_verification_ready" -eq 1 ]]; then
          release_zip_code_signature_identifier_ready=0
          if release_zip_code_signature_identifier_status "$release_zip_file"; then
            printf 'Release artifact code signature identifier: matches\n'
            release_zip_code_signature_identifier_ready=1
          else
            release_zip_code_signature_identifier_status=$?
            case "$release_zip_code_signature_identifier_status" in
              1)
                printf 'Release artifact code signature identifier: mismatch\n'
                ;;
              *)
                printf 'Release artifact code signature identifier: could not inspect\n'
                ;;
            esac
            mark_blocker
          fi

          if [[ "$release_zip_code_signature_identifier_ready" -eq 1 ]]; then
            if release_zip_code_signature_runtime_status "$release_zip_file"; then
              printf 'Release artifact code signature runtime: present\n'
            else
              release_zip_code_signature_runtime_status=$?
              case "$release_zip_code_signature_runtime_status" in
                1)
                  printf 'Release artifact code signature runtime: missing\n'
                  ;;
                *)
                  printf 'Release artifact code signature runtime: could not inspect\n'
                  ;;
              esac
              mark_blocker
            fi
          fi
        fi
      fi
    fi
  fi

  if release_zip_top_level_entries_status "$release_zip_file"; then
    printf 'Release artifact top-level entries: clean\n'
  else
    release_zip_top_level_status=$?
    case "$release_zip_top_level_status" in
      1)
        printf 'Release artifact top-level entries: unexpected\n'
        ;;
      *)
        printf 'Release artifact top-level entries: could not inspect\n'
        ;;
    esac
    mark_blocker
  fi
fi

if [[ -z "$RELEASE_ZIP_SHA256" ]]; then
  printf 'Release artifact SHA-256: missing\n'
  mark_blocker
elif [[ ! "$RELEASE_ZIP_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
  printf 'Release artifact SHA-256: invalid format\n'
  mark_blocker
elif [[ "$release_zip_present" -eq 1 ]]; then
  set +e
  shasum_output="$(/usr/bin/shasum -a 256 "$release_zip_file" 2>/dev/null)"
  shasum_status=$?
  set -e
  actual_sha="${shasum_output%% *}"
  if [[ "$shasum_status" -ne 0 || -z "$actual_sha" ]]; then
    printf 'Release artifact SHA-256: could not compute\n'
    mark_blocker
  else
    expected_sha="$(printf '%s' "$RELEASE_ZIP_SHA256" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    if [[ "$actual_sha" == "$expected_sha" ]]; then
      printf 'Release artifact SHA-256: matches\n'
    else
      printf 'Release artifact SHA-256: mismatch\n'
      mark_blocker
    fi
  fi
fi

printf '\nExternal publication inputs (values redacted):\n'
print_config_status LITHEPG_CODESIGN_IDENTITY
print_config_status LITHEPG_NOTARY_PROFILE
print_config_status LITHEPG_SECURITY_CONTACT
print_config_status LITHEPG_HOMEBREW_TAP
print_approval_status LITHEPG_GITHUB_ACTIONS_READY
print_approval_status LITHEPG_RELEASE_COPY_APPROVED
print_approval_status LITHEPG_PUBLICATION_APPROVED

printf '\n'
if [[ "$BLOCKERS" -eq 0 ]]; then
  printf '%s fast preflight is clear.\n' "$TAG"
  printf 'Before tagging or publishing, still run the full local gate commands in docs/RELEASING.md (Swift tests, dogfood/package verification, and signing/notarization validation).\n'
  exit 0
fi

printf '%s publication blocked: %s blocker(s) found.\n' "$TAG" "$BLOCKERS"
printf 'Resolve the release copy, Homebrew cask, security policy placeholders, release artifact zip/SHA-256 issues, missing/false external inputs, and any tag-readiness blockers before tagging or publishing.\n'
exit 1
