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
artifact_filename_mismatch_output="$(mktemp)"
artifact_app_wrapper_missing_output="$(mktemp)"
artifact_bundle_file_type_inspect_failure_output="$(mktemp)"
artifact_bundle_contents_missing_output="$(mktemp)"
artifact_bundle_file_type_invalid_output="$(mktemp)"
artifact_bundle_executable_permission_output="$(mktemp)"
artifact_bundle_owner_execute_permission_output="$(mktemp)"
artifact_top_level_unexpected_output="$(mktemp)"
missing_artifact_sha_output="$(mktemp)"
invalid_artifact_sha_output="$(mktemp)"
mismatched_artifact_sha_output="$(mktemp)"
mismatched_release_copy_sha_output="$(mktemp)"
embedded_release_copy_sha_output="$(mktemp)"
unchecked_release_copy_output="$(mktemp)"
mismatched_homebrew_cask_sha_output="$(mktemp)"
homebrew_cask_url_mismatch_output="$(mktemp)"
homebrew_cask_token_mismatch_output="$(mktemp)"
missing_homebrew_cask_token_output="$(mktemp)"
homebrew_cask_name_mismatch_output="$(mktemp)"
missing_homebrew_cask_name_output="$(mktemp)"
homebrew_cask_desc_mismatch_output="$(mktemp)"
missing_homebrew_cask_desc_output="$(mktemp)"
homebrew_cask_verified_mismatch_output="$(mktemp)"
missing_homebrew_cask_verified_output="$(mktemp)"
homebrew_cask_homepage_mismatch_output="$(mktemp)"
missing_homebrew_cask_homepage_output="$(mktemp)"
homebrew_cask_bundle_id_mismatch_output="$(mktemp)"
missing_homebrew_cask_bundle_id_output="$(mktemp)"
homebrew_cask_version_mismatch_output="$(mktemp)"
missing_homebrew_cask_version_output="$(mktemp)"
missing_homebrew_cask_sha_output="$(mktemp)"
homebrew_cask_app_mismatch_output="$(mktemp)"
missing_homebrew_cask_app_output="$(mktemp)"
homebrew_cask_macos_mismatch_output="$(mktemp)"
missing_homebrew_cask_macos_output="$(mktemp)"
homebrew_cask_zap_mismatch_output="$(mktemp)"
missing_homebrew_cask_zap_output="$(mktemp)"
commented_homebrew_cask_zap_output="$(mktemp)"
inline_commented_homebrew_cask_zap_output="$(mktemp)"
unterminated_homebrew_cask_zap_output="$(mktemp)"
syntax_error_homebrew_cask_output="$(mktemp)"
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
mismatched_release_copy_sha="$(mktemp)"
embedded_release_copy_sha="$(mktemp)"
unchecked_release_copy="$(mktemp)"
placeholder_homebrew_cask="$(mktemp)"
placeholder_free_homebrew_cask="$(mktemp)"
mismatched_homebrew_cask="$(mktemp)"
token_mismatch_homebrew_cask="$(mktemp)"
missing_token_homebrew_cask="$(mktemp)"
name_mismatch_homebrew_cask="$(mktemp)"
missing_name_homebrew_cask="$(mktemp)"
desc_mismatch_homebrew_cask="$(mktemp)"
missing_desc_homebrew_cask="$(mktemp)"
url_mismatch_homebrew_cask="$(mktemp)"
verified_mismatch_homebrew_cask="$(mktemp)"
missing_verified_homebrew_cask="$(mktemp)"
homepage_mismatch_homebrew_cask="$(mktemp)"
missing_homepage_homebrew_cask="$(mktemp)"
bundle_id_mismatch_homebrew_cask="$(mktemp)"
missing_bundle_id_homebrew_cask="$(mktemp)"
version_mismatch_homebrew_cask="$(mktemp)"
missing_version_homebrew_cask="$(mktemp)"
missing_sha_homebrew_cask="$(mktemp)"
app_mismatch_homebrew_cask="$(mktemp)"
missing_app_homebrew_cask="$(mktemp)"
macos_mismatch_homebrew_cask="$(mktemp)"
missing_macos_homebrew_cask="$(mktemp)"
zap_mismatch_homebrew_cask="$(mktemp)"
missing_zap_homebrew_cask="$(mktemp)"
commented_zap_homebrew_cask="$(mktemp)"
inline_commented_zap_homebrew_cask="$(mktemp)"
unterminated_zap_homebrew_cask="$(mktemp)"
syntax_error_homebrew_cask="$(mktemp)"
placeholder_security_doc="$(mktemp)"
placeholder_free_security_doc="$(mktemp)"
release_zip_dir="$(mktemp -d)"
release_zip_fixture="$release_zip_dir/LithePG.app.zip"
missing_wrapper_zip_dir="$(mktemp -d)"
missing_wrapper_zip="$missing_wrapper_zip_dir/LithePG.app.zip"
missing_wrapper_release_copy="$(mktemp)"
missing_wrapper_homebrew_cask="$(mktemp)"
cannot_inspect_zip_dir="$(mktemp -d)"
cannot_inspect_zip="$cannot_inspect_zip_dir/LithePG.app.zip"
cannot_inspect_release_copy="$(mktemp)"
cannot_inspect_homebrew_cask="$(mktemp)"
incomplete_bundle_zip_dir="$(mktemp -d)"
incomplete_bundle_zip="$incomplete_bundle_zip_dir/LithePG.app.zip"
incomplete_bundle_release_copy="$(mktemp)"
incomplete_bundle_homebrew_cask="$(mktemp)"
symlink_bundle_zip_dir="$(mktemp -d)"
symlink_bundle_zip="$symlink_bundle_zip_dir/LithePG.app.zip"
symlink_bundle_release_copy="$(mktemp)"
symlink_bundle_homebrew_cask="$(mktemp)"
non_executable_bundle_zip_dir="$(mktemp -d)"
non_executable_bundle_zip="$non_executable_bundle_zip_dir/LithePG.app.zip"
non_executable_bundle_release_copy="$(mktemp)"
non_executable_bundle_homebrew_cask="$(mktemp)"
owner_execute_missing_bundle_zip_dir="$(mktemp -d)"
owner_execute_missing_bundle_zip="$owner_execute_missing_bundle_zip_dir/LithePG.app.zip"
owner_execute_missing_bundle_release_copy="$(mktemp)"
owner_execute_missing_bundle_homebrew_cask="$(mktemp)"
unexpected_top_level_zip_dir="$(mktemp -d)"
unexpected_top_level_zip="$unexpected_top_level_zip_dir/LithePG.app.zip"
unexpected_top_level_release_copy="$(mktemp)"
unexpected_top_level_homebrew_cask="$(mktemp)"
wrong_basename_zip_dir="$(mktemp -d)"
wrong_basename_zip="$wrong_basename_zip_dir/NotLithePG.zip"
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
    "$artifact_filename_mismatch_output" \
    "$artifact_app_wrapper_missing_output" \
    "$artifact_bundle_file_type_inspect_failure_output" \
    "$artifact_bundle_contents_missing_output" \
    "$artifact_bundle_file_type_invalid_output" \
    "$artifact_bundle_executable_permission_output" \
    "$artifact_bundle_owner_execute_permission_output" \
    "$artifact_top_level_unexpected_output" \
    "$missing_artifact_sha_output" \
    "$invalid_artifact_sha_output" \
    "$mismatched_artifact_sha_output" \
    "$mismatched_release_copy_sha_output" \
    "$embedded_release_copy_sha_output" \
    "$unchecked_release_copy_output" \
    "$mismatched_homebrew_cask_sha_output" \
    "$homebrew_cask_url_mismatch_output" \
    "$homebrew_cask_token_mismatch_output" \
    "$missing_homebrew_cask_token_output" \
    "$homebrew_cask_name_mismatch_output" \
    "$missing_homebrew_cask_name_output" \
    "$homebrew_cask_desc_mismatch_output" \
    "$missing_homebrew_cask_desc_output" \
    "$homebrew_cask_verified_mismatch_output" \
    "$missing_homebrew_cask_verified_output" \
    "$homebrew_cask_homepage_mismatch_output" \
    "$missing_homebrew_cask_homepage_output" \
    "$homebrew_cask_bundle_id_mismatch_output" \
    "$missing_homebrew_cask_bundle_id_output" \
    "$homebrew_cask_version_mismatch_output" \
    "$missing_homebrew_cask_version_output" \
    "$missing_homebrew_cask_sha_output" \
    "$homebrew_cask_app_mismatch_output" \
    "$missing_homebrew_cask_app_output" \
    "$homebrew_cask_macos_mismatch_output" \
    "$missing_homebrew_cask_macos_output" \
    "$homebrew_cask_zap_mismatch_output" \
    "$missing_homebrew_cask_zap_output" \
    "$commented_homebrew_cask_zap_output" \
    "$inline_commented_homebrew_cask_zap_output" \
    "$unterminated_homebrew_cask_zap_output" \
    "$syntax_error_homebrew_cask_output" \
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
    "$mismatched_release_copy_sha" \
    "$embedded_release_copy_sha" \
    "$unchecked_release_copy" \
    "$placeholder_homebrew_cask" \
    "$placeholder_free_homebrew_cask" \
    "$mismatched_homebrew_cask" \
    "$token_mismatch_homebrew_cask" \
    "$missing_token_homebrew_cask" \
    "$name_mismatch_homebrew_cask" \
    "$missing_name_homebrew_cask" \
    "$desc_mismatch_homebrew_cask" \
    "$missing_desc_homebrew_cask" \
    "$url_mismatch_homebrew_cask" \
    "$verified_mismatch_homebrew_cask" \
    "$missing_verified_homebrew_cask" \
    "$homepage_mismatch_homebrew_cask" \
    "$missing_homepage_homebrew_cask" \
    "$bundle_id_mismatch_homebrew_cask" \
    "$missing_bundle_id_homebrew_cask" \
    "$version_mismatch_homebrew_cask" \
    "$missing_version_homebrew_cask" \
    "$missing_sha_homebrew_cask" \
    "$app_mismatch_homebrew_cask" \
    "$missing_app_homebrew_cask" \
    "$macos_mismatch_homebrew_cask" \
    "$missing_macos_homebrew_cask" \
    "$zap_mismatch_homebrew_cask" \
    "$missing_zap_homebrew_cask" \
    "$commented_zap_homebrew_cask" \
    "$inline_commented_zap_homebrew_cask" \
    "$unterminated_zap_homebrew_cask" \
    "$syntax_error_homebrew_cask" \
    "$placeholder_security_doc" \
    "$placeholder_free_security_doc" \
    "$release_zip_fixture" \
    "$missing_wrapper_zip" \
    "$missing_wrapper_release_copy" \
    "$missing_wrapper_homebrew_cask" \
    "$cannot_inspect_zip" \
    "$cannot_inspect_release_copy" \
    "$cannot_inspect_homebrew_cask" \
    "$incomplete_bundle_zip" \
    "$incomplete_bundle_release_copy" \
    "$incomplete_bundle_homebrew_cask" \
    "$symlink_bundle_zip" \
    "$symlink_bundle_release_copy" \
    "$symlink_bundle_homebrew_cask" \
    "$non_executable_bundle_zip" \
    "$non_executable_bundle_release_copy" \
    "$non_executable_bundle_homebrew_cask" \
    "$owner_execute_missing_bundle_zip" \
    "$owner_execute_missing_bundle_release_copy" \
    "$owner_execute_missing_bundle_homebrew_cask" \
    "$unexpected_top_level_zip" \
    "$unexpected_top_level_release_copy" \
    "$unexpected_top_level_homebrew_cask" \
    "$wrong_basename_zip" \
    "$grep_error_release_copy" \
    "$missing_release_copy"
  rm -rf "$fake_git_dir" "$default_security_docs_repo" "$release_zip_dir" "$missing_wrapper_zip_dir" "$cannot_inspect_zip_dir" "$incomplete_bundle_zip_dir" "$symlink_bundle_zip_dir" "$non_executable_bundle_zip_dir" "$owner_execute_missing_bundle_zip_dir" "$unexpected_top_level_zip_dir" "$wrong_basename_zip_dir"
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
mkdir -p "$release_zip_dir/fixture-root/LithePG.app/Contents/MacOS"
printf '<plist><dict></dict></plist>\n' >"$release_zip_dir/fixture-root/LithePG.app/Contents/Info.plist"
printf 'fake public release app executable fixture\n' >"$release_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
/bin/chmod 755 "$release_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
(
  cd "$release_zip_dir/fixture-root"
  /usr/bin/zip -qr "$release_zip_fixture" LithePG.app
)
release_zip_sha="$(/usr/bin/shasum -a 256 "$release_zip_fixture" | /usr/bin/cut -d ' ' -f 1)"
release_zip_sha_upper="$(printf '%s' "$release_zip_sha" | /usr/bin/tr '[:lower:]' '[:upper:]')"
/bin/cp "$release_zip_fixture" "$wrong_basename_zip"
mkdir -p "$missing_wrapper_zip_dir/fixture-root/NotLithePG.app/Contents/MacOS"
printf 'fake wrong release app executable fixture\n' >"$missing_wrapper_zip_dir/fixture-root/NotLithePG.app/Contents/MacOS/NotLithePG"
(
  cd "$missing_wrapper_zip_dir/fixture-root"
  /usr/bin/zip -qr "$missing_wrapper_zip" NotLithePG.app
)
missing_wrapper_zip_sha="$(/usr/bin/shasum -a 256 "$missing_wrapper_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$missing_wrapper_zip_sha" >"$missing_wrapper_release_copy"
cannot_inspect_archive_marker="NONZIP_RELEASE_ARTIFACT_CONTENT_SHOULD_NOT_LEAK"
printf '%s\n' "$cannot_inspect_archive_marker" >"$cannot_inspect_zip"
cannot_inspect_zip_sha="$(/usr/bin/shasum -a 256 "$cannot_inspect_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$cannot_inspect_zip_sha" >"$cannot_inspect_release_copy"
mkdir -p "$incomplete_bundle_zip_dir/fixture-root/LithePG.app/Contents/Resources"
printf 'fake incomplete release app bundle fixture\n' >"$incomplete_bundle_zip_dir/fixture-root/LithePG.app/Contents/Resources/placeholder.txt"
(
  cd "$incomplete_bundle_zip_dir/fixture-root"
  /usr/bin/zip -qr "$incomplete_bundle_zip" LithePG.app
)
incomplete_bundle_zip_sha="$(/usr/bin/shasum -a 256 "$incomplete_bundle_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$incomplete_bundle_zip_sha" >"$incomplete_bundle_release_copy"
mkdir -p "$symlink_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS"
printf '<plist><dict></dict></plist>\n' >"$symlink_bundle_zip_dir/fixture-root/LithePG.app/Contents/Info.target"
printf 'fake public release app executable fixture\n' >"$symlink_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp.target"
(
  cd "$symlink_bundle_zip_dir/fixture-root/LithePG.app/Contents"
  /bin/ln -s Info.target Info.plist
  cd MacOS
  /bin/ln -s LithePGApp.target LithePGApp
)
(
  cd "$symlink_bundle_zip_dir/fixture-root"
  /usr/bin/zip -qry "$symlink_bundle_zip" LithePG.app
)
symlink_bundle_zip_sha="$(/usr/bin/shasum -a 256 "$symlink_bundle_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$symlink_bundle_zip_sha" >"$symlink_bundle_release_copy"
mkdir -p "$unexpected_top_level_zip_dir/fixture-root/LithePG.app/Contents/MacOS"
printf '<plist><dict></dict></plist>\n' >"$unexpected_top_level_zip_dir/fixture-root/LithePG.app/Contents/Info.plist"
printf 'fake public release app executable fixture\n' >"$unexpected_top_level_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
/bin/chmod 755 "$unexpected_top_level_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
printf 'unexpected public release top-level file\n' >"$unexpected_top_level_zip_dir/fixture-root/README.txt"
(
  cd "$unexpected_top_level_zip_dir/fixture-root"
  /usr/bin/zip -qr "$unexpected_top_level_zip" LithePG.app README.txt
)
unexpected_top_level_zip_sha="$(/usr/bin/shasum -a 256 "$unexpected_top_level_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$unexpected_top_level_zip_sha" >"$unexpected_top_level_release_copy"
mkdir -p "$non_executable_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS"
printf '<plist><dict></dict></plist>\n' >"$non_executable_bundle_zip_dir/fixture-root/LithePG.app/Contents/Info.plist"
printf 'fake non-executable release app executable fixture\n' >"$non_executable_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
/bin/chmod 644 "$non_executable_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
(
  cd "$non_executable_bundle_zip_dir/fixture-root"
  /usr/bin/zip -qr "$non_executable_bundle_zip" LithePG.app
)
non_executable_bundle_zip_sha="$(/usr/bin/shasum -a 256 "$non_executable_bundle_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$non_executable_bundle_zip_sha" >"$non_executable_bundle_release_copy"
mkdir -p "$owner_execute_missing_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS"
printf '<plist><dict></dict></plist>\n' >"$owner_execute_missing_bundle_zip_dir/fixture-root/LithePG.app/Contents/Info.plist"
printf 'fake owner-execute-missing app executable fixture\n' >"$owner_execute_missing_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
/bin/chmod 645 "$owner_execute_missing_bundle_zip_dir/fixture-root/LithePG.app/Contents/MacOS/LithePGApp"
(
  cd "$owner_execute_missing_bundle_zip_dir/fixture-root"
  /usr/bin/zip -qr "$owner_execute_missing_bundle_zip" LithePG.app
)
owner_execute_missing_bundle_zip_sha="$(/usr/bin/shasum -a 256 "$owner_execute_missing_bundle_zip" | /usr/bin/cut -d ' ' -f 1)"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$owner_execute_missing_bundle_zip_sha" >"$owner_execute_missing_bundle_release_copy"
printf 'LithePG v1.0 release copy with REPLACE_WITH_FINAL_VALUE placeholder.\n' >"$placeholder_release_copy"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n' "$release_zip_sha" >"$placeholder_free_release_copy"
wrong_release_copy_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf 'LithePG v1.0 release copy with stale SHA-256 %s.\n' "$wrong_release_copy_sha" >"$mismatched_release_copy_sha"
printf 'LithePG v1.0 release copy with malformed SHA-256 %s0.\n' "$release_zip_sha" >"$embedded_release_copy_sha"
printf 'LithePG v1.0 release copy with approved SHA-256 %s.\n- [ ] Remove draft checklist\n' "$release_zip_sha" >"$unchecked_release_copy"
cat >"$placeholder_homebrew_cask" <<'CASK'
cask "lithepg" do
  version "REPLACE_WITH_VERSION"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_wrapper_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$missing_wrapper_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$cannot_inspect_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$cannot_inspect_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$incomplete_bundle_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$incomplete_bundle_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$symlink_bundle_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$symlink_bundle_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$unexpected_top_level_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$unexpected_top_level_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$non_executable_bundle_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$non_executable_bundle_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$owner_execute_missing_bundle_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$owner_execute_missing_bundle_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
