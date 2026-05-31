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
release zip artifact path (default: dist/LithePG.app.zip) and
LITHEPG_RELEASE_ZIP_SHA256 to the approved expected 64-hex SHA-256 digest.
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
if [[ ! -f "$release_zip_file" ]]; then
  printf 'Release artifact zip: missing at %s\n' "$RELEASE_ZIP_PATH"
  mark_blocker
else
  printf 'Release artifact zip: present\n'
  release_zip_present=1
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
