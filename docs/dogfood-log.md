# LithePG Dogfood Log

Per the roadmap (`docs/superpowers/specs/2026-04-18-roadmap-design.md` §6 v0.3 + §9),
this log captures every time the maintainer reaches for a different Postgres
client. The log starts empty at v0.1 and becomes active from v0.3 (Dogfood-Ready).

## v0.1 — 2026-04-18 — Exit-Criteria Smoke Test

- [x] **Plain loopback** — `.build/debug/lithepg --url postgres://postgres:postgres@localhost:55432/postgres` → `SELECT 1 → 1`, exit 0. Tested against `postgres:16` in Docker.
- [x] **TLS verify-full with pinned CA** — `.build/debug/lithepg --url postgres://postgres:postgres@localhost:5433/postgres --tls --tls-ca /tmp/lithepg-tls/server.crt` → `SELECT 1 → 1`, exit 0. Self-signed cert with SAN `DNS:localhost,IP:127.0.0.1`, routed through BoringSSL via `pinnedRootCertificatePath` because Darwin's SecTrust path rejects self-signed anchors.
- [x] **SSH tunnel** — verified on maintainer's machine via macOS loopback (Remote Login on, authorized own key, tunneled back to local Postgres). Three-part verification all green:
  1. `SSH_TEST_TARGET=omar@localhost:22 swift test --filter SSHTunnelTests` → `openAndClose` passed (tunnel opens, local port listens, closes cleanly).
  2. `POSTGRES_SSH_TEST_TARGET=omar@localhost:22,127.0.0.1:5432 POSTGRES_SSH_TEST_CREDS=omar::minmaxing swift test --filter PostgresConnectorTests.sshTunnelSelect1` → `SELECT 1 → 1` through tunnel.
  3. CLI smoke: `.build/debug/lithepg --url postgres://omar:@127.0.0.1:5432/minmaxing --ssh omar@127.0.0.1:22` → `SELECT 1 → 1`, exit 0.

  The tunnel is driven by `/usr/bin/ssh -N -L <local>:<remoteHost>:<remotePort>` with `ExitOnForwardFailure=yes` and `StrictHostKeyChecking=accept-new`. Proves the escape-hatch path that replaces NIOSSH until a later milestone.

### Pure-Swift verification

`swift package show-dependencies` resolves only `postgres-nio` and its transitive graph (swift-nio, swift-nio-ssl, swift-nio-transport-services, swift-crypto, swift-asn1, swift-log, swift-metrics, swift-service-lifecycle, swift-async-algorithms, swift-collections, swift-atomics, swift-system). `grep -i libpq` → no matches. No C shims authored by LithePG (BoringSSL ships vendored inside `swift-nio-ssl`, which is a conscious trade-off documented in `docs/TECH_STACK.md` §3).

## Switches to Other Tools

*(Log entries start at v0.3.)*

## v0.2a — 2026-05-02 — Implementation Progress

- [x] Local test gate: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 35 tests across 6 suites; Postgres/TLS/SSH integration tests skipped because their env vars were not set.
- [x] Release binary size observation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product LithePGApp` produced `.build/release/LithePGApp` at 20,492,808 bytes (19.54 MiB). This is an observation only; the v0.2c binary-size gate will decide the target/trade-offs.
- [x] Post-merge main verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 35 tests across 6 suites after PR #9 merge. `swift run LithePGApp` builds and starts the app process successfully; visual screenshot/manual UI receipt is pending Screen Recording permission and live DB smoke.
- [x] Follow-up polish on main: TLS CA file picker added to `ConnectSheet`; result headers now tolerate duplicate SQL column names; `PostgresConnector.execute` caps stored rows at 10,000 while counting beyond the cap for the `truncated` flag.
- [x] Headless app-layer live smoke: `POSTGRES_TEST_URL=postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter liveConnectAndRunQuery` passed. This verifies `AppState.connect` + `runCurrentQuery` render `SELECT 42 AS lithepg_app_smoke` through the same persistent connector path the SwiftUI app uses, without UI automation or clicking.

## v0.2a — Editor Library Spike — Blocked

- [x] Runestone resolved to `0.5.2` for the planned spike, but native macOS SPM build failed before app launch.
- Blocking error: `Runestone/Sources/Runestone/Library/Caret.swift:1:8: error: no such module 'UIKit'`.
- Conclusion: the planned Runestone `TextView` path is iOS/UIKit-oriented for this dependency/version and is not viable for native AppKit/SwiftUI macOS via SPM as specified. Re-brainstorm editor technology before continuing v0.2a implementation tasks.

## v0.2b — 2026-05-03 — Results Grid + Schema Tree Progress

- [x] **Schema/sidebar implementation present** — `SchemaMetadata`, `SchemaIntrospector`, `AppState.refreshSchema()`, `SchemaSidebar`, and the split workspace are on `main`.
- [x] **Results polish present** — table status/truncation presentation is clearer, and result copying now exports tab-separated text/status details instead of exposing a no-op copy affordance.
- [x] **Default verification** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 56 Swift Testing tests in 10 suites plus the gated XCTest UI smoke skipped because `LITHEPG_UI_SMOKE_URL` is unset.
- [x] **Live schema smoke** — `./script/dogfood_postgres.sh start` followed by `POSTGRES_TEST_URL=postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'live|Live|refresh schema|connects through AppState|SchemaIntrospector'` passed with 7 selected schema/AppState tests in 2 suites.
- [x] **Rendered-results pagination** — client-side result paging landed for the rendered 10,000-row cap; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 61 Swift Testing tests in 10 suites.
- [x] **Binary size observation** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product LithePGApp` produced `.build/release/LithePGApp` at 21,158,552 bytes (20.18 MiB) after schema/sidebar + tabs + pagination. Still above the eventual v0.4 <15 MiB target; v0.2 keeps this as measured evidence, not a fail gate.
- [ ] **Manual UI receipt** — pending Omar/local dogfood confirmation of sidebar refresh, tab switching, pagination, and results copy behavior against a real database.