wrong_homebrew_cask_token="not-lithepg"
cat >"$token_mismatch_homebrew_cask" <<CASK
cask "$wrong_homebrew_cask_token" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_token_homebrew_cask" <<CASK
# cask token intentionally omitted
version "1.0"
sha256 "$release_zip_sha"

url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
    verified: "github.com/omarpr/lithepg/"
name "LithePG"
desc "Lean PostgreSQL client with local-first AI"
homepage "https://github.com/omarpr/lithepg"
uninstall quit: "dev.omarpr.lithepg"

depends_on macos: ">= :sonoma"

app "LithePG.app"

zap trash: [
  "~/Library/Application Support/LithePG",
  "~/Library/Preferences/dev.omarpr.lithepg.plist",
]
CASK
wrong_homebrew_cask_name="NotLithePG"
cat >"$name_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "$wrong_homebrew_cask_name"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_name_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
wrong_homebrew_cask_desc="Not a PostgreSQL client"
cat >"$desc_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "$wrong_homebrew_cask_desc"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_desc_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
wrong_homebrew_cask_homepage="https://example.invalid/not-lithepg"
cat >"$homepage_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "$wrong_homebrew_cask_homepage"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_homepage_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
wrong_homebrew_cask_bundle_id="not.dev.omarpr.lithepg"
cat >"$bundle_id_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "$wrong_homebrew_cask_bundle_id"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_bundle_id_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
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
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
wrong_homebrew_cask_app="NotLithePG.app"
cat >"$app_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "$wrong_homebrew_cask_app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_app_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$macos_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :ventura"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_macos_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$zap_mismatch_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/NotLithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$missing_zap_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"
end
CASK
cat >"$commented_zap_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    # "~/Library/Application Support/LithePG",
    # "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
