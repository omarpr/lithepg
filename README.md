# LithePG

[![CI](https://github.com/omarpr/lithepg/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/omarpr/lithepg/actions/workflows/ci.yml?query=branch%3Amain)
&nbsp;**Release:** [`v1.0.0`](https://github.com/omarpr/lithepg/tree/v1.0.0)

Website: [www.lithepg.app](https://www.lithepg.app)

LithePG is a lean, Mac-native PostgreSQL client with local-first AI. It is pure Swift on `postgres-nio` (no `libpq`), has a ~12.5 MiB stripped release executable and never sends prompts or database contents to an AI service.

![LithePG app window showing a seeded dogfood schema, query editor, and results grid](docs/assets/lithepg-app-snapshot.png)

*Screenshot shows the seeded demo database, not real data.*

## What you get

- A native macOS app for testing and opening Postgres connections, writing SQL and viewing results.
- Saved connections with passwords in the macOS Keychain, never on disk.
- A left-side connection navigator plus schema sidebar, query tabs and history.
- Optional Neon CLI scanning imports missing project/branch databases when the user-installed CLI is available; otherwise the action stays disabled.
- Result copy and export as CSV, TSV, JSON, Markdown or SQL inserts.
- One-click table preview: the sidebar's select action inserts and runs `SELECT * ... LIMIT 100`.
- Clickable cells: select and `⌘C`, right-click to copy cell or row, double-click to view and edit a value locally.
- EXPLAIN and EXPLAIN ANALYZE (`⌘E` / `⇧⌘E`) with an indented plan tree that flags the costliest node.
- A schema graph (`⇧⌘G`): tables as nodes, foreign keys as edges, columns and types in an inspector.
- Ask in English drafting that inserts SQL for review and never auto-runs it.
- Pasted connection strings just work, including Neon URLs, quoted strings and `psql` command copies.
- Light, dark and system appearance.
- A CLI smoke utility (`lithepg`) for plain TCP, TLS and SSH-tunneled checks.

## Status

The `v1.0.0` source release is complete. The local suite passes with 252 tests across 40 suites, connectivity is proven live against local Docker Postgres and real Neon endpoints (direct and pooled), the full git history has been scanned for secrets, and the release executable remains under the 50 MiB cap. Public binary distribution remains separate: Apple Developer ID signing and notarization, a final security contact, a Homebrew target and publication approval are still required. Release history lives in [`CHANGELOG.md`](CHANGELOG.md).

## Install

### GitHub Release zip

When a signed release exists: download `LithePG.app.zip` from [Releases](https://github.com/omarpr/lithepg/releases), verify the checksum if provided, unzip and move `LithePG.app` to `/Applications`. Until then, build from source.

### Homebrew cask (planned)

`brew install --cask lithepg` will work once the v1.0.0 signed artifact and tap are approved.

### Build from source

Requirements: macOS 14+ and an Xcode/Swift 6.2 toolchain.

```sh
git clone https://github.com/omarpr/lithepg.git
cd lithepg
swift build && swift test
./script/build_and_run.sh --package
open dist/LithePG.app
```

Or rebuild, verify, install to `/Applications`, and launch in one step:

```sh
./script/rebuild_and_install.sh
```

The installer validates any existing `LithePG.app` before replacing it and uses
`sudo` only when `/Applications` is not writable. Pass `--no-open` to install
without launching.

## Local-first AI in plain language

Ask in English (`⇧⌘K`) drafts SQL from your request plus local schema metadata. On macOS 26, when Apple Intelligence is supported, enabled and ready, LithePG uses Apple's on-device system foundation model with guided structured output. It supplies a compact schema and foreign-key context, then admits only one read-only statement through a local safety gate. Older or unsupported Macs retain the deterministic local drafter for relation listing, counts, column projection, ordering, limits and known foreign-key joins. The draft lands in the editor for review and never runs automatically. LithePG makes no cloud AI call and downloads no model artifact; the system model is managed by macOS.

## Neon CLI scanner

When `neon` or `neonctl` is installed, the connection navigator can explicitly scan the user's Neon projects, branches and databases and save only endpoints LithePG does not already know. The scanner invokes machine-readable, read-only CLI commands with Neon analytics disabled. Generated passwords are never logged or written to JSON; imported passwords go directly to the macOS Keychain. Without the CLI, the scan button remains visible but disabled.

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
./script/rebuild_and_install.sh --no-open
./script/package_verify.sh dist/LithePG.app
```

Live Postgres, TLS, SSH and Neon integration tests are gated on env vars (`POSTGRES_TEST_URL` and friends) and auto-skip without them.

Running from Xcode: open the package folder (`xed .`), pick the `LithePGApp` scheme and hit run.

See [`CORE_TECHNOLOGIES.md`](CORE_TECHNOLOGIES.md) for what the app is built on and why.

## Project layout

- `Sources/LithePGCore/` — connector, schema introspection, AI drafting, export, shared logic.
- `Sources/LithePGApp/` — SwiftUI app, app state, persistence, Keychain store.
- `Sources/LithePGAppMain/` — thin executable launcher for packaging.
- `Sources/lithepg/` — CLI smoke utility.
- `Tests/` — Swift Testing suites; integration tests env-gated.
- `script/` — package, release and focused test helpers.
- `webapp/` — Vite + React promotional site and Fly.io deployment configuration for `www.lithepg.app`.
- `docs/` — architecture, tech stack, security and release documentation.

## Contributors

Thank you to the people building and improving LithePG.

<p>
  <a href="https://github.com/omarpr">
    <img src="https://github.com/omarpr.png?size=128" width="96" height="96" alt="Contributor avatar">
  </a>
</p>

[See every contributor and their commits](https://github.com/omarpr/lithepg/graphs/contributors).

## CI

Every push and PR runs `.github/workflows/ci.yml`: build and full test suite on macOS plus dependency, secret and static-analysis scans (osv-scanner, gitleaks, semgrep) on Linux. Actions are pinned by commit SHA and scanner binaries are checksum-verified.
