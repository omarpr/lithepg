#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/script/prepare_release_changelog.sh"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lithepg-test-changelog.XXXXXX")"

cleanup() {
  [[ -n "${FIXTURE_DIR:-}" && -d "$FIXTURE_DIR" ]] && rm -rf -- "$FIXTURE_DIR"
}
trap cleanup EXIT

fail() {
  printf 'test_prepare_release_changelog failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

[[ -x "$HELPER" ]] || fail "prepare release changelog helper is missing or not executable"

REPOSITORY="$FIXTURE_DIR/repository"
mkdir -p "$REPOSITORY"
git -C "$REPOSITORY" init -q -b main
git -C "$REPOSITORY" config user.name "Synthetic Release Test"
git -C "$REPOSITORY" config user.email "release-test@example.invalid"
printf '# Changelog\n\n## [Unreleased]\n\n[v1.0.3]: https://example.invalid/v1.0.3\n' >"$REPOSITORY/CHANGELOG.md"
printf 'baseline\n' >"$REPOSITORY/fixture.txt"
git -C "$REPOSITORY" add -- CHANGELOG.md fixture.txt
git -C "$REPOSITORY" commit -q -m "chore: baseline"
git -C "$REPOSITORY" tag -a v1.0.7-preview.1 -m "preview"
printf 'first change\n' >>"$REPOSITORY/fixture.txt"
git -C "$REPOSITORY" add -- fixture.txt
git -C "$REPOSITORY" commit -q -m "feat: add organization signing"
printf 'second change\n' >>"$REPOSITORY/fixture.txt"
git -C "$REPOSITORY" add -- fixture.txt
git -C "$REPOSITORY" commit -q -m "fix: parse the Team ID from standard input"

SOURCE_BEFORE="$(<"$REPOSITORY/CHANGELOG.md")"
OUTPUT_PATH="$FIXTURE_DIR/CHANGELOG-1.0.8.md"
helper_output="$(LITHEPG_RELEASE_DATE=2026-08-05 \
  LITHEPG_GITHUB_REPOSITORY=example/lithepg \
  "$HELPER" 1.0.8 "$OUTPUT_PATH" "$REPOSITORY")"
assert_contains "$helper_output" "Prepared CHANGELOG.md for v1.0.8 from v1.0.7-preview.1..HEAD."
[[ "$SOURCE_BEFORE" == "$(<"$REPOSITORY/CHANGELOG.md")" ]] || fail "source changelog was modified"

prepared="$(<"$OUTPUT_PATH")"
assert_contains "$prepared" "## [v1.0.8] — 2026-08-05"
assert_contains "$prepared" '### Changes since `v1.0.7-preview.1`'
assert_contains "$prepared" '- feat: add organization signing (`'
assert_contains "$prepared" '- fix: parse the Team ID from standard input (`'
assert_contains "$prepared" "[v1.0.8]: https://github.com/example/lithepg/compare/v1.0.7-preview.1...v1.0.8"
[[ "$(printf '%s\n' "$prepared" | grep -c '^## \[v1\.0\.8\]')" -eq 1 ]] || fail "release section count was not one"

printf 'test_prepare_release_changelog passed\n'