CASK
cat >"$inline_commented_zap_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/Other", # "~/Library/Application Support/LithePG"
    "~/Library/Preferences/other.plist", # "~/Library/Preferences/dev.omarpr.lithepg.plist"
  ]
end
CASK
cat >"$unterminated_zap_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
end
CASK
cat >"$syntax_error_homebrew_cask" <<CASK
cask "lithepg" do
  version "1.0"
  sha256 "$release_zip_sha"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"
  uninstall quit: "dev.omarpr.lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
  if true
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

if run_gate_capture "$artifact_filename_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$placeholder_free_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$wrong_basename_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$release_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_filename_mismatch_text="$(<"$artifact_filename_mismatch_output")"
  assert_not_contains "$artifact_filename_mismatch_text" "$wrong_basename_zip"
  assert_not_contains "$artifact_filename_mismatch_text" "$release_zip_sha"
  fail "gate unexpectedly passed with mismatched release artifact filename"
fi
artifact_filename_mismatch_text="$(<"$artifact_filename_mismatch_output")"
assert_contains "$artifact_filename_mismatch_text" "Release artifact filename: mismatch"
assert_contains "$artifact_filename_mismatch_text" "Release artifact zip: present"
assert_contains "$artifact_filename_mismatch_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_filename_mismatch_text" "v1.0 publication blocked"
assert_not_contains "$artifact_filename_mismatch_text" "$wrong_basename_zip"
assert_not_contains "$artifact_filename_mismatch_text" "$release_zip_sha"
assert_not_contains "$artifact_filename_mismatch_text" "fast preflight is clear"

