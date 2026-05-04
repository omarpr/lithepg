# LithePG

[![CI](https://github.com/omarpr/lithepg/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/omarpr/lithepg/actions/workflows/ci.yml?query=branch%3Amain)
&nbsp;**Release:** [`v0.1`](https://github.com/omarpr/lithepg/tree/v0.1) — Walking Skeleton

A lean, Mac-native PostgreSQL client with local-first AI. Pure Swift, no `libpq`, target app binary under 50 MiB, with a 30 MiB stretch goal.

> Badges resolve against a private repository — they render for viewers signed into GitHub with access to `omarpr/lithepg`.

## Status: v0.1 Walking Skeleton

End-to-end proof that the stack is real. Ships as a CLI that runs `SELECT 1` across three connection modes:

- **Plain TCP** against local Postgres.
- **TLS verify-full** with a pinned self-signed CA (routed through BoringSSL via `NIOSSL`).
- **SSH tunnel** to a bastion via an `/usr/bin/ssh -L` subprocess, Postgres loopback on the far side.

Exit-criteria evidence: [`docs/dogfood-log.md`](docs/dogfood-log.md).

## Quickstart

```sh
swift build
swift test
```

```sh
.build/debug/lithepg --url postgres://user:pass@host:5432/db
.build/debug/lithepg --url postgres://user:pass@host:5432/db --tls --tls-ca /path/to/ca.pem
.build/debug/lithepg --url postgres://user:@127.0.0.1:5432/db --ssh user@bastion.example.com:22
```

`--tls` and `--ssh` together are rejected in v0.1 — threading an SNI override for tunneled TLS is a later milestone.


## Dogfood Postgres + App Startup

Spin up a local Docker Postgres with sample data and launch the app directly into it:

```sh
./script/dogfood_postgres.sh
LITHEPG_STARTUP_URL="postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable" \
LITHEPG_STARTUP_QUERY="SELECT * FROM lithepg_demo.customer_revenue ORDER BY revenue_cents DESC;" \
.build/arm64-apple-macosx/debug/LithePGApp
```

Or use the helper, which seeds Docker, builds `LithePGApp`, injects the startup URL/query, and launches the app:

```sh
./script/run_dogfood_app.sh
```

The startup env is intentionally opt-in for dogfood/smoke runs. Normal app launches still show the connection sheet.

## App Shortcuts

- `⌘↩` — run the active query tab.
- `⌘.` — cancel the running query.
- `⌘T` — open a new query tab.
- `⌘W` — close the active query tab, keeping at least one tab open.
- `⇧⌘[` / `⇧⌘]` — move to the previous / next query tab.

## Project Layout

- `Sources/lithepg/` — app code (CLI entry, connector, SSH tunnel, config).
- `Tests/lithepgTests/` — Swift Testing suites; Postgres/TLS/SSH integration tests are gated on env vars and auto-skip without them.
- `docs/` — tech stack, roadmap, security posture, specs, and plans.
- `CLAUDE.md`, `AGENTS.md`, `GOVERNANCE.md` — tooling and contribution entry points.

## CI

`.github/workflows/ci.yml` runs `swift build && swift test` on `macos-15` with `latest-stable` Xcode for every push to `main` and every pull request. Integration tests auto-skip in CI; unit coverage is the gate.
