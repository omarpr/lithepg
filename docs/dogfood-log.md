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
- [x] **Schema-to-query helper** — relation rows in the schema sidebar can insert a safe quoted `SELECT * FROM "schema"."relation" LIMIT 100;` into the active query tab without auto-running it; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 62 Swift Testing tests in 10 suites.
- [x] **Editor/tab polish** — query tabs preserve buffers/results, result state resets on new results, SQL keyword highlighting skips comments/quoted text, and async query completion is guarded against stale cancelled runs; latest `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 65 Swift Testing tests in 11 suites.
- [x] **Visual dogfood receipt** — latest app build launched via `./script/run_dogfood_app.sh` against the local smoke database; cropped window screenshot captured at `/Users/omar/.openclaw/workspace/artifacts/lithepg-window-20260503-173416.png` (900×672).
- [x] **Binary size observation** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product LithePGApp` produced `.build/release/LithePGApp` at 21,158,552 bytes (20.18 MiB) after schema/sidebar + tabs + pagination. This was above the original v0.4 <15 MiB target; that target was later raised to a 50 MiB hard cap with a 30 MiB stretch goal after the pure-Swift dependency baseline proved the original budget unrealistic.
- [ ] **Manual UI receipt** — pending Omar/local dogfood confirmation of sidebar refresh, tab switching, pagination, schema SELECT insertion, and results copy behavior against a real database.

## 2026-05-03 21:45 EDT — v0.3 persistence/UI wiring slice

- Added durable saved-connection metadata persistence via JSON under Application Support, with passwords routed through a Keychain-facing credential store abstraction.
- Wired AppState saved-connection load/save/delete/connect methods with in-memory stores in tests and file/keychain defaults in the app.
- Added Connect sheet save flow: save checkbox, name field, environment picker, saved-connection list, and environment badges.
- Added active environment tracking and a production warning banner for production-tagged saved connections.
- Verification in progress: targeted AppState and Persistence tests passed; full `swift test` and dogfood app launch remain next before the commit.

## 2026-05-03 22:30 EDT — v0.3 query history wiring slice

- Added opt-in query history AppState state and persistence wiring.
- Successful queries append SQL, connection/environment metadata, timing, summary, and success flag; result rows are not stored.
- Added query history popover UI with enable toggle, clear action, and “Use SQL” reuse action.
- Added AppState tests for loading/clearing/reusing history and env-gated live history capture.

## 2026-05-03 23:00 EDT — saved-connection safe delete polish

- Added a destructive delete affordance for saved connections in the Connect sheet.
- Delete now requires a confirmation dialog and clarifies it only removes local metadata and credential-store secret reference, not the database.
- Verification: targeted AppState/Persistence test suite passed.
## 2026-05-03 23:30 EDT — v0.3 saved connections + history dogfood validation

- Added an env-gated live AppState smoke covering the saved-connection flow end-to-end: save metadata, store credentials separately, connect from the saved record, track production environment, execute a query, and record query history with the saved connection/environment metadata.
- Verification: default `swift test` passed with 78 Swift Testing tests in 12 suites. GitHub Actions CI for `e837550` passed.
- Live dogfood verification: `./script/dogfood_postgres.sh start` then `POSTGRES_TEST_URL=postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable swift test --filter 'saved connection flow|query history records|connects through AppState|refresh schema|reconnect|live|Live'` passed 6 selected live tests in 2 suites.
- Result: saved-connection persistence, connect-from-saved, production tracking, schema refresh/reconnect, and opt-in query-history capture all have automated local dogfood coverage against the seeded Postgres container.


## 2026-05-04 04:50 EDT — v0.3 final results-pane polish

- Omar caught that the bottom results table still was not using the full allocated pane vertically after the width fix.
- Increased the results pane's layout priority/minimum height, reduced the editor minimum height so the bottom pane has room, and added viewport filler rows so sparse result sets visually occupy the full table area instead of ending early.
- Verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 80 Swift Testing tests in 12 suites. Dogfood app relaunched against the local seeded Postgres container and a cropped window screenshot was captured at `/Users/omar/.openclaw/workspace/artifacts/lithepg-layout-fix-20260504-0451.png`.

## 2026-05-04 04:58 EDT — v0.4 lean/fast baseline opened