if run_gate_capture "$artifact_app_wrapper_missing_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$missing_wrapper_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_wrapper_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$missing_wrapper_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$missing_wrapper_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_app_wrapper_missing_text="$(<"$artifact_app_wrapper_missing_output")"
  assert_not_contains "$artifact_app_wrapper_missing_text" "NotLithePG.app"
  assert_not_contains "$artifact_app_wrapper_missing_text" "$missing_wrapper_zip_sha"
  fail "gate unexpectedly passed with release artifact missing top-level LithePG.app wrapper"
fi
artifact_app_wrapper_missing_text="$(<"$artifact_app_wrapper_missing_output")"
assert_contains "$artifact_app_wrapper_missing_text" "Release artifact filename: matches"
assert_contains "$artifact_app_wrapper_missing_text" "Release artifact zip: present"
assert_contains "$artifact_app_wrapper_missing_text" "Release artifact app wrapper: missing"
assert_contains "$artifact_app_wrapper_missing_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_app_wrapper_missing_text" "v1.0 publication blocked"
assert_not_contains "$artifact_app_wrapper_missing_text" "NotLithePG.app"
assert_not_contains "$artifact_app_wrapper_missing_text" "$missing_wrapper_zip_sha"
assert_not_contains "$artifact_app_wrapper_missing_text" "fast preflight is clear"

if run_gate_capture "$artifact_bundle_file_type_inspect_failure_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$cannot_inspect_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$cannot_inspect_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$cannot_inspect_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$cannot_inspect_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_bundle_file_type_inspect_failure_text="$(<"$artifact_bundle_file_type_inspect_failure_output")"
  assert_not_contains "$artifact_bundle_file_type_inspect_failure_text" "$cannot_inspect_archive_marker"
  assert_not_contains "$artifact_bundle_file_type_inspect_failure_text" "$cannot_inspect_zip_sha"
  fail "gate unexpectedly passed with uninspectable release artifact zip"
fi
artifact_bundle_file_type_inspect_failure_text="$(<"$artifact_bundle_file_type_inspect_failure_output")"
assert_contains "$artifact_bundle_file_type_inspect_failure_text" "Release artifact filename: matches"
assert_contains "$artifact_bundle_file_type_inspect_failure_text" "Release artifact zip: present"
assert_contains "$artifact_bundle_file_type_inspect_failure_text" "Release artifact app wrapper: could not inspect"
assert_contains "$artifact_bundle_file_type_inspect_failure_text" "Release artifact bundle file types: could not inspect"
assert_contains "$artifact_bundle_file_type_inspect_failure_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_bundle_file_type_inspect_failure_text" "v1.0 publication blocked"
assert_not_contains "$artifact_bundle_file_type_inspect_failure_text" "$cannot_inspect_archive_marker"
assert_not_contains "$artifact_bundle_file_type_inspect_failure_text" "$cannot_inspect_zip_sha"
assert_not_contains "$artifact_bundle_file_type_inspect_failure_text" "fast preflight is clear"

if run_gate_capture "$artifact_bundle_contents_missing_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$incomplete_bundle_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$incomplete_bundle_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$incomplete_bundle_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$incomplete_bundle_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_bundle_contents_missing_text="$(<"$artifact_bundle_contents_missing_output")"
  assert_not_contains "$artifact_bundle_contents_missing_text" "placeholder.txt"
  assert_not_contains "$artifact_bundle_contents_missing_text" "$incomplete_bundle_zip_sha"
  fail "gate unexpectedly passed with release artifact missing essential app bundle contents"
