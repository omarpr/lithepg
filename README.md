# LithePG

[![CI](https://github.com/omarpr/lithepg/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/omarpr/lithepg/actions/workflows/ci.yml?query=branch%3Amain)
&nbsp;**Latest tagged release:** [`v0.5`](https://github.com/omarpr/lithepg/tree/v0.5)

LithePG is a lean, Mac-native PostgreSQL client with local-first AI. Pure Swift on `postgres-nio` (no `libpq`), a ~22 MiB binary and nothing ever leaves your machine.

![LithePG app window showing a seeded dogfood schema, query editor, and results grid](docs/assets/lithepg-app-snapshot.png)

*Screenshot shows the seeded demo database, not real data.*

## What you get

- A native macOS app for connecting to Postgres, writing SQL and viewing results.
- Saved connections with passwords in the macOS Keychain, never on disk.
- Schema sidebar, query tabs, history, result copy and export as CSV, TSV, JSON, Markdown or SQL inserts.
- One-click table preview: the sidebar's select action inserts and runs `SELECT * ... LIMIT 100`.
- Clickable cells: select and `⌘C`, right-click to copy cell or row, double-click to view and edit a value locally.
- EXPLAIN and EXPLAIN ANALYZE (`⌘E` / `⇧⌘E`) with an indented plan tree that flags the costliest node.
- A schema graph (`⇧⌘G`): tables as nodes, foreign keys as edges, columns and types in an inspector.
- Ask in English drafting that inserts SQL for review and never auto-runs it.
- Pasted connection strings just work, including Neon URLs, quoted strings and `psql` command copies.
- Light, dark and system appearance.
- A CLI smoke utility (`lithepg`) for plain TCP, TLS and SSH-tunneled checks.

## Status

v0.5 is the current tag. The v1.0 code is complete and verified: 224 tests across 34 suites, CI green on push, connectivity proven live against local Docker Postgres and real Neon endpoints (direct and pooled), full git history scanned for secrets, binary at ~22 MiB against a 50 MiB cap. What remains for a public v1.0 is distribution, not code: Apple signing and notarization credentials, a final security contact, a Homebrew tap and release approval. Receipts live in [`docs/dogfood-log.md`](docs/dogfood-log.md) and [`CHANGELOG.md`](CHANGELOG.md).

## Install

### GitHub Release zip

When a signed release exists: download `LithePG.app.zip` from [Releases](https://github.com/omarpr/lithepg/releases), verify the checksum if provided, unzip and move `LithePG.app` to `/Applications`. Until then, build from source.

### Homebrew cask (planned)

`brew install --cask lithepg` will work once the v1.0 artifact and tap are approved.

### Build from source

Requirements: macOS 14+ and an Xcode/Swift 6.2 toolchain.

```sh
git clone https://github.com/omarpr/lithepg.git
cd lithepg
swift build && swift test
./script/build_and_run.sh --package
open dist/LithePG.app
```

## Try it with the seeded demo

```sh
./script/dogfood_postgres.sh              # Docker Postgres with sample data
POSTGRES_TEST_URL="postgres://postgres:***@localhost:55432/postgres?sslmode=disable" ./script/run_dogfood_app.sh
```

The demo database uses the synthetic local password `postgres`. Normal app launches show the connect sheet; the startup env vars exist for demo and smoke runs only.

## Local-first AI in plain language

Ask in English (`⇧⌘K`) drafts SQL from your request plus local schema metadata. The draft lands in the editor for you to inspect; it never runs automatically. There is no telemetry, no cloud call path and no model download. The default engine is deterministic and local. An optional CoreML adapter activates only when you set `LITHEPG_ENABLE_LOCAL_MODEL=1` and point `LITHEPG_LOCAL_MODEL_PATH` at your own model artifact.

## CLI smoke utility

```sh
.build/debug/lithepg --url postgres://user:***@host:5432/db
.build/debug/lithepg --url postgres://user:***@host:5432/db --tls --tls-ca /path/to/ca.pem
.build/debug/lithepg --url postgres://user:@127.0.0.1:5432/db --ssh user@bastion.example.com:22
```

Plain TCP, TLS verify-full with an optional pinned CA, or an SSH tunnel through `/usr/bin/ssh -L`. `--tls` with `--ssh` is rejected (tunneled TLS needs later SNI work). Set `LITHEPG_DEBUG_ERROR=1` to print the redacted underlying error on failures.

## App shortcuts

- `⌘↩` run the active query tab
- `⌘.` cancel the running query
- `⌘T` / `⌘W` open / close a query tab
- `⇧⌘[` / `⇧⌘]` previous / next query tab
- `⇧⌘K` Ask in English
- `⌘E` / `⇧⌘E` Explain / Explain Analyze
- `⇧⌘G` schema graph

## Developer commands

```sh
swift build
swift test                                # add LITHEPG_KEYCHAIN_TESTS=1 for the real-keychain suite
./script/build_and_run.sh --package
./script/package_verify.sh dist/LithePG.app
```

Live Postgres, TLS, SSH and Neon integration tests are gated on env vars (`POSTGRES_TEST_URL` and friends) and auto-skip without them. Release-impacting changes should also run `./script/dogfood_check.sh` when Docker is available.

Running from Xcode: open the package folder (`xed .`), pick the `LithePGApp` scheme and hit run.

Tired of Keychain prompts on every rebuild? Run `./script/dev_signing_setup.sh` once. It creates a persistent local signing identity so one "Always Allow" per saved password sticks across rebuilds. See [`CORE_TECHNOLOGIES.md`](CORE_TECHNOLOGIES.md) for what the app is built on and why.

## Project layout

- `Sources/LithePGCore/` — connector, schema introspection, AI drafting, export, shared logic.
- `Sources/LithePGApp/` — SwiftUI app, app state, persistence, Keychain store.
- `Sources/LithePGAppMain/` — thin executable launcher for packaging.
- `Sources/lithepg/` — CLI smoke utility.
- `Tests/` — Swift Testing suites; integration tests env-gated.
- `script/` — dogfood, package, release and measurement helpers.
- `docs/` — architecture, tech stack, security, releasing, receipts.

## CI

Every push and PR runs `.github/workflows/ci.yml`: build and full test suite on macOS plus dependency, secret and static-analysis scans (osv-scanner, gitleaks, semgrep) on Linux. Actions are pinned by commit SHA and scanner binaries are checksum-verified.