- Created v0.4 Lean & Fast spec/plan from the roadmap and started the measurement-first phase.
- Release binary baseline: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product LithePGApp` produced `.build/release/LithePGApp` at 21,909,208 bytes (20.89 MiB). The original 15 MiB target is unrealistic for the pure-Swift GUI + postgres-nio dependency baseline, so v0.4 now uses a 50 MiB hard cap with a 30 MiB stretch goal.
- Initial local blocker for the query-overhead gate: `psql` was not yet installed/available on this machine, so final overhead comparison needed either installing `psql` or documenting an agreed temporary comparator. Resolved on 2026-05-05 by using `/opt/homebrew/opt/libpq/bin/psql`.

## 2026-05-04 07:50 EDT — v0.4 binary budget adjusted

- Omar called out that the original bundle-size goal is now unrealistic. Agreed: the pure-Swift GUI + postgres-nio/NIO/crypto baseline already sits around 20.89 MiB before v0.4 optimization work.
- Raised the v0.4 app binary budget to a 50 MiB hard cap with a 30 MiB stretch goal. This keeps the app lean by desktop standards while avoiding fake optimization pressure that would weaken correctness/security.
- CI now treats binary size above 30 MiB as a warning and above 50 MiB as a failure. AI models remain separate downloads and do not count toward the app binary budget.

## 2026-05-05 08:20 EDT — v0.4 measurement harness baseline

- Added a repeatable v0.4 measurement harness: `script/v04_measure.sh` builds release `LithePGApp` + `lithepg-bench`, records app binary size, measures app startup readiness through `LITHEPG_STARTUP_METRICS_PATH`, and compares persistent LithePG query execution against one-session `psql` timings.
- Local `psql` comparator is now available at `/opt/homebrew/opt/libpq/bin/psql` and is used automatically by the harness when `psql` is not on `PATH`.
- Baseline output directory: `.build/v04-measurements/20260505-082000`.
- Release binary baseline: 21,923,016 bytes / 20.91 MiB, under both the 50 MiB hard cap and 30 MiB stretch goal.
- Cold startup-to-useful-result baseline: 192.81 ms for startup URL + `SELECT 1`, below the 500 ms goal.
- Query-path baseline, persistent connection, 30 measured iterations after 5 warmups:
  - `SELECT 1`: LithePG median/p95 0.211/0.266 ms vs `psql` median/p95 0.183/0.251 ms; median overhead 0.028 ms.
  - Dogfood `customer_revenue`: LithePG median/p95 0.262/0.300 ms vs `psql` median/p95 0.209/0.272 ms; median overhead 0.053 ms.
- Current measurement result: v0.4 already clears the binary, cold-start, and simple query-overhead targets on the primary local baseline. Continue with binary contributor inspection and stability/dogfood tracking before tagging v0.4.

## 2026-05-05 08:23 EDT — v0.4 binary contributor inspection

- Inspected the release Mach-O with `otool -L`, `size -m`, and a copy-only `strip -x` probe.
- Dynamic dependencies are system Swift/AppKit/Foundation/Security/Network/CryptoKit libraries plus Swift runtime libraries; no `libpq` is linked.
- Segment snapshot: `__TEXT` is ~8.68 MiB and `__LINKEDIT` is ~12.63 MiB. A local-symbol strip probe reduces the binary from 21,923,016 bytes / 20.91 MiB to 12,320,608 bytes / 11.75 MiB, saving 9.16 MiB without changing source. This suggests the shipped/distribution artifact can be much smaller than the raw SwiftPM release executable if we add a packaging/signing step that strips symbols safely.
- Added strip-probe fields to `script/v04_measure.sh` so future baselines track both raw release size and stripped distribution-size potential.

## 2026-05-05 08:29 EDT — v0.4 stability/security hardening pass

- Folded first-pass security-audit findings into the active workstream without expanding dependencies.
- `ConnectionConfig(url:)` now honors `sslmode=`: `disable/allow/prefer` stay cleartext, while `require/verify-ca/verify-full` map to LithePG's verified TLS mode instead of being silently ignored. Unsupported `sslmode` values now fail parsing explicitly.
- Credential redaction now also scrubs passwords embedded in `postgres://user:password@host/db` and `postgresql://...` URLs, not only `password=`/`password:` fields.
- Resolved Swift concurrency warnings in the query row-collection path by moving row aggregation behind a small locked accumulator instead of mutating captured vars from the `@Sendable` PostgresNIO row callback.
- Verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 84 tests across 12 suites.
- v0.4 measurement re-run after hardening: `.build/v04-measurements/20260505-082920`; binary 21,923,432 bytes / 20.91 MiB raw, strip probe 11.75 MiB; cold startup 196.70 ms; simple query median overhead 0.044 ms vs `psql`; dogfood query median overhead -0.030 ms vs `psql`.

## 2026-05-05 08:31 EDT — keychain hardening and security posture docs

- Keychain saves now target the data-protection keychain (`kSecUseDataProtectionKeychain`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, while reads retain a legacy fallback for passwords saved before the migration. Deletes remove both data-protection and legacy entries.
- Updated `docs/SECURITY.md` to match the current pre-1.0 implementation instead of over-claiming sandbox/TLS defaults.
- Verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 84 tests across 12 suites.
- v0.4 measurement re-run: `.build/v04-measurements/20260505-083136`; binary 21,924,008 bytes / 20.91 MiB raw, strip probe 11.75 MiB; cold startup 188.82 ms; simple query median overhead 0.018 ms vs `psql`; dogfood query median overhead 0.033 ms vs `psql`.

## 2026-05-05 08:33 EDT — remote cleartext UI warning

- Connect sheet now surfaces an inline warning when a non-loopback Postgres URL would connect cleartext without TLS or SSH. Localhost dogfood remains quiet.
- Verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 84 tests across 12 suites.
- v0.4 measurement re-run: `.build/v04-measurements/20260505-083321`; binary 21,936,264 bytes / 20.92 MiB raw, strip probe 11.75 MiB; cold startup 181.18 ms; simple query median overhead 0.030 ms vs `psql`; dogfood query median overhead 0.026 ms vs `psql`.


## 2026-05-05 08:37 EDT — shell-start metric and startup deferral receipt

- Added a standalone shell-start metric path: `LITHEPG_STARTUP_METRICS_PATH` can now be provided without `LITHEPG_STARTUP_URL`, so the app records first-shell readiness without auto-connecting.
- Updated `script/v04_measure.sh` to capture both `shell-start.json` and the existing connected/query `cold-start.json`. The script now scrubs inherited startup/smoke env vars for each app launch so shell and connected measurements are isolated.
- Startup deferral receipt: saved connections are loaded by the connect sheet task, query history is loaded by the history popover task, and schema loading remains connection-scoped; none are required for first shell readiness.
- Verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 85 tests across 12 suites.
- v0.4 measurement re-run: `.build/v04-measurements/20260505-083711`; shell readiness 133.76 ms; connected startup + `SELECT 1` 184.91 ms; binary 21,936,264 bytes / 20.92 MiB raw, strip probe 11.75 MiB; simple query median overhead 0.040 ms vs `psql`; dogfood query median overhead 0.038 ms vs `psql`.