fi
artifact_bundle_contents_missing_text="$(<"$artifact_bundle_contents_missing_output")"
assert_contains "$artifact_bundle_contents_missing_text" "Release artifact filename: matches"
assert_contains "$artifact_bundle_contents_missing_text" "Release artifact zip: present"
assert_contains "$artifact_bundle_contents_missing_text" "Release artifact app wrapper: present"
assert_contains "$artifact_bundle_contents_missing_text" "Release artifact bundle contents: missing"
assert_contains "$artifact_bundle_contents_missing_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_bundle_contents_missing_text" "v1.0 publication blocked"
assert_not_contains "$artifact_bundle_contents_missing_text" "placeholder.txt"
assert_not_contains "$artifact_bundle_contents_missing_text" "$incomplete_bundle_zip_sha"
assert_not_contains "$artifact_bundle_contents_missing_text" "fast preflight is clear"

if run_gate_capture "$artifact_bundle_file_type_invalid_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$symlink_bundle_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$symlink_bundle_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$symlink_bundle_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$symlink_bundle_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_bundle_file_type_invalid_text="$(<"$artifact_bundle_file_type_invalid_output")"
  assert_not_contains "$artifact_bundle_file_type_invalid_text" "Info.target"
  assert_not_contains "$artifact_bundle_file_type_invalid_text" "LithePGApp.target"
  assert_not_contains "$artifact_bundle_file_type_invalid_text" "$symlink_bundle_zip_sha"
  fail "gate unexpectedly passed with symlink essential app bundle files"
fi
artifact_bundle_file_type_invalid_text="$(<"$artifact_bundle_file_type_invalid_output")"
assert_contains "$artifact_bundle_file_type_invalid_text" "Release artifact filename: matches"
assert_contains "$artifact_bundle_file_type_invalid_text" "Release artifact zip: present"
assert_contains "$artifact_bundle_file_type_invalid_text" "Release artifact app wrapper: present"
assert_contains "$artifact_bundle_file_type_invalid_text" "Release artifact bundle contents: present"
assert_contains "$artifact_bundle_file_type_invalid_text" "Release artifact bundle file types: invalid"
assert_contains "$artifact_bundle_file_type_invalid_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_bundle_file_type_invalid_text" "v1.0 publication blocked"
assert_not_contains "$artifact_bundle_file_type_invalid_text" "Info.target"
assert_not_contains "$artifact_bundle_file_type_invalid_text" "LithePGApp.target"
assert_not_contains "$artifact_bundle_file_type_invalid_text" "$symlink_bundle_zip_sha"
assert_not_contains "$artifact_bundle_file_type_invalid_text" "fast preflight is clear"

if run_gate_capture "$artifact_bundle_executable_permission_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$non_executable_bundle_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$non_executable_bundle_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$non_executable_bundle_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$non_executable_bundle_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_bundle_executable_permission_text="$(<"$artifact_bundle_executable_permission_output")"
  assert_not_contains "$artifact_bundle_executable_permission_text" "non-executable release app executable fixture"
  assert_not_contains "$artifact_bundle_executable_permission_text" "$non_executable_bundle_zip_sha"
  fail "gate unexpectedly passed with non-executable app bundle executable"
fi
artifact_bundle_executable_permission_text="$(<"$artifact_bundle_executable_permission_output")"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact filename: matches"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact zip: present"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact app wrapper: present"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact bundle contents: present"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact bundle file types: regular"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact bundle executable: not executable"
assert_contains "$artifact_bundle_executable_permission_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_bundle_executable_permission_text" "v1.0 publication blocked"
assert_not_contains "$artifact_bundle_executable_permission_text" "non-executable release app executable fixture"
assert_not_contains "$artifact_bundle_executable_permission_text" "$non_executable_bundle_zip_sha"
assert_not_contains "$artifact_bundle_executable_permission_text" "fast preflight is clear"

if run_gate_capture "$artifact_bundle_owner_execute_permission_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$owner_execute_missing_bundle_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$owner_execute_missing_bundle_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$owner_execute_missing_bundle_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$owner_execute_missing_bundle_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_bundle_owner_execute_permission_text="$(<"$artifact_bundle_owner_execute_permission_output")"
  assert_not_contains "$artifact_bundle_owner_execute_permission_text" "owner-execute-missing app executable fixture"
  assert_not_contains "$artifact_bundle_owner_execute_permission_text" "$owner_execute_missing_bundle_zip_sha"
  fail "gate unexpectedly passed with app bundle executable missing owner execute permission"
fi
artifact_bundle_owner_execute_permission_text="$(<"$artifact_bundle_owner_execute_permission_output")"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact filename: matches"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact zip: present"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact app wrapper: present"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact bundle contents: present"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact bundle file types: regular"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact bundle executable: not executable"
assert_contains "$artifact_bundle_owner_execute_permission_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_bundle_owner_execute_permission_text" "v1.0 publication blocked"
assert_not_contains "$artifact_bundle_owner_execute_permission_text" "owner-execute-missing app executable fixture"
assert_not_contains "$artifact_bundle_owner_execute_permission_text" "$owner_execute_missing_bundle_zip_sha"
assert_not_contains "$artifact_bundle_owner_execute_permission_text" "fast preflight is clear"

if run_gate_capture "$artifact_top_level_unexpected_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$unexpected_top_level_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$unexpected_top_level_homebrew_cask" \
  LITHEPG_SECURITY_DOC_PATH="$placeholder_free_security_doc" \
  LITHEPG_RELEASE_ZIP_PATH="$unexpected_top_level_zip" \
  LITHEPG_RELEASE_ZIP_SHA256="$unexpected_top_level_zip_sha" \
  LITHEPG_CODESIGN_IDENTITY="configured" \
  LITHEPG_NOTARY_PROFILE="configured" \
  LITHEPG_SECURITY_CONTACT="configured" \
  LITHEPG_HOMEBREW_TAP="configured" \
  LITHEPG_GITHUB_ACTIONS_READY="approved" \
  LITHEPG_RELEASE_COPY_APPROVED="approved" \
  LITHEPG_PUBLICATION_APPROVED="approved"; then
  artifact_top_level_unexpected_text="$(<"$artifact_top_level_unexpected_output")"
  assert_not_contains "$artifact_top_level_unexpected_text" "README.txt"
  assert_not_contains "$artifact_top_level_unexpected_text" "$unexpected_top_level_zip_sha"
  fail "gate unexpectedly passed with unexpected top-level release artifact entry"
