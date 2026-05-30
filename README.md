# LithePG

[![CI](https://github.com/omarpr/lithepg/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/omarpr/lithepg/actions/workflows/ci.yml?query=branch%3Amain)
&nbsp;**Latest tagged release:** [`v0.5`](https://github.com/omarpr/lithepg/tree/v0.5) — AI-Ready

LithePG is a lean, Mac-native PostgreSQL client with local-first AI. It is pure Swift, uses `postgres-nio` instead of `libpq`, and keeps the shipped app binary under the 50 MiB hard cap.

![LithePG app window showing a seeded dogfood schema, query editor, and results grid](docs/assets/lithepg-app-snapshot.png)

*Screenshot uses the seeded dogfood database only; it does not show real private schemas, credentials, or query results.*

## What you get

- A native macOS app for connecting to PostgreSQL, writing SQL, and viewing results.
- Saved connection metadata with passwords stored separately in the macOS Keychain.
- Schema sidebar, tabbed query workspace, query history, pagination, and keyboard shortcuts.
- Ask-in-English SQL drafting that inserts suggested SQL for review and never auto-runs it.
- Light, dark, and system appearance choices, with dark as the default.
- A small CLI smoke utility (`lithepg`) for plain TCP, TLS, and SSH-tunneled connection checks.

## Status

v0.5 is the current tagged milestone. v1.0 public launch work is in progress and remains unreleased until signed/notarized distribution, Homebrew metadata, final release receipts, and Omar-approved external publication gates are complete.

Current local receipts:

- **AI drafting:** deterministic local Ask flow drafts runnable SQL for simple single-table prompts and two-table joins using schema/foreign-key metadata; drafts are inserted for human review and never auto-run.
- **Model posture:** the CoreML adapter scaffold is disabled by default, requires a user-provided external model artifact, and keeps prompts, schema context, query results, history, and credentials on-device.
- **Binary budget:** 21.338 MiB raw release executable / 11.959 MiB stripped packaged executable, under the 50 MiB hard cap and 30 MiB stretch goal.
- **Startup:** 138.14 ms shell readiness; 222.00 ms connected startup through seeded dogfood Postgres.
- **Query overhead:** -0.032 ms median overhead versus `psql` for `SELECT 1`; -0.004 ms for the dogfood query.
- **Stability:** v0.4 seven-day zero-crash dogfood window satisfied; v0.5 dogfood/test/measurement gates passed.

Evidence and policies: [`CHANGELOG.md`](CHANGELOG.md), [`docs/RELEASING.md`](docs/RELEASING.md), [`SECURITY.md`](SECURITY.md), and [`docs/dogfood-log.md`](docs/dogfood-log.md).

## Install

### GitHub Release zip

The v1.0 public distribution path is a signed and notarized `LithePG.app.zip` attached to a GitHub Release:

1. Open the [GitHub Releases page](https://github.com/omarpr/lithepg/releases).
2. Download `LithePG.app.zip` for the release you want.
3. If the release notes include checksums, verify the downloaded zip before opening it.
4. Unzip it, move `LithePG.app` to `/Applications`, and open it from Finder.

If a v1.0 signed/notarized release zip is not present yet, build from source instead. Unsigned local bundles from `dist/` are development artifacts, not official public releases. Maintainer release steps live in [`docs/RELEASING.md`](docs/RELEASING.md).

### Homebrew cask (planned)

A Homebrew cask is planned for v1.0 after the release artifact URL, SHA-256, and tap target are approved. The intended user command will be:

```sh
brew install --cask lithepg
```

Until that cask exists, use the GitHub Release zip when available or the source build below.

### Build from source

Requirements: macOS 14+ and an Xcode/Swift 6.2 toolchain.

```sh
git clone https://github.com/omarpr/lithepg.git
cd lithepg
swift build
swift test
./script/build_and_run.sh --package
./script/package_verify.sh dist/LithePG.app
open dist/LithePG.app
```

The package step produces `dist/LithePG.app`, strips the copied release executable, applies local/ad-hoc signing when public signing credentials are not configured, and runs the bundle verifier.

## Quickstart for the seeded demo

Start the local Docker Postgres with synthetic sample data, then launch the app directly into it. The Docker demo database uses the synthetic local password `postgres`; replace it with your own password for any non-demo database.

```sh
./script/dogfood_postgres.sh
LITHEPG_STARTUP_URL="postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable" \
LITHEPG_STARTUP_QUERY="SELECT * FROM lithepg_demo.customer_revenue ORDER BY revenue_cents DESC;" \
.build/arm64-apple-macosx/debug/LithePGApp
```

Or use the helper, which seeds Docker, builds `LithePGApp`, injects the startup URL/query, and launches the app:

```sh
POSTGRES_TEST_URL="postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable" ./script/run_dogfood_app.sh
```

The startup environment variables are intentionally opt-in for dogfood and smoke runs. Normal app launches show the connection sheet.

## Local-first AI in plain language

LithePG's Ask-in-English feature is designed to help draft SQL without sending your database context to a cloud service:

- The app builds context from your request and local schema metadata.
- Generated SQL is inserted into the editor so you can inspect or edit it first.
- Generated SQL is never run automatically.
- There is no telemetry, no cloud AI call path, and no model download path in the app.
- The default Ask implementation is deterministic and local. A CoreML adapter exists for future/local experiments, but it is off by default and only activates when you explicitly provide `LITHEPG_ENABLE_LOCAL_MODEL=1` and `LITHEPG_LOCAL_MODEL_PATH` for your own model artifact.
- Model artifacts are not bundled with LithePG and do not count toward the app binary budget.

## CLI smoke utility

The original v0.1 CLI remains useful for connection checks:

```sh
.build/debug/lithepg --url postgres://user:***@host:5432/db
.build/debug/lithepg --url postgres://user:***@host:5432/db --tls --tls-ca /path/to/ca.pem
.build/debug/lithepg --url postgres://user:@127.0.0.1:5432/db --ssh user@bastion.example.com:22
```

The CLI supports plain TCP, TLS verify-full with a pinned CA, and an SSH tunnel through `/usr/bin/ssh -L`. `--tls` and `--ssh` together are still rejected; tunneled TLS needs later SNI work.

## App shortcuts

- `⌘↩` — run the active query tab.
- `⌘.` — cancel the running query.
- `⌘T` — open a new query tab.
- `⌘W` — close the active query tab, keeping at least one tab open.
- `⇧⌘[` / `⇧⌘]` — move to the previous / next query tab.
- `⇧⌘K` — open Ask in English for local SQL drafting.

## Developer commands

```sh
swift build
swift test
./script/build_and_run.sh --package
./script/package_verify.sh dist/LithePG.app
```

Docs-only changes can skip Swift tests, but release-impacting changes should also run the package verifier and, when Docker is available, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh`.

## Project layout

- `Sources/LithePGCore/` — Postgres connector, saved-connection persistence models, AI drafting services, and shared core logic.
- `Sources/LithePGApp/` — SwiftUI macOS app.
- `Sources/lithepg/` — CLI smoke utility.
- `Tests/` — Swift Testing suites; Postgres/TLS/SSH/model-artifact integration tests are gated on env vars and auto-skip without them.
- `script/` — dogfood, package, release, and measurement helpers.
- `docs/` — tech stack, roadmap, release docs, dogfood receipts, specs, plans, and screenshots.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `GOVERNANCE.md`, `SECURITY.md` — public collaboration and policy entry points.

## CI

`.github/workflows/ci.yml` currently exists as a manual workflow because account billing/spending-limit settings previously blocked push/PR-triggered Actions. The latest manual dispatch also failed before any job steps or logs were produced, so local verification receipts remain the release gate until the external GitHub Actions account setting is cleared.
