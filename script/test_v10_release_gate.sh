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

run_specific_gate_capture() {
  local output_file="$1"
  local helper="$2"
  shift 2
  set +e
  (
    cd "$(cd "$(dirname "$helper")/.." && pwd)"
    "$@" "$helper"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

missing_output="$(mktemp)"
redaction_output="$(mktemp)"
missing_artifact_output="$(mktemp)"
missing_artifact_zip="$(mktemp)"
missing_artifact_sha_output="$(mktemp)"
invalid_artifact_sha_output="$(mktemp)"
mismatched_artifact_sha_output="$(mktemp)"
mismatched_homebrew_cask_sha_output="$(mktemp)"
homebrew_cask_url_mismatch_output="$(mktemp)"
homebrew_cask_verified_mismatch_output="$(mktemp)"
missing_homebrew_cask_verified_output="$(mktemp)"
homebrew_cask_version_mismatch_output="$(mktemp)"
missing_homebrew_cask_version_output="$(mktemp)"
missing_homebrew_cask_sha_output="$(mktemp)"
placeholder_output="$(mktemp)"
homebrew_cask_placeholder_output="$(mktemp)"
security_doc_placeholder_output="$(mktemp)"
default_security_docs_output="$(mktemp)"
missing_copy_output="$(mktemp)"
external_placeholder_output="$(mktemp)"
no_remote_lookup_output="$(mktemp)"
remote_opt_in_output="$(mktemp)"
remote_v05_missing_output="$(mktemp)"
status_failure_output="$(mktemp)"
grep_error_output="$(mktemp)"
placeholder_release_copy="$(mktemp)"
placeholder_free_release_copy="$(mktemp)"
placeholder_homebrew_cask="$(mktemp)"
placeholder_free_homebrew_cask="$(mktemp)"
mismatched_homebrew_cask="$(mktemp)"
url_mismatch_homebrew_cask="$(mktemp)"
verified_mismatch_homebrew_cask="$(mktemp)"
missing_verified_homebrew_cask="$(mktemp)"
version_mismatch_homebrew_cask="$(mktemp)"
missing_version_homebrew_cask="$(mktemp)"
missing_sha_homebrew_cask="$(mktemp)"
placeholder_security_doc="$(mktemp)"
placeholder_free_security_doc="$(mktemp)"
release_zip_fixture="$(mktemp)"
grep_error_release_copy="$(mktemp)"
missing_release_copy="$(mktemp)"
rm -f "$missing_release_copy"
rm -f "$missing_artifact_zip"
fake_git_dir="$(mktemp -d)"
fake_git_marker="$fake_git_dir/ls-remote-called"
default_security_docs_repo="$(mktemp -d)"
cleanup() {
  rm -f \
    "$missing_output" \
    "$redaction_output" \
    "$missing_artifact_output" \
    "$missing_artifact_zip" \
    "$missing_artifact_sha_output" \
    "$invalid_artifact_sha_output" \
    "$mismatched_artifact_sha_output" \
    "$mismatched_homebrew_cask_sha_output" \
    "$homebrew_cask_url_mismatch_output" \
    "$homebrew_cask_verified_mismatch_output" \
    "$missing_homebrew_cask_verified_output" \
    "$homebrew_cask_version_mismatch_output" \
    "$missing_homebrew_cask_version_output" \
    "$missing_homebrew_cask_sha_output" \
    "$placeholder_output" \
    "$homebrew_cask_placeholder_output" \
    "$security_doc_placeholder_output" \
    "$default_security_docs_output" \
    "$missing_copy_output" \
    "$external_placeholder_output" \
    "$no_remote_lookup_output" \
    "$remote_opt_in_output" \
    "$remote_v05_missing_output" \
    "$status_failure_output" \
    "$grep_error_output" \
    "$placeholder_release_copy" \
    "$placeholder_free_release_copy" \
    "$placeholder_homebrew_cask" \
    "$placeholder_free_homebrew_cask" \
    "$mismatched_homebrew_cask" \
    "$url_mismatch_homebrew_cask" \
    "$verified_mismatch_homebrew_cask" \
    "$missing_verified_homebrew_cask" \
    "$version_mismatch_homebrew_cask" \
    "$missing_version_homebrew_cask" \
    "$missing_sha_homebrew_cask" \
    "$placeholder_security_doc" \
    "$placeholder_free_security_doc" \
    "$release_zip_fixture" \
    "$grep_error_release_copy" \
    "$missing_release_copy"
  rm -rf "$fake_git_dir" "$default_security_docs_repo"
}
trap cleanup EXIT

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
    tag_ref="${5:-}"
    if [[ "${FAKE_GIT_REMOTE_V05_MISSING:-}" == "1" && "$tag_ref" == "refs/tags/v0.5" ]]; then
      exit 2
    fi
    if [[ "${FAKE_GIT_REMOTE_V10_ABSENT:-}" == "1" && "$tag_ref" == "refs/tags/v1.0" ]]; then
      exit 2
    fi
    exit 99
    ;;
esac

printf 'unexpected fake git invocation:' >&2
printf ' %s' "$@" >&2
printf '\n' >&2
exit 98
FAKE_GIT
chmod +x "$fake_git_dir/git"
cat >"$fake_git_dir/grep" <<'FAKE_GREP'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_GREP_ERROR_PATH:-}" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == "$FAKE_GREP_ERROR_PATH" ]]; then
      printf 'grep: %s: fake read error\n' "$arg" >&2
      exit 2
    fi
  done
fi

exec /usr/bin/grep "$@"
FAKE_GREP
chmod +x "$fake_git_dir/grep"
fake_path="$fake_git_dir:${PATH:-/usr/bin:/bin}"
printf 'fake public release zip fixture\n' >"$release_zip_fixture"
release_zip_sha="$(/usr/bin/shasum -a 256 "$release_zip_fixture" | /usr/bin/cut -d ' ' -f 1)"
release_zip_sha_upper="$(printf '%s' "$release_zip_sha" | /usr/bin/tr '[:lower:]' '[:upper:]')"
printf 'LithePG v1.0 release copy with REPLACE_WITH_FINAL_VALUE placeholder.\n' >"$placeholder_release_copy"
printf 'LithePG v1.0 release copy with final values only.\n' >"$placeholder_free_release_copy"
cat >"$placeholder_homebrew_cask" <<'CASK'
cask "lithepg" do
  version "REPLACE_WITH_VERSION"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
cat >"$placeholder_free_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
cat >"$mismatched_homebrew_cask" <<'CASK'
cask "lithepg" do
  version "1.0"
  sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
wrong_homebrew_cask_url="https://example.invalid/not-lithepg/releases/download/v1.0/NotLithePG.app.zip"
cat >"$url_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "$wrong_homebrew_cask_url",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
wrong_homebrew_cask_verified="github.com/example/not-lithepg/"
cat >"$verified_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "$wrong_homebrew_cask_verified"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
cat >"$missing_verified_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
cat >"$version_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "0.9"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
cat >"$missing_version_homebrew_cask" <<CASK
cask "lithepg" do
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v1.0/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
cat >"$missing_sha_homebrew_cask" <<'CASK'
cask "lithepg" do
  version "1.0"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  app "LithePG.app"
end
CASK
printf 'Report vulnerabilities to [security contact pending].\n' >"$placeholder_security_doc"
printf 'Report vulnerabilities using the configured private security advisory flow.\n' >"$placeholder_free_security_doc"
printf 'LithePG v1.0 release copy that cannot be scanned by fake grep.\n' >"$grep_error_release_copy"

mkdir -p "$default_security_docs_repo/script" "$default_security_docs_repo/docs"
default_security_docs_helper="$default_security_docs_repo/script/v10_release_gate.sh"
cp "$HELPER" "$default_security_docs_helper"
chmod +x "$default_security_docs_helper"
printf 'Report vulnerabilities using the configured private security advisory flow.\n' >"$default_security_docs_repo/SECURITY.md"
printf 'Report vulnerabilities to [security contact pending].\n' >"$default_security_docs_repo/docs/SECURITY.md"

if run_gate_capture "$missing_output" env -i PATH="$fake_path" FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker"; then
  fail "gate unexpectedly passed with all required external inputs missing"
fi
missing_text="$(<"$missing_output")"
assert_contains "$missing_text" "v1.0 publication blocked"
assert_contains "$missing_text" "LITHEPG_CODESIGN_IDENTITY: missing"
assert_contains "$missing_text" "LITHEPG_NOTARY_PROFILE: missing"
assert_contains "$missing_text" "LITHEPG_SECURITY_CONTACT: missing"
assert_contains "$missing_text" "LITHEPG_HOMEBREW_TAP: missing"
assert_contains "$missing_text" "LITHEPG_GITHUB_ACTIONS_READY: not approved"
assert_contains "$missing_text" "LITHEPG_RELEASE_COPY_APPROVED: not approved"
assert_contains "$missing_text" "LITHEPG_PUBLICATION_APPROVED: not approved"
assert_contains "$missing_text" "Release artifact zip: missing at dist/LithePG.app.zip"
assert_contains "$missing_text" "Release artifact SHA-256: missing"
assert_not_contains "$missing_text" "fast preflight is clear"

secret_identity="SECRET_CODESIGN_IDENTITY_DO_NOT_PRINT"
secret_notary="SECRET_NOTARY_PROFILE_DO_NOT_PRINT"
secret_contact="security-secret@example.invalid"
secret_tap="SECRET_HOMEBREW_TAP_DO_NOT_PRINT"

if run_gate_capture "$redaction_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="$secret_identity" \
  LITHEPG_NOTARY_PROFILE="$secret_notary" \
  LITHEPG_SECURITY_CONTACT="$secret_contact" \
  LITHEPG_HOMEBREW_TAP="$secret_tap" \
  LITHEPG_GITHUB_ACTIONS_READY="no" \
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
assert_contains "$redaction_text" "LITHEPG_GITHUB_ACTIONS_READY: not approved"
assert_contains "$redaction_text" "LITHEPG_RELEASE_COPY_APPROVED: not approved"
assert_contains "$redaction_text" "LITHEPG_PUBLICATION_APPROVED: not approved"
assert_not_contains "$redaction_text" "$secret_identity"
assert_not_contains "$redaction_text" "$secret_notary"
assert_not_contains "$redaction_text" "$secret_contact"
assert_not_contains "$redaction_text" "$secret_tap"

if run_gate_capture "$missing_artifact_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$missing_artifact_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with missing release artifact zip"
fi
missing_artifact_text="$(<"$missing_artifact_output")"
assert_contains "$missing_artifact_text" "Release artifact zip: missing at $missing_artifact_zip"
assert_contains "$missing_artifact_text" "v1.0 publication blocked"
assert_not_contains "$missing_artifact_text" "fast preflight is clear"

if run_gate_capture "$missing_artifact_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with missing release artifact SHA-256"
fi
missing_artifact_sha_text="$(<"$missing_artifact_sha_output")"
assert_contains "$missing_artifact_sha_text" "Release artifact zip: present"
assert_contains "$missing_artifact_sha_text" "Release artifact SHA-256: missing"
assert_contains "$missing_artifact_sha_text" "v1.0 publication blocked"
assert_not_contains "$missing_artifact_sha_text" "fast preflight is clear"

invalid_sha_marker="INVALID_SHA_VALUE_DO_NOT_PRINT"
if run_gate_capture "$invalid_artifact_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$invalid_sha_marker" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with invalid release artifact SHA-256"
fi
invalid_artifact_sha_text="$(<"$invalid_artifact_sha_output")"
assert_contains "$invalid_artifact_sha_text" "Release artifact zip: present"
assert_contains "$invalid_artifact_sha_text" "Release artifact SHA-256: invalid format"
assert_not_contains "$invalid_artifact_sha_text" "$invalid_sha_marker"
assert_contains "$invalid_artifact_sha_text" "v1.0 publication blocked"

mismatched_sha_marker="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
if run_gate_capture "$mismatched_artifact_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$mismatched_sha_marker" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with mismatched release artifact SHA-256"
fi
mismatched_artifact_sha_text="$(<"$mismatched_artifact_sha_output")"
assert_contains "$mismatched_artifact_sha_text" "Release artifact zip: present"
assert_contains "$mismatched_artifact_sha_text" "Release artifact SHA-256: mismatch"
assert_not_contains "$mismatched_artifact_sha_text" "$mismatched_sha_marker"
assert_not_contains "$mismatched_artifact_sha_text" "$release_zip_sha"
assert_contains "$mismatched_artifact_sha_text" "v1.0 publication blocked"

mismatched_cask_sha_marker="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
if run_gate_capture "$mismatched_homebrew_cask_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$mismatched_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with mismatched Homebrew cask SHA-256"
fi
mismatched_homebrew_cask_sha_text="$(<"$mismatched_homebrew_cask_sha_output")"
assert_contains "$mismatched_homebrew_cask_sha_text" "Homebrew cask placeholders: none found"
assert_contains "$mismatched_homebrew_cask_sha_text" "Homebrew cask SHA-256: mismatch"
assert_not_contains "$mismatched_homebrew_cask_sha_text" "$mismatched_cask_sha_marker"
assert_not_contains "$mismatched_homebrew_cask_sha_text" "$release_zip_sha"
assert_contains "$mismatched_homebrew_cask_sha_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_url_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$url_mismatch_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  homebrew_cask_url_mismatch_text="$(<"$homebrew_cask_url_mismatch_output")"
  assert_not_contains "$homebrew_cask_url_mismatch_text" "$wrong_homebrew_cask_url"
  fail "gate unexpectedly passed with mismatched Homebrew cask URL"
fi
homebrew_cask_url_mismatch_text="$(<"$homebrew_cask_url_mismatch_output")"
assert_contains "$homebrew_cask_url_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_url_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_url_mismatch_text" "Homebrew cask URL: mismatch"
assert_contains "$homebrew_cask_url_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_url_mismatch_text" "$wrong_homebrew_cask_url"
assert_not_contains "$homebrew_cask_url_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_url_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_verified_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$verified_mismatch_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  homebrew_cask_verified_mismatch_text="$(<"$homebrew_cask_verified_mismatch_output")"
  assert_not_contains "$homebrew_cask_verified_mismatch_text" "$wrong_homebrew_cask_verified"
  fail "gate unexpectedly passed with mismatched Homebrew cask verified URL"
fi
homebrew_cask_verified_mismatch_text="$(<"$homebrew_cask_verified_mismatch_output")"
assert_contains "$homebrew_cask_verified_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_verified_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_verified_mismatch_text" "Homebrew cask URL: matches"
assert_contains "$homebrew_cask_verified_mismatch_text" "Homebrew cask verified URL: mismatch"
assert_contains "$homebrew_cask_verified_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_verified_mismatch_text" "$wrong_homebrew_cask_verified"
assert_not_contains "$homebrew_cask_verified_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_verified_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_verified_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_verified_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with missing Homebrew cask verified URL"
fi
missing_homebrew_cask_verified_text="$(<"$missing_homebrew_cask_verified_output")"
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask URL: matches"
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask verified URL: missing"
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_verified_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_verified_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_version_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$version_mismatch_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with mismatched Homebrew cask version"
fi
homebrew_cask_version_mismatch_text="$(<"$homebrew_cask_version_mismatch_output")"
assert_contains "$homebrew_cask_version_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_version_mismatch_text" "Homebrew cask version: mismatch"
assert_contains "$homebrew_cask_version_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_version_mismatch_text" "0.9"
assert_not_contains "$homebrew_cask_version_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_version_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_version_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_version_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with missing Homebrew cask version"
fi
missing_homebrew_cask_version_text="$(<"$missing_homebrew_cask_version_output")"
assert_contains "$missing_homebrew_cask_version_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_version_text" "Homebrew cask version: missing"
assert_contains "$missing_homebrew_cask_version_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_version_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_version_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_sha_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with missing Homebrew cask SHA-256"
fi
missing_homebrew_cask_sha_text="$(<"$missing_homebrew_cask_sha_output")"
assert_contains "$missing_homebrew_cask_sha_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_sha_text" "Homebrew cask SHA-256: missing"
assert_not_contains "$missing_homebrew_cask_sha_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_sha_text" "v1.0 publication blocked"

if run_gate_capture "$placeholder_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with placeholders in release copy fixture"
fi
placeholder_text="$(<"$placeholder_output")"
assert_contains "$placeholder_text" "Release copy placeholders: present in $placeholder_release_copy"
assert_contains "$placeholder_text" "v1.0 publication blocked"
assert_not_contains "$placeholder_text" "fast preflight is clear"

if run_gate_capture "$homebrew_cask_placeholder_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with placeholders in Homebrew cask template"
fi
homebrew_cask_placeholder_text="$(<"$homebrew_cask_placeholder_output")"
assert_contains "$homebrew_cask_placeholder_text" "Release copy placeholders: none found"
assert_contains "$homebrew_cask_placeholder_text" "Homebrew cask placeholders: present in $placeholder_homebrew_cask"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask version: mismatch"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask version: missing"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask URL: mismatch"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask verified URL:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask SHA-256: mismatch"
assert_contains "$homebrew_cask_placeholder_text" "v1.0 publication blocked"
assert_not_contains "$homebrew_cask_placeholder_text" "fast preflight is clear"

if run_specific_gate_capture "$default_security_docs_output" "$default_security_docs_helper" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed when default docs/SECURITY.md contained a security-contact placeholder"
fi
default_security_docs_text="$(<"$default_security_docs_output")"
assert_contains "$default_security_docs_text" "Release copy placeholders: none found"
assert_contains "$default_security_docs_text" "Homebrew cask placeholders: none found"
assert_contains "$default_security_docs_text" "Security policy placeholders: none found in SECURITY.md"
assert_contains "$default_security_docs_text" "Security policy placeholders: present in docs/SECURITY.md"
assert_contains "$default_security_docs_text" "v1.0 publication blocked"
assert_not_contains "$default_security_docs_text" "[security contact pending]"
assert_not_contains "$default_security_docs_text" "fast preflight is clear"

if run_gate_capture "$security_doc_placeholder_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with placeholders in security policy fixture"
fi
security_doc_placeholder_text="$(<"$security_doc_placeholder_output")"
assert_contains "$security_doc_placeholder_text" "Release copy placeholders: none found"
assert_contains "$security_doc_placeholder_text" "Homebrew cask placeholders: none found"
assert_contains "$security_doc_placeholder_text" "Security policy placeholders: present in $placeholder_security_doc"
assert_contains "$security_doc_placeholder_text" "v1.0 publication blocked"
assert_not_contains "$security_doc_placeholder_text" "[security contact pending]"
assert_not_contains "$security_doc_placeholder_text" "fast preflight is clear"

if run_gate_capture "$missing_copy_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$missing_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with missing release copy"
fi
missing_copy_text="$(<"$missing_copy_output")"
assert_contains "$missing_copy_text" "Release copy placeholders: missing release copy at $missing_release_copy"
assert_contains "$missing_copy_text" "v1.0 publication blocked"
assert_not_contains "$missing_copy_text" "fast preflight is clear"

if run_gate_capture "$grep_error_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  FAKE_GREP_ERROR_PATH="$grep_error_release_copy" \
  LITHEPG_RELEASE_COPY_PATH="$grep_error_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed when release copy grep scan failed"
fi
grep_error_text="$(<"$grep_error_output")"
assert_contains "$grep_error_text" "Release copy placeholders: could not scan $grep_error_release_copy"
assert_contains "$grep_error_text" "v1.0 publication blocked"
assert_not_contains "$grep_error_text" "Release copy placeholders: none found"
assert_not_contains "$grep_error_text" "fast preflight is clear"

if run_gate_capture "$external_placeholder_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="[security contact pending]" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed with placeholder external security contact"
fi
external_placeholder_text="$(<"$external_placeholder_output")"
assert_contains "$external_placeholder_text" "Release copy placeholders: none found"
assert_contains "$external_placeholder_text" "Homebrew cask placeholders: none found"
assert_contains "$external_placeholder_text" "LITHEPG_CODESIGN_IDENTITY: configured"
assert_contains "$external_placeholder_text" "LITHEPG_NOTARY_PROFILE: configured"
assert_contains "$external_placeholder_text" "LITHEPG_SECURITY_CONTACT: placeholder"
assert_contains "$external_placeholder_text" "LITHEPG_HOMEBREW_TAP: configured"
assert_contains "$external_placeholder_text" "v1.0 publication blocked"
assert_not_contains "$external_placeholder_text" "[security contact pending]"
assert_not_contains "$external_placeholder_text" "fast preflight is clear"

rm -f "$fake_git_marker"
if ! run_gate_capture "$no_remote_lookup_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha_upper" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly failed with all required external inputs configured"
fi
no_remote_lookup_text="$(<"$no_remote_lookup_output")"
assert_contains "$no_remote_lookup_text" "Release copy placeholders: none found"
assert_contains "$no_remote_lookup_text" "Homebrew cask placeholders: none found"
assert_contains "$no_remote_lookup_text" "Homebrew cask version: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask URL: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask verified URL: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask SHA-256: matches"
assert_contains "$no_remote_lookup_text" "Release artifact zip: present"
assert_contains "$no_remote_lookup_text" "Release artifact SHA-256: matches"
assert_contains "$no_remote_lookup_text" "Remote origin tag v1.0: not checked (set LITHEPG_CHECK_REMOTE_TAGS=1 or pass --check-remote)"
if [[ -e "$fake_git_marker" ]]; then
  fail "default gate invoked git ls-remote despite remote lookup not being requested"
fi

rm -f "$fake_git_marker"
if ! run_gate_capture "$remote_opt_in_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_CHECK_REMOTE_TAGS="1" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly failed when opt-in remote lookup returned unknown"
fi
remote_opt_in_text="$(<"$remote_opt_in_output")"
assert_contains "$remote_opt_in_text" "Release copy placeholders: none found"
assert_contains "$remote_opt_in_text" "Homebrew cask placeholders: none found"
assert_contains "$remote_opt_in_text" "Remote origin tag v1.0: unknown (remote/network unavailable; not blocking this fast check)"
if [[ ! -e "$fake_git_marker" ]]; then
  fail "opt-in remote lookup did not invoke git ls-remote"
fi

rm -f "$fake_git_marker"
if run_gate_capture "$remote_v05_missing_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  FAKE_GIT_REMOTE_V05_MISSING="1" \
  FAKE_GIT_REMOTE_V10_ABSENT="1" \
  LITHEPG_CHECK_REMOTE_TAGS="1" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed when remote origin v0.5 was missing"
fi
remote_v05_missing_text="$(<"$remote_v05_missing_output")"
assert_contains "$remote_v05_missing_text" "Remote origin tag v0.5: missing"
assert_contains "$remote_v05_missing_text" "Remote origin tag v1.0: absent"
assert_contains "$remote_v05_missing_text" "v1.0 publication blocked"
assert_not_contains "$remote_v05_missing_text" "fast preflight is clear"
if [[ ! -e "$fake_git_marker" ]]; then
  fail "opt-in remote v0.5 readiness check did not invoke git ls-remote"
fi

if run_gate_capture "$status_failure_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  FAKE_GIT_STATUS_FAIL="1" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$release_zip_fixture" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  fail "gate unexpectedly passed when git status failed"
fi
status_failure_text="$(<"$status_failure_output")"
assert_contains "$status_failure_text" "Git status: unknown (git status failed; expected clean before tagging/publishing)"
assert_contains "$status_failure_text" "v1.0 publication blocked"
assert_not_contains "$status_failure_text" "Git status: clean"

printf 'test_v10_release_gate passed\n'