fi
artifact_top_level_unexpected_text="$(<"$artifact_top_level_unexpected_output")"
assert_contains "$artifact_top_level_unexpected_text" "Release artifact filename: matches"
assert_contains "$artifact_top_level_unexpected_text" "Release artifact zip: present"
assert_contains "$artifact_top_level_unexpected_text" "Release artifact app wrapper: present"
assert_contains "$artifact_top_level_unexpected_text" "Release artifact bundle contents: present"
assert_contains "$artifact_top_level_unexpected_text" "Release artifact top-level entries: unexpected"
assert_contains "$artifact_top_level_unexpected_text" "Release artifact SHA-256: matches"
assert_contains "$artifact_top_level_unexpected_text" "v1.0 publication blocked"
assert_not_contains "$artifact_top_level_unexpected_text" "README.txt"
assert_not_contains "$artifact_top_level_unexpected_text" "$unexpected_top_level_zip_sha"
assert_not_contains "$artifact_top_level_unexpected_text" "fast preflight is clear"

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

if run_gate_capture "$mismatched_release_copy_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$mismatched_release_copy_sha" \
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
  fail "gate unexpectedly passed with mismatched release copy SHA-256"
fi
mismatched_release_copy_sha_text="$(<"$mismatched_release_copy_sha_output")"
assert_contains "$mismatched_release_copy_sha_text" "Release copy placeholders: none found"
assert_contains "$mismatched_release_copy_sha_text" "Release copy SHA-256: mismatch"
assert_contains "$mismatched_release_copy_sha_text" "Release artifact SHA-256: matches"
assert_not_contains "$mismatched_release_copy_sha_text" "$wrong_release_copy_sha"
assert_not_contains "$mismatched_release_copy_sha_text" "$release_zip_sha"
assert_contains "$mismatched_release_copy_sha_text" "v1.0 publication blocked"
assert_not_contains "$mismatched_release_copy_sha_text" "fast preflight is clear"

if run_gate_capture "$embedded_release_copy_sha_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$embedded_release_copy_sha" \
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
  fail "gate unexpectedly passed with embedded release copy SHA-256"
fi
embedded_release_copy_sha_text="$(<"$embedded_release_copy_sha_output")"
assert_contains "$embedded_release_copy_sha_text" "Release copy placeholders: none found"
assert_contains "$embedded_release_copy_sha_text" "Release copy SHA-256: mismatch"
assert_contains "$embedded_release_copy_sha_text" "Release artifact SHA-256: matches"
assert_not_contains "$embedded_release_copy_sha_text" "$release_zip_sha"
assert_not_contains "$embedded_release_copy_sha_text" "${release_zip_sha}0"
assert_contains "$embedded_release_copy_sha_text" "v1.0 publication blocked"
assert_not_contains "$embedded_release_copy_sha_text" "fast preflight is clear"

if run_gate_capture "$unchecked_release_copy_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$unchecked_release_copy" \
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
  fail "gate unexpectedly passed with unchecked release-copy checklist"
fi
unchecked_release_copy_text="$(<"$unchecked_release_copy_output")"
assert_contains "$unchecked_release_copy_text" "Release copy placeholders: none found"
assert_contains "$unchecked_release_copy_text" "Release copy checklist: unchecked items present"
assert_contains "$unchecked_release_copy_text" "Release copy SHA-256: matches"
assert_contains "$unchecked_release_copy_text" "v1.0 publication blocked"
assert_not_contains "$unchecked_release_copy_text" "Remove draft checklist"
assert_not_contains "$unchecked_release_copy_text" "$release_zip_sha"
assert_not_contains "$unchecked_release_copy_text" "fast preflight is clear"

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

if run_gate_capture "$homebrew_cask_token_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$token_mismatch_homebrew_cask" \
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
  homebrew_cask_token_mismatch_text="$(<"$homebrew_cask_token_mismatch_output")"
  assert_not_contains "$homebrew_cask_token_mismatch_text" "$wrong_homebrew_cask_token"
  fail "gate unexpectedly passed with mismatched Homebrew cask token"
fi
homebrew_cask_token_mismatch_text="$(<"$homebrew_cask_token_mismatch_output")"
assert_contains "$homebrew_cask_token_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_token_mismatch_text" "Homebrew cask token: mismatch"
assert_contains "$homebrew_cask_token_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_token_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_token_mismatch_text" "$wrong_homebrew_cask_token"
assert_not_contains "$homebrew_cask_token_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_token_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_token_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_token_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask token"
fi
missing_homebrew_cask_token_text="$(<"$missing_homebrew_cask_token_output")"
assert_contains "$missing_homebrew_cask_token_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_token_text" "Homebrew cask token: missing"
assert_contains "$missing_homebrew_cask_token_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_token_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_token_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_token_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_name_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_name_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask name"
fi
missing_homebrew_cask_name_text="$(<"$missing_homebrew_cask_name_output")"
assert_contains "$missing_homebrew_cask_name_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_name_text" "Homebrew cask token: matches"
assert_contains "$missing_homebrew_cask_name_text" "Homebrew cask name: missing"
assert_contains "$missing_homebrew_cask_name_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_name_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_name_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_name_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_name_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$name_mismatch_homebrew_cask" \
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
  homebrew_cask_name_mismatch_text="$(<"$homebrew_cask_name_mismatch_output")"
  assert_not_contains "$homebrew_cask_name_mismatch_text" "$wrong_homebrew_cask_name"
  fail "gate unexpectedly passed with mismatched Homebrew cask name"
fi
homebrew_cask_name_mismatch_text="$(<"$homebrew_cask_name_mismatch_output")"
assert_contains "$homebrew_cask_name_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_name_mismatch_text" "Homebrew cask token: matches"
assert_contains "$homebrew_cask_name_mismatch_text" "Homebrew cask name: mismatch"
assert_contains "$homebrew_cask_name_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_name_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_name_mismatch_text" "$wrong_homebrew_cask_name"
assert_not_contains "$homebrew_cask_name_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_name_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_desc_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$desc_mismatch_homebrew_cask" \
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
  homebrew_cask_desc_mismatch_text="$(<"$homebrew_cask_desc_mismatch_output")"
  assert_not_contains "$homebrew_cask_desc_mismatch_text" "$wrong_homebrew_cask_desc"
  fail "gate unexpectedly passed with mismatched Homebrew cask desc"
