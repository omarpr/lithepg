#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"
HELPER="$ROOT_DIR/script/dogfood_postgres.sh"

fail() {
  /usr/bin/printf 'test_dogfood_postgres failed: %s\n' "$1" >&2
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

assert_not_contains_if_set() {
  local haystack="$1"
  local needle="$2"
  [[ -z "$needle" ]] || assert_not_contains "$haystack" "$needle"
}

assert_foreign_ambient_not_used() {
  local haystack="$1"
  local needle="$2"
  local allowed_value="$3"
  [[ -z "$needle" || "$needle" == "$allowed_value" ]] || assert_not_contains "$haystack" "$needle"
}

run_helper_capture() {
  local output_file="$1"
  local fixture_root="$2"
  local fake_bin="$3"
  local docker_log="$4"
  local ready_counter="$5"
  local marker_dir="$6"

  set +e
  (
    builtin cd "$fixture_root"
    export LITHEPG_DOGFOOD_CONTAINER="$ambient_fixture_container"
    export LITHEPG_DOGFOOD_IMAGE="$ambient_fixture_image"
    export LITHEPG_DOGFOOD_PORT="$ambient_fixture_port"
    export LITHEPG_DOGFOOD_PASSWORD="$ambient_fixture_password"
    export LITHEPG_DOGFOOD_DATABASE="$ambient_fixture_database"
    builtin() {
      /usr/bin/printf '%s builtin invoked\n' "${BUILTIN_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'builtin\n' >"${SHADOW_MARKER_DIR:?}/builtin"
      exit 97
    }
    cd() {
      /usr/bin/printf '%s cd invoked\n' "${CD_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'cd\n' >"${SHADOW_MARKER_DIR:?}/cd"
      exit 97
    }
    pwd() {
      /usr/bin/printf '%s pwd invoked\n' "${PWD_SHADOW_SENTINEL:?}" >&2
      /usr/bin/printf 'pwd\n' >"${SHADOW_MARKER_DIR:?}/pwd"
      exit 97
    }
    export -f builtin
    export -f cd
    export -f pwd
    PATH="$fake_bin:$PATH" \
      FAKE_DOCKER_LOG="$docker_log" \
      FAKE_READY_COUNTER="$ready_counter" \
      SHADOW_MARKER_DIR="$marker_dir" \
      BUILTIN_SHADOW_SENTINEL="$builtin_sentinel" \
      CD_SHADOW_SENTINEL="$cd_sentinel" \
      PWD_SHADOW_SENTINEL="$pwd_sentinel" \
      LITHEPG_DOGFOOD_CONTAINER="$fixture_container" \
      LITHEPG_DOGFOOD_IMAGE="$fixture_image" \
      LITHEPG_DOGFOOD_PORT="$fixture_port" \
      LITHEPG_DOGFOOD_PASSWORD="$fixture_password" \
      LITHEPG_DOGFOOD_DATABASE="$fixture_database" \
      /bin/bash "$fixture_root/script/dogfood_postgres.sh"
  ) >"$output_file" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -f "$HELPER" ]] || fail "helper script missing: $HELPER"

incoming_ambient_container="${LITHEPG_DOGFOOD_CONTAINER:-}"
incoming_ambient_port="${LITHEPG_DOGFOOD_PORT:-}"
incoming_ambient_password="${LITHEPG_DOGFOOD_PASSWORD:-}"

fixture_container="lithepg-smoke"
fixture_image="postgres:16"
fixture_port="55432"
fixture_password="fixture-password-SHOULD-NOT-LEAK"
fixture_database="postgres"

ambient_fixture_container="ambient-container-SHOULD-NOT-BE-USED"
ambient_fixture_image="ambient-image-SHOULD-NOT-BE-USED"
ambient_fixture_port="59999"
ambient_fixture_password="ambient-password-SHOULD-NOT-LEAK"
ambient_fixture_database="ambientdb_should_not_be_used"

