#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/v10_release_gate.sh"

fail() {
  printf 'test_v10_release_gate failed: %s\n' "$1" >&2
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

run_gate_capture() {
  local output_file="$1"
  shift
  set +e
  (
    cd "$ROOT_DIR"
    "$@" "$HELPER"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

missing_output="$(mktemp)"
redaction_output="$(mktemp)"
no_remote_lookup_output="$(mktemp)"
remote_opt_in_output="$(mktemp)"
status_failure_output="$(mktemp)"
fake_git_dir="$(mktemp -d)"
fake_git_marker="$fake_git_dir/ls-remote-called"
trap 'rm -f "$missing_output" "$redaction_output" "$no_remote_lookup_output" "$remote_opt_in_output" "$status_failure_output"; rm -rf "$fake_git_dir"' EXIT

cat >"$fake_git_dir/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  rev-parse)
    if [[ "${2:-}" == "--is-inside-work-tree" ]]; then
      printf 'true\n'
      exit 0
    fi
    if [[ "${2:-}" == "--short" ]]; then
      printf 'abc123\n'
      exit 0
    fi
    if [[ "${2:-}" == "-q" && "${3:-}" == "--verify" ]]; then
      case "${4:-}" in
        refs/tags/v0.5)
          exit 0
          ;;
        refs/tags/v*)
          exit 1
          ;;
      esac
    fi
    ;;
  branch)
    if [[ "${2:-}" == "--show-current" ]]; then
      printf 'main\n'
      exit 0
    fi
    ;;
  status)
    if [[ "${2:-}" == "--short" ]]; then
      if [[ "${FAKE_GIT_STATUS_FAIL:-}" == "1" ]]; then
        printf 'fatal: fake status failure\n' >&2
        exit 77
      fi
      exit 0
    fi
    ;;
  remote)
    if [[ "${2:-}" == "get-url" && "${3:-}" == "origin" ]]; then
      printf 'https://example.invalid/lithepg.git\n'
      exit 0
    fi
    ;;
  ls-remote)
    printf 'git ls-remote was invoked\n' >>"${FAKE_GIT_LS_REMOTE_MARKER:?}"
    exit 99
    ;;
esac

printf 'unexpected fake git invocation:' >&2
printf ' %s' "$@" >&2
printf '\n' >&2
exit 98
FAKE_GIT
chmod +x "$fake_git_dir/git"
fake_path="$fake_git_dir:${PATH:-/usr/bin:/bin}"

if run_gate_capture "$missing_output" env -i PATH="$fake_path" FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker"; then
  fail "gate unexpectedly passed with all required external inputs missing"
fi
missing_text="$(<"$missing_output")"
assert_contains "$missing_text" "v1.0 publication blocked"
assert_contains "$missing_text" "LITHEPG_CODESIGN_IDENTITY: missing"
assert_contains "$missing_text" "LITHEPG_NOTARY_PROFILE: missing"
assert_contains "$missing_text" "LITHEPG_SECURITY_CONTACT: missing"
assert_contains "$missing_text" "LITHEPG_HOMEBREW_TAP: missing"
assert_contains "$missing_text" "LITHEPG_RELEASE_COPY_APPROVED: not approved"
assert_contains "$missing_text" "LITHEPG_PUBLICATION_APPROVED: not approved"
assert_not_contains "$missing_text" "fast preflight is clear"

secret_identity="SECRET_CODESIGN_IDENTITY_DO_NOT_PRINT"
secret_notary="SECRET_NOTARY_PROFILE_DO_NOT_PRINT"
secret_contact="security-secret@example.invalid"
secret_tap="SECRET_HOMEBREW_TAP_DO_NOT_PRINT"

if run_gate_capture "$redaction_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_CODESIGN_IDENTITY="$secret_identity" \
  LITHEPG_NOTARY_PROFILE="$secret_notary" \
  LITHEPG_SECURITY_CONTACT="$secret_contact" \
  LITHEPG_HOMEBREW_TAP="$secret_tap" \
  LITHEPG_RELEASE_COPY_APPROVED="false" \
  LITHEPG_PUBLICATION_APPROVED="no"; then
  fail "gate unexpectedly passed with release/publication approvals false"
fi
redaction_text="$(<"$redaction_output")"
assert_contains "$redaction_text" "v1.0 publication blocked"
assert_contains "$redaction_text" "LITHEPG_CODESIGN_IDENTITY: configured"
assert_contains "$redaction_text" "LITHEPG_NOTARY_PROFILE: configured"
assert_contains "$redaction_text" "LITHEPG_SECURITY_CONTACT: configured"
assert_contains "$redaction_text" "LITHEPG_HOMEBREW_TAP: configured"
assert_contains "$redaction_text" "LITHEPG_RELEASE_COPY_APPROVED: not approved"
assert_contains "$redaction_text" "LITHEPG_PUBLICATION_APPROVED: not approved"
assert_not_contains "$redaction_text" "$secret_identity"
assert_not_contains "$redaction_text" "$secret_notary"
assert_not_contains "$redaction_text" "$secret_contact"
assert_not_contains "$redaction_text" "$secret_tap"

rm -f "$fake_git_marker"
if ! run_gate_capture "$no_remote_lookup_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly failed with all required external inputs configured"
fi
no_remote_lookup_text="$(<"$no_remote_lookup_output")"
assert_contains "$no_remote_lookup_text" "Remote origin tag v1.0: not checked (set LITHEPG_CHECK_REMOTE_TAGS=1 or pass --check-remote)"
if [[ -e "$fake_git_marker" ]]; then
  fail "default gate invoked git ls-remote despite remote lookup not being requested"
fi

rm -f "$fake_git_marker"
if ! run_gate_capture "$remote_opt_in_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_CHECK_REMOTE_TAGS="1" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly failed when opt-in remote lookup returned unknown"
fi
remote_opt_in_text="$(<"$remote_opt_in_output")"
assert_contains "$remote_opt_in_text" "Remote origin tag v1.0: unknown (remote/network unavailable; not blocking this fast check)"
if [[ ! -e "$fake_git_marker" ]]; then
  fail "opt-in remote lookup did not invoke git ls-remote"
fi

if run_gate_capture "$status_failure_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  FAKE_GIT_STATUS_FAIL="1" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed when git status failed"
fi
status_failure_text="$(<"$status_failure_output")"
assert_contains "$status_failure_text" "Git status: unknown (git status failed; expected clean before tagging/publishing)"
assert_contains "$status_failure_text" "v1.0 publication blocked"
assert_not_contains "$status_failure_text" "Git status: clean"

printf 'test_v10_release_gate passed\n'
