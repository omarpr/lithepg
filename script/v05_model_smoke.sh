#!/bin/bash -p

BASH_BIN=/bin/bash
PERL_BIN=/usr/bin/perl

startup_env_sanitize_needed=0
if [[ "${BASH_ENV+x}" == x || "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
  startup_env_sanitize_needed=1
elif /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB "$PERL_BIN" -e '
  for my $key (keys %ENV) {
    exit 0 if $key =~ /\ABASH_FUNC_/;
  }
  exit 1;
'; then
  startup_env_sanitize_needed=1
fi

if [[ "$startup_env_sanitize_needed" == "1" ]]; then
  if [[ "${LITHEPG_V05_MODEL_SMOKE_STARTUP_ENV_SANITIZED:-}" == "1" ]]; then
    /usr/bin/printf 'unsanitized startup environment remains after v05_model_smoke sanitizer\n' >&2
    exit 2
  fi
  /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB "$PERL_BIN" -e '
    use strict;
    use warnings;
    my $bash = shift @ARGV;
    for my $key (keys %ENV) {
      delete $ENV{$key} if $key =~ /\ABASH_FUNC_/;
    }
    delete $ENV{BASH_ENV};
    delete $ENV{PERL5OPT};
    delete $ENV{PERL5LIB};
    delete $ENV{PERLLIB};
    $ENV{LITHEPG_V05_MODEL_SMOKE_STARTUP_ENV_SANITIZED} = "1";
    exec { $bash } $bash, "-p", @ARGV;
    die "exec $bash: $!\n";
  ' "$BASH_BIN" "${BASH_SOURCE[0]}" "$@"
  exit $?
fi

if [[ "${PERL5OPT+x}" == x || "${PERL5LIB+x}" == x || "${PERLLIB+x}" == x ]]; then
  /usr/bin/printf 'unsanitized Perl startup environment remains\n' >&2
  exit 2
elif ! /usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB "$PERL_BIN" -e '
  for my $key (keys %ENV) {
    die "unsanitized bash function environment key remains: $key\n" if $key =~ /\ABASH_FUNC_/;
  }
  die "unsanitized BASH_ENV remains\n" if exists $ENV{BASH_ENV};
  exit 0;
'; then
  exit 2
fi

set -euo pipefail

ROOT_DIR="$(/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/..")"

run_from_root() {
  "$PERL_BIN" -e '
    use strict;
    use warnings;
    my $root = shift @ARGV;
    chdir $root or die "chdir $root: $!\n";
    exec @ARGV;
    die "exec $ARGV[0]: $!\n";
  ' "$ROOT_DIR" "$@"
}

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

OUT_DIR="${LITHEPG_MODEL_SMOKE_OUT_DIR:-$ROOT_DIR/.build/v05-model-smoke/$(/bin/date +%Y%m%d-%H%M%S)}"
/bin/mkdir -p "$OUT_DIR"

run_from_root swift test --filter LocalModelAIQueryService | /usr/bin/tee "$OUT_DIR/local-model-tests.log"
run_from_root swift build -c release --product LithePGApp | /usr/bin/tee "$OUT_DIR/release-build.log"

APP_BIN="$ROOT_DIR/.build/release/LithePGApp"
if [[ ! -x "$APP_BIN" ]]; then
  echo "missing app binary: $APP_BIN" >&2
  exit 1
fi

COREML_LINKED=0
if /usr/bin/otool -L "$APP_BIN" | /usr/bin/grep -q "CoreML.framework"; then
  COREML_LINKED=1
fi

/usr/bin/python3 - <<PY > "$OUT_DIR/summary.json"
import json, os
path = "$APP_BIN"
size = os.path.getsize(path)
print(json.dumps({
  "product": "LithePGApp",
  "path": path,
  "bytes": size,
  "mib": size / 1024 / 1024,
  "coreMLFrameworkLinked": bool(int("$COREML_LINKED")),
  "modelArtifactBundled": False,
  "requiresPackageDependency": False,
  "gatedModelSmokeEnabled": os.environ.get("LITHEPG_ENABLE_LOCAL_MODEL") == "1" and bool(os.environ.get("LITHEPG_LOCAL_MODEL_PATH")),
  "modelPathProvided": bool(os.environ.get("LITHEPG_LOCAL_MODEL_PATH")),
}, indent=2, sort_keys=True))
PY

/bin/cat "$OUT_DIR/summary.json"
echo
echo "Model smoke measurements written to $OUT_DIR"