fi
homebrew_cask_desc_mismatch_text="$(<"$homebrew_cask_desc_mismatch_output")"
assert_contains "$homebrew_cask_desc_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_desc_mismatch_text" "Homebrew cask token: matches"
assert_contains "$homebrew_cask_desc_mismatch_text" "Homebrew cask name: matches"
assert_contains "$homebrew_cask_desc_mismatch_text" "Homebrew cask desc: mismatch"
assert_contains "$homebrew_cask_desc_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_desc_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_desc_mismatch_text" "$wrong_homebrew_cask_desc"
assert_not_contains "$homebrew_cask_desc_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_desc_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_desc_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_desc_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask desc"
fi
missing_homebrew_cask_desc_text="$(<"$missing_homebrew_cask_desc_output")"
assert_contains "$missing_homebrew_cask_desc_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_desc_text" "Homebrew cask token: matches"
assert_contains "$missing_homebrew_cask_desc_text" "Homebrew cask name: matches"
assert_contains "$missing_homebrew_cask_desc_text" "Homebrew cask desc: missing"
assert_contains "$missing_homebrew_cask_desc_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_desc_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_desc_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_desc_text" "v1.0 publication blocked"

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
assert_contains "$homebrew_cask_verified_mismatch_text" "Homebrew cask homepage: matches"
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
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask homepage: matches"
assert_contains "$missing_homebrew_cask_verified_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_verified_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_verified_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_homepage_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$homepage_mismatch_homebrew_cask" \
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
  homebrew_cask_homepage_mismatch_text="$(<"$homebrew_cask_homepage_mismatch_output")"
  assert_not_contains "$homebrew_cask_homepage_mismatch_text" "$wrong_homebrew_cask_homepage"
  fail "gate unexpectedly passed with mismatched Homebrew cask homepage"
fi
homebrew_cask_homepage_mismatch_text="$(<"$homebrew_cask_homepage_mismatch_output")"
assert_contains "$homebrew_cask_homepage_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_homepage_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_homepage_mismatch_text" "Homebrew cask URL: matches"
assert_contains "$homebrew_cask_homepage_mismatch_text" "Homebrew cask verified URL: matches"
assert_contains "$homebrew_cask_homepage_mismatch_text" "Homebrew cask homepage: mismatch"
assert_contains "$homebrew_cask_homepage_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_homepage_mismatch_text" "$wrong_homebrew_cask_homepage"
assert_not_contains "$homebrew_cask_homepage_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_homepage_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_homepage_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_homepage_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask homepage"
fi
missing_homebrew_cask_homepage_text="$(<"$missing_homebrew_cask_homepage_output")"
assert_contains "$missing_homebrew_cask_homepage_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_homepage_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_homepage_text" "Homebrew cask URL: matches"
assert_contains "$missing_homebrew_cask_homepage_text" "Homebrew cask verified URL: matches"
assert_contains "$missing_homebrew_cask_homepage_text" "Homebrew cask homepage: missing"
assert_contains "$missing_homebrew_cask_homepage_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_homepage_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_homepage_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_bundle_id_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$bundle_id_mismatch_homebrew_cask" \
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
  homebrew_cask_bundle_id_mismatch_text="$(<"$homebrew_cask_bundle_id_mismatch_output")"
  assert_not_contains "$homebrew_cask_bundle_id_mismatch_text" "$wrong_homebrew_cask_bundle_id"
  assert_not_contains "$homebrew_cask_bundle_id_mismatch_text" "$release_zip_sha"
  fail "gate unexpectedly passed with mismatched Homebrew cask uninstall quit bundle ID"
fi
homebrew_cask_bundle_id_mismatch_text="$(<"$homebrew_cask_bundle_id_mismatch_output")"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask token: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask name: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask desc: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask URL: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask verified URL: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask homepage: matches"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask uninstall quit bundle ID: mismatch"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_bundle_id_mismatch_text" "$wrong_homebrew_cask_bundle_id"
assert_not_contains "$homebrew_cask_bundle_id_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_bundle_id_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_bundle_id_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_bundle_id_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask uninstall quit bundle ID"
fi
missing_homebrew_cask_bundle_id_text="$(<"$missing_homebrew_cask_bundle_id_output")"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask token: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask name: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask desc: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask URL: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask verified URL: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask homepage: matches"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask uninstall quit bundle ID: missing"
assert_contains "$missing_homebrew_cask_bundle_id_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_bundle_id_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_bundle_id_text" "v1.0 publication blocked"

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

if run_gate_capture "$homebrew_cask_app_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$app_mismatch_homebrew_cask" \
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
  homebrew_cask_app_mismatch_text="$(<"$homebrew_cask_app_mismatch_output")"
  assert_not_contains "$homebrew_cask_app_mismatch_text" "$wrong_homebrew_cask_app"
  fail "gate unexpectedly passed with mismatched Homebrew cask app stanza"
fi
homebrew_cask_app_mismatch_text="$(<"$homebrew_cask_app_mismatch_output")"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask URL: matches"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask verified URL: matches"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask homepage: matches"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask app stanza: mismatch"
assert_contains "$homebrew_cask_app_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_app_mismatch_text" "$wrong_homebrew_cask_app"
assert_not_contains "$homebrew_cask_app_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_app_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_app_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_app_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask app stanza"
fi
missing_homebrew_cask_app_text="$(<"$missing_homebrew_cask_app_output")"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask URL: matches"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask verified URL: matches"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask homepage: matches"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask app stanza: missing"
assert_contains "$missing_homebrew_cask_app_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_app_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_app_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_macos_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$macos_mismatch_homebrew_cask" \
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
  fail "gate unexpectedly passed with mismatched Homebrew cask macOS requirement"
fi
homebrew_cask_macos_mismatch_text="$(<"$homebrew_cask_macos_mismatch_output")"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask URL: matches"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask verified URL: matches"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask homepage: matches"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask app stanza: matches"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask macOS requirement: mismatch"
assert_contains "$homebrew_cask_macos_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_macos_mismatch_text" "ventura"
assert_not_contains "$homebrew_cask_macos_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_macos_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_macos_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_macos_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask macOS requirement"
fi
missing_homebrew_cask_macos_text="$(<"$missing_homebrew_cask_macos_output")"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask URL: matches"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask verified URL: matches"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask homepage: matches"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask app stanza: matches"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask macOS requirement: missing"
assert_contains "$missing_homebrew_cask_macos_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_macos_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_macos_text" "v1.0 publication blocked"

if run_gate_capture "$homebrew_cask_zap_mismatch_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$zap_mismatch_homebrew_cask" \
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
  fail "gate unexpectedly passed with mismatched Homebrew cask zap stanza"