output_file="$(/usr/bin/mktemp)"
fixture_root="$(/usr/bin/mktemp -d)"
trap '/bin/rm -f "$output_file"; /bin/rm -rf "$fixture_root"' EXIT

sentinel="DOGFOOD_POSTGRES_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN"
builtin_sentinel="DOGFOOD_POSTGRES_BUILTIN_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
cd_sentinel="DOGFOOD_POSTGRES_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
pwd_sentinel="DOGFOOD_POSTGRES_PWD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN"
fake_bin="$fixture_root/fake-bin"
docker_log="$fixture_root/fake-docker.log"
ready_counter="$fixture_root/pg-isready-count"
marker_dir="$fixture_root/path-shadow-markers"
/bin/mkdir -p "$fixture_root/script" "$fake_bin" "$marker_dir"
/bin/cp "$HELPER" "$fixture_root/script/dogfood_postgres.sh"
/bin/chmod +x "$fixture_root/script/dogfood_postgres.sh"
/bin/cat >"$fixture_root/script/dogfood_seed.sql" <<'SQL'
SELECT 1;
SQL

for tool in dirname grep realpath sleep; do
  /bin/cat >"$fake_bin/$tool" <<SHIM
#!/bin/bash
set -euo pipefail
/usr/bin/printf '%s %s invoked\\n' '$sentinel' '$tool' >&2
/usr/bin/printf '%s\\n' '$tool' >"\${SHADOW_MARKER_DIR:?}/$tool"
exit 97
SHIM
  /bin/chmod +x "$fake_bin/$tool"
done

/bin/cat >"$fake_bin/docker" <<'DOCKER'
#!/bin/bash
set -euo pipefail
case "$1" in
  ps)
    /usr/bin/printf 'docker ps -a --format {{.Names}}\n' >>"${FAKE_DOCKER_LOG:?}"
    /usr/bin/printf 'lithepg-smoke\n'
    ;;
  inspect)
    /usr/bin/printf 'docker inspect -f {{.State.Running}} lithepg-smoke\n' >>"${FAKE_DOCKER_LOG:?}"
    /usr/bin/printf 'true\n'
    ;;
  exec)
    if [[ "$*" == *" pg_isready "* ]]; then
      /usr/bin/printf 'docker exec lithepg-smoke pg_isready -U postgres -d postgres\n' >>"${FAKE_DOCKER_LOG:?}"
      count=0
      if [[ -f "${FAKE_READY_COUNTER:?}" ]]; then
        count="$(/bin/cat "$FAKE_READY_COUNTER")"
      fi
      count=$((count + 1))
      /usr/bin/printf '%s\n' "$count" >"$FAKE_READY_COUNTER"
      if [[ "$count" -eq 1 ]]; then
        exit 1
      fi
      exit 0
    fi
    if [[ "$*" == *" psql "* ]]; then
      /usr/bin/printf 'docker exec -i lithepg-smoke psql -v ON_ERROR_STOP=1 -U postgres -d postgres\n' >>"${FAKE_DOCKER_LOG:?}"
      /bin/cat >/dev/null
      /usr/bin/printf 'seeded dogfood fixture\n' >>"$FAKE_DOCKER_LOG"
      exit 0
    fi
    /usr/bin/printf 'unexpected fake docker exec invocation\n' >>"${FAKE_DOCKER_LOG:?}"
    /usr/bin/printf 'unexpected fake docker exec invocation\n' >&2
    exit 98
    ;;
  run|start)
    /usr/bin/printf 'unexpected fake docker lifecycle invocation\n' >>"${FAKE_DOCKER_LOG:?}"
    /usr/bin/printf 'unexpected fake docker lifecycle invocation\n' >&2
    exit 99
    ;;
  *)
    /usr/bin/printf 'unexpected fake docker invocation\n' >>"${FAKE_DOCKER_LOG:?}"
    /usr/bin/printf 'unexpected fake docker invocation\n' >&2
    exit 98
    ;;
esac
DOCKER
/bin/chmod +x "$fake_bin/docker"

