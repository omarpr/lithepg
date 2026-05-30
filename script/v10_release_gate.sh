#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0"
CHECK_REMOTE_TAGS="${LITHEPG_CHECK_REMOTE_TAGS:-0}"
RELEASE_COPY_PATH="${LITHEPG_RELEASE_COPY_PATH:-docs/releases/v1.0-draft.md}"

usage() {
  cat <<'USAGE'
Usage: script/v10_release_gate.sh [--version <version>] [--check-remote]

Fast v1.0 publication preflight. Summarizes local tag readiness and required
external release inputs without running long build/test/dogfood gates, contacting
origin by default, or printing secret/contact/tap environment values.

Pass --check-remote or set LITHEPG_CHECK_REMOTE_TAGS=1 to opt into a non-fatal
origin tag lookup. Set LITHEPG_RELEASE_COPY_PATH to scan a non-default release
copy file (relative to the repository root or absolute).
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
TAG="v$VERSION"
BLOCKERS=0

mark_blocker() {
  BLOCKERS=$((BLOCKERS + 1))
}

print_config_status() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    printf '%s: configured\n' "$name"
  else
    printf '%s: missing\n' "$name"
    mark_blocker
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
      printf 'Remote origin tag %s: not checked (set LITHEPG_CHECK_REMOTE_TAGS=1 or pass --check-remote)\n' "$TAG"
    fi
  else
    printf 'Remote origin tag %s: unknown (no origin remote; not blocking this fast check)\n' "$TAG"
  fi
else
  printf 'Git repository: unavailable\n'
  mark_blocker
fi

printf '\nRelease copy readiness:\n'
release_copy_file="$(release_copy_full_path)"
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
      ;;
    *)
      printf 'Release copy placeholders: could not scan %s\n' "$RELEASE_COPY_PATH"
      mark_blocker
      ;;
  esac
fi

printf '\nExternal publication inputs (values redacted):\n'
print_config_status LITHEPG_CODESIGN_IDENTITY
print_config_status LITHEPG_NOTARY_PROFILE
print_config_status LITHEPG_SECURITY_CONTACT
print_config_status LITHEPG_HOMEBREW_TAP
print_approval_status LITHEPG_RELEASE_COPY_APPROVED
print_approval_status LITHEPG_PUBLICATION_APPROVED

printf '\n'
if [[ "$BLOCKERS" -eq 0 ]]; then
  printf '%s fast preflight is clear.\n' "$TAG"
  printf 'Before tagging or publishing, still run the full local gate commands in docs/RELEASING.md (Swift tests, dogfood/package verification, and signing/notarization validation).\n'
  exit 0
fi

printf '%s publication blocked: %s blocker(s) found.\n' "$TAG" "$BLOCKERS"
printf 'Resolve the release copy, missing/false external inputs, and any tag-readiness blockers before tagging or publishing.\n'
exit 1