fi
homebrew_cask_zap_mismatch_text="$(<"$homebrew_cask_zap_mismatch_output")"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask placeholders: none found"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask version: matches"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask URL: matches"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask verified URL: matches"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask homepage: matches"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask app stanza: matches"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask macOS requirement: matches"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask zap stanza: mismatch"
assert_contains "$homebrew_cask_zap_mismatch_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$homebrew_cask_zap_mismatch_text" "NotLithePG"
assert_not_contains "$homebrew_cask_zap_mismatch_text" "$release_zip_sha"
assert_contains "$homebrew_cask_zap_mismatch_text" "v1.0 publication blocked"

if run_gate_capture "$missing_homebrew_cask_zap_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$missing_zap_homebrew_cask" \
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
  fail "gate unexpectedly passed with missing Homebrew cask zap stanza"
fi
missing_homebrew_cask_zap_text="$(<"$missing_homebrew_cask_zap_output")"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask placeholders: none found"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask version: matches"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask URL: matches"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask verified URL: matches"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask homepage: matches"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask app stanza: matches"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask macOS requirement: matches"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask zap stanza: missing"
assert_contains "$missing_homebrew_cask_zap_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$missing_homebrew_cask_zap_text" "$release_zip_sha"
assert_contains "$missing_homebrew_cask_zap_text" "v1.0 publication blocked"

if run_gate_capture "$commented_homebrew_cask_zap_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$commented_zap_homebrew_cask" \
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
  fail "gate unexpectedly passed with commented-out Homebrew cask zap paths"
fi
commented_homebrew_cask_zap_text="$(<"$commented_homebrew_cask_zap_output")"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask placeholders: none found"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask version: matches"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask URL: matches"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask verified URL: matches"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask homepage: matches"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask app stanza: matches"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask macOS requirement: matches"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask zap stanza: mismatch"
assert_contains "$commented_homebrew_cask_zap_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$commented_homebrew_cask_zap_text" "$release_zip_sha"
assert_contains "$commented_homebrew_cask_zap_text" "v1.0 publication blocked"

if run_gate_capture "$inline_commented_homebrew_cask_zap_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$inline_commented_zap_homebrew_cask" \
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
  fail "gate unexpectedly passed with inline-commented Homebrew cask zap paths"
fi
inline_commented_homebrew_cask_zap_text="$(<"$inline_commented_homebrew_cask_zap_output")"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask placeholders: none found"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask version: matches"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask URL: matches"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask verified URL: matches"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask homepage: matches"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask app stanza: matches"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask macOS requirement: matches"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask zap stanza: mismatch"
assert_contains "$inline_commented_homebrew_cask_zap_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$inline_commented_homebrew_cask_zap_text" "$release_zip_sha"
assert_contains "$inline_commented_homebrew_cask_zap_text" "v1.0 publication blocked"

if run_gate_capture "$unterminated_homebrew_cask_zap_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$unterminated_zap_homebrew_cask" \
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
  fail "gate unexpectedly passed with unterminated Homebrew cask zap array"
fi
unterminated_homebrew_cask_zap_text="$(<"$unterminated_homebrew_cask_zap_output")"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask placeholders: none found"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask version: matches"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask URL: matches"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask verified URL: matches"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask homepage: matches"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask app stanza: matches"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask macOS requirement: matches"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask zap stanza: missing"
assert_contains "$unterminated_homebrew_cask_zap_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$unterminated_homebrew_cask_zap_text" "$release_zip_sha"
assert_contains "$unterminated_homebrew_cask_zap_text" "v1.0 publication blocked"

if run_gate_capture "$syntax_error_homebrew_cask_output" env -i \
  PATH="$fake_path" \
  FAKE_GIT_LS_REMOTE_MARKER="$fake_git_marker" \
  LITHEPG_RELEASE_COPY_PATH="$placeholder_free_release_copy" \
  LITHEPG_HOMEBREW_CASK_PATH="$syntax_error_homebrew_cask" \
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
  fail "gate unexpectedly passed with invalid Homebrew cask Ruby syntax"
fi
syntax_error_homebrew_cask_text="$(<"$syntax_error_homebrew_cask_output")"
assert_contains "$syntax_error_homebrew_cask_text" "Homebrew cask placeholders: none found"
assert_contains "$syntax_error_homebrew_cask_text" "Homebrew cask zap stanza: matches"
assert_contains "$syntax_error_homebrew_cask_text" "Homebrew cask Ruby syntax: invalid"
assert_contains "$syntax_error_homebrew_cask_text" "Homebrew cask SHA-256: matches"
assert_not_contains "$syntax_error_homebrew_cask_text" "$release_zip_sha"
assert_contains "$syntax_error_homebrew_cask_text" "v1.0 publication blocked"
assert_not_contains "$syntax_error_homebrew_cask_text" "fast preflight is clear"

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
assert_not_contains "$placeholder_text" "Release copy checklist:"
assert_not_contains "$placeholder_text" "Release copy SHA-256:"
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
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask token:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask name:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask version: mismatch"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask version: missing"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask URL: mismatch"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask verified URL:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask homepage:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask uninstall quit bundle ID:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask app stanza:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask macOS requirement:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask zap stanza:"
assert_not_contains "$homebrew_cask_placeholder_text" "Homebrew cask Ruby syntax:"
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
assert_contains "$no_remote_lookup_text" "Release copy checklist: none unchecked"
assert_contains "$no_remote_lookup_text" "Release copy SHA-256: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask placeholders: none found"
assert_contains "$no_remote_lookup_text" "Homebrew cask token: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask name: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask desc: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask version: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask URL: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask verified URL: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask homepage: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask uninstall quit bundle ID: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask app stanza: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask macOS requirement: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask zap stanza: matches"
assert_contains "$no_remote_lookup_text" "Homebrew cask Ruby syntax: valid"
assert_contains "$no_remote_lookup_text" "Homebrew cask SHA-256: matches"
assert_contains "$no_remote_lookup_text" "Release artifact filename: matches"
assert_contains "$no_remote_lookup_text" "Release artifact zip: present"
assert_contains "$no_remote_lookup_text" "Release artifact app wrapper: present"
assert_contains "$no_remote_lookup_text" "Release artifact bundle contents: present"
assert_contains "$no_remote_lookup_text" "Release artifact bundle file types: regular"
assert_contains "$no_remote_lookup_text" "Release artifact bundle executable: executable"
assert_contains "$no_remote_lookup_text" "Release artifact top-level entries: clean"
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