if ! run_helper_capture "$output_file" "$fixture_root" "$fake_bin" "$docker_log" "$ready_counter" "$marker_dir"; then
  helper_output="$(<"$output_file")"
  assert_not_contains "$helper_output" "$fixture_password"
  assert_not_contains "$helper_output" "$ambient_fixture_password"
  assert_not_contains_if_set "$helper_output" "$incoming_ambient_password"
  if [[ -s "$docker_log" ]]; then
    docker_output="$(<"$docker_log")"
    assert_not_contains "$docker_output" "$fixture_password"
    assert_not_contains "$docker_output" "$ambient_fixture_password"
    assert_not_contains_if_set "$docker_output" "$incoming_ambient_password"
  fi
  /usr/bin/printf '%s\n' "$helper_output" >&2
  fail "dogfood_postgres.sh was affected by PATH-shadowed core utilities"
fi

helper_output="$(<"$output_file")"
assert_not_contains "$helper_output" "$sentinel"
assert_not_contains "$helper_output" "$builtin_sentinel"
assert_not_contains "$helper_output" "$cd_sentinel"
assert_not_contains "$helper_output" "$pwd_sentinel"
assert_not_contains "$helper_output" " invoked"
assert_contains "$helper_output" "Dogfood database ready."
assert_contains "$helper_output" "POSTGRES_TEST_URL="
assert_contains "$helper_output" "postgres://postgres:***@localhost:$fixture_port/$fixture_database?sslmode=disable"
assert_not_contains "$helper_output" "postgres://postgres:$fixture_password@"
assert_not_contains "$helper_output" "$fixture_password"
assert_not_contains "$helper_output" "$ambient_fixture_container"
assert_not_contains "$helper_output" "$ambient_fixture_port"
assert_not_contains "$helper_output" "$ambient_fixture_password"
assert_foreign_ambient_not_used "$helper_output" "$incoming_ambient_container" "$fixture_container"
assert_foreign_ambient_not_used "$helper_output" "$incoming_ambient_port" "$fixture_port"
assert_foreign_ambient_not_used "$helper_output" "$incoming_ambient_password" "$fixture_password"

[[ -s "$docker_log" ]] || fail "fake docker was not used"
docker_output="$(<"$docker_log")"
assert_contains "$docker_output" "docker ps -a --format {{.Names}}"
assert_contains "$docker_output" "docker inspect -f {{.State.Running}} lithepg-smoke"
assert_contains "$docker_output" "docker exec lithepg-smoke pg_isready -U postgres -d postgres"
assert_contains "$docker_output" "docker exec -i lithepg-smoke psql -v ON_ERROR_STOP=1 -U postgres -d postgres"
assert_contains "$docker_output" "seeded dogfood fixture"
assert_not_contains "$docker_output" "$fixture_password"
assert_not_contains "$docker_output" "$ambient_fixture_container"
assert_not_contains "$docker_output" "$ambient_fixture_port"
assert_not_contains "$docker_output" "$ambient_fixture_password"
assert_foreign_ambient_not_used "$docker_output" "$incoming_ambient_container" "$fixture_container"
assert_foreign_ambient_not_used "$docker_output" "$incoming_ambient_port" "$fixture_port"
assert_foreign_ambient_not_used "$docker_output" "$incoming_ambient_password" "$fixture_password"

ready_attempts="$(/bin/cat "$ready_counter")"
[[ "$ready_attempts" == "2" ]] || fail "expected fake pg_isready to be attempted twice, got $ready_attempts"

for tool in dirname grep realpath sleep; do
  [[ ! -e "$marker_dir/$tool" ]] || fail "PATH-shadowed $tool was invoked"
done
[[ ! -e "$marker_dir/builtin" ]] || fail "function-shadowed builtin was invoked"
[[ ! -e "$marker_dir/cd" ]] || fail "function-shadowed cd was invoked"
[[ ! -e "$marker_dir/pwd" ]] || fail "function-shadowed pwd was invoked"

/usr/bin/printf 'test_dogfood_postgres passed\n'
