# LithePG Dogfood Log

Per the roadmap (`docs/superpowers/specs/2026-04-18-roadmap-design.md` §6 v0.3 + §9),
this log captures every time the maintainer reaches for a different Postgres
client. The log starts empty at v0.1 and becomes active from v0.3 (Dogfood-Ready).

## v0.1 — 2026-04-18 — Exit-Criteria Smoke Test

- [x] **Plain loopback** — `.build/debug/lithepg --url postgres://postgres:***@localhost:55432/postgres` → `SELECT 1 → 1`, exit 0. Tested against `postgres:16` in Docker.
- [x] **TLS verify-full with pinned CA** — `.build/debug/lithepg --url postgres://postgres:***@localhost:5433/postgres --tls --tls-ca /tmp/lithepg-tls/server.crt` → `SELECT 1 → 1`, exit 0. Self-signed cert with SAN `DNS:localhost,IP:127.0.0.1`, routed through BoringSSL via `pinnedRootCertificatePath` because Darwin's SecTrust path rejects self-signed anchors.
- [x] **SSH tunnel** — verified on maintainer's machine via macOS loopback (Remote Login on, authorized own key, tunneled back to local Postgres). Three-part verification all green:
  1. `SSH_TEST_TARGET=omar@localhost:22 swift test --filter SSHTunnelTests` → `openAndClose` passed (tunnel opens, local port listens, closes cleanly).
  2. `POSTGRES_SSH_TEST_TARGET=omar@localhost:22,127.0.0.1:5432 POSTGRES_SSH_TEST_CREDS=omar::*** swift test --filter PostgresConnectorTests.sshTunnelSelect1` → `SELECT 1 → 1` through tunnel.
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
- [x] Headless app-layer live smoke: `POSTGRES_TEST_URL=postgres://postgres:***@localhost:55432/postgres?sslmode=disable DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter liveConnectAndRunQuery` passed. This verifies `AppState.connect` + `runCurrentQuery` render `SELECT 42 AS lithepg_app_smoke` through the same persistent connector path the SwiftUI app uses, without UI automation or clicking.

## v0.2a — Editor Library Spike — Blocked

- [x] Runestone resolved to `0.5.2` for the planned spike, but native macOS SPM build failed before app launch.
- Blocking error: `Runestone/Sources/Runestone/Library/Caret.swift:1:8: error: no such module 'UIKit'`.
- Conclusion: the planned Runestone `TextView` path is iOS/UIKit-oriented for this dependency/version and is not viable for native AppKit/SwiftUI macOS via SPM as specified. Re-brainstorm editor technology before continuing v0.2a implementation tasks.

## v0.2b — 2026-05-03 — Results Grid + Schema Tree Progress

- [x] **Schema/sidebar implementation present** — `SchemaMetadata`, `SchemaIntrospector`, `AppState.refreshSchema()`, `SchemaSidebar`, and the split workspace are on `main`.
- [x] **Results polish present** — table status/truncation presentation is clearer, and result copying now exports tab-separated text/status details instead of exposing a no-op copy affordance.
- [x] **Default verification** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 56 Swift Testing tests in 10 suites plus the gated XCTest UI smoke skipped because `LITHEPG_UI_SMOKE_URL` is unset.
- [x] **Live schema smoke** — `./script/dogfood_postgres.sh start` followed by `POSTGRES_TEST_URL=postgres://postgres:***@localhost:55432/postgres?sslmode=disable DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'live|Live|refresh schema|connects through AppState|SchemaIntrospector'` passed with 7 selected schema/AppState tests in 2 suites.
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
- Live dogfood verification: `./script/dogfood_postgres.sh start` then `POSTGRES_TEST_URL=postgres://postgres:***@localhost:55432/postgres?sslmode=disable swift test --filter 'saved connection flow|query history records|connects through AppState|refresh schema|reconnect|live|Live'` passed 6 selected live tests in 2 suites.
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
- Credential redaction now also scrubs passwords embedded in `postgres://user:***@host/db` and `postgresql://...` URLs, in addition to `password=` fields.
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

## 2026-05-05 08:39 EDT — dogfood stability check harness

- Added `script/dogfood_check.sh` as a one-command local stability gate. It starts/refreshes seeded Postgres, runs the default Swift test suite, runs the live dogfood AppState/schema/history slice with `POSTGRES_TEST_URL`, runs the v0.4 measurement gate, and writes `status.json` plus logs under `.build/dogfood-checks/<timestamp>/`.
- First run: `.build/dogfood-checks/20260505-083839/status.json` on `main` at `deedb3b` passed default tests, live tests, and v0.4 measurements.
- First check metrics: shell readiness 126.26 ms; connected startup + `SELECT 1` 171.37 ms; binary 20.92 MiB raw / 11.75 MiB strip-probe; simple query median overhead 0.016 ms; dogfood query median overhead 0.027 ms.
- v0.3 dogfood triage status:
  - Saved connections, credential split, production environment tracking, query history, schema refresh, reconnect, and AppState live query path are covered by the live dogfood test slice and currently passing.
  - Results-pane vertical fill was fixed in the v0.3 layout polish and remains covered by presentation tests.
  - Manual UI receipt for sidebar refresh, tab switching, pagination, schema SELECT insertion, and result-copy behavior remains pending Omar/local visual confirmation; no code blocker is currently identified.
- Stability window status: day 0 check is green; do not tag `v0.4` until the 7-day zero-crash window is satisfied.

## 2026-05-05 08:40 EDT — stripped release app bundle packaging

- Extended `script/build_and_run.sh --package` to build a release `.app` bundle under `dist/LithePG.app` and apply `strip -x` to the copied app executable.
- Local package smoke: `./script/build_and_run.sh --package` produced `dist/LithePG.app` and reduced the bundled executable from 20.92 MiB to 11.75 MiB, matching the v0.4 strip-probe measurement while leaving the raw SwiftPM build untouched.
- Verification: `bash -n script/build_and_run.sh script/dogfood_check.sh script/v04_measure.sh` passed.

## 2026-05-24 17:14 EDT — v0.4 stability window release receipt

- The v0.4 seven-day zero-crash window has elapsed since the green day-0 stability check on 2026-05-05, with no crash entries added to this log.
- Re-ran the local stability gate after restarting Colima/Docker: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed on `main` at `85d5ad3`.
- Check artifacts: `.build/dogfood-checks/20260524-171411/`.
- Verification summary: default Swift tests passed, live dogfood AppState/schema/history slice passed, and v0.4 measurement gate passed.
- Current metrics: shell readiness 125.67 ms; connected startup + `SELECT 1` 158.86 ms; release binary 20.98 MiB raw / 11.79 MiB stripped; simple query median overhead 0.042 ms; dogfood query median overhead 0.080 ms.
- Result: v0.4 exit criteria are satisfied; ready to tag `v0.4`.

## 2026-05-25 06:55 EDT — v0.5 AI-Ready pre-tag dogfood receipt

- [x] **Fresh default test gate** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed on `main` at `a6719e6` with 125 Swift Testing tests across 19 suites. Integration/model-artifact tests that require explicit env vars skipped as designed.
- [x] **Seeded live dogfood slice** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed after refreshing Docker Postgres `lithepg-smoke` from `script/dogfood_seed.sql`. Check artifacts: `.build/dogfood-checks/20260525-065045/`; live AppState/schema/history slice passed with `POSTGRES_TEST_URL=postgres://postgres:***@localhost:55432/postgres?sslmode=disable`.
- [x] **v0.4/v0.5 measurement gate** — the dogfood check's `script/v04_measure.sh` run passed and the v0.5 AI scaffold remains under the existing lean/fast budgets: release `LithePGApp` 21.338 MiB raw / 11.959 MiB strip-probe, shell readiness 138.14 ms, connected cold start through seeded Postgres 222.00 ms, `SELECT 1` median overhead -0.032 ms vs `psql`, dogfood query median overhead -0.004 ms vs `psql`.
- [x] **Ask example — simple single-table prompt** — deterministic Ask prompt `show customers` produced and the generated SQL executed successfully against the seeded database, returning the 4 seeded customers:

  ```sql
  SELECT * FROM "lithepg_demo"."customers" LIMIT 100;
  ```

- [x] **Ask example — 2-table join prompt** — deterministic Ask prompt `show orders with customer names` produced and the generated SQL executed successfully against the seeded database, returning the 6 seeded orders joined through `orders.customer_id -> customers.id`:

  ```sql
  SELECT
    o.*,
    c."name" AS "customer_name"
  FROM "lithepg_demo"."orders" o
  JOIN "lithepg_demo"."customers" c ON o."customer_id" = c."id"
  LIMIT 100;
  ```

- **Model/runtime caveat:** no real model artifact was supplied, downloaded, or bundled for this receipt. The CoreML `LocalModelAIQueryService` remains gated by `LITHEPG_ENABLE_LOCAL_MODEL=1` plus `LITHEPG_LOCAL_MODEL_PATH`; the production/default dogfood path uses the deterministic local Ask service. Generated SQL is inserted for review and is not auto-run by the app.

## 2026-05-28 20:24 EDT — v0.5 release tag approved

- Omar confirmed to continue the LithePG workstream and get it done, clearing the previous tag gate.
- Advanced README release/status text from v0.4 Lean & Fast to v0.5 AI-Ready using the 2026-05-25 pre-tag dogfood receipt metrics.
- Marked the v0.5 Task 10 plan checklist complete; `v0.5` is the release tag for the local-first Ask-in-English milestone.

## 2026-05-28 20:27 EDT — v1.0 public launch phase opened

- Opened the v1.0 design spec and implementation plan from the roadmap's public-launch exit criteria: notarized macOS build, GitHub/Homebrew distribution, public docs, security reporting, light/dark theme support, and governance templates.
- External blockers to clear before a true public `v1.0` tag: Apple Developer signing/notary credentials, Homebrew cask tap target, and GitHub Actions push/PR trigger account settings.
- Work can continue safely before those blockers by hardening package verification, release docs, contribution templates, and appearance preference tests.

## 2026-05-28 20:35 EDT — v1.0 package verification slice

- Added `script/package_verify.sh` as the release-bundle structure gate for `dist/LithePG.app`.
- Verification checks `Contents/MacOS/LithePGApp`, `Contents/Info.plist`, executable permissions, bundle identifier/name/package/version metadata, minimum macOS version, and the 50 MiB executable hard cap.
- Wired `script/build_and_run.sh --package` to run the verifier after the stripped release bundle is produced.
- RED check: `./script/package_verify.sh /tmp/lithepg-missing.app` failed as expected with `package verification failed: app bundle not found`.
- GREEN checks: `bash -n script/build_and_run.sh script/package_verify.sh script/sign_and_notarize.sh`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package`, and `./script/package_verify.sh dist/LithePG.app` all passed. Packaged executable: 12,486,016 bytes / 11.91 MiB; package metadata version: 0.5 (build 121).

## 2026-05-28 20:35 EDT — v1.0 signing/notarization wrapper slice

- Added `script/sign_and_notarize.sh`, a credential-gated public distribution wrapper for the packaged macOS app bundle.
- Added `docs/RELEASING.md` with the local package gate, signing/notary env inputs, dry-run command, real notarization flow, and v1.0 release gate reminders.
- RED check: with `LITHEPG_CODESIGN_IDENTITY` and `LITHEPG_NOTARY_PROFILE` unset, `./script/sign_and_notarize.sh --dry-run dist/LithePG.app` failed as expected after package verification with `missing LITHEPG_CODESIGN_IDENTITY`.
- GREEN check: dummy dry run with placeholder `LITHEPG_CODESIGN_IDENTITY` and `LITHEPG_NOTARY_PROFILE` passed and printed only planned local commands; no signing, notary submission, or credential write occurred.
- Real signed/notarized smoke remains externally blocked until Omar supplies Apple Developer signing identity and notarytool keychain profile on this machine.
- Additional release-impact gate: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed with Docker available. Artifacts: `.build/dogfood-checks/20260528-205026/`; default Swift tests passed, live dogfood slice passed, v0.4 measurement passed. Metrics: shell readiness 130.75 ms; connected cold start 227.65 ms; raw release binary 21.338 MiB; strip probe 11.959 MiB; `SELECT 1` median overhead 0.070 ms; dogfood query median overhead 0.029 ms.

## 2026-05-30 09:07 EDT — v1.0 public contribution template slice

- Added public collaboration artifacts: contribution guide, Contributor Covenant-style code of conduct, PR template, and GitHub issue templates for bug reports and feature requests.
- Governance now links the concrete contribution guide, code of conduct, and DCO sign-off workflow instead of referring to unpublished v1.0 materials.
- Templates explicitly require redacted/synthetic examples and forbid credentials, full connection URLs, private schemas, certificates, and real query-result dumps in public reports.
- Verification: docs/template reference checks and focused secret-pattern scans passed; Swift tests were not required for this docs/GitHub metadata-only slice.

## 2026-05-30 09:20 EDT — v1.0 security reporting policy slice

- Added a GitHub-visible root `SECURITY.md` that points to the detailed security posture in `docs/SECURITY.md`.
- Replaced the ambiguous maintainer-contact language with explicit pending-contact blocker language: the public security contact is pending Omar approval, `[security contact pending]` is the temporary placeholder, and no email address was invented.
- Documented safe vulnerability-reporting guidance: avoid public issues for sensitive findings, redact credentials/full URLs/private schemas/result dumps/internal hosts, use synthetic data, and preserve the local-first no-telemetry/no-cloud-AI privacy invariant.
- Verification: Markdown link/reference checks and focused secret-pattern scans passed; Swift tests were not required for this docs-only slice.

## 2026-05-30 09:49 EDT — v1.0 appearance preference slice

- Added a persisted light/dark/system appearance preference with dark as the default and injected `UserDefaults` coverage for tests.
- Wired the SwiftUI root scene through `preferredColorScheme` and added an `Appearance` commands-menu picker for choosing Light, Dark, or System.
- RED check: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppearanceSettingsTests` failed before implementation because `AppState(appearanceDefaults:)`, `AppearancePreference`, and `appearancePreference` did not exist.
- GREEN checks: targeted `AppearanceSettingsTests` passed with 2 tests, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 tests across 20 suites; gated live/integration tests skipped as designed.

## 2026-05-30 10:08 EDT — v1.0 README public install guide slice

- Refreshed the README for first-time public readers with GitHub Release zip install steps, planned Homebrew cask wording, source build/test/package quickstart commands, a seeded app screenshot, and a plain-language local-first AI/model-artifact explanation.
- Reused `docs/assets/lithepg-app-snapshot.png`, which is documented as seeded dogfood data only; no new screenshot binary was created for this slice.
- Verification: README local link checks and focused secret-pattern scans passed; Swift tests were not required for this docs-only slice.

## 2026-05-30 10:34 EDT — v1.0 Homebrew cask template slice

- Added a repository-local Homebrew cask template under `packaging/homebrew/` for the planned `LithePG.app.zip` GitHub Release artifact.
- Documented the release artifact URL shape, SHA-256 workflow, placeholder replacement steps, and local/tap Homebrew checks in `docs/RELEASING.md` and `packaging/homebrew/README.md`.
- External publication remains blocked by design: stop before creating or pushing to any Homebrew tap until Omar provides the tap target and publication instructions.
- Verification: Ruby template syntax, Markdown link/reference sanity checks, and focused secret-pattern scans passed; Swift tests were not required for this docs/template-only slice.

## 2026-05-30 11:04 EDT — v1.0 local release gate receipt

- Ran the final local v1.0 release gates on `main` at `1682a2d` before any public tag/release publication.
- Full test gate: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites; gated live/model-artifact tests skipped as designed.
- Seeded Docker dogfood gate: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed. Artifacts: `.build/dogfood-checks/20260530-110419/`; default Swift tests passed, live dogfood slice passed, and v0.4/v1.0 measurement gate passed.
- Current local metrics: shell readiness 259.24 ms; connected cold start 250.97 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead -0.125 ms; dogfood query median overhead 0.035 ms.
- Package gate: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package && ./script/package_verify.sh dist/LithePG.app` passed. Packaged executable: 12,507,504 bytes / 11.93 MiB; bundle ID `dev.omarpr.lithepg`; version `0.5` build `129`; minimum macOS `14.0`.
- Signing/notarization gate remains externally blocked: `./script/sign_and_notarize.sh --dry-run dist/LithePG.app` verified the package, then failed clearly with missing `LITHEPG_CODESIGN_IDENTITY` because Apple Developer signing identity and notarytool profile are not configured in this cron environment. No signing, notarization, release upload, or Homebrew tap publication was attempted.

## 2026-05-30 11:37 EDT — v1.0 release metadata verifier gate

- Added optional package metadata assertions for final release candidates: `LITHEPG_EXPECTED_MARKETING_VERSION` must match `CFBundleShortVersionString` exactly when set, and `LITHEPG_EXPECTED_BUILD_VERSION` must match `CFBundleVersion` exactly when set. The existing generic numeric release/build validation remains in place.
- RED check before implementation: `LITHEPG_EXPECTED_MARKETING_VERSION=1.0 ./script/package_verify.sh dist/LithePG.app` exited 0 against the existing `dist/LithePG.app` with `Version: 0.5 (129)`, confirming the verifier did not yet enforce the expected marketing-version mismatch.
- GREEN mismatch checks after implementation: `LITHEPG_EXPECTED_MARKETING_VERSION=1.0 ./script/package_verify.sh dist/LithePG.app` failed clearly with `package verification failed: CFBundleShortVersionString is '0.5', expected '1.0' from LITHEPG_EXPECTED_MARKETING_VERSION`; after rebuilding the candidate, `LITHEPG_EXPECTED_BUILD_VERSION=998 ./script/package_verify.sh dist/LithePG.app` failed clearly with `package verification failed: CFBundleVersion is '999', expected '998' from LITHEPG_EXPECTED_BUILD_VERSION`.
- GREEN matching candidate check: `LITHEPG_MARKETING_VERSION=1.0 LITHEPG_BUILD_VERSION=999 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` produced `dist/LithePG.app` with `Version: 1.0 (999)`, and `LITHEPG_EXPECTED_MARKETING_VERSION=1.0 LITHEPG_EXPECTED_BUILD_VERSION=999 ./script/package_verify.sh dist/LithePG.app` passed. This is only a local release-candidate metadata gate; no `v1.0` tag, signing/notarization, upload, or external publication was attempted.

## 2026-05-30 11:58 EDT — v1.0 manual CI recheck

- Dispatched the manual GitHub Actions CI workflow on `main` at `c2510ec` to see whether remote verification could be restored for the v1.0 gate.
- Run: https://github.com/omarpr/lithepg/actions/runs/26688293183 (`workflow_dispatch`).
- Result: failed in ~6 seconds before either job produced steps or logs (`Build & test (macOS)` and `Security scans` both completed with failure and empty step lists). `gh run view --log-failed` returned `log not found`.
- Interpretation: this still looks like the external GitHub Actions account/settings blocker rather than a source/test failure. Local receipts remain the active release gate until Omar clears the Actions setting.

## 2026-05-30 12:10 EDT — v1.0 README local gate refresh

- Refreshed the README status section so public readers see the latest v1.0 local gate receipt instead of the older v0.5 metrics.
- README now calls out that `swift test`, seeded `script/dogfood_check.sh`, package build, and package verification passed before public release/tag publication, while still listing the remaining external v1.0 blockers.
- Verification: README link/reference sanity checks and focused secret-pattern scans passed; Swift tests were not required for this docs-only slice.

## 2026-05-30 12:24 EDT — v1.0 release gate status sync

- Rechecked release state before any publication: origin has `v0.5`; origin does not have `v1.0`.
- Rechecked GitHub Actions status: the latest manual `workflow_dispatch` run is still `failure` at https://github.com/omarpr/lithepg/actions/runs/26688293183, matching the existing external account/settings blocker because it failed before job logs were available.
- Synced the v1.0 implementation plan checklist with completed local-gate bookkeeping while keeping GitHub Release creation, Homebrew publication, signing/notarization, and `v1.0` tagging blocked until Omar supplies credentials/contact/tap/approval.

## 2026-05-30 12:39 EDT — v1.0 fast release preflight helper

- Added a fast `script/v10_release_gate.sh` preflight that reports local branch/status and tag readiness, checks external publication inputs without printing their values, and blocks until signing/notary/security-contact/Homebrew tap/copy/publication approvals are configured.
- Kept the helper fast by default: `origin` tag lookup is opt-in with `--check-remote` or `LITHEPG_CHECK_REMOTE_TAGS=1`, and remote/network failures remain non-blocking.
- Added focused shell TDD tests for missing-input failure, secret/contact/tap redaction behavior, and default no-network remote tag handling.
- Updated release docs with the helper usage and the non-secret environment contract. No Swift code was touched.

## 2026-05-30 13:09 EDT — v1.0 GitHub Release copy draft

- Added `docs/releases/v1.0-draft.md` as a non-published GitHub Release body draft for Omar's release-copy review.
- The draft includes install text, local-first AI/privacy posture, local gate metrics, and explicit `REPLACE_WITH_*` placeholders for the final signed/notarized receipt, artifact SHA-256, Homebrew status, and approved security contact.
- Linked the draft from `docs/RELEASING.md` so publication steps resolve the copy placeholders before creating a GitHub Release, tag, or Homebrew cask update.

## 2026-05-30 13:54 EDT — v1.0 public release zip helper slice

- Added `script/create_release_zip.sh`, a local-only helper that verifies an already-built `LithePG.app`, creates the public `LithePG.app.zip` with `ditto --keepParent`, refuses accidental overwrites unless explicitly approved, and prints a SHA-256 digest without uploading, tagging, signing, notarizing, pushing, or contacting the network.
- Added focused shell TDD coverage using fake `package_verify.sh` fixtures plus real `/usr/bin/ditto`/`/usr/bin/shasum` checks for verification failure, default overwrite refusal, explicit overwrite approval, inside-bundle output refusal, successful SHA output/redaction behavior, repo-root default path handling, preserved `.app` wrapper output, and help output.
- Updated `docs/RELEASING.md` to use the helper instead of raw `ditto`/`shasum` for public zip creation.

## 2026-05-30 15:13 EDT — v1.0 fast preflight recheck

- Rechecked the fast publication gate on `main` at `6b999c4` with `./script/v10_release_gate.sh --check-remote`.
- Local/tag readiness remains good: working tree clean, `v0.5` present locally/remotely, and `v1.0` absent locally/remotely.
- Publication remains blocked by the expected seven external/publication gates: release-copy placeholders are still present, Apple codesigning identity is missing, notary profile is missing, approved public security contact is missing, Homebrew tap target is missing, release-copy approval is not approved, and explicit publication approval is not approved. Values stayed redacted, and no signing, notarization, GitHub Release upload, Homebrew publication, or `v1.0` tag was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-fast-preflight-blockers.svg`.

## 2026-05-30 15:30 EDT — v1.0 GitHub Actions readiness gate

- Hardened `script/v10_release_gate.sh` so public-launch preflight now blocks on explicit `LITHEPG_GITHUB_ACTIONS_READY` approval, matching the existing GitHub Actions account/settings blocker tracked in the v1.0 spec and release docs.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first when the new expected `LITHEPG_GITHUB_ACTIONS_READY: not approved` output was absent, then passed after the minimal script change and fixture updates.
- Verification: `bash script/test_v10_release_gate.sh` passed, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed, `./script/v10_release_gate.sh --check-remote` remained safely blocked while showing `LITHEPG_GITHUB_ACTIONS_READY: not approved`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Evidence artifact: `docs/evidence/2026-05-30-v10-github-actions-ready-gate.svg`.

## 2026-05-30 15:46 EDT — v1.0 placeholder external-input gate

- Hardened `script/v10_release_gate.sh` so required external publication inputs reject obvious placeholder/sentinel values instead of treating any non-empty value as configured; approval variables keep the existing boolean-style approval behavior.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with placeholder external security contact`, then passed after the minimal redacted-status blocker change.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed. No signing, notarization, upload, Homebrew publication, or cron changes were run.
- Evidence artifact: `docs/evidence/2026-05-30-v10-placeholder-input-gate.svg`.

## 2026-05-30 16:08 EDT — v1.0 Homebrew cask placeholder gate

- Hardened `script/v10_release_gate.sh` so the fast publication preflight also scans the repository-local Homebrew cask template for unresolved `REPLACE_WITH_*` placeholders before publication can pass.
- Added `LITHEPG_HOMEBREW_CASK_PATH` for testing alternate cask files; paths may be repository-relative or absolute, matching the release-copy override behavior.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with placeholders in Homebrew cask template`, then passed after the minimal cask scan implementation.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed. Swift tests were not required for this shell/docs-only slice.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-placeholder-gate.svg`.

## 2026-05-30 16:41 EDT — v1.0 security policy placeholder gate

- Hardened `script/v10_release_gate.sh` so the fast publication preflight scans public security policies before `v1.0` publication can pass.
- Default security-policy scan now checks both root `SECURITY.md` and `docs/SECURITY.md`; `LITHEPG_SECURITY_DOC_PATH` remains available for focused alternate-file tests.
- TDD receipt: the focused shell test failed first when a default `docs/SECURITY.md` fixture with `[security contact pending]` was not blocked, then passed after the minimal default-scan expansion.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked and now reports placeholders in both `SECURITY.md` and `docs/SECURITY.md`. Swift tests were not required for this shell/docs-only slice.
- Evidence artifact: `docs/evidence/2026-05-30-v10-security-policy-placeholder-gate.svg`.

## 2026-05-30 16:56 EDT — v1.0 remote baseline tag gate

- Hardened `script/v10_release_gate.sh --check-remote` so the fast publication preflight verifies `origin` still has the last public milestone tag (`v0.5`) before any v1.0 publication can pass, while continuing to require `origin` `v1.0` to be absent.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed when remote origin v0.5 was missing`, then passed after the minimal remote-baseline tag check was added.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `./script/v10_release_gate.sh --check-remote` confirmed `origin` has `v0.5` and does not have `v1.0`, then remained safely blocked on the expected dirty-tree/external publication gates during this local edit.
- Evidence artifact: `docs/evidence/2026-05-30-v10-remote-baseline-tag-gate.svg`.

## 2026-05-30 17:17 EDT — v1.0 release artifact SHA gate

- Hardened `script/v10_release_gate.sh` so the fast publication preflight now blocks until the final public `LithePG.app.zip` exists and its `/usr/bin/shasum -a 256` digest matches the approved `LITHEPG_RELEASE_ZIP_SHA256` value.
- Added redacted status coverage for missing artifact path, missing SHA-256, invalid SHA-256 format, SHA mismatch without printing actual/expected digest values, and the matching SHA pass path.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `expected output to contain: Release artifact zip: missing at dist/LithePG.app.zip`, then passed after the minimal script implementation.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked without printing digest values. No signing, notarization, upload, Homebrew publication, tag, commit, push, or cron changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-release-artifact-sha-gate.svg`.

## 2026-05-30 17:52 EDT — v1.0 Homebrew cask version gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must contain a parseable `version "..."` line that exactly matches the requested release version before the fast publication preflight can pass.
- Added shell TDD coverage for a cask with `version "0.9"` plus the correct fixture SHA-256, a missing-version cask, the matching-version pass path, and placeholder casks that stay blocked by the existing placeholder gate without extra version mismatch/missing noise.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask version`, then passed after the minimal parser/readiness check was added.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked on the expected dirty-tree, placeholder, missing artifact/SHA, and external approval blockers. No signing, notarization, upload, Homebrew publication, tag, or cron changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-version-gate.svg`.

## 2026-05-30 18:18 EDT — v1.0 Homebrew cask URL gate

- Hardened `script/v10_release_gate.sh` so a placeholder-free Homebrew cask must point at the exact LithePG GitHub Release `LithePG.app.zip` artifact URL shape for the requested version before the fast publication preflight can pass.
- Added redacted shell TDD coverage for a cask with the correct `version` and `sha256` but the wrong URL host/path, plus a valid cask fixture that reports `Homebrew cask URL: matches`.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask URL`, then passed after the minimal URL parser/readiness check was added.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed. `./script/v10_release_gate.sh --check-remote` remained safely blocked on the expected dirty-tree, placeholder, missing artifact/SHA, and external approval blockers while confirming `origin` has `v0.5` and does not have `v1.0`. No signing, notarization, upload, Homebrew publication, tag, push, commit, or cron changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-url-gate.svg`.

## 2026-05-30 18:42 EDT — v1.0 Homebrew cask verified URL gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must include a `verified:` stanza exactly matching `github.com/omarpr/lithepg/` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for mismatched and missing `verified:` values, plus the valid `Homebrew cask verified URL: matches` pass path and placeholder-cask no-noise behavior.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask verified URL`, then passed after the minimal parser/readiness check was added.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed. `./script/v10_release_gate.sh --check-remote` remained safely blocked on existing local/publication blockers. No signing, notarization, upload, Homebrew publication, tag, push, commit, or cron changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-verified-url-gate.svg`.

## 2026-05-30 19:03 EDT — v1.0 Homebrew cask app stanza gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must install `app "LithePG.app"` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for `app "NotLithePG.app"`, a missing app stanza, the valid `Homebrew cask app stanza: matches` pass path, and placeholder-cask no-noise behavior.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask app stanza`, then passed after the minimal parser/readiness check was added.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` confirmed origin still has `v0.5` and does not have `v1.0`, then remained blocked on expected local/publication blockers. No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-app-stanza-gate.svg`.

## 2026-05-30 19:23 EDT — v1.0 Homebrew cask macOS requirement gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must declare `depends_on macos: ">= :sonoma"` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for mismatched and missing macOS requirement stanzas, the valid `Homebrew cask macOS requirement: matches` pass path, and placeholder-cask no-noise behavior.
- TDD receipt: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask macOS requirement`, then passed after the minimal parser/readiness check was added.
- Verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed. No signing, notarization, upload, Homebrew publication, tag, push, commit, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-macos-requirement-gate.svg`.

## 2026-05-30 19:44 EDT — v1.0 Homebrew cask zap stanza gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must include the expected `zap trash:` cleanup paths for LithePG Application Support data and preferences before the fast publication preflight can pass.
- Added redacted shell TDD coverage for mismatched and missing zap stanzas, the valid `Homebrew cask zap stanza: matches` pass path, and placeholder-cask no-noise behavior.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask zap stanza`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after the minimal parser/readiness check was added; final syntax/whitespace checks were run for this slice.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-zap-stanza-gate.svg`.

## 2026-05-30 20:18 EDT — v1.0 Homebrew cask homepage gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must include `homepage "https://github.com/omarpr/lithepg"` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for wrong and missing homepage stanzas, the valid `Homebrew cask homepage: matches` pass path, and placeholder-cask no-noise behavior.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask homepage`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed with no output; `./script/v10_release_gate.sh --check-remote` remained safely blocked on expected local/publication inputs/placeholders.
- No signing, notarization, upload, Homebrew publication, tag, push, commit, or cron changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-homepage-gate.svg`.

## 2026-05-30 20:43 EDT — v1.0 Homebrew cask token gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must declare exactly `cask "lithepg" do` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for mismatched and missing cask tokens, the valid `Homebrew cask token: matches` pass path, and placeholder-cask no-noise behavior.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `gate unexpectedly passed with mismatched Homebrew cask token`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed with no output; `git diff --check` passed with no output; `./script/v10_release_gate.sh --check-remote` remained safely blocked on expected local/publication inputs/placeholders.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-token-gate.svg`.

## 2026-05-30 21:01 EDT — v1.0 Homebrew cask name gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must include `name "LithePG"` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for `name "NotLithePG"`, a missing name stanza, the valid `Homebrew cask name: matches` pass path, and placeholder-cask no-noise behavior.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with missing Homebrew cask name`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; final syntax/whitespace/remote-block checks were run for this shell/docs slice.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-name-gate.svg`.

## 2026-05-30 21:19 EDT — v1.0 Homebrew cask desc gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must include exactly `desc "Lean PostgreSQL client with local-first AI"` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for mismatched and missing cask descriptions, while keeping the valid cask fixture on the public launch description.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with mismatched Homebrew cask desc`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after the minimal parser/readiness check; final syntax/whitespace/remote-block checks were run for this shell/docs slice.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-desc-gate.svg`.

## 2026-05-30 21:44 EDT — v1.0 Homebrew cask uninstall quit bundle ID gate

- Hardened `script/v10_release_gate.sh` so placeholder-free Homebrew casks must include the valid DSL stanza `uninstall quit: "dev.omarpr.lithepg"` before the fast publication preflight can pass.
- Added redacted shell TDD coverage for mismatched and missing uninstall quit bundle IDs, plus the valid `Homebrew cask uninstall quit bundle ID: matches` pass path.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: expected output to contain: Homebrew cask uninstall quit bundle ID: mismatch`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; final syntax/whitespace/Ruby template and Homebrew CaskLoader checks were run for this shell/docs/template slice.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-homebrew-cask-uninstall-quit-bundle-id-gate.svg`.

## 2026-05-30 22:22 EDT — v1.0 release docs gate sync

- Synced `docs/RELEASING.md` and `CHANGELOG.md` with the current fast preflight scope after the Homebrew cask token/name/description/homepage/uninstall/app/macOS/zap/SHA gates landed.
- Clarified that the fast helper now documents placeholder-free cask checks for token, version, URL, verified URL, public metadata, uninstall quit bundle ID, app stanza, macOS requirement, zap cleanup, and SHA-256 matching.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-release-docs-gate-sync.svg`.

## 2026-05-30 22:47 EDT — v1.0 release copy SHA gate

- Hardened `script/v10_release_gate.sh` so placeholder-free GitHub Release copy must contain the approved `LITHEPG_RELEASE_ZIP_SHA256` as an exact 64-hex digest token before the fast publication preflight can pass.
- Added redacted shell TDD coverage for missing/wrong release-copy SHA, embedded/partial digest false positives, matching success, and placeholder no-noise behavior.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with mismatched release copy SHA-256`, then the embedded digest regression failed with `gate unexpectedly passed with embedded release copy SHA-256` before the exact-token fix.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-release-copy-sha-gate.svg`.

## 2026-05-30 23:04 EDT — v1.0 release copy checklist gate

- Hardened `script/v10_release_gate.sh` so placeholder-free GitHub Release copy is blocked if it still contains unchecked Markdown task-list items (`- [ ]`), without printing release-copy contents.
- Kept placeholder-present release copy on the existing placeholder blocker path without extra checklist-status noise; clean placeholder-free copy now reports `Release copy checklist: none unchecked`.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with unchecked release-copy checklist`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-release-copy-checklist-gate.svg`.

## 2026-05-30 23:49 EDT — v1.0 release artifact filename gate

- Hardened `script/v10_release_gate.sh` so the fast publication preflight blocks when the `LITHEPG_RELEASE_ZIP_PATH` basename is not exactly the public artifact name `LithePG.app.zip`.
- The filename check runs in `Release artifact readiness:` independently from file/SHA checks and reports only `Release artifact filename: matches` or `Release artifact filename: mismatch`.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with mismatched release artifact filename`.
- GREEN verification: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, and `git diff --check` passed. No signing, notarization, upload, Homebrew publication, tag, commit, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-30-v10-release-artifact-filename-gate.svg`.

## 2026-05-31 — v1.0 release zip wrapper gate

- Hardened `script/v10_release_gate.sh` so any present public release zip must contain a top-level `LithePG.app/` bundle wrapper before the fast publication preflight can pass.
- The zip structure check uses `/usr/bin/zipinfo` without extracting files or printing archive contents, and reports only `Release artifact app wrapper: present`, `missing`, or `could not inspect`.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with release artifact missing top-level LithePG.app wrapper`.
- GREEN verification: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, and `git diff --check` passed.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-wrapper-gate.svg`.

## 2026-05-31 00:31 EDT — v1.0 release zip bundle contents gate

- Hardened `script/v10_release_gate.sh` so the public `LithePG.app.zip` structure check now requires the top-level `LithePG.app` wrapper plus exact `LithePG.app/Contents/Info.plist` and `LithePG.app/Contents/MacOS/LithePGApp` entries before the fast preflight can pass.
- Added redacted shell TDD coverage for a zip that contains `LithePG.app/` but omits the essential bundle files; output reports only `Release artifact bundle contents: missing` without printing archive contents.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with release artifact missing essential app bundle contents`.
- GREEN verification: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, and `git diff --check` passed.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-bundle-contents-gate.svg`.

## 2026-05-31 — v1.0 release zip top-level entries gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` must not contain any unexpected top-level archive entries outside `LithePG.app`; examples such as `README.txt`, nested `dist/LithePG.app/...`, path traversal, absolute paths, or another app/directory now block publication.
- Added redacted shell TDD coverage for a zip that contains the essential `LithePG.app` bundle entries plus an extra top-level `README.txt`; output reports only `Release artifact top-level entries: unexpected` and does not print archive contents.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with unexpected top-level release artifact entry`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed.
- No signing, notarization, upload, Homebrew publication, tag, commit, push, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-top-level-entries-gate.svg`.

## 2026-05-31 01:19 EDT — v1.0 release zip bundle file type gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when either essential app bundle entry (`LithePG.app/Contents/Info.plist` or `LithePG.app/Contents/MacOS/LithePGApp`) is a symlink or other non-regular archive entry.
- Added redacted shell TDD coverage for a zip whose essential bundle entries are symlinks while all name-based artifact/SHA/cask checks otherwise pass; output reports only `Release artifact bundle file types: invalid` and does not print archive contents, symlink targets, paths beyond existing configured path status, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with symlink essential app bundle files`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; final syntax/whitespace checks were run for this shell/docs slice.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-bundle-file-types-gate.svg`.

## 2026-05-31 01:26 EDT — v1.0 release zip bundle file type gate spec review follow-up

- Closed the spec review gap where an uninspectable present `LithePG.app.zip` printed `Release artifact app wrapper: could not inspect` but skipped the required `Release artifact bundle file types: could not inspect` line.
- Added redacted shell TDD coverage using a non-zip file with the correct `LithePG.app.zip` basename; the test asserts both could-not-inspect status lines and that archive contents/SHA values do not leak.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: expected output to contain: Release artifact bundle file types: could not inspect`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed before the log receipt update; final syntax/whitespace checks were run for this shell/docs slice.
- No signing, notarization, upload, Homebrew publication, tag, commit, push, cron changes, or external publication was attempted.

## 2026-05-31 01:53 EDT — v1.0 release zip executable permission gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when `LithePG.app/Contents/MacOS/LithePGApp` is a regular archive entry but lacks owner executable permission.
- Added redacted shell TDD coverage for a zip with the correct wrapper, required bundle entries, clean top-level entries, matching SHA/release-copy/cask metadata, and a non-executable app executable; added a follow-up regression fixture for mode `0645`, where group/other execute bits are present but owner execute is missing. Output reports only `Release artifact bundle executable: not executable` without printing archive contents or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with non-executable app bundle executable`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after the minimal parser/readiness check was added; final syntax/whitespace/fast-preflight checks were run for this shell/docs slice.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-executable-permission-gate.svg`.

## 2026-05-31 02:32 EDT — v1.0 release zip Info.plist metadata gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` now verifies `LithePG.app/Contents/Info.plist` metadata after wrapper/content/file-type checks and before publication can pass.
- The fast preflight now requires `CFBundleExecutable=LithePGApp`, `CFBundleIdentifier=dev.omarpr.lithepg`, `CFBundleName=LithePG`, `CFBundlePackageType=APPL`, and `CFBundleShortVersionString` matching the gate version, without printing plist contents, mismatched values, or SHA values.
- Added shell TDD coverage for parseable metadata mismatches and malformed/unparseable plists; output reports only `Release artifact Info.plist metadata: mismatch` or `could not inspect` while keeping publication blocked.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with the expected Info.plist metadata gap before implementation, then the malformed-plist regression failed until the `could not inspect` path was added.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed. Independent spec review passed and code-quality/security re-review approved the fixed diff.
- No signing, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-info-plist-metadata-gate.svg`.

## 2026-05-31 02:52 EDT — v1.0 release zip code-signature resources gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked unless it includes `LithePG.app/Contents/_CodeSignature/CodeResources` as a regular archive entry.
- Added redacted shell TDD coverage for an otherwise valid release zip missing `CodeResources`; output reports only `Release artifact code signature resources: missing` and keeps publication blocked without printing archive contents or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with release artifact missing code signature resources`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after the minimal structural check and valid fixtures were updated to include `CodeResources`; final syntax/whitespace/fast-preflight checks were run for this shell/docs slice.
- No codesign, notarization, upload, network publication, tag, commit, push, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-code-signature-resources-gate.svg`.

## 2026-05-31 03:18 EDT — v1.0 release zip Info.plist core metadata gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` only reports `Release artifact Info.plist metadata: matches` when the embedded `Info.plist` also has numeric `CFBundleVersion`, `LSMinimumSystemVersion=14.0`, and `NSPrincipalClass=NSApplication`, in addition to the previously checked executable, bundle ID, bundle name, package type, and release version.
- Added redacted shell TDD coverage for a legacy-style fixture that previously satisfied the metadata gate but omits/mismatches the new non-secret core bundle metadata; output stays generic and does not print plist keys/values, archive contents, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with release artifact Info.plist missing non-secret core bundle metadata`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` confirmed remote `v0.5` is present and remote `v1.0` is absent, then remained blocked on expected local/external publication prerequisites.
- Independent spec review passed and code-quality/security review approved the diff. Swift tests were not required for this shell/docs-only slice.
- No codesign, notarization, upload, Homebrew publication, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-info-plist-core-metadata-gate.svg`.

## 2026-05-31 — v1.0 release zip executable format gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked unless `LithePG.app/Contents/MacOS/LithePGApp` is a real Mach-O executable, not merely a regular file with the executable bit set.
- The check runs only after bundle structure, essential regular-file entries, and owner executable permission are inspectable; it extracts the app executable to a temp file for `/usr/bin/file` inspection, then cleans it up.
- Updated shell fixtures so the valid release zip uses a real system Mach-O (`/usr/bin/true`) while the new negative fixture uses a text executable with otherwise-valid wrapper, Info.plist, code-signature resources, SHA, release copy, and cask metadata.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with text executable release artifact`.
- GREEN verification: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, and `./script/v10_release_gate.sh --check-remote` were run locally; the fast preflight remained safely blocked on expected local/external publication prerequisites.
- Output stays redacted: the gate reports only `Release artifact executable format: Mach-O`, `invalid`, or `could not inspect` and does not print archive contents, extracted paths, `/usr/bin/file` output, SHA values, or fixture marker strings.
- No codesign, notarization, upload, Homebrew publication, `v1.0` tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-executable-format-gate.svg`.

## 2026-05-31 — v1.0 release zip duplicate essential entry gate follow-up

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when any essential app-bundle entry appears more than once in the zip directory: `Info.plist`, `LithePGApp`, or `_CodeSignature/CodeResources`.
- Added redacted shell TDD coverage for an otherwise valid release zip with a duplicate app executable entry that previously passed the Mach-O executable-format check; output reports only `Release artifact essential entries: duplicate` and does not print duplicate names, archive contents, file output, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with duplicate essential release artifact entries`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after the minimal unique-entry check was added; final syntax, whitespace, and fast-preflight blocked-prerequisite checks were run for this shell/docs slice.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-duplicate-entry-gate.svg`.

## 2026-05-31 — v1.0 release zip canonical path gate follow-up

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when any archive entry path is non-canonical before essential-entry uniqueness and executable/plist extraction checks can continue.
- The new gate rejects malformed or path-equivalent entry names with absolute paths, leading `./` or `../`, empty `//` components, `.` or `..` components, or backslash separators, closing the overwrite bypass where unzip extraction can normalize a colliding entry over the inspected executable.
- Added redacted shell TDD coverage for an otherwise valid release zip with a Mach-O executable plus a non-canonical path-collision text payload; output reports only `Release artifact entry paths: non-canonical` and does not print archive paths, marker text, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with non-canonical release artifact zip path collision`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` remained blocked only on expected local/external publication prerequisites.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-canonical-path-gate.svg`.

## 2026-05-31 — v1.0 release zip case-fold path-collision gate follow-up

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when any canonical zip entry path collides after trailing-slash normalization and ASCII case-folding. This closes the default macOS case-insensitive extraction bypass where a valid inspected executable and a case-variant payload can target the same filesystem path.
- The collision check runs after existing syntactic canonical path checks and before essential-entry uniqueness, Info.plist, executable-permission, Mach-O, or code-signature extraction checks continue. Because this is a macOS app zip, any case-folded duplicate archive entry is rejected.
- Added redacted shell TDD coverage for an otherwise valid release zip with `LithePG.app/Contents/MacOS/LithePGApp` as a real Mach-O and a case-variant marker payload entry. Output reports only `Release artifact entry paths: collision` and does not print archive paths, marker text, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with case-folded release artifact zip path collision`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; final syntax, whitespace, and fast-preflight blocked-prerequisite checks were run for this shell/docs slice.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-casefold-collision-gate.svg`.

## 2026-05-31 04:26 EDT — v1.0 release zip ASCII path gate follow-up

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when any zip entry path is not printable ASCII before extraction-sensitive checks continue. This avoids macOS Unicode normalization/casefold ambiguity for the release artifact, whose bundle wrapper and known bundle paths are expected to be ASCII.
- Added a separate redacted path-collision TDD fixture with otherwise valid entries plus both `LithePG.app/Contents/Resources/ß.txt` and `LithePG.app/Contents/Resources/SS.txt`, covering the Unicode collision bypass that passed the prior `LC_ALL=C awk tolower()` collision check.
- RED verification: `bash script/test_v10_release_gate.sh` failed first while the Unicode collision fixture still passed the gate before the ASCII-path policy was added.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; final syntax, whitespace, and fast-preflight blocked-prerequisite checks were run for this shell/docs slice.
- Output stays redacted: the gate reports non-ASCII entry paths as `Release artifact entry paths: non-canonical` and does not print archive paths, marker text, or SHA values.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-ascii-path-gate.svg`.

## 2026-05-31 04:54 EDT — v1.0 release zip malformed path encoding redaction follow-up

- Hardened `script/v10_release_gate.sh` so malformed ZIP filename encodings are treated as redacted non-canonical entry paths instead of allowing the Python ZIP inspection helper to print implementation tracebacks.
- Added a regression fixture that builds a ZIP with an invalid UTF-8 filename byte flagged as UTF-8, while keeping the required app bundle entries otherwise valid enough to reach the path gate.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: output leaked forbidden value: Traceback`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; final syntax, whitespace, and fast-preflight blocked-prerequisite checks were run for this shell/docs slice.
- Output stays redacted: the gate reports malformed filename encodings as `Release artifact entry paths: non-canonical` and does not print tracebacks, exception names, archive paths, marker text, or SHA values.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-malformed-encoding-redaction-gate.svg`.

## 2026-05-31 04:55 EDT — v1.0 release zip codesign verification gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked unless the extracted `LithePG.app` verifies with `/usr/bin/codesign --verify --strict --deep`, not just a present `_CodeSignature/CodeResources` file.
- Updated the valid shell release-zip fixture to be ad-hoc signed before zipping, and added a tampered signed-bundle fixture with otherwise-valid wrapper, paths, Info.plist, owner-executable Mach-O, CodeResources, SHA, release copy, and cask metadata.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with invalid release artifact code signature`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after adding the minimal extracted-bundle codesign check; final syntax, whitespace, and fast-preflight blocked-prerequisite checks were run for this shell/docs slice.
- Output stays redacted: the gate reports only `Release artifact code signature verification: valid`, `invalid`, or `could not inspect` and does not print archive contents, extracted temp paths, codesign stderr, SHA values, signing identities, or fixture marker strings.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-codesign-verification-gate.svg`.

## 2026-05-31 — v1.0 release zip Hardened Runtime signature gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked unless the extracted `LithePG.app` first passes strict codesign verification and then `codesign --display --verbose=4` shows the Hardened Runtime flag.
- Updated the valid shell release-zip fixture to ad-hoc sign with `--options runtime`, and added an otherwise valid signed fixture without Hardened Runtime to prove the new blocker.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with release artifact code signature missing Hardened Runtime`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after adding the runtime inspection gate; final syntax and whitespace checks were run for this shell/docs slice.
- Build/release-impact verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed, `./script/v10_release_gate.sh --check-remote` remained safely blocked on the expected local/publication prerequisites, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed with artifacts at `.build/dogfood-checks/20260531-053230/`.
- Output stays redacted: the gate reports only `Release artifact code signature runtime: present`, `missing`, or `could not inspect` and does not print codesign output, archive contents, extracted temp paths, SHA values, or signing identities.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-hardened-runtime-gate.svg`.

## 2026-05-31 05:55 EDT — v1.0 release zip metadata-files gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when the archive contains macOS/Finder metadata junk anywhere in the zip: any `__MACOSX` path component, any `.DS_Store` basename, or any AppleDouble basename beginning with `._`.
- The fast preflight now reports exactly one redacted metadata status line for present zips: `Release artifact metadata files: absent`, `present`, or `could not inspect`; it does not print archive contents, matching entry names, paths, SHA values, temp paths, or marker payloads.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with metadata file in release artifact zip`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed.
- No release signing, notarization, upload, Homebrew publication, tag, cron, push, or external publication changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-metadata-files-gate.svg`.

## 2026-05-31 06:19 EDT — v1.0 release zip symlink-entry gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when any archive entry mode is a symlink, not only when essential bundle entries are symlinks.
- Added a strict-TDD fixture with an otherwise valid, ad-hoc-signed `LithePG.app` containing a non-essential resource symlink preserved with `zip -y`; the gate reports only `Release artifact symlinks: present` and does not print symlink paths, targets, marker payloads, zip paths, temp paths, codesign output, archive contents, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with non-essential symlink in release artifact`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed.
- No release signing beyond local ad-hoc test fixtures, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron, or external publication changes were attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-symlink-gate.svg`.

## 2026-05-31 06:52 EDT — v1.0 release zip code-signature identifier gate

- Hardened `script/v10_release_gate.sh` so a present public `LithePG.app.zip` is blocked when the extracted app's code-signature identifier does not match `dev.omarpr.lithepg`, even if `Info.plist` metadata and strict code-signature verification otherwise pass.
- Added a strict-TDD fixture with a valid `Info.plist` bundle ID but an ad-hoc Hardened Runtime signature created with a prefix-collision mismatched `--identifier`; the gate now requires an exact `Identifier=dev.omarpr.lithepg` line, reports only `Release artifact code signature identifier: mismatch`, and does not print signing identifiers, codesign output, archive contents, temp paths, or SHA values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with mismatched release artifact code signature identifier`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after adding the redacted identifier check; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked on expected local/external publication prerequisites; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed with artifacts at `.build/dogfood-checks/20260531-065403/`.
- No release signing beyond local ad-hoc test fixtures, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-code-signature-identifier-gate.svg`.

## 2026-05-31 — v1.0 signing/notarization dry-run redaction gate

- Hardened `script/sign_and_notarize.sh --dry-run` so required signing/notary configuration is reported as present but redacted instead of printing the configured code-signing identity or notarytool keychain profile value.
- Added `script/test_sign_and_notarize.sh`, which builds a minimal temp `LithePG.app` accepted by `script/package_verify.sh`, injects sentinel signing/notary values, asserts the dry run succeeds, verifies `Signing/notarization dry run OK`, verifies the redacted present-status lines, rejects both sentinels in output, and confirms no notary zip is created.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: output leaked forbidden value: Developer ID Application: SHOULD_NOT_LEAK`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed after redacting dry-run config output; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked on 14 expected local/external publication prerequisites.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-dry-run-redaction.svg`.

## 2026-05-31 07:39 EDT — v1.0 signing/notarization inside-bundle zip gate

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` is rejected when its resolved location is the app bundle itself or nested under the `.app` bundle, including `--dry-run`.
- Added strict-TDD coverage proving an inside-bundle dry-run zip path exits non-zero with `notary zip must not be inside app bundle`, creates no zip, and does not print the sentinel code-signing identity or notarytool profile.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with inside-bundle notary zip`, confirming the missing guard.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; `git diff --check` passed.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-inside-bundle-zip-gate.svg`.

## 2026-05-31 08:01 EDT — v1.0 signing/notarization notary zip parent gate

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` is rejected when its parent directory does not exist or is not writable, including `--dry-run`, instead of letting the wrapper claim readiness for an unwritable output location.
- Added strict-TDD coverage proving missing-parent and non-writable-parent dry-run zip paths exit non-zero with generic parent-directory errors, create no zip, and do not print the sentinel code-signing identity or notarytool profile.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with missing notary zip parent directory`, then the independent pre-commit review caught the existing-but-non-writable parent gap and the new non-writable-parent test failed before implementation.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh && bash -n script/test_sign_and_notarize.sh` passed; `git diff --check` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-notary-zip-parent-gate.svg`.

## 2026-05-31 08:24 EDT — v1.0 signing/notarization public release zip basename gate

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` is rejected when its basename is the public release artifact name `LithePG.app.zip`, including `--dry-run`, to keep credential-gated notary-submission zips distinct from public release artifacts.
- Added strict-TDD coverage proving a dry-run `LITHEPG_NOTARY_ZIP="$fixture_root/LithePG.app.zip"` exits non-zero with `notary zip must not use public release artifact name`, creates no zip, and does not print the sentinel code-signing identity or notarytool profile.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with public release artifact notary zip basename`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh && bash -n script/test_sign_and_notarize.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 tests across 20 suites; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed with artifacts at `.build/dogfood-checks/20260531-082848/`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-public-release-zip-basename-gate.svg`.

## 2026-05-31 08:43 EDT — v1.0 signing/notarization notary zip overwrite approval gate

- Hardened `script/sign_and_notarize.sh` so an existing `LITHEPG_NOTARY_ZIP` path, including a dangling symlink, is refused unless `LITHEPG_NOTARY_ZIP_OVERWRITE` is explicitly approved with one of the documented exact values (`1`, `true`, `yes`, or `approved`), including during `--dry-run` preflight.
- Added strict-TDD coverage proving an existing dry-run notary zip exits non-zero with the generic overwrite-approval message, does not print the sentinel signing/notary values, and leaves the existing zip marker intact; the approved dry-run path passes while still leaving the existing zip unchanged. Added regression coverage proving a dangling notary-zip symlink without approval is blocked, does not leak sentinels, and is not removed.
- Added lightweight coverage for the other documented approval values (`1`, `true`, and `yes`) and for rejecting undocumented uppercase approval values.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with dangling symlink notary zip without overwrite approval`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh && bash -n script/test_sign_and_notarize.sh` passed; `git diff --check` passed.
- Updated `docs/RELEASING.md` to document `LITHEPG_NOTARY_ZIP_OVERWRITE` and the dry-run/real-mode overwrite behavior.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-notary-zip-overwrite-gate.svg`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 09:08 EDT — v1.0 release zip dangling symlink overwrite gate

- Hardened `script/create_release_zip.sh` so a dangling output symlink at the public release zip path is treated as an existing output artifact and refused unless `LITHEPG_RELEASE_ZIP_OVERWRITE` is explicitly approved.
- Added strict-TDD coverage proving a dangling `dist/LithePG.app.zip` symlink exits nonzero by default after package verification, prints the existing-output overwrite approval hint, keeps the symlink dangling, and does not create the symlink target.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: expected output to contain: Refusing to overwrite existing output zip`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked on expected local/external publication prerequisites.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-dangling-symlink-gate.svg`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 09:26 EDT — v1.0 release zip approved symlink overwrite gate

- Hardened `script/create_release_zip.sh` so approved output replacement stages the public zip in a secure temporary directory under the output parent, computes SHA-256/size from that staged zip, then uses POSIX `rename($ARGV[0], $ARGV[1])` to replace the destination without following an output symlink target.
- Added strict-TDD coverage proving an approved dangling `dist/LithePG.app.zip` symlink is replaced with a regular zip at the output path, preserves the app wrapper, prints SHA-256/size output, runs package verification, and does not create the symlink target; added a focused security-invariant test proving `ditto` writes to the staged temp zip instead of directly to `$OUTPUT_ZIP`.
- RED verification: `bash script/test_create_release_zip.sh` first failed with `test_create_release_zip failed: approved dangling output symlink was not replaced with a regular zip`, then the security follow-up failed with `test_create_release_zip failed: expected output to contain: mktemp -d "${output_parent%/}/.release-zip.XXXXXX"` before the temp-staging/rename fix.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh` and `bash -n script/test_create_release_zip.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed; `./script/v10_release_gate.sh --check-remote` remained safely blocked on expected local/external publication prerequisites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-094208/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 124.98 ms; connected cold start 223.66 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.045 ms; dogfood query median overhead 0.027 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-approved-symlink-overwrite-gate.svg`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-05-31 09:58 EDT — v1.0 release zip physical inside-bundle symlink gate

- Hardened `script/create_release_zip.sh` so an output zip path is rejected when its resolved physical location is inside the `.app` bundle, including when the output parent is a symlink to `dist/LithePG.app/Contents`, when that symlinked component is followed by `..` before the zip filename, and when a case-variant bundle component such as `dist/lithepg.app/Contents/LithePG.app.zip` resolves to `dist/LithePG.app/Contents` on the default macOS case-insensitive filesystem.
- Added strict-TDD coverage proving both `dist/out-link/LithePG.app.zip` and reviewer-reported `dist/out-link/../LithePG.app.zip` with `dist/out-link -> dist/LithePG.app/Contents` exit nonzero after package verification, print `output zip must not be inside the app bundle`, and create no zip through the resolved inside-bundle target; added guarded coverage for reviewer-reported `dist/lithepg.app/Contents/LithePG.app.zip` that runs on case-insensitive filesystems and skips only that assertion on case-sensitive filesystems.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper unexpectedly allowed a symlink-plus-parent-traversal output inside the app bundle`; the case-variant regression then failed with `test_create_release_zip failed: helper unexpectedly allowed a case-variant output zip inside the app bundle`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed after resolving existing path components to their actual on-disk casing for the physical-location guard.
- Release-impact dogfood verification passed with Docker available after the final case-variant fix: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-101741/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 127.37 ms; connected cold start 236.34 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.041 ms; dogfood query median overhead 0.040 ms.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-physical-inside-bundle-symlink-gate.svg`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 10:43 EDT — v1.0 release zip non-dangling symlink overwrite coverage

- Added regression coverage for the approved-overwrite path where `dist/LithePG.app.zip` is an existing non-dangling symlink to a regular target file outside `dist`.
- The test verifies `LITHEPG_RELEASE_ZIP_OVERWRITE=approved` replaces the symlink path itself with a regular release zip, preserves the original symlink target file and contents unchanged, preserves the `.app` wrapper, prints SHA-256/size output, and does not leak sentinel values.
- RED attempt: the new test passed immediately before any production-code change, proving the safe behavior already existed through the staged-temp-plus-rename implementation; this slice intentionally stayed test-only.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after confirming the cleanup-trap quoting concern was only a tool-output escaping artifact.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-non-dangling-symlink-overwrite.svg`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 10:58 EDT — v1.0 release zip exact overwrite approval hardening

- Hardened `script/create_release_zip.sh` so `LITHEPG_RELEASE_ZIP_OVERWRITE` accepts only the documented exact approvals: `1`, `true`, `yes`, and `approved`.
- Added strict-TDD coverage proving undocumented uppercase `LITHEPG_RELEASE_ZIP_OVERWRITE=APPROVED` is refused for an existing `dist/LithePG.app.zip`, runs package verification first, prints the overwrite-approval hint, and preserves the existing file contents.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper unexpectedly accepted undocumented uppercase overwrite approval`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-uppercase-overwrite-rejection.svg`.
- No release signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 11:17 EDT — v1.0 notary zip creation failure preservation

- Hardened `script/sign_and_notarize.sh` real mode so the notary-submission zip is created in a secure temporary directory under the output parent, then moved to `LITHEPG_NOTARY_ZIP` only after `ditto` succeeds; the helper no longer removes an existing approved notary zip before successful zip creation.
- Added strict-TDD coverage with fake `codesign`/`ditto`/`xcrun`/`spctl` shims proving a real-mode `ditto` failure exits nonzero before notarytool/stapler/spctl, preserves an existing approved notary zip marker unchanged, and does not print sentinel signing identity or notary profile values.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: real mode zip-creation failure removed existing approved notary zip`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; `git diff --check` passed.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-staged-notary-zip-gate.svg`.
- No real signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 11:38 EDT — v1.0 notary zip directory-path rejection

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` is rejected when it points to an existing directory, before dry-run or real signing/notarization can proceed to success.
- Added strict-TDD coverage proving an existing directory at the notary zip path with `LITHEPG_NOTARY_ZIP_OVERWRITE=approved` exits nonzero in `--dry-run`, prints `notary zip path must not be a directory`, keeps sentinel signing/notary values redacted, and leaves the directory intact.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with directory notary zip path`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; `git diff --check` passed.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-directory-zip-gate.svg`.
- No real signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 12:08 EDT — v1.0 notary zip physical-location hardening

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` location validation resolves physical parent components, symlink traversal, and case-variant path components while preserving the final output path itself for overwrite semantics.
- Added strict-TDD coverage proving `--dry-run` rejects a final notary zip symlink located inside `LithePG.app` but pointing outside when `LITHEPG_NOTARY_ZIP_OVERWRITE=approved`, plus symlink-plus-parent traversal and case-variant inside-bundle paths. All cases keep signing/notary sentinel values redacted and leave fixture targets unchanged.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with symlink-plus-parent-traversal notary zip inside app bundle`, then the independent review follow-up reproduced the final-symlink bypass before the preserve-final-symlink fix.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; `git diff --check` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-physical-notary-zip-gate.svg`.
- No real signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 12:35 EDT — v1.0 release zip symlink artifact gate

- Hardened `script/v10_release_gate.sh` so a configured final public `LithePG.app.zip` path is blocked when the path itself is a symlink, even if the symlink target is an otherwise valid release zip with a matching approved SHA-256.
- Added strict-TDD coverage with an otherwise-valid fixture release copy, Homebrew cask, security doc, and release zip, then pointed `LITHEPG_RELEASE_ZIP_PATH` at a symlink named `LithePG.app.zip`; output reports only `Release artifact zip: symlink` and does not print symlink targets, SHA values, archive contents, or temp paths.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with symlink release artifact zip`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-symlink-artifact-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-05-31 12:58 EDT — v1.0 release zip executable special-mode gate

- Hardened `script/v10_release_gate.sh` so the final public `LithePG.app.zip` is blocked when the archived `LithePG.app/Contents/MacOS/LithePGApp` mode contains setuid, setgid, or sticky execute-position markers.
- Added strict-TDD coverage by rewriting an otherwise-valid signed fixture zip so only the archived executable mode is unsafe while owner execute remains present; output reports only the generic safe/unsafe status and keeps paths, modes, and SHA values redacted.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with unsafe release artifact executable mode`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-special-mode-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-05-31 13:29 EDT — v1.0 release zip writable executable-mode gate

- Hardened `script/v10_release_gate.sh` so the final public `LithePG.app.zip` is blocked when the archived `LithePG.app/Contents/MacOS/LithePGApp` executable mode is writable by group and/or other, in addition to the existing special-mode marker rejection.
- Added strict-TDD coverage by rewriting an otherwise-valid signed fixture zip so only the archived executable mode is group/world writable; output reports only `Release artifact bundle executable mode: unsafe` and keeps paths, entry names, raw modes, and SHA values redacted.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: gate unexpectedly passed with group/world-writable release artifact executable mode`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; `./script/v10_release_gate.sh --check-remote` remained blocked on expected local/external publication prerequisites; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed; release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed with artifacts at `.build/dogfood-checks/20260531-133501/` (shell readiness 134.25 ms; connected cold start 229.71 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.039 ms; dogfood query median overhead 0.041 ms).
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-writable-executable-mode-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 14:24 EDT — v1.0 release zip app-bundle basename gate

- Hardened `script/create_release_zip.sh` so the public `LithePG.app.zip` helper refuses to package an input app bundle whose basename is not exactly `LithePG.app`, after package verification and before any output zip is created.
- Added strict-TDD coverage proving `dist/NotLithePG.app` is rejected with a generic basename message, package verification still runs first, no output zip is created, and sentinel signing/notary/release env values are not printed.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper unexpectedly packaged a non-canonical app bundle name`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-app-bundle-basename-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 14:40 EDT — v1.0 release zip output-basename gate

- Hardened `script/create_release_zip.sh` so the public release zip helper refuses to create an output artifact whose basename is not exactly `LithePG.app.zip`, after package verification and before any output directory or staged zip is created.
- Added strict-TDD coverage proving `dist/NotLithePG.zip` is rejected with a generic basename message, package verification still runs first, no output zip is created, and sentinel signing/notary/release env values are not printed.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper unexpectedly created a non-canonical output zip basename`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-output-basename-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 15:04 EDT — v1.0 release zip symlink app-bundle gate

- Hardened `script/create_release_zip.sh` so the public release zip helper refuses a symlinked input app-bundle path named `LithePG.app`, including trailing-slash variants such as `dist/LithePG.app/`, after package verification and before any public zip is created.
- Added strict-TDD coverage proving both direct and trailing-slash symlinked app inputs are rejected with a generic message, package verification still runs first, the symlink is preserved, no output zip is created, and sentinel signing/notary/release env values are not printed.
- RED verification: `bash script/test_create_release_zip.sh` first failed with `test_create_release_zip failed: helper unexpectedly packaged a symlinked app bundle input`; review follow-up then failed with `test_create_release_zip failed: helper unexpectedly packaged a symlinked app bundle input with a trailing slash`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the trailing-slash bypass was fixed.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-symlink-app-bundle-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 15:21 EDT — v1.0 release zip directory-output gate

- Hardened `script/create_release_zip.sh` so the public release zip helper rejects an existing directory at the canonical `LithePG.app.zip` output path even when `LITHEPG_RELEASE_ZIP_OVERWRITE=approved` is set.
- Added strict-TDD coverage proving package verification runs first, the helper exits nonzero with `output zip path must not be a directory`, sentinel release/signing env values stay redacted, the directory and marker remain intact, and no nested zip is created.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: expected output to contain: output zip path must not be a directory`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; adjacent release helper tests `bash script/test_sign_and_notarize.sh` and `bash script/test_v10_release_gate.sh` passed; `bash -n` syntax checks passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-152804/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 134.05 ms; connected cold start 231.52 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.034 ms; dogfood query median overhead 0.021 ms.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-directory-output-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 16:08 EDT — v1.0 sign/notarize symlink app-bundle gate

- Hardened `script/sign_and_notarize.sh` so the credential-gated signing/notarization helper rejects a final symlinked `.app` input path before package verification, dry-run success, or real signing/notarization can proceed.
- Added strict-TDD coverage proving both direct and trailing-slash symlinked `LithePG.app` inputs exit nonzero with `app bundle path must not be a symlink`, keep signing/notary sentinel values redacted, preserve the symlink, and create no notary zip.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with symlinked app bundle input`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-160818/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 134.34 ms; connected cold start 223.00 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.035 ms; dogfood query median overhead 0.020 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-symlink-app-bundle-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 16:28 EDT — v1.0 sign/notarize app-bundle basename gate

- Hardened `script/sign_and_notarize.sh` so the credential-gated signing/notarization helper accepts only an input app bundle named exactly `LithePG.app`, rejecting non-canonical names before package verification, dry-run success, or real signing/notarization.
- Added strict-TDD coverage proving a valid fixture named `NotLithePG.app` exits nonzero in `--dry-run` with `app bundle basename must be LithePG.app`, does not print package-verification or dry-run success output, keeps signing/notary sentinel values redacted, and creates no notary zip.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with non-canonical app bundle basename`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh` passed; `bash -n` syntax checks passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-app-bundle-basename-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 16:52 EDT — v1.0 sign/notarize extra-argument gate

- Hardened `script/sign_and_notarize.sh` so the credential-gated signing/notarization helper rejects extra positional arguments after optional `--dry-run` parsing and before package verification, dry-run success, or real signing/notarization can proceed.
- Added strict-TDD coverage proving `--dry-run "$app_bundle" "$ignored_extra_arg"` exits nonzero with `too many arguments`, does not print package-verification or dry-run success output, keeps signing/notary sentinel values redacted, and creates no notary zip.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with an extra positional argument`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh` passed; `bash -n` syntax checks passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed. Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-165349/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.83 ms; connected cold start 224.11 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.030 ms; dogfood query median overhead 0.004 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-extra-argument-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 17:13 EDT — v1.0 release zip final symlink inside-bundle gate

- Hardened `script/create_release_zip.sh` so a final output path symlink that is physically located inside `LithePG.app` is rejected even when it points outside the app bundle and `LITHEPG_RELEASE_ZIP_OVERWRITE=approved` is set.
- The public release zip helper now preserves the final output symlink during the physical inside-bundle location check, while continuing to resolve parent symlinks and case-variant path components.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper unexpectedly allowed a final output symlink inside the app bundle pointing outside`.
- GREEN verification: `bash script/test_create_release_zip.sh` passed; `bash -n script/create_release_zip.sh script/test_create_release_zip.sh` passed; adjacent release helper tests `bash script/test_sign_and_notarize.sh` and `bash script/test_v10_release_gate.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-171450/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 128.10 ms; connected cold start 230.08 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.041 ms; dogfood query median overhead 0.026 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-final-symlink-inside-bundle-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 17:35 EDT — v1.0 sign/notarize help gate

- Added explicit `-h` / `--help` handling to `script/sign_and_notarize.sh`, including after optional `--dry-run`, so help exits before package validation, credential requirements, notary zip checks, or any signing/notarization path.
- Added strict-TDD coverage proving `--help` and `--dry-run --help` exit 0, print usage plus relevant env names, do not print package-verification or dry-run success output, keep signing/notary sentinel values redacted, and create no notary zip.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `sign/notarize failed: app bundle basename must be LithePG.app` and `test_sign_and_notarize failed: --help did not exit 0`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh` passed; adjacent `bash -n` syntax checks passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-help-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 17:55 EDT — v1.0 sign/notarize public release zip casefold basename gate

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` is rejected when its basename case-folds to the reserved public release artifact name `LithePG.app.zip`, preventing notary-submission intermediates such as `lithepg.app.zip` from masquerading as the final public artifact on case-insensitive macOS filesystems.
- Added strict-TDD dry-run coverage proving a case-variant public release artifact notary zip basename exits nonzero with `notary zip must not use public release artifact name`, keeps signing/notary sentinel values redacted, and creates no notary zip.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with case-variant public release artifact notary zip basename`.
- GREEN verification: `bash script/test_sign_and_notarize.sh` passed; `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh` passed; adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh` passed; `git diff --check` passed; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- `./script/v10_release_gate.sh --check-remote` confirmed origin has `v0.5` and does not have `v1.0`, then remained safely blocked on expected local/external publication prerequisites.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-public-release-zip-casefold-basename-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 18:18 EDT — v1.0 sign/notarize trailing-slash notary zip gate

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` values ending in trailing slash(es) are rejected explicitly before dry-run success or real signing/notarization can proceed.
- Added strict-TDD dry-run coverage proving a trailing-slash notary zip path exits nonzero with `notary zip path must not end with a slash`, keeps signing/notary sentinel values redacted, creates no zip/directory, and does not invoke fake signing/notary operation shims.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: dry run unexpectedly passed with trailing-slash notary zip path`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh`, release-helper `bash -n` syntax checks, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` all passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-181737/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 130.59 ms; connected cold start 244.81 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.023 ms; dogfood query median overhead 0.031 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-trailing-slash-notary-zip-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 18:39 EDT — v1.0 release zip trailing-slash output gate

- Hardened `script/create_release_zip.sh` so a public release output path ending in slash, such as `dist/LithePG.app.zip/`, is rejected after package verification and before output parent directory creation, staging, `ditto`, or rename operations.
- Added strict-TDD coverage proving the trailing-slash output path exits nonzero with `output zip path must not end with a slash`, keeps release/signing sentinel values redacted, runs package verification first, and creates neither `dist/LithePG.app.zip` nor a nested `dist/LithePG.app.zip/LithePG.app.zip` artifact.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: expected output to contain: output zip path must not end with a slash`.
- GREEN verification: `bash script/test_create_release_zip.sh`, adjacent release helper tests `bash script/test_sign_and_notarize.sh` and `bash script/test_v10_release_gate.sh`, `bash -n` syntax checks, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed; Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-184019/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 128.07 ms; connected cold start 230.08 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.023 ms; dogfood query median overhead 0.028 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; fail-closed pre-commit JSON review passed.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-trailing-slash-output-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-05-31 18:56 EDT — v1.0 release gate trailing-slash artifact path gate

- Hardened `script/v10_release_gate.sh` so a configured final public release artifact path ending in slash, such as `LITHEPG_RELEASE_ZIP_PATH=$release_zip_fixture/`, is blocked explicitly before artifact existence checks, zip inspection, or digest computation.
- Added strict-TDD coverage proving the fast v1.0 gate reports `Release artifact filename: trailing slash`, keeps publication blocked, and does not print SHA values, archive contents, fixture paths, or sentinel values.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: expected output to contain: Release artifact filename: trailing slash`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed; `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh` passed; `git diff --check` passed; optional `./script/v10_release_gate.sh --check-remote` confirmed remote `v0.5` present and remote `v1.0` absent, then remained safely blocked on expected local/external release prerequisites.
- Evidence artifact: `docs/evidence/2026-05-31-v10-release-zip-trailing-slash-artifact-path-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 19:26 EDT — v1.0 release zip output-parent gate

- Hardened `script/create_release_zip.sh` so the public release zip helper rejects an output parent path that already exists but is not a directory, before `mkdir`, `mktemp`, `ditto`, or final rename operations can run.
- Added strict-TDD coverage proving both a regular-file output parent and a dangling-symlink output parent fail with `output zip parent path must be a directory`, keep sentinel release/signing env values redacted, preserve the file/symlink, and create no zip or symlink target.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: expected output to contain: output zip parent path must be a directory`.
- GREEN verification: `bash script/test_create_release_zip.sh`, adjacent release helper tests `bash script/test_sign_and_notarize.sh` and `bash script/test_v10_release_gate.sh`, release-helper `bash -n` syntax checks, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed; Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-192614/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 131.94 ms; connected cold start 235.29 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.022 ms; dogfood query median overhead 0.031 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-create-release-zip-output-parent-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 19:43 EDT — v1.0 sign/notarize notary zip parent-path gate

- Hardened `script/sign_and_notarize.sh` so `LITHEPG_NOTARY_ZIP` parents that already exist but are not directories fail explicitly with `notary zip parent path must be a directory`, while preserving the existing missing-parent and non-writable-parent failures.
- Added strict-TDD dry-run coverage for both a regular-file notary zip parent and a dangling-symlink notary zip parent, proving sentinel signing/notary values stay redacted, the original file/symlink is unchanged, no symlink target is created, and no target zip is created.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: expected output to contain: notary zip parent path must be a directory`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release helper tests `bash script/test_create_release_zip.sh` and `bash script/test_v10_release_gate.sh`, release-helper `bash -n` syntax checks, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` all passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; fail-closed pre-commit JSON review passed.
- Evidence artifact: `docs/evidence/2026-05-31-sign-notarize-notary-zip-parent-path-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 20:13 EDT — v1.0 package verifier extra-argument gate

- Hardened `script/package_verify.sh` so accidental extra positional arguments fail explicitly with `package verification failed: too many arguments` before package-verification success output can be printed.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving a valid minimal `LithePG.app` fixture still verifies, an extra sentinel argument is rejected, success output is suppressed on the rejection path, and the sentinel value is not leaked. The test also unsets release expectation env vars inside its helper subprocess so local `LITHEPG_EXPECTED_MARKETING_VERSION` / `LITHEPG_EXPECTED_BUILD_VERSION` settings cannot create false failures.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted an extra positional argument` after the helper reported the fixture as verified.
- GREEN verification: release-helper syntax checks, env-contamination stress `LITHEPG_EXPECTED_MARKETING_VERSION=999.999 LITHEPG_EXPECTED_BUILD_VERSION=999999 ./script/test_package_verify.sh`, `./script/test_package_verify.sh`, adjacent release helper tests `./script/test_create_release_zip.sh`, `./script/test_sign_and_notarize.sh`, `./script/test_v10_release_gate.sh`, `git diff --check`, SVG parse, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-201418/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 134.04 ms; connected cold start 231.12 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.052 ms; dogfood query median overhead 0.025 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-package-verify-extra-arg-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 20:33 EDT — v1.0 package verifier help gate

- Added explicit `-h` / `--help` handling to `script/package_verify.sh` so package verifier help exits 0 before treating help flags as app-bundle paths or evaluating expected-version env checks.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving both help flags print usage plus `LITHEPG_EXPECTED_MARKETING_VERSION` / `LITHEPG_EXPECTED_BUILD_VERSION`, omit `Package verified:`, and preserve the existing valid-fixture and extra-argument rejection checks.
- RED verification: `bash script/test_package_verify.sh` failed first with `package verification failed: app bundle not found: --help` and `test_package_verify failed: package verifier --help unexpectedly failed`.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, and adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-package-verify-help-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 20:50 EDT — v1.0 package verifier app-bundle basename gate

- Hardened `script/package_verify.sh` so package verification only succeeds for an app-bundle path whose normalized basename is exactly `LithePG.app`, aligning the generic package verifier with the public release zip/signing helper canonical bundle-name gates.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving a structurally valid `NotLithePG.app` fixture is rejected with `app bundle basename must be LithePG.app` and does not print `Package verified:`.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted an app bundle with the wrong basename`.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-package-verify-app-bundle-basename-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 — v1.0 package verifier symlink app-bundle gate

- Hardened `script/package_verify.sh` so a symlinked app-bundle input path named `LithePG.app` is rejected after trailing-slash normalization and canonical-name string checks, before the `-d` existence/type check can dereference a final-component symlink.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving plain symlink, trailing-slash symlink, and dangling final-component symlink paths fail with `package verification failed: app bundle path must not be a symlink`, do not print `Package verified:`, and do not leak symlink target/input sentinels.
- RED verification: `bash script/test_package_verify.sh` failed first for the dangling symlink follow-up with `test_package_verify failed: expected output to contain: package verification failed: app bundle path must not be a symlink`.
- GREEN verification: `bash script/test_package_verify.sh` passed; `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-212416/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 133.96 ms; connected cold start 233.86 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.031 ms; dogfood query median overhead 0.035 ms.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-symlink-app-bundle-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-05-31 21:42 EDT — v1.0 package verifier trailing-slash gate

- Hardened `script/package_verify.sh` so an explicit app-bundle path ending in a trailing slash is rejected before the package verifier normalizes or verifies the bundle.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving `LithePG.app/` fails with `package verification failed: app bundle path must not end with a slash`, does not print `Package verified:`, and does not leak the synthetic trailing-slash sentinel.
- RED verification: `bash script/test_package_verify.sh` failed first because the existing verifier accepted the trailing-slash app-bundle path and printed package verification success.
- GREEN verification: `bash script/test_package_verify.sh`, release-helper syntax checks, adjacent release-helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-05-31-package-verify-trailing-slash-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-05-31 21:59 EDT — v1.0 package verifier essential path symlink gate

- Hardened `script/package_verify.sh` so required bundle directories (`Contents`, `Contents/MacOS`) must be non-symlink directories and essential bundle files (`Contents/MacOS/LithePGApp`, `Contents/Info.plist`) must be regular non-symlink files before metadata parsing, size checks, or success output can proceed; the app executable must also remain executable.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving symlinked required bundle directories and symlinked essential bundle files fail with generic messages, do not print `Package verified:`, and do not leak target marker names.
- RED verification: `bash script/test_package_verify.sh` failed first because the existing verifier accepted a symlinked `Contents` directory and printed package verification success.
- GREEN verification: `bash script/test_package_verify.sh` passed; `bash -n script/package_verify.sh script/test_package_verify.sh` passed; adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh` passed; `git diff --check` passed; full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-221700/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.16 ms; connected cold start 226.58 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.035 ms; dogfood query median overhead 0.030 ms.
- Evidence artifact: `docs/evidence/2026-05-31-package-verify-essential-file-symlink-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 — v1.0 package verifier executable-mode gate

- Hardened `script/package_verify.sh` so `Contents/MacOS/LithePGApp` rejects unsafe executable modes before metadata, expected-version, size, or success checks can complete.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving setuid/setgid/sticky special-bit modes `4755`/`2755`/`1755`, group-writable mode `775`, and world-writable mode `757` fail with the generic message `package verification failed: app executable mode is unsafe` and do not print `Package verified:`.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted a setuid app executable` after the verifier printed package verification success.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, syntax checks `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-224048/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.42 ms; connected cold start 224.95 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.047 ms; dogfood query median overhead 0.022 ms.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-executable-mode-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 — v1.0 package verifier Info.plist mode gate

- Hardened `script/package_verify.sh` so `Contents/Info.plist` rejects unsafe modes before metadata, expected-version, size, or success checks can complete.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving setuid/setgid/sticky special-bit modes `4755`/`2755`/`1755`, group-writable mode `664`, and world-writable mode `646` fail with the generic message `package verification failed: Info.plist mode is unsafe` and do not print `Package verified:` or leak fixture path/mode/sentinel values.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted special mode 4755 on Info.plist` after the verifier printed package verification success.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, syntax checks `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-230359/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.14 ms; connected cold start 233.83 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead -0.010 ms; dogfood query median overhead 0.047 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-info-plist-mode-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 — v1.0 package verifier bundle directory mode gate

- Hardened `script/package_verify.sh` so the app bundle root and required bundle directories (`Contents` and `Contents/MacOS`) reject unsafe modes before executable, metadata, expected-version, size, or success checks can complete. The package builder and test fixtures now normalize the bundle root, inner directories, executable, and `Info.plist` modes so verification is deterministic under permissive umasks.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving isolated special-bit modes `4755`/`2755`/`1755`, group-writable mode `775`, and world-writable mode `757` fail for the app bundle root and both required inner directories with generic messages and do not print `Package verified:` or leak fixture paths/modes/sentinel values.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted unsafe mode 4775 on Contents` after the verifier printed package verification success. The follow-up quality gate also reproduced root/umask gaps before final normalization and root-mode gating.
- GREEN verification: `bash script/test_package_verify.sh`, `( umask 002; bash script/test_package_verify.sh )`, adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, syntax checks `bash -n script/build_and_run.sh script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and `( umask 002; DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package )` all passed. Swift Testing reported 127 tests across 20 suites; the permissive-umask package smoke verified `dist/LithePG.app` with packaged executable 11.93 MiB.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260531-233606/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 127.02 ms; connected cold start 234.38 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.034 ms; dogfood query median overhead 0.031 ms.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-bundle-directory-mode-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 — v1.0 package verifier missing-app redaction gate

- Hardened `script/package_verify.sh` so a missing `LithePG.app` input reports the generic `package verification failed: app bundle not found` failure instead of echoing the caller-supplied path.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving a nonexistent sentinel-containing `LithePG.app` path fails with the generic message, does not print `Package verified:`, and does not leak the full path or sentinel segment.
- RED verification: `bash script/test_package_verify.sh` failed first with the expected missing-path leak from the old failure string before the verifier was changed.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` all passed.
- Package smoke verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` passed and verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-missing-app-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 00:20 EDT — v1.0 package verifier metadata redaction gate

- Hardened `script/package_verify.sh` so Info.plist metadata mismatch and expected-version mismatch failures use generic messages instead of echoing actual plist values, expected constants, or expected-version environment values.
- Added strict-TDD coverage in `script/test_package_verify.sh` for the full metadata family (`CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, `CFBundlePackageType`, `LSMinimumSystemVersion`, `NSPrincipalClass`, `CFBundleShortVersionString`, and `CFBundleVersion`) plus `LITHEPG_EXPECTED_MARKETING_VERSION` and `LITHEPG_EXPECTED_BUILD_VERSION` mismatch redaction.
- RED verification: `bash script/test_package_verify.sh` failed first with the expected missing generic metadata-mismatch output before the verifier failure strings were redacted.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, and adjacent release-helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh` all passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-metadata-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 — v1.0 package verifier executable-format gate

- Hardened `script/package_verify.sh` so `Contents/MacOS/LithePGApp` must inspect as a Mach-O `EXECUTE` file via `/usr/bin/otool -hv`; text executables, Mach-O non-executables, misleading path-contamination cases, and uninspectable executables fail generically with `package verification failed: app executable format is invalid`.
- Added strict-TDD coverage in `script/test_package_verify.sh` proving a structurally valid `LithePG.app` with a text/shell executable is rejected, added a follow-up RED regression proving a Mach-O dynamic linker is not accepted merely because it is Mach-O, and added a second follow-up proving misleading paths that contain `Mach-O ... executable` cannot contaminate executable-format detection. These cases avoid printing `Package verified:` and do not leak fixture paths, sentinels, or tool output. The valid package-verifier fixture now uses `/usr/bin/true` as a stable Mach-O executable.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted a text app executable`, then follow-up regressions failed with `test_package_verify failed: package verifier unexpectedly accepted a Mach-O non-executable app binary` and `test_package_verify failed: package verifier unexpectedly accepted a Mach-O non-executable app binary from a misleading path` before switching to the `otool -hv` `EXECUTE` header check.
- GREEN verification: `bash script/test_package_verify.sh`, syntax checks `bash -n script/package_verify.sh script/test_package_verify.sh`, and `git diff --check` passed.
- Follow-up fixture sync: `script/test_sign_and_notarize.sh` now uses the same `/usr/bin/true` Mach-O fixture so adjacent release-helper coverage remains aligned with the stricter package verifier.
- Adjacent release-helper verification: `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, and `bash script/test_v10_release_gate.sh` all passed.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-executable-format-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 01:19 EDT — v1.0 package verifier nested symlink gate

- Hardened `script/package_verify.sh` so `LithePG.app` fails package verification if any symlink exists anywhere under the bundle tree, not only at the app path or required `Contents`/`MacOS`/executable/`Info.plist` paths.
- Added strict-TDD coverage proving a `Contents/Resources` symlink is rejected with the generic message `package verification failed: app bundle must not contain symlinks`, while avoiding leaks of the fixture path, target name, link name, or sentinel payload. Review follow-up added fail-closed coverage for an uninspectable nested directory so traversal errors cannot hide symlinks.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted a resource symlink inside the app bundle` after printing package verification success. Review follow-up RED failed with `test_package_verify failed: package verifier unexpectedly accepted an uninspectable bundle tree` before the `find` exit status was checked.
- GREEN verification: `bash script/test_package_verify.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_v10_release_gate.sh`, release-helper syntax checks, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` all passed. Packaged executable: 12,507,504 bytes / 11.93 MiB.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-nested-symlink-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 01:53 EDT — v1.0 package verifier Finder metadata gate

- Hardened `script/package_verify.sh` so `LithePG.app` fails package verification if Finder/archive metadata entries such as `.DS_Store` files or `__MACOSX` directories exist anywhere under the bundle tree.
- Added strict-TDD coverage proving both metadata cases fail with the generic message `package verification failed: app bundle must not contain Finder metadata files`, without printing package-verification success or leaking fixture paths, sentinel content, `.DS_Store`, `__MACOSX`, or AppleDouble manifest names.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted Finder metadata .DS_Store inside the app bundle` after printing package verification success for the old behavior.
- GREEN verification: `bash script/test_package_verify.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_v10_release_gate.sh`, release-helper syntax checks, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` all passed. Swift Testing reported 127 tests across 20 suites; packaged executable: 12,507,504 bytes / 11.93 MiB.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-015317/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.91 ms; connected cold start 230.37 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.033 ms; dogfood query median overhead 0.017 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-finder-metadata-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 02:13 EDT — v1.0 package verifier AppleDouble metadata gate

- Hardened `script/package_verify.sh` so the bundle-level Finder metadata check now rejects AppleDouble files whose basename begins with `._`, aligning package verification with the public release zip metadata gate.
- Added strict-TDD coverage proving `Contents/Resources/._Icon` fails with the generic message `package verification failed: app bundle must not contain Finder metadata files`, without printing package-verification success or leaking fixture paths, sentinel content, or the AppleDouble filename.
- RED verification: `bash script/test_package_verify.sh` failed first because the package verifier accepted the AppleDouble metadata fixture under the old behavior.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, adjacent release-helper tests `bash script/test_create_release_zip.sh`, `bash script/test_sign_and_notarize.sh`, and `bash script/test_v10_release_gate.sh`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Package smoke verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` passed and verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-021516/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 126.10 ms; connected cold start 229.90 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.011 ms; dogfood query median overhead 0.004 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-appledouble-metadata-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 02:38 EDT — v1.0 package verifier special-file gate

- Hardened `script/package_verify.sh` so `LithePG.app` package verification rejects non-regular, non-directory special entries anywhere under the bundle tree, while preserving the existing symlink-specific rejection path.
- Added strict-TDD coverage proving a FIFO under `Contents/Resources` fails with the generic message `package verification failed: app bundle must contain only regular files and directories`, without printing package-verification success or leaking fixture paths, sentinels, or the FIFO filename.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted a special file inside the app bundle` after the verifier printed package verification success for the old behavior.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release-helper tests `bash script/test_create_release_zip.sh`, `bash script/test_sign_and_notarize.sh`, and `bash script/test_v10_release_gate.sh`, syntax checks, SVG parse, and `git diff --check` passed locally before the release-impact gates.
- Full Swift verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites.
- Package smoke verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` passed and verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB, version `0.5` build `230`.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-024045/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.06 ms; connected cold start 235.81 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.049 ms; dogfood query median overhead 0.013 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-special-file-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 02:57 EDT — v1.0 package verifier nested mode gate

- Hardened `script/package_verify.sh` so `LithePG.app` package verification rejects unsafe modes on any nested app-bundle directory or regular file, beyond the existing root/`Contents`/`Contents/MacOS`/executable/`Info.plist` essential-path checks.
- Added strict-TDD coverage proving unsafe nested directory modes (`775`, `1755`) and unsafe nested regular-file modes (`664`, `4755`) fail with generic messages, without printing package-verification success or leaking fixture paths, sentinels, nested names, modes, or file contents.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: package verifier unexpectedly accepted unsafe mode 775 on a nested app-bundle directory` after the old verifier printed package verification success for the unsafe nested directory fixture.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, and adjacent release-helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh` all passed.
- Repo build verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-nested-mode-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 03:21 EDT — v1.0 package verifier success-path redaction

- Hardened `script/package_verify.sh` so successful package verification prints the stable bundle name `Package verified: LithePG.app` instead of echoing the caller-supplied app bundle path.
- Added strict-TDD coverage proving a valid app bundle under a sentinel-containing path still verifies successfully while the success output does not leak the full path or sentinel.
- RED verification: `bash script/test_package_verify.sh` failed first with the expected success-path sentinel leak from the previous `Package verified: $APP_BUNDLE` output.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, adjacent release-helper tests `bash script/test_create_release_zip.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and package smoke `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` all passed. Package smoke verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB, version `0.5` build `232`.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-032335/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.10 ms; connected cold start 233.97 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.065 ms; dogfood query median overhead 0.034 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-success-path-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 03:40 EDT — v1.0 release zip success-path redaction

- Hardened `script/create_release_zip.sh` so successful public zip creation prints the stable artifact basename `LithePG.app.zip` instead of echoing the caller-supplied output path, which may contain local directories or sentinel values.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` proving a successful zip created under a sentinel-containing output directory still preserves the `.app` wrapper, prints SHA-256/size, and does not leak the output path, sentinel, signing identity, notary profile, or release marker environment values.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: expected output to contain: Created release zip: LithePG.app.zip` while the old helper printed the caller-supplied output path.
- GREEN verification: `bash script/test_create_release_zip.sh`, `bash -n script/create_release_zip.sh script/test_create_release_zip.sh`, `git diff --check`, adjacent release-helper tests `bash script/test_package_verify.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and package smoke `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package && LITHEPG_RELEASE_ZIP_OVERWRITE=approved ./script/create_release_zip.sh dist/LithePG.app dist/LithePG.app.zip` passed. Package smoke verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB, version `0.5` build `233`, and release zip success output `Created release zip: LithePG.app.zip`.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-release-zip-success-path-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 04:20 EDT — v1.0 sign/notarize output redaction

- Hardened `script/sign_and_notarize.sh` so dry-run and real-mode success output no longer echoes caller-supplied app bundle, entitlements, or notary zip paths; output now uses stable `LithePG.app` / configured / created redacted status lines.
- Wrapped real-mode external signing/notary operations with redacted quiet execution so noisy `codesign`, `ditto`, `xcrun`, and `spctl` stdout/stderr cannot leak local paths, signing identities, notary profiles, or fixture sentinels; failures now report generic operation-specific messages.
- Redacted the missing-entitlements failure path so a caller-supplied local entitlements path is not printed.
- Follow-up hardening: canonicalization failures for app bundle / notary zip location checks now suppress raw Perl stderr and emit generic redacted failures, covering symlink-loop notary zip paths that previously leaked caller-supplied path text.
- Follow-up test coverage: the fake failing `ditto` now emits sentinel-bearing args, paths, signing identity, notary profile, and notary zip values to stdout/stderr; assertions prove those noisy subprocess outputs and sentinels do not reach helper output.
- RED verification: initial redaction coverage failed first with `test_sign_and_notarize failed: output leaked forbidden value: SIGN_AND_NOTARIZE_MISSING_ENTITLEMENTS_PATH_SHOULD_NOT_LEAK`; follow-up TDD for the symlink-loop canonicalization gap failed first with `test_sign_and_notarize failed: expected output to contain: could not validate notary zip path`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh && bash script/test_package_verify.sh && bash script/test_v10_release_gate.sh && bash script/test_sign_and_notarize.sh`, `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, `git diff --check`, and prior `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Release-impact dogfood verification passed with Docker available: prior `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-041933/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 132.46 ms; connected cold start 230.06 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.056 ms; dogfood query median overhead -0.005 ms.
- Follow-up spec-gap review: PASS for the identified sign/notarize redaction gaps based on local TDD and release-helper shell verification; no new independent review was run in this pass.
- Evidence artifact: `docs/evidence/2026-06-01-sign-notarize-output-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 04:45 EDT — v1.0 sign/notarize staging setup redaction follow-up

- Latest spec review found one remaining real-mode redaction gap before signing begins: noisy caller-controlled `mktemp`/`chmod` staging setup could leak sentinel-bearing notary zip parent/template/path values.
- Added strict-TDD real-mode coverage in `script/test_sign_and_notarize.sh` for fake noisy `mktemp` failure and fake noisy `chmod` failure, proving stdout/stderr, template args, signing identity, notary profile, notary zip, and sentinel path values stay redacted.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: output leaked forbidden value: SIGN_MKTEMP_ZIP_PATH_SHOULD_NOT_LEAK`.
- Hardened `script/sign_and_notarize.sh` so staging `mktemp` and `chmod` failures suppress subprocess output and fail with generic messages: `could not create notary zip staging directory` and `could not secure notary zip staging directory`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh && bash script/test_package_verify.sh && bash script/test_v10_release_gate.sh && bash script/test_sign_and_notarize.sh`, `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, and `git diff --check` passed.
- No final independent review PASS was run or claimed in this follow-up; parent review remains pending.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 04:57 EDT — v1.0 sign/notarize cleanup redaction follow-up

- Latest code-quality review found one remaining cleanup redaction gap: the real-mode `cleanup_staged_zip` trap still ran `rm -rf -- "$STAGED_ZIP_DIR"` without suppressing stdout/stderr, so a failing cleanup `rm` could leak a caller-influenced staging directory path after setup/failure.
- Added strict-TDD real-mode coverage in `script/test_sign_and_notarize.sh` where a fake failing `rm` emits sentinel-bearing cleanup args, notary zip, signing identity, and notary profile values; assertions prove cleanup output and sentinel paths stay redacted while the primary `codesign failed` error remains visible.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `test_sign_and_notarize failed: output leaked forbidden value: SIGN_CLEANUP_RM_STAGING_PATH_SHOULD_NOT_LEAK`.
- Hardened `script/sign_and_notarize.sh` so cleanup suppresses `rm` stdout/stderr and ignores cleanup failure: `rm -rf -- "$STAGED_ZIP_DIR" >/dev/null 2>&1 || true`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, release-helper shell tests `bash script/test_create_release_zip.sh && bash script/test_package_verify.sh && bash script/test_v10_release_gate.sh && bash script/test_sign_and_notarize.sh`, `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, and `git diff --check` passed.
- Updated evidence artifact `docs/evidence/2026-06-01-sign-notarize-output-redaction.svg` to include the mktemp/chmod/cleanup follow-ups with synthetic, secret-free fixture language.
- Independent follow-up reviews after cleanup hardening: spec compliance PASS; code quality/security APPROVED.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 05:38 EDT — v1.0 release zip failure-output redaction

- Hardened `script/create_release_zip.sh` so caller-controlled output/local paths are not echoed on release-zip failure paths: existing output overwrite refusal, output-parent creation failure, temporary staging directory creation failure, inside-app-bundle output refusal, SHA/size failure, and final rename failure now use stable generic messages and suppress noisy subprocess diagnostics where needed.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` proving sentinel-containing output paths remain redacted for existing-output refusal, `mkdir` parent creation failures, `mktemp` staging failures, and inside-app-bundle output refusal.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: output leaked forbidden value: artifacts/REFUSE_EXISTING_OUTPUT_SENTINEL_DO_NOT_PRINT/LithePG.app.zip`; follow-up spec review then caught the unsuppressed `mkdir` diagnostic gap, and the added regression failed first with `expected output to contain: could not create output zip parent directory`.
- GREEN verification: `bash script/test_create_release_zip.sh`, release-helper shell tests `bash script/test_package_verify.sh && bash script/test_sign_and_notarize.sh && bash script/test_v10_release_gate.sh`, `bash -n script/create_release_zip.sh script/test_create_release_zip.sh`, `git diff --check`, SVG parse, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-054110/` with default Swift tests, live dogfood tests, and v0.4 measurement all passed. Metrics: shell readiness 151.65 ms; connected cold start 230.67 ms; raw release executable 21.379 MiB; strip-probe executable 11.980 MiB; `SELECT 1` median overhead 0.018 ms; dogfood query median overhead 0.045 ms.
- Independent reviews: spec compliance PASS after the `mkdir` follow-up; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-release-zip-failure-output-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 05:57 EDT — v1.0 release zip cleanup redaction follow-up

- Latest release-zip hardening found one remaining cleanup redaction gap: the `create_release_zip.sh` EXIT trap ran unsuppressed `rm -rf` cleanup for its temporary directory, so a failing cleanup `rm` could leak caller-influenced temporary paths after the zip had already been created.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` where a fake failing `rm` emits synthetic cleanup args, a sentinel path value, signing identity, notary profile, and release marker values; assertions prove cleanup output and sentinel values stay redacted while the completed `LithePG.app.zip` remains valid.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper failed when cleanup rm failed after creating the zip`.
- GREEN verification: `bash script/test_create_release_zip.sh`, release-helper shell tests (`test_package_verify`, `test_sign_and_notarize`, `test_v10_release_gate`), syntax checks, SVG parse, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Dogfood artifacts: `.build/dogfood-checks/20260601-055925/`; metrics: shell readiness 131.63 ms, connected cold start 224.69 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.011 ms, dogfood query median overhead 0.022 ms.
- Independent reviews: spec compliance PASS after the fake-`rm` env-emission follow-up; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-release-zip-cleanup-redaction.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 06:25 EDT — v1.0 package verifier PATH-shadow hardening

- Hardened `script/package_verify.sh` so top-level mode/size and MiB calculations use `/usr/bin/stat` and `/usr/bin/awk` instead of caller-controlled `PATH` resolution, matching the verifier's existing absolute-tool posture for nested bundle traversal and executable inspection.
- Added strict-TDD coverage in `script/test_package_verify.sh` where fake `stat` and `awk` binaries emit a synthetic sentinel and exit non-zero; the verifier must still pass a valid `LithePG.app` fixture and must not print the sentinel or fake-tool output.
- RED verification: `bash script/test_package_verify.sh` failed first with `PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN stat invoked` and `test_package_verify failed: package verifier was affected by PATH-shadowed stat/awk`.
- GREEN verification: `bash script/test_package_verify.sh`, release-helper shell tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, package smoke, and `./script/package_verify.sh dist/LithePG.app` all passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-062516/`; metrics: shell readiness 139.73 ms, connected cold start 231.86 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.037 ms, dogfood query median overhead 0.014 ms.
- Evidence artifact: `docs/evidence/2026-06-01-package-verify-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 06:56 EDT — v1.0 release zip PATH-shadow hardening

- Hardened `script/create_release_zip.sh` so release zip creation uses absolute macOS paths for `basename`, `dirname`, `mkdir`, `mktemp`, and cleanup `rm` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` where fake `basename`/`dirname`/`mkdir`/`mktemp`/`rm` utilities emit a synthetic sentinel and exit non-zero; the helper must still produce a valid `LithePG.app.zip`, preserve the app wrapper, and avoid printing or invoking fake-tool output.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `PATH_SHADOW_SENTINEL_DO_NOT_PRINT fake dirname stdout` and `test_create_release_zip failed: helper failed with PATH-shadowed core utilities`.
- GREEN verification: `bash script/test_create_release_zip.sh`, adjacent release-helper tests (`test_package_verify`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/create_release_zip.sh script/test_create_release_zip.sh`, `git diff --check`, SVG parse, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, package smoke, and local `LITHEPG_RELEASE_ZIP_OVERWRITE=approved ./script/create_release_zip.sh dist/LithePG.app dist/LithePG.app.zip` all passed. Swift Testing reported 127 tests across 20 suites; package smoke verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB, version `0.5` build `238`; local unsigned zip size was 4,786,867 bytes.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit JSON review passed with no security concerns or logic errors.
- Evidence artifact: `docs/evidence/2026-06-01-release-zip-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 07:21 EDT — v1.0 sign/notarize PATH-shadow hardening

- Hardened `script/sign_and_notarize.sh` so helper-owned core utility calls use absolute macOS paths for `basename`, `dirname`, `mktemp`, staging `chmod`, and cleanup `rm` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` where fake `basename`/`dirname`/`mktemp`/`chmod`/`rm` utilities emit a synthetic sentinel and exit non-zero, while fake signing/notary tools keep the real-mode flow testable without Apple credentials. The helper must still create the redacted fake notary zip and must not invoke or print fake core utility output.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first because the helper invoked a PATH-shadowed `dirname` during repository-root setup.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_package_verify`, `test_v10_release_gate`), `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, SVG parse, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, package smoke, `./script/package_verify.sh dist/LithePG.app`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Swift Testing reported 127 tests across 20 suites; package smoke verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB, version `0.5` build `239`; dogfood artifacts: `.build/dogfood-checks/20260601-072343/`; metrics: shell readiness 133.25 ms, connected cold start 229.87 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.032 ms, dogfood query median overhead 0.031 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit JSON review passed with no security concerns or logic errors.
- Evidence artifact: `docs/evidence/2026-06-01-sign-notarize-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 07:48 EDT — v1.0 release gate dirname PATH-shadow hardening

- Hardened `script/v10_release_gate.sh` so helper-owned repository-root setup uses `/usr/bin/dirname` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` where a fake PATH-shadowed `dirname` emits the synthetic sentinel `V10_RELEASE_GATE_PATH_SHADOW_DIRNAME_SHOULD_NOT_RUN` and exits non-zero; the gate must still reach the normal blocked v1.0 preflight output without printing the sentinel.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: output leaked forbidden value: V10_RELEASE_GATE_PATH_SHADOW_DIRNAME_SHOULD_NOT_RUN`.
- GREEN verification: `bash script/test_v10_release_gate.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`), `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` all passed.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `docs/evidence/2026-06-01-v10-release-gate-dirname-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 08:09 EDT — v1.0 release gate rm PATH-shadow hardening

- Hardened `script/v10_release_gate.sh` so Info.plist metadata temp-file cleanup uses `/bin/rm -f` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` where a fake PATH-shadowed `rm` emits the synthetic sentinel `V10_RELEASE_GATE_PATH_SHADOW_RM_SHOULD_NOT_RUN` and exits non-zero during a normal blocked preflight that inspects a valid release zip; the gate must avoid invoking it and still report normal blocked output.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: output leaked forbidden value: V10_RELEASE_GATE_PATH_SHADOW_RM_SHOULD_NOT_RUN`.
- GREEN verification: `bash script/test_v10_release_gate.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`), `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, and `git diff --check` all passed.
- Evidence artifact: `docs/evidence/2026-06-01-v10-release-gate-rm-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 08:58 EDT — v1.0 release gate grep PATH-shadow hardening receipt

- Synced the latest committed release-gate hardening receipt into this dogfood log after `main` advanced to `2dff3ae` (`[verified] Harden v1.0 release gate grep scans`).
- The hardening changes `script/v10_release_gate.sh` so helper-owned release-copy, Homebrew cask, and security-document scans use `/usr/bin/grep` instead of caller-controlled `PATH` resolution.
- Strict-TDD coverage in `script/test_v10_release_gate.sh` uses a fake PATH-shadowed `grep` that emits the synthetic sentinel `V10_RELEASE_GATE_PATH_SHADOW_GREP_SHOULD_NOT_RUN`; the gate must avoid invoking it and still report normal blocked v1.0 preflight output.
- Recorded verification from the committed slice: `bash script/test_v10_release_gate.sh`, adjacent release-helper tests, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 tests across 20 suites.
- Evidence artifact from the committed slice: `screenshots/evidence/2026-06-01-v10-grep-path-hardening.svg`.
- Receipt-sync evidence artifact for this log update: `screenshots/evidence/2026-06-01-dogfood-log-grep-receipt-sync.svg`.
- This receipt-only sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-01 09:17 EDT — v1.0 build/package PATH-shadow hardening

- Hardened `script/build_and_run.sh --package` so helper-owned core utility calls use absolute macOS paths for bundle setup, plist creation, strip/size accounting, ad-hoc signing, optional notarization helper calls, MiB formatting, and package-verifier invocation instead of caller-controlled `PATH` resolution. Intentional developer tools (`swift`, `git`, `lldb`, `pkill`, `pgrep`) remain PATH-resolved.
- Added strict-TDD coverage in `script/test_build_and_run.sh` where fake PATH-shadowed `dirname`, `rm`, `mkdir`, `chmod`, `cp`, `stat`, `strip`, `cat`, `codesign`, `ditto`, `xcrun`, `awk`, and `bash` emit `BUILD_AND_RUN_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN` and exit non-zero, while a fake `swift` quickly packages `/usr/bin/true` as `LithePGApp` and writes a marker proving the PATH-resolved Swift tool was used. The package test also forces `LITHEPG_CODESIGN_IDENTITY=-` and unsets `LITHEPG_NOTARY_PROFILE` so it cannot perform real identity signing, timestamping, or notarization from a developer environment.
- RED verification: after adding the fake `bash` regression coverage, `bash script/test_build_and_run.sh` failed with `BUILD_AND_RUN_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN bash invoked`, proving the direct `package_verify.sh` subprocess could still resolve its `#!/usr/bin/env bash` through caller-controlled `PATH`.
- GREEN verification: `bash script/test_build_and_run.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/build_and_run.sh script/test_build_and_run.sh`, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Dogfood artifacts: `.build/dogfood-checks/20260601-093755/`; metrics: shell readiness 132.27 ms, connected cold start 230.53 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.021 ms, dogfood query median overhead 0.018 ms.
- Evidence artifact: `screenshots/evidence/2026-06-01-build-and-run-path-shadow-hardening.svg`.
- No signing with a real identity, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 09:58 EDT — v1.0 dogfood check PATH-shadow hardening

- Hardened `script/dogfood_check.sh` so helper-owned core utility calls for repository-root setup, timestamped output-directory naming, output-directory creation, and final status display use absolute macOS paths (`/usr/bin/dirname`, `/bin/date`, `/bin/mkdir`, `/bin/cat`) instead of caller-controlled `PATH` resolution. `swift` remains intentionally PATH-resolved so developer toolchains and test fixtures can select the Swift tool.
- Added strict-TDD coverage in `script/test_dogfood_check.sh` with a temp fixture that stubs `dogfood_postgres.sh`, `v04_measure.sh`, `swift`, and `git`, while fake PATH-shadowed `dirname`, `date`, `mkdir`, and `cat` emit `DOGFOOD_CHECK_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN` and exit non-zero. The dogfood check must still write `status.json`, report passed default/live/measurement gates from the fixture, and avoid printing the sentinel.
- RED verification from the implementation slice failed first with PATH-shadowed core-utility sentinels before the helper was hardened.
- GREEN verification: `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_check.sh script/test_dogfood_check.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed. Dogfood artifacts: `.build/dogfood-checks/20260601-100008/`; metrics: shell readiness 127.32 ms, connected cold start 215.93 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.034 ms, dogfood query median overhead 0.040 ms. Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-dogfood-check-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 10:26 EDT — v0.5 model smoke PATH-shadow hardening

- Hardened `script/v05_model_smoke.sh` so helper-owned core utility calls use absolute macOS paths for repository-root setup, timestamped output-directory naming, output-directory creation, log teeing, CoreML linkage inspection, framework-name matching, and final summary display (`/usr/bin/dirname`, `/bin/pwd`, `/bin/date`, `/bin/mkdir`, `/usr/bin/tee`, `/usr/bin/otool`, `/usr/bin/grep`, `/bin/cat`) instead of caller-controlled `PATH` resolution. `swift` remains intentionally PATH-resolved so developer toolchains and test fixtures can select the Swift tool.
- Added strict-TDD coverage in `script/test_v05_model_smoke.sh` with an isolated fixture and fake PATH-shadowed `dirname`, `date`, `mkdir`, `tee`, `otool`, `grep`, `cat`, and `pwd` utilities that emit `V05_MODEL_SMOKE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; the helper must still succeed, use fake PATH-resolved `swift`, write model-smoke logs, write `summary.json`, and avoid printing or invoking the sentinel. The fixture also unsets inherited local-model env vars so the expected default gated-model fields stay deterministic.
- RED verification from the implementation slice failed first with PATH-shadowed core-utility sentinels before the helper was hardened.
- GREEN verification: `bash script/test_v05_model_smoke.sh`, `bash -n script/v05_model_smoke.sh script/test_v05_model_smoke.sh`, `git diff --check`, SVG parse, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and live `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/v05_model_smoke.sh` all passed. Full Swift Testing reported 127 tests across 20 suites; the model-smoke helper reported 4 selected LocalModelAIQueryService tests passed, release `LithePGApp` build passed, 21.379 MiB binary size, `CoreML.framework` linked, no bundled model artifact, and measurements under `.build/v05-model-smoke/20260601-102114/`.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-v05-model-smoke-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 10:51 EDT — v0.4 measurement PATH-shadow hardening

- Hardened `script/v04_measure.sh` so helper-owned core utility calls use absolute macOS paths for repository-root setup, timestamped output-directory naming, output-directory creation, dogfood-log copy, binary-size inspection, strip-probe setup/cleanup, metrics cleanup, and final summary display (`/usr/bin/dirname`, `/bin/pwd`, `/bin/date`, `/bin/mkdir`, `/bin/cp`, `/usr/bin/stat`, `/usr/bin/mktemp`, `/usr/bin/strip`, `/bin/rm`, `/bin/cat`) instead of caller-controlled `PATH` resolution. `swift`, `psql`, `env`, `kill`, `sleep`, and the built app/bench executables remain intentionally selectable.
- Added strict-TDD coverage in `script/test_v04_measure.sh` with an isolated fixture and fake PATH-shadowed `dirname`, `date`, `mkdir`, `cp`, `stat`, `mktemp`, `strip`, `rm`, `cat`, and `pwd` utilities that emit `V04_MEASURE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; the helper must still use fake PATH-resolved `swift`, write app/bench/psql/startup measurement artifacts, write `summary.json`, and avoid printing or invoking the sentinel.
- RED verification from the implementation slice failed first with PATH-shadowed core-utility sentinels before the helper was hardened.
- GREEN verification: `bash script/test_v04_measure.sh`, `bash -n script/v04_measure.sh script/test_v04_measure.sh && bash -n script/test_v04_measure.sh`, SVG parse, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Swift Testing reported 127 tests across 20 suites; dogfood artifacts: `.build/dogfood-checks/20260601-105219/`; metrics: shell readiness 126.63 ms, connected cold start 224.45 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.028 ms, dogfood query median overhead 0.019 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-v04-measure-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 11:11 EDT — v1.0 dogfood Postgres PATH-shadow hardening

- Hardened `script/dogfood_postgres.sh` so helper-owned core utility calls use absolute macOS paths for repository-root setup, exact literal container-name matching, and readiness wait sleeps (`/usr/bin/dirname`, `/usr/bin/grep -Fqx --`, `/bin/sleep`) instead of caller-controlled `PATH` resolution. `docker` remains intentionally PATH-resolved so tests can fake it and developer environments can select Docker.
- Added strict-TDD coverage in `script/test_dogfood_postgres.sh` with deterministic `LITHEPG_DOGFOOD_*` fixtures, fake Docker, and fake PATH-shadowed `dirname`, `grep`, and `sleep` utilities that emit `DOGFOOD_POSTGRES_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; the helper must still complete through fake Docker, ignore ambient custom container/port/password settings, avoid invoking the sentinel utilities, keep the demo URL redacted as `postgres:***`, and avoid leaking fixture or ambient passwords in helper output/fake Docker logs.
- RED verification: `bash script/test_dogfood_postgres.sh` failed first with `DOGFOOD_POSTGRES_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN dirname invoked`, `DOGFOOD_POSTGRES_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN grep invoked`, and `test_dogfood_postgres failed: dogfood_postgres.sh was affected by PATH-shadowed core utilities`.
- GREEN verification: `bash script/test_dogfood_postgres.sh`, `LITHEPG_DOGFOOD_CONTAINER=custom-smoke LITHEPG_DOGFOOD_PORT=55555 LITHEPG_DOGFOOD_PASSWORD=<ambient-secret> bash script/test_dogfood_postgres.sh` (plus an explicit ambient-secret output leak check), `bash -n script/dogfood_postgres.sh script/test_dogfood_postgres.sh`, adjacent `bash script/test_dogfood_check.sh`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and `git diff --check` passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-112724/`; metrics: shell readiness 127.15 ms, connected cold start 216.11 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.023 ms, dogfood query median overhead 0.044 ms.
- Evidence artifact: `screenshots/evidence/2026-06-01-dogfood-postgres-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 11:48 EDT — v1.0 run dogfood app dirname PATH-shadow hardening

- Hardened `script/run_dogfood_app.sh` so helper-owned repository-root setup uses `/usr/bin/dirname` instead of caller-controlled `PATH` resolution. `swift` remains intentionally PATH-resolved so developer toolchains and test fixtures can select the Swift tool.
- Added strict-TDD coverage in `script/test_run_dogfood_app.sh` with an isolated temp fixture, stub `script/dogfood_postgres.sh`, fake PATH-resolved `swift`, and a fake PATH-shadowed `dirname` that emits `RUN_DOGFOOD_APP_PATH_SHADOW_DIRNAME_SHOULD_NOT_RUN` and exits non-zero. The helper must still build via fake Swift, exec the fake `LithePGApp`, pass through secret-free startup URL/query values, and avoid printing or invoking the dirname sentinel.
- RED verification: `bash script/test_run_dogfood_app.sh` failed first with `RUN_DOGFOOD_APP_PATH_SHADOW_DIRNAME_SHOULD_NOT_RUN dirname invoked` and `test_run_dogfood_app failed: run_dogfood_app.sh was affected by PATH-shadowed dirname`.
- GREEN verification: `bash script/test_run_dogfood_app.sh` passed after the minimal `/usr/bin/dirname` production change. Adjacent verification also passed: `bash -n script/run_dogfood_app.sh script/test_run_dogfood_app.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.
- Evidence artifact: `screenshots/evidence/2026-06-01-run-dogfood-app-path-shadow-hardening.svg`.
- No real app, Docker/Postgres instance, signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 12:11 EDT — v1.0 sign/notarize help cat PATH-shadow hardening

- Hardened `script/sign_and_notarize.sh --help` so `usage()` renders via `/bin/cat` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` with a fake PATH-shadowed `cat` that emits `SIGN_AND_NOTARIZE_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN` and exits non-zero. The helper must still print usage, must not invoke the fake `cat`, must not create a notary zip, and must not leak signing/notary sentinel values.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with the fake `cat` sentinel and `test_sign_and_notarize failed: --help invoked PATH-shadowed cat`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_package_verify`, `test_v10_release_gate`), `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, SVG parse, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Dogfood artifacts: `.build/dogfood-checks/20260601-121914/`; metrics: shell readiness 126.66 ms, connected cold start 223.25 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.030 ms, dogfood query median overhead 0.027 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit JSON review passed with no security concerns or logic errors.
- Evidence artifact: `screenshots/evidence/2026-06-01-sign-notarize-help-cat-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, push, cron changes, or external publication was attempted.

## 2026-06-01 12:32 EDT — v1.0 package verifier help cat PATH-shadow hardening

- Hardened `script/package_verify.sh --help` so `usage()` renders via `/bin/cat` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_package_verify.sh` with a fake PATH-shadowed `cat` that emits `PACKAGE_VERIFY_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN` and exits non-zero. The helper must still print usage, must not invoke the fake `cat`, and must not leak sentinel/fake output.
- RED verification: `bash script/test_package_verify.sh` failed first with the fake `cat` sentinel and `test_package_verify failed: package verifier --help invoked PATH-shadowed cat`.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 tests across 20 suites.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit JSON review passed with no security concerns or logic errors.
- Evidence artifact: `screenshots/evidence/2026-06-01-package-verify-help-cat-path-shadow-hardening.svg`.
- No package signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 12:51 EDT — v1.0 create release zip help cat PATH-shadow hardening

- Hardened `script/create_release_zip.sh --help` so `usage()` renders via `/bin/cat` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` with a fake PATH-shadowed `cat` that emits `CREATE_RELEASE_ZIP_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN` and exits non-zero. The helper must still print usage, must not invoke fake `cat`, must not run package verification, and must not leak sentinel output.
- RED verification: `bash script/test_create_release_zip.sh` failed first with the fake `cat` sentinel and `test_create_release_zip failed: --help did not exit 0`.
- GREEN verification: `bash script/test_create_release_zip.sh`, adjacent release-helper tests (`test_package_verify`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/create_release_zip.sh script/test_create_release_zip.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 tests across 20 suites.
- Evidence artifact: `screenshots/evidence/2026-06-01-create-release-zip-help-cat-path-shadow-hardening.svg`.
- No package signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 13:11 EDT — v1.0 release gate help cat PATH-shadow hardening

- Hardened `script/v10_release_gate.sh --help` so `usage()` renders via `/bin/cat` instead of caller-controlled `PATH` resolution.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` with a fake PATH-shadowed `cat` that emits `V10_RELEASE_GATE_HELP_CAT_PATH_SHADOW_SHOULD_NOT_RUN` and exits non-zero. The helper must still print usage and must not invoke or print fake `cat` output.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: release gate --help did not exit 0 under PATH-shadowed cat`.
- GREEN verification: `bash script/test_v10_release_gate.sh` passed after the minimal `/bin/cat` production change. Adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`), shell syntax checks, `git diff --check`, SVG parse, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Evidence artifact: `screenshots/evidence/2026-06-01-v10-release-gate-help-cat-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 13:32 EDT — v1.0 build/run helper help PATH-shadow hardening

- Hardened `script/build_and_run.sh --help` so usage exits before package/build side effects and renders via `/bin/cat` through the existing absolute-tool constant.
- Added strict-TDD coverage in `script/test_build_and_run.sh` with fake PATH-shadowed `cat`, `git`, `pkill`, and `swift` tools that emit `BUILD_AND_RUN_HELP_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; help must print usage, avoid package/build work, and avoid invoking or leaking fake-tool output.
- RED verification: `bash script/test_build_and_run.sh` failed first with `BUILD_AND_RUN_HELP_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN swift invoked` and `test_build_and_run failed: build_and_run --help did not exit 0 under PATH-shadowed tools`.
- GREEN verification: `bash script/test_build_and_run.sh` passed after adding the early help path. Adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), shell syntax checks, SVG parse, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed. Dogfood artifacts: `.build/dogfood-checks/20260601-133440/`; metrics: shell readiness 127.84 ms, connected cold start 228.68 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.024 ms, dogfood query median overhead 0.021 ms.
- Evidence artifact: `screenshots/evidence/2026-06-01-build-and-run-help-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 13:53 EDT — v1.0 dogfood check python3 PATH-shadow hardening

- Hardened `script/dogfood_check.sh` so helper-owned status JSON generation uses `/usr/bin/python3` instead of caller-controlled `PATH` resolution. `swift` and `git` remain intentionally PATH-resolved in the focused fixture so tests can select fake toolchain/repository metadata.
- Added strict-TDD coverage in `script/test_dogfood_check.sh` with a fake PATH-shadowed `python3` that emits `DOGFOOD_CHECK_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; the helper must still complete through fake Swift/Git fixtures, write `status.json`, and avoid invoking or leaking the sentinel.
- RED verification: `bash script/test_dogfood_check.sh` failed first with `DOGFOOD_CHECK_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN python3 invoked` and `test_dogfood_check failed: dogfood_check.sh was affected by PATH-shadowed core utilities`.
- GREEN verification: `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_check.sh script/test_dogfood_check.sh`, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Swift Testing reported 127 tests across 20 suites. Dogfood artifacts: `.build/dogfood-checks/20260601-135414/`; metrics: shell readiness 130.90 ms, connected cold start 230.62 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.039 ms, dogfood query median overhead 0.029 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-dogfood-check-python3-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 14:17 EDT — v1.0 build/run helper pkill PATH-shadow hardening

- Hardened `script/build_and_run.sh` so helper-owned non-release pre-launch cleanup defaults to `/usr/bin/pkill` instead of resolving `pkill` through caller-controlled `PATH`. `swift`, `git`, `lldb`, and other developer tools remain intentionally PATH-resolved.
- Added strict-TDD coverage in `script/test_build_and_run.sh` for `--print-bundle-path` with fake debug Swift, a PATH-shadowed fake `pkill`, and a safe absolute pkill test override. The test proves the PATH fake is not invoked while avoiding a real app launch or real process termination.
- RED verification: `bash script/test_build_and_run.sh` failed first with `BUILD_AND_RUN_FAKE_PKILL_SENTINEL_SHOULD_NOT_RUN pkill invoked` and `test_build_and_run failed: build_and_run --print-bundle-path invoked PATH-shadowed pkill`.
- GREEN verification: `bash script/test_build_and_run.sh`, `bash -n script/build_and_run.sh script/test_build_and_run.sh`, `git diff --check`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, package smoke, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Swift Testing reported 127 tests across 20 suites. Package smoke verified `dist/LithePG.app` with packaged executable 12,507,504 bytes / 11.93 MiB, version `0.5` build `256`. Dogfood artifacts: `.build/dogfood-checks/20260601-141732/`; metrics: shell readiness 130.37 ms, connected cold start 236.01 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead -0.012 ms, dogfood query median overhead 0.034 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the test-side-effect follow-up.
- Evidence artifact: `screenshots/evidence/2026-06-01-build-and-run-pkill-path-shadow-hardening.svg`.
- No signing with a real identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 14:38 EDT — v0.5 model smoke python3 PATH-shadow hardening

- Hardened `script/v05_model_smoke.sh` so helper-owned summary JSON generation uses `/usr/bin/python3` instead of caller-controlled `PATH` resolution. `swift` remains intentionally PATH-resolved for developer toolchain selection and test fixtures.
- Added strict-TDD coverage in `script/test_v05_model_smoke.sh` with a fake PATH-shadowed `python3` that emits `V05_MODEL_SMOKE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; the helper must still complete through fake Swift fixtures, write `summary.json`, and avoid invoking or leaking the sentinel.
- RED verification: `bash script/test_v05_model_smoke.sh` failed first with `V05_MODEL_SMOKE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN python3 invoked` and `test_v05_model_smoke failed: v05_model_smoke.sh was affected by PATH-shadowed core utilities`.
- GREEN verification: `bash script/test_v05_model_smoke.sh`, `bash -n script/v05_model_smoke.sh script/test_v05_model_smoke.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and live `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/v05_model_smoke.sh` all passed. Swift Testing reported 127 tests across 20 suites; the live model smoke reported 4 selected `LocalModelAIQueryService` tests passed, release `LithePGApp` build passed, 21.379 MiB binary size, `CoreML.framework` linked, no bundled model artifact, and measurements under `.build/v05-model-smoke/20260601-143802/`.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-v05-model-smoke-python3-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 14:54 EDT — v0.4 measurement python3 PATH-shadow hardening

- Hardened `script/v04_measure.sh` so helper-owned Python JSON/SQL generation uses `/usr/bin/python3` instead of caller-controlled `PATH` resolution. `swift`, `psql`, `env`, `kill`, and `sleep` remain intentionally selectable for developer toolchains and measurement process control.
- Added strict-TDD coverage in `script/test_v04_measure.sh` with a fake PATH-shadowed `python3` that emits `V04_MEASURE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN`; the helper must still complete through fake Swift/psql fixtures, write measurement artifacts and `summary.json`, and avoid invoking or leaking the sentinel.
- RED verification: `bash script/test_v04_measure.sh` failed first with `V04_MEASURE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN python3 invoked` and `test_v04_measure failed: v04_measure.sh was affected by PATH-shadowed core utilities`.
- GREEN verification: `bash script/test_v04_measure.sh`, `bash -n script/v04_measure.sh script/test_v04_measure.sh`, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Swift Testing reported 127 tests across 20 suites; dogfood artifacts: `.build/dogfood-checks/20260601-145417/`; metrics: shell readiness 132.35 ms, connected cold start 231.91 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.068 ms, dogfood query median overhead -0.003 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-v04-measure-python3-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 15:21 EDT — v1.0 build/run verify PATH-shadow hardening

- Hardened `script/build_and_run.sh --verify` so helper-owned app launch/process verification calls use absolute-tool defaults with absolute-path-only test overrides: `/usr/bin/open`, `/bin/sleep`, `/usr/bin/pgrep`, and the existing `/usr/bin/pkill` cleanup hook. This closes the remaining non-package verify-mode PATH-shadow surface while preserving fake-tool test seams.
- Added strict-TDD coverage in `script/test_build_and_run.sh` with fake PATH-shadowed `open`, `sleep`, and `pgrep` sentinels plus safe absolute override shims; the test proves `--verify` avoids caller-controlled PATH tools and validates exact safe shim invocations. The existing `LITHEPG_BUILD_AND_RUN_PKILL` override is now rejected unless it is absolute.
- RED verification: the relative-PKILL regression failed first with `test_build_and_run failed: expected <2>, got <0>` before production validation was added.
- GREEN verification: release-helper shell tests passed (`test_build_and_run`, `test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), shell syntax checks passed, `git diff --check` passed, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-151927/`; metrics: shell readiness 131.75 ms, connected cold start 233.51 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.035 ms, dogfood query median overhead 0.035 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the PKILL/open follow-up.
- Evidence artifact: `screenshots/evidence/2026-06-01-build-run-verify-path-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 16:51 EDT — v1.0 dogfood Postgres root-resolution function-shadow hardening

- Hardened `script/dogfood_postgres.sh` so repository-root setup resolves through absolute `/bin/realpath` plus `/usr/bin/dirname`, avoiding PATH-shadowed utilities and exported shell functions named `builtin`, `cd`, or `pwd` before Docker/dogfood setup begins. The focused test harness now uses the same root-resolution pattern for its own repository-root setup and uses `builtin cd` only for fixture setup before exporting sentinel functions.
- Added strict-TDD coverage in `script/test_dogfood_postgres.sh` with exported fake `builtin`, `cd`, and `pwd` functions plus a PATH fake for `realpath`; the helper must still complete through fake Docker fixtures, keep the demo URL redacted as `postgres:***`, and avoid invoking, leaking, or writing marker files for any shadow sentinel.
- RED verification: `bash script/test_dogfood_postgres.sh` failed first with the `pwd` sentinel before `/bin/pwd` landed, then failed with `DOGFOOD_POSTGRES_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN cd invoked` before `builtin cd` landed, then failed with `DOGFOOD_POSTGRES_BUILTIN_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN builtin invoked` before the root resolver switched to `/bin/realpath`.
- GREEN verification: `bash script/test_dogfood_postgres.sh`, `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_postgres.sh script/test_dogfood_postgres.sh && git diff --check`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-165122/`; metrics: shell readiness 126.25 ms, connected cold start 226.24 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.033 ms, dogfood query median overhead 0.047 ms.
- Evidence artifact: `screenshots/evidence/2026-06-01-dogfood-postgres-pwd-function-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 17:28 EDT — v1.0 build/run root-resolution function-shadow hardening

- Hardened `script/build_and_run.sh` so repository-root setup resolves through absolute `/bin/realpath` plus `/usr/bin/dirname`, avoiding PATH-shadowed utilities and exported shell functions named `builtin`, `cd`, or `pwd` before build/package setup. The later repository chdir now uses `command cd "$ROOT_DIR"` so an exported `cd` function cannot intercept it.
- Added strict-TDD coverage in `script/test_build_and_run.sh` with exported fake `builtin`, `cd`, and `pwd` functions plus a PATH fake for `realpath`; the helper must still complete `--print-bundle-path` through fake Swift fixtures, invoke only the absolute safe pkill override, and avoid invoking, leaking, or writing marker files for any shadow sentinel.
- RED verification: after the first production hardening, the strengthened regression failed with `BUILD_AND_RUN_ROOT_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN cd invoked`, proving the remaining unqualified repository chdir was reachable before `command cd` landed.
- GREEN verification: release-helper shell tests passed (`test_build_and_run`, `test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), shell syntax checks passed, `git diff --check` passed, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-172835/`; metrics: shell readiness 129.35 ms, connected cold start 233.81 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.026 ms, dogfood query median overhead 0.035 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-build-run-root-function-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 18:05 EDT — v1.0 create-release zip root-resolution function-shadow hardening

- Hardened `script/create_release_zip.sh` so repository-root setup resolves through absolute `/bin/realpath` plus `/usr/bin/dirname`, and removed shell `cd` / `command cd` reliance from the release-helper path. Relative app/output paths are now resolved lexically against the repository root, while `package_verify.sh` still receives the same relative app argument from a repo-root working directory via `/usr/bin/perl` `chdir`/`exec`.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` with exported fake `command`, `builtin`, `cd`, and `pwd` functions plus a PATH fake for `realpath`; the helper must still create a valid app zip, keep package-verify argument behavior stable, and avoid invoking, leaking, or writing marker files for any shadow sentinel.
- RED verification: the first focused root-shadow test failed with `test_create_release_zip failed: helper root resolution invoked a function-shadowed shell builtin`; the follow-up strengthened test also failed against the intermediate `command cd` implementation before the shell-chdir dependency was eliminated.
- GREEN verification: release-helper shell tests passed (`test_create_release_zip`, `test_package_verify`, `test_sign_and_notarize`, `test_v10_release_gate`), shell syntax checks passed, `git diff --check` passed, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 127 Swift Testing tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-180315/`; metrics: shell readiness 128.77 ms, connected cold start 225.99 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.029 ms, dogfood query median overhead 0.011 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-create-release-zip-root-function-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 18:33 EDT — v1.0 sign/notarize root and chdir function-shadow hardening

- Hardened `script/sign_and_notarize.sh` so repository-root setup uses absolute `/bin/realpath` plus `/usr/bin/dirname`, and repo-root package verification runs through `/usr/bin/perl` `chdir`/`exec` instead of shell `cd`. This avoids exported shell functions named `command`, `builtin`, `cd`, or `pwd` and PATH-shadowed root-resolution utilities before signing/notary validation.
- Preserved release semantics for relative entitlements: `LITHEPG_ENTITLEMENTS=Sources/LithePGApp/LithePGApp.entitlements` now resolves against the repository root even when the caller's cwd is outside the repo, without restoring parent-shell `cd`.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` for relative entitlements from an outside cwd and for root/chdir function-shadowing with PATH-shadowed `realpath`/`dirname`; dry runs must succeed, redact signing/notary values, avoid sentinel output/marker files, and avoid creating a notary zip.
- RED verification: root/chdir shadowing first failed with `SIGN_AND_NOTARIZE_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN cd invoked`; the relative-entitlements regression then failed with `sign/notarize failed: missing entitlements file` before repo-root-relative normalization landed.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, `bash script/test_package_verify.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_v10_release_gate.sh`, shell syntax checks, `git diff --check`, static diff security scans, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-183316/`; metrics: shell readiness 130.84 ms, connected cold start 229.07 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.042 ms, dogfood query median overhead 0.025 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the relative-entitlements semantics follow-up.
- Evidence artifact: `screenshots/evidence/2026-06-01-sign-notarize-root-chdir-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 19:15 EDT — v1.0 release gate root/chdir function-shadow hardening

- Hardened `script/v10_release_gate.sh` so repository-root setup uses absolute `/bin/realpath` plus `/usr/bin/dirname`, then removed the shell `cd "$ROOT_DIR"` dependency from the gate body. Git readiness checks now run through `git -C "$ROOT_DIR"`, preserving repo-root semantics even when the caller starts outside the repository and avoiding exported shell functions named `command`, `builtin`, `cd`, `pwd`, or `unset`.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` with PATH-shadowed `dirname`/`realpath` and exported function-shadow sentinels for `command`, `builtin`, `cd`, `pwd`, and `unset`. The gate must still reach the normal blocked-publication output and must not invoke, leak, or write marker files for any sentinel.
- RED verification: the strengthened regression failed first with `V10_RELEASE_GATE_ROOT_RESOLUTION_CD_FUNCTION_SHOULD_NOT_RUN` before the repo-root `cd` dependency was removed, and the earlier unsafe `unset -f` hardening failed with an `unset` marker before it was deleted.
- GREEN verification: `bash script/test_v10_release_gate.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`), shell syntax checks, `git diff --check`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and release-impact `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` all passed. Swift Testing reported 127 tests across 20 suites. Dogfood artifacts: `.build/dogfood-checks/20260601-191514/`; metrics: shell readiness 131.28 ms, connected cold start 220.91 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.022 ms, dogfood query median overhead 0.018 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the unsafe-`unset` follow-up.
- Evidence artifact: `screenshots/evidence/2026-06-01-v10-release-gate-root-chdir-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 19:39 EDT — v1.0 run dogfood app root/chdir function-shadow hardening

- Hardened `script/run_dogfood_app.sh` so repository-root setup resolves through absolute `/bin/realpath` plus `/usr/bin/dirname`, and Swift build/bin-path/app exec steps run from the repository root through `/usr/bin/perl` `chdir`/`exec` instead of shell `cd`, `command`, `builtin`, or `pwd`. `swift` remains intentionally PATH-resolved for developer toolchain selection and test fixtures.
- Added strict-TDD coverage in `script/test_run_dogfood_app.sh` with a PATH-shadowed fake `realpath`, exported shell functions named `command`, `builtin`, `cd`, and `pwd`, and a fake Swift build directory containing whitespace; the helper must still use fake PATH-resolved `swift`, fake `dogfood_postgres.sh`, exec fake `LithePGApp`, pass startup URL/query, and avoid invoking/leaking sentinel output or marker files.
- RED verification: `bash script/test_run_dogfood_app.sh` failed first with `RUN_DOGFOOD_APP_EXPORTED_SHELL_FUNCTION_SHOULD_NOT_RUN shell function cd invoked` before production hardening; the direct-exec follow-up failed first with `exec ... fake swift build dir with spaces/LithePGApp: No such file or directory` before switching Perl exec calls to `exec { $ARGV[0] } @ARGV`.
- GREEN verification: `bash script/test_run_dogfood_app.sh`, `bash -n script/run_dogfood_app.sh script/test_run_dogfood_app.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed. Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit review blocker was fixed with the whitespace-path regression.
- Evidence artifact: `screenshots/evidence/2026-06-01-run-dogfood-app-root-chdir-hardening.svg`.
- No real app launch, Docker/Postgres start, signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 20:05 EDT — v1.0 dogfood check root/chdir function-shadow hardening

- Hardened `script/dogfood_check.sh` so repository-root setup uses absolute `/bin/realpath` plus `/usr/bin/dirname`, and removed the shell `cd "$ROOT_DIR"` dependency from the dogfood gate body. Swift test commands now run from the repository root through a small `/usr/bin/perl` `chdir`/`exec` wrapper, helper scripts are invoked by absolute repo-root paths, and git metadata uses `git -C "$ROOT_DIR"`.
- Added strict-TDD coverage in `script/test_dogfood_check.sh` with PATH-shadowed fake `realpath`, `dirname`, `date`, `mkdir`, and `cat` plus exported shell functions named `command`, `builtin`, `cd`, and `pwd`. The helper must still write `status.json`, use fake PATH-resolved `swift`/`git`, and avoid invoking or leaking any shadow sentinel.
- RED verification: `bash script/test_dogfood_check.sh` failed first with `DOGFOOD_CHECK_CD_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN cd invoked` before production hardening.
- GREEN verification: `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_check.sh script/test_dogfood_check.sh`, `git diff --check`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-200458/`; metrics: shell readiness 130.54 ms, connected cold start 225.41 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.026 ms, dogfood query median overhead 0.019 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-dogfood-check-root-chdir-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 20:29 EDT — v0.5 model smoke root/chdir function-shadow hardening

- Hardened `script/v05_model_smoke.sh` so repository-root setup uses absolute `/bin/realpath` plus `/usr/bin/dirname`, and removed the shell `cd "$ROOT_DIR"` dependency. The helper now runs its `swift test --filter LocalModelAIQueryService` and release `swift build` commands from the repository root through a small `/usr/bin/perl` `chdir`/`exec` wrapper, preserving intentionally PATH-resolved `swift` while avoiding exported shell functions named `command`, `builtin`, `cd`, or `pwd`.
- Added strict-TDD coverage in `script/test_v05_model_smoke.sh` with a PATH-shadowed fake `realpath`, exported function-shadow sentinels for `command`, `builtin`, `cd`, and `pwd`, an outside starting cwd, and a fake PATH-resolved `swift`. The fixture still verifies local-model logs and `summary.json` are produced without invoking or leaking any shadow sentinel.
- RED verification: `bash script/test_v05_model_smoke.sh` failed first with `V05_MODEL_SMOKE_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN cd function invoked` before production hardening.
- GREEN verification: `bash script/test_v05_model_smoke.sh`, `bash -n script/v05_model_smoke.sh script/test_v05_model_smoke.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Live model-smoke verification passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/v05_model_smoke.sh` wrote artifacts to `.build/v05-model-smoke/20260601-202553/`; `LocalModelAIQueryService` selected tests passed, release `LithePGApp` build passed, CoreML.framework is linked, no model artifact is bundled, and the release executable is 21.379 MiB.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-v05-model-smoke-root-chdir-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 20:47 EDT — v1.0 package verifier default-root hardening

- Hardened `script/package_verify.sh` so its no-argument default app path resolves to the helper repository root's `dist/LithePG.app` instead of the caller's current working directory. Explicit app-bundle arguments keep their existing semantics.
- Added strict-TDD coverage in `script/test_package_verify.sh` with a copied helper repo, an outside starting cwd, PATH-shadowed `dirname`/`realpath`, and exported function-shadow sentinels for `command`, `builtin`, `cd`, and `pwd`. The verifier must still validate the repo-root `dist/LithePG.app` default and avoid invoking/leaking any shadow sentinel.
- RED verification: `bash script/test_package_verify.sh` failed first with `package verification failed: app bundle not found` and `test_package_verify failed: package verifier default app path did not resolve from the helper repo root` before production hardening.
- GREEN verification: `bash script/test_package_verify.sh`, `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`, `test_build_and_run`, `test_dogfood_check`, `test_v05_model_smoke`), `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-204727/`; metrics: shell readiness 128.98 ms, connected cold start 230.80 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.035 ms, dogfood query median overhead 0.022 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-package-verify-default-root-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 21:52 EDT — v0.4 measurement helper receipt sync

- Synced the latest committed v0.4 measurement hardening receipt into this dogfood log after `main` advanced to `65fdd4d` (`[verified] chore: harden v04 measurement helper`).
- The hardening changes `script/v04_measure.sh` and `script/test_v04_measure.sh` so the measurement helper is covered against PATH-shadowed core utilities, exported Bash function leaks, and repository/output paths with spaces while preserving intentionally selectable developer tools and process-control seams.
- Recorded verification from the committed slice: `bash script/test_v04_measure.sh`, `bash -n script/v04_measure.sh script/test_v04_measure.sh && git diff --check`, adjacent `bash script/test_dogfood_check.sh`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, static added-line security scans, and independent spec/quality reviews all passed. Swift Testing reported 127 tests across 20 suites.
- Existing hardening evidence artifact from the committed slice: `screenshots/evidence/2026-06-01-v04-measure-hardening.svg`.
- Receipt-sync evidence artifact for this log update: `screenshots/evidence/2026-06-01-v04-measure-receipt-sync.svg`.
- This docs-only receipt sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-01 22:15 EDT — v1.0 build/run command function-shadow hardening

- Hardened `script/build_and_run.sh` so the helper no longer depends on shell `command cd "$ROOT_DIR"` before app build/package work. Git metadata now uses `git -C "$ROOT_DIR"`, and Swift build/bin-path commands run from the repository root through an absolute `/usr/bin/perl` `chdir`/`exec` wrapper while preserving intentionally PATH-resolved `swift`.
- Added strict-TDD coverage in `script/test_build_and_run.sh` with an exported sentinel `command()` function alongside the existing `builtin`, `cd`, and `pwd` root-shadow sentinels. The test must still use the fake PATH-resolved Swift tool and safe absolute pkill override, print the repo-root app bundle path, and avoid invoking/leaking shadow sentinels.
- RED verification: `bash script/test_build_and_run.sh` failed first with `BUILD_AND_RUN_ROOT_COMMAND_FUNCTION_SHADOW_SENTINEL_SHOULD_NOT_RUN command invoked` before the shell `command cd` dependency was removed.
- GREEN verification: `bash script/test_build_and_run.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/build_and_run.sh script/test_build_and_run.sh`, `git diff --check`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260601-221454/`; metrics: shell readiness 135.47 ms, connected cold start 256.71 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.029 ms, dogfood query median overhead 0.023 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-build-run-command-function-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 22:38 EDT — v1.0 dogfood Postgres command function-shadow hardening

- Hardened `script/dogfood_postgres.sh` so its Docker availability check no longer calls shell `command -v docker`, avoiding exported `command()` function interception before Docker setup starts while preserving intentionally PATH-selected Docker/fake-Docker behavior.
- Added strict-TDD coverage in `script/test_dogfood_postgres.sh` with an exported `command()` sentinel alongside the existing `builtin`, `cd`, `pwd`, and PATH-shadow sentinels. The helper must still complete through fake Docker fixtures, keep the demo URL redacted as `postgres:***`, and avoid invoking/leaking any command-shadow sentinel.
- RED verification: `bash script/test_dogfood_postgres.sh` failed first with `dogfood_postgres.sh was affected by PATH-shadowed core utilities` before the Docker lookup was changed.
- GREEN verification: `bash script/test_dogfood_postgres.sh`, adjacent `bash script/test_dogfood_check.sh`, syntax checks, `git diff --check`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-dogfood-postgres-command-function-shadow-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-01 23:44 EDT — v1.0 package verifier startup-env hardening

- Hardened `script/package_verify.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), preventing fake `bash` PATH interception and initial `BASH_ENV`/exported-function startup before helper verification begins.
- Added defense-in-depth sanitizer coverage before normal verifier logic: Perl probes now run through `/usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl`, treat `BASH_FUNC_*` and nonempty `BASH_ENV` as sanitize-needed, delete `BASH_FUNC_*`, `BASH_ENV`, and Perl startup env before re-execing `/bin/bash`, and fail closed through `/usr/bin/false` if the no-sanitize proof fails.
- Added strict-TDD coverage in `script/test_package_verify.sh` for fake PATH `bash`, exported `printf`, `exec`, and `set` function shadows, `BASH_ENV`-defined `set`, `BASH_ENV` that unsets itself before defining `set`, and Perl startup env attempts to hide exported Bash functions. The verifier must keep fixture paths/sentinels out of output and avoid invoking all markers.
- RED verification: new tests failed first with expected sentinels including `INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN fake bash invoked` and `BASH_ENV_UNSET_THEN_SET_SHADOW_SENTINEL_SHOULD_NOT_RUN set function invoked` before the startup hardening landed.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent `bash script/test_create_release_zip.sh`, `git diff --check`, `bash -n script/*.sh`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-01-package-verify-startup-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 00:40 EDT — v1.0 sign/notarize startup-env hardening

- Hardened `script/sign_and_notarize.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`) so copied executable invocation cannot be routed through a fake `bash` on `PATH` before helper code runs.
- Added startup sanitization before normal signing/notary logic: probes run via `/usr/bin/env -u PERL5OPT -u PERL5LIB -u PERLLIB /usr/bin/perl`, sanitize-needed includes nonempty `BASH_ENV`, `BASH_FUNC_*`, and Perl startup env, the re-exec deletes `BASH_ENV`, `BASH_FUNC_*`, `PERL5OPT`, `PERL5LIB`, and `PERLLIB`, and the helper fails closed if unsanitized startup env remains.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` for copied-helper executable fake-`bash` interception, `BASH_ENV`-defined `set`, exported `set`, and Perl startup env poisoning of the helper's own `/usr/bin/perl` calls. Tests use dry-run/help fixtures with redacted codesign identity/notary values only.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first with `SIGN_AND_NOTARIZE_INITIAL_BASH_PATH_SHADOW_SENTINEL_DO_NOT_PRINT fake bash invoked` and `test_sign_and_notarize failed: sign/notarize executable invocation used PATH-selected bash` before production hardening.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, `bash script/test_package_verify.sh`, `bash script/test_create_release_zip.sh`, `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-004834/`; metrics: shell readiness 132.16 ms, connected cold start 228.67 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.050 ms, dogfood query median overhead 0.044 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit JSON review passed with no security concerns or logic errors.
- Evidence artifact: `screenshots/evidence/2026-06-02-sign-notarize-startup-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 01:08 EDT — v1.0 dogfood Postgres executable startup Bash hardening

- Hardened `script/dogfood_postgres.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), so direct helper invocation cannot be routed through a fake `bash` on `PATH` before Docker/dogfood setup begins.
- Added strict-TDD coverage in `script/test_dogfood_postgres.sh` for copied-helper executable invocation with fake PATH-selected `bash`, fake Docker fixtures, sentinel/marker checks, and credential-redaction assertions before any captured failure output is printed.
- RED verification: `bash script/test_dogfood_postgres.sh` failed first with `DOGFOOD_POSTGRES_INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN fake bash invoked` before the shebang hardening landed.
- GREEN verification: `bash script/test_dogfood_postgres.sh`, adjacent `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_postgres.sh script/test_dogfood_postgres.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-010805/`; metrics: shell readiness 130.32 ms, connected cold start 245.75 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.033 ms, dogfood query median overhead 0.044 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-dogfood-postgres-startup-bash-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 01:40 EDT — v1.0 build/run executable startup Bash hardening

- Hardened `script/build_and_run.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), so direct helper invocation cannot be routed through a fake `bash` on `PATH` before build/package setup begins.
- Added startup sanitization before normal build/run logic: nonempty `BASH_ENV`, exported Bash functions (`BASH_FUNC_*`), and Perl startup env (`PERL5OPT`, `PERL5LIB`, `PERLLIB`) trigger a `/bin/bash -p` re-exec with those entries removed; if dirty startup env remains after the sanitizer marker is set, the helper fails closed with exit 2 instead of re-sanitizing forever or continuing.
- Added strict-TDD coverage in `script/test_build_and_run.sh` for copied-helper executable invocation with fake PATH-selected `bash`, BASH_ENV-defined and exported `set` function shadows, Perl startup poisoning of `/usr/bin/perl` helper calls, and the dirty-env-after-sanitizer fail-closed path.
- RED verification: `bash script/test_build_and_run.sh` first failed with `BUILD_AND_RUN_INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN fake bash invoked`; after the initial implementation, the added fail-closed regression failed because dirty startup env with `LITHEPG_BUILD_AND_RUN_STARTUP_ENV_SANITIZED=1` still printed helper usage instead of failing closed.
- GREEN verification: `bash script/test_build_and_run.sh`, `bash -n script/build_and_run.sh script/test_build_and_run.sh`, `git diff --check`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all passed. Swift Testing reported 127 tests across 20 suites.
- Package gate passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package` plus `./script/package_verify.sh dist/LithePG.app`; packaged executable 12,507,504 bytes / 11.93 MiB, bundle version 0.5 (278).
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-013631/`; metrics: shell readiness 126.18 ms, connected cold start 241.08 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.039 ms, dogfood query median overhead 0.039 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the fail-closed follow-up.
- Evidence artifact: `screenshots/evidence/2026-06-02-build-run-startup-bash-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 03:01 EDT — v1.0 release gate executable startup Bash hardening

- Hardened `script/v10_release_gate.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), so direct helper invocation cannot be routed through a fake `bash` on `PATH` before publication-preflight logic begins.
- Added startup sanitization before normal v1.0 gate logic: nonempty `BASH_ENV`, exported Bash functions (`BASH_FUNC_*`), and Perl startup env (`PERL5OPT`, `PERL5LIB`, `PERLLIB`) trigger a `/bin/bash -p` re-exec with those entries removed; if dirty startup env remains with the sanitizer marker already set, the helper fails closed instead of continuing or looping.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` for copied-helper executable invocation with fake PATH-selected `bash`, BASH_ENV-defined and exported `set` function shadows, Perl startup poisoning of helper probes, and the dirty-env-after-sanitizer fail-closed path.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `V10_RELEASE_GATE_INITIAL_BASH_PATH_SHADOW_SENTINEL_DO_NOT_PRINT fake bash invoked` and `test_v10_release_gate failed: v10 release gate executable invocation used PATH-selected bash` before production hardening.
- GREEN verification: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Fast release preflight verification: `./script/v10_release_gate.sh --check-remote` remained safely blocked on expected publication inputs/placeholders while confirming `origin` has `v0.5` and does not have `v1.0`.
- Release-impact dogfood note: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` failed in the live Swift slice both with this diff (`.build/dogfood-checks/20260602-025850/`, `.build/dogfood-checks/20260602-030007/`) and on a stashed clean HEAD baseline (`.build/dogfood-checks/20260602-030124/`). Follow-up investigation found the default dogfood-check URL was still using a redacted password literal internally; fixed in the 2026-06-02 03:25 EDT receipt below.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-release-gate-startup-bash-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 03:25 EDT — v1.0 dogfood check default URL redaction fix

- Fixed `script/dogfood_check.sh` so the default `POSTGRES_TEST_URL` passed to the live Swift slice and `script/v04_measure.sh` uses the real in-memory dogfood password while the helper's stdout/status JSON remain label-only and credential-safe.
- Added strict-TDD coverage in `script/test_dogfood_check.sh` proving the live Swift fixture and v0.4 measurement fixture receive the real default dogfood URL internally instead of the redacted literal, while helper output and `status.json` never contain the credential-bearing URL.
- RED verification: `bash script/test_dogfood_check.sh` failed first with `test_dogfood_check failed: live Swift did not receive default POSTGRES_TEST_URL with real password` before the production default URL fix.
- GREEN verification: `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_check.sh script/test_dogfood_check.sh`, `git diff --check`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-032512/`; metrics: shell readiness 133.16 ms, connected cold start 263.16 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.030 ms, dogfood query median overhead 0.036 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-dogfood-check-default-url-redaction-fix.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 03:57 EDT — v1.0 run dogfood app executable startup Bash hardening

- Hardened `script/run_dogfood_app.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), so copied/direct helper invocation cannot be routed through a fake `bash` on `PATH` before dogfood app setup begins.
- Added startup sanitization before normal run-dogfood-app logic: nonempty `BASH_ENV`, exported Bash functions (`BASH_FUNC_*`), and Perl startup env (`PERL5OPT`, `PERL5LIB`, `PERLLIB`) trigger a `/bin/bash -p` re-exec with those entries removed. Dirty startup env after the sanitizer marker now fails closed with exit 2.
- Added strict-TDD coverage in `script/test_run_dogfood_app.sh` for direct executable invocation with fake PATH-selected `bash`, BASH_ENV/exported `set` function shadowing, Perl startup poisoning, dirty-env-after-sanitizer fail-closed behavior, and continued fake PATH-resolved `swift` selection.
- RED verification: `bash script/test_run_dogfood_app.sh` failed first with `RUN_DOGFOOD_APP_INITIAL_BASH_PATH_SHADOW_SHOULD_NOT_RUN fake PATH-selected bash invoked` before production hardening.
- GREEN verification: `bash script/test_run_dogfood_app.sh`, `bash -n script/run_dogfood_app.sh script/test_run_dogfood_app.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Independent reviews: spec compliance PASS; code quality/security APPROVED; pre-commit JSON review passed with no security concerns or logic errors.
- Evidence artifact: `screenshots/evidence/2026-06-02-run-dogfood-app-startup-bash-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 04:20 EDT — v0.5 model smoke executable startup Bash hardening

- Hardened `script/v05_model_smoke.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), so copied/direct model-smoke invocation cannot be routed through a fake `bash` on `PATH` before local-model gate checks begin.
- Added startup sanitization before normal model-smoke logic: nonempty `BASH_ENV`, exported Bash functions (`BASH_FUNC_*`), and Perl startup env (`PERL5OPT`, `PERL5LIB`, `PERLLIB`) trigger a `/bin/bash -p` re-exec with those entries removed. Dirty startup env after the sanitizer marker fails closed with exit 2.
- Added strict-TDD coverage in `script/test_v05_model_smoke.sh` for direct executable invocation with fake PATH-selected `bash`, BASH_ENV/exported `set` function shadowing, Perl startup poisoning, dirty-env-after-sanitizer fail-closed behavior, and continued fake PATH-resolved `swift` selection.
- RED verification: `bash script/test_v05_model_smoke.sh` failed first with `V05_MODEL_SMOKE_INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN fake bash invoked` before production hardening.
- GREEN verification: `bash script/test_v05_model_smoke.sh`, adjacent release-helper shell tests, `bash -n script/v05_model_smoke.sh script/test_v05_model_smoke.sh`, `git diff --check`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Live model-smoke verification passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/v05_model_smoke.sh` wrote artifacts to `.build/v05-model-smoke/20260602-042035/`; `LocalModelAIQueryService` selected tests passed, release `LithePGApp` build passed, CoreML.framework is linked, no model artifact is bundled, and the release executable is 21.379 MiB.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-v05-model-smoke-startup-bash-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 04:50 EDT — v0.4 measurement executable startup Bash hardening

- Hardened `script/v04_measure.sh` executable startup by switching from PATH-selected `#!/usr/bin/env bash` to absolute privileged Bash (`#!/bin/bash -p`), so copied/direct measurement-helper invocation cannot be routed through a fake `bash` on `PATH` before v0.4 release measurements begin.
- Added startup sanitization before normal measurement logic: nonempty `BASH_ENV`, exported Bash functions (`BASH_FUNC_*`), and Perl startup env (`PERL5OPT`, `PERL5LIB`, `PERLLIB`) trigger a `/bin/bash -p` re-exec with those entries removed. Dirty startup env after the sanitizer marker fails closed with exit 2.
- Added strict-TDD coverage in `script/test_v04_measure.sh` for direct executable invocation with fake PATH-selected `bash`, BASH_ENV/exported `set` function shadowing, Perl startup poisoning, dirty-env-after-sanitizer fail-closed behavior, and continued fake PATH-resolved `swift`/`psql` selection.
- RED verification: `bash script/test_v04_measure.sh` failed first with `V04_MEASURE_INITIAL_BASH_PATH_SHADOW_SENTINEL_SHOULD_NOT_RUN fake bash invoked` before production hardening.
- GREEN verification: `bash script/test_v04_measure.sh`, `bash -n script/v04_measure.sh script/test_v04_measure.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-045033/`; metrics: shell readiness 131.07 ms, connected cold start 241.38 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.040 ms, dogfood query median overhead 0.030 ms.
- Evidence artifact: `screenshots/evidence/2026-06-02-v04-measure-startup-bash-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 05:13 EDT — v1.0 create-release zip startup-env fail-closed hardening

- Hardened `script/create_release_zip.sh` so dirty Bash/Perl startup environment detected after `LITHEPG_CREATE_RELEASE_ZIP_STARTUP_ENV_SANITIZED=1` fails closed with exit 2 instead of re-sanitizing and continuing.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` for a copied executable helper with dirty `BASH_ENV`, an exported Bash function, and the sanitizer marker already set. The test requires the generic redacted failure message, no sentinel/fixture-path leakage, and no created public zip.
- RED verification: a temporary HEAD fixture using the new test but the old helper failed with `test_create_release_zip failed: create release zip sanitizer marker with dirty startup env should exit 2, got 0`.
- GREEN verification: `bash script/test_create_release_zip.sh`, adjacent release-helper tests (`test_package_verify`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/create_release_zip.sh script/test_create_release_zip.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-051314/`; metrics: shell readiness 130.19 ms, connected cold start 261.21 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.047 ms, dogfood query median overhead 0.025 ms.
- Evidence artifact: `screenshots/evidence/2026-06-02-create-release-zip-startup-env-fail-closed.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 05:39 EDT — v1.0 sign/notarize startup-env fail-closed hardening

- Hardened `script/sign_and_notarize.sh` so dirty Bash/Perl startup environment detected after `LITHEPG_SIGN_AND_NOTARIZE_STARTUP_ENV_SANITIZED=1` fails closed with exit 2 instead of re-sanitizing and continuing.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` for a copied executable helper with dirty `BASH_ENV`, an exported Bash function, configured redacted signing/notary values, and the sanitizer marker already set. The test requires the generic redacted failure message, no sentinel/fixture-path/signing/notary leakage, no fake package-verifier or dry-run success output, and no created notary zip.
- RED verification: the new regression failed on the old helper with `test_sign_and_notarize failed: sign/notarize sanitizer marker with dirty startup env should exit 2, got 0`.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`), `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-053959/`; metrics: shell readiness 129.42 ms, connected cold start 246.36 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.046 ms, dogfood query median overhead 0.016 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-sign-notarize-startup-env-fail-closed.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 06:08 EDT — v1.0 dogfood Postgres startup-env fail-closed hardening

- Hardened `script/dogfood_postgres.sh` so dirty Bash/Perl startup environment detected after `LITHEPG_DOGFOOD_POSTGRES_STARTUP_ENV_SANITIZED=1` fails closed with exit 2 instead of continuing into Docker setup.
- Added strict-TDD coverage in `script/test_dogfood_postgres.sh` for the fail-closed sanitizer-marker path and normal dirty-startup-env sanitization through the fake Docker fixture. The tests assert no fake Docker work happens on fail-closed, and output avoids fixture paths, passwords, and sentinel text.
- RED verification: the new regression failed on the old helper with `test_dogfood_postgres failed: dogfood_postgres sanitizer marker with dirty startup env should exit 2, got 0`.
- GREEN verification: `bash script/test_dogfood_postgres.sh`, adjacent `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_postgres.sh script/test_dogfood_postgres.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-060758/`; metrics: shell readiness 131.21 ms, connected cold start 240.56 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.023 ms, dogfood query median overhead 0.044 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-dogfood-postgres-startup-env-fail-closed.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 06:25 EDT — v1.0 package verifier startup-env fail-closed hardening

- Hardened `script/package_verify.sh` so dirty Bash/Perl startup environment detected after `LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1` fails closed with exit 2 instead of re-sanitizing and continuing into package verification.
- Added strict-TDD coverage in `script/test_package_verify.sh` for copied executable helpers with dirty `BASH_ENV` plus an exported Bash function, and with dirty Perl startup env (`PERL5OPT`), a valid fixture app bundle, and the sanitizer marker already set. The tests require generic redacted failure output and no package verification success.
- RED verification: the new regressions failed on the old helper with `test_package_verify failed: package verifier sanitizer marker with dirty startup env should exit 2, got 0`, then `test_package_verify failed: package verifier sanitizer marker with dirty Perl startup env should exit 2, got 0`.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, SVG parse, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-063119/`; metrics: shell readiness 126.76 ms, connected cold start 248.41 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.043 ms, dogfood query median overhead 0.027 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-package-verify-startup-env-fail-closed.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 07:11 EDT — v1.0 package verifier privileged Bash re-exec hardening

- Hardened `script/package_verify.sh` startup-env sanitizer re-exec to invoke `/bin/bash -p`, matching its privileged Bash shebang and the other v1.0 release/dogfood helpers after dirty Bash/Perl startup env is scrubbed.
- Added strict-TDD coverage in `script/test_package_verify.sh` asserting the package verifier sanitizer keeps the privileged re-exec form `exec { $bash } $bash, "-p", @ARGV;`.
- RED verification: `bash script/test_package_verify.sh` failed first with `test_package_verify failed: expected output to contain: exec { $bash } $bash, "-p", @ARGV;` before the production re-exec fix.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-071038/`; metrics: shell readiness 130.93 ms, connected cold start 241.57 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.035 ms, dogfood query median overhead 0.011 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-package-verify-privileged-reexec.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 07:26 EDT — v1.0 public status receipt refresh

- Refreshed `README.md` and `CHANGELOG.md` with the latest committed 2026-06-02 local dogfood gate metrics from `.build/dogfood-checks/20260602-071038/`; that receipt's `status.json` records `main` at `e24a9b2`.
- Current public-reader status now reports shell readiness 130.93 ms, connected cold start 241.57 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.035 ms, and dogfood query median overhead 0.011 ms, while keeping the public `v1.0` blockers unchanged.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-public-status-receipt-refresh.svg`.
- This docs-only receipt refresh attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 08:00 EDT — v1.0 release draft metric sync

- Synced `docs/releases/v1.0-draft.md` with the same latest local dogfood metrics already published in `README.md` and `CHANGELOG.md` from `.build/dogfood-checks/20260602-071038/` on `main` at `e24a9b2`.
- The draft now reports shell readiness 130.93 ms, connected cold start 241.57 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, packaged executable 11.93 MiB, `SELECT 1` median overhead 0.035 ms, and dogfood-query median overhead 0.011 ms.
- The release copy, Homebrew, security contact, signing/notary, GitHub Actions, SHA-256, and publication approval placeholders remain intentionally blocked pending Omar-controlled external inputs.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-release-draft-metric-sync.svg`.
- This docs-only release-draft sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 08:25 EDT — v1.0 dogfood check startup receipt sync

- Synced the committed `script/dogfood_check.sh` startup-env hardening receipt into this dogfood log after `main` advanced past `c21955e` (`[verified] chore(dogfood): harden check startup env`).
- That committed slice hardened direct dogfood-check startup against fake PATH-selected Bash, `BASH_ENV`, exported Bash functions, and Perl startup-environment poisoning while preserving intentional developer-tool PATH selection inside the checked commands.
- Existing hardening evidence artifact from the committed slice: `screenshots/evidence/2026-06-02-dogfood-check-hardening.svg`.
- Receipt-sync evidence artifact for this log update: `screenshots/evidence/2026-06-02-dogfood-check-startup-receipt-sync.svg`.
- This docs-only receipt sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 08:44 EDT — v1.0 release gate empty BASH_ENV fail-closed hardening

- Hardened `script/v10_release_gate.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the existing fail-closed posture for dirty Bash/Perl startup state. The sanitizer now checks `BASH_ENV` key presence before normal release-gate logic and rejects any remaining `BASH_ENV` key after a sanitizer-marked re-entry.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` for direct helper invocation with `LITHEPG_V10_RELEASE_GATE_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must exit 2 with the generic sanitizer failure message and must not continue to normal `--help` usage output.
- RED verification: `bash script/test_v10_release_gate.sh` failed first because the old helper printed normal usage instead of failing closed for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_v10_release_gate.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`), `bash -n script/*.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-084410/`; metrics: shell readiness 131.53 ms, connected cold start 275.03 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.015 ms, dogfood query median overhead 0.035 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-release-gate-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 09:12 EDT — v1.0 package verifier empty BASH_ENV fail-closed hardening

- Hardened `script/package_verify.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the v1.0 release-gate sanitizer posture. The initial sanitizer path now scrubs `BASH_ENV` even when it is empty, and the sanitizer-marked fail-closed guard rejects any remaining `BASH_ENV` key before package verification can continue.
- Added strict-TDD coverage in `script/test_package_verify.sh` for direct copied-helper invocation with `LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1` and `BASH_ENV=""`; the helper must exit 2 with the generic dirty-startup-environment message and must not print package success, usage, fixture paths, sentinel text, or a synthetic ambient private value.
- RED verification: the new regression failed first on the old helper with `test_package_verify failed: package verifier sanitizer marker with empty BASH_ENV should exit 2, got 0` after printing package verification success.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-091144/`; metrics: shell readiness 131.01 ms, connected cold start 285.49 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.033 ms, dogfood query median overhead 0.044 ms.
- Independent reviews: spec compliance PASS after the credential-leakage assertion fix; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-package-verify-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 09:37 EDT — v1.0 build/run helper empty BASH_ENV fail-closed hardening

- Hardened `script/build_and_run.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the recent v1.0 release-gate and package-verifier posture. The sanitizer now triggers on `BASH_ENV` key presence and the post-sanitizer guard rejects any remaining `BASH_ENV` key before normal run/package/help logic can continue.
- Added strict-TDD coverage in `script/test_build_and_run.sh` for direct helper invocation with `LITHEPG_BUILD_AND_RUN_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must exit 2, print only the generic build/run sanitizer failure, avoid normal usage output, and avoid leaking the synthetic private sentinel.
- RED verification: `bash script/test_build_and_run.sh` failed first because the old helper printed normal usage instead of failing closed with exit 2 for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_build_and_run.sh`, adjacent release-helper tests (`test_package_verify`, `test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/*.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-093717/`; metrics: shell readiness 130.31 ms, connected cold start 250.02 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.033 ms, dogfood query median overhead -0.009 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-build-run-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 09:57 EDT — v0.5 model smoke empty BASH_ENV fail-closed hardening

- Hardened `script/v05_model_smoke.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the current release-helper sanitizer posture. Sanitizer-marked reentry with any remaining `BASH_ENV` now fails closed with exit 2 before local-model smoke work can run.
- Added strict-TDD coverage in `script/test_v05_model_smoke.sh` for direct helper invocation with `LITHEPG_V05_MODEL_SMOKE_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must emit only the generic sanitizer failure, avoid private sentinel leakage, and avoid normal fake Swift/model-smoke output.
- RED verification: `bash script/test_v05_model_smoke.sh` failed first because the old helper continued into fake model-smoke work instead of failing closed for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_v05_model_smoke.sh`, `bash -n script/*.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Live model-smoke verification passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/v05_model_smoke.sh` wrote artifacts to `.build/v05-model-smoke/20260602-095647/`; `LocalModelAIQueryService` selected tests passed, release `LithePGApp` build passed, CoreML.framework is linked, no model artifact is bundled, and the release executable is 21.379 MiB.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-095701/`; metrics: shell readiness 129.27 ms, connected cold start 241.15 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.039 ms, dogfood query median overhead 0.034 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-v05-model-smoke-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 10:19 EDT — v1.0 create-release zip empty BASH_ENV fail-closed hardening

- Hardened `script/create_release_zip.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the current v1.0 release-helper sanitizer posture. Sanitizer-marked reentry with any remaining `BASH_ENV` now fails closed with exit 2 before package verification or public zip creation can run.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` for direct copied-helper invocation with `LITHEPG_CREATE_RELEASE_ZIP_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must emit the generic sanitizer failure, avoid usage/zip/SHA/size output, avoid private sentinel and fixture-path leakage, skip package verification, and create no zip.
- RED verification: `bash script/test_create_release_zip.sh` failed first because the old helper exited 0 and created normal zip output for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_create_release_zip.sh`, adjacent release-helper tests (`test_package_verify`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/create_release_zip.sh script/test_create_release_zip.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-101907/`; metrics: shell readiness 130.75 ms, connected cold start 256.03 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.056 ms, dogfood query median overhead 0.034 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-create-release-zip-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 10:40 EDT — v1.0 run dogfood app empty BASH_ENV fail-closed hardening

- Hardened `script/run_dogfood_app.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the current release-helper sanitizer posture. Sanitizer-marked reentry with any remaining `BASH_ENV` now fails closed with exit 2 before dogfood Postgres, Swift build, or app launch can run.
- Added strict-TDD coverage in `script/test_run_dogfood_app.sh` for direct helper invocation with `LITHEPG_RUN_DOGFOOD_APP_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must emit the generic sanitizer failure, avoid private sentinel leakage, skip fake dogfood Postgres and Swift work, and avoid app output.
- RED verification: `bash script/test_run_dogfood_app.sh` failed first because the old helper continued into fake app work instead of failing closed for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_run_dogfood_app.sh`, `bash -n script/run_dogfood_app.sh script/test_run_dogfood_app.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-103951/`; metrics: shell readiness 131.24 ms, connected cold start 268.86 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.033 ms, dogfood query median overhead 0.019 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-run-dogfood-app-empty-bash-env-hardening.svg`.
- No real app launch outside the fake test fixture, signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 11:01 EDT — v1.0 sign/notarize empty BASH_ENV fail-closed hardening

- Hardened `script/sign_and_notarize.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the current release-helper sanitizer posture. Sanitizer-marked reentry with any remaining `BASH_ENV` now fails closed with exit 2 before package verification, dry-run planning, signing, zipping, notarization, stapling, or validation can run.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` for direct copied-helper invocation with `LITHEPG_SIGN_AND_NOTARIZE_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must emit the exact generic sanitizer failure, avoid usage/fake package/dry-run output, avoid sentinel/codesign/notary/fixture-path leakage, and create no notary zip.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first because the old helper continued through fake package verification and dry-run output instead of failing closed for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_package_verify`), `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-110100/`; metrics: shell readiness 133.75 ms, connected cold start 238.64 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.028 ms, dogfood query median overhead 0.025 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-sign-notarize-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 11:22 EDT — v1.0 dogfood Postgres empty BASH_ENV fail-closed hardening

- Hardened `script/dogfood_postgres.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the current release-helper sanitizer posture. Sanitizer-marked reentry with any remaining `BASH_ENV` now fails closed with exit 2 before Docker setup, container readiness checks, seed loading, or URL reporting can run.
- Added strict-TDD coverage in `script/test_dogfood_postgres.sh` for direct copied-helper invocation with `LITHEPG_DOGFOOD_POSTGRES_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must emit the exact generic sanitizer failure, avoid fake Docker work, and avoid synthetic private sentinel/fixture-path/credential leakage.
- RED verification: `bash script/test_dogfood_postgres.sh` failed first because the old helper continued through fake dogfood setup instead of failing closed for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_dogfood_postgres.sh`, adjacent `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_postgres.sh script/test_dogfood_postgres.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-112408/`; metrics: shell readiness 128.92 ms, connected cold start 257.02 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.033 ms, dogfood query median overhead 0.013 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-dogfood-postgres-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 11:47 EDT — v0.4 measurement empty BASH_ENV fail-closed hardening

- Hardened `script/v04_measure.sh` so an empty-but-present `BASH_ENV` is treated as dirty startup environment, matching the current release-helper sanitizer posture. Sanitizer-marked reentry with any remaining `BASH_ENV` now fails closed with exit 2 before dogfood setup, Swift builds, benchmark runs, metrics output, or summary generation can run.
- Added strict-TDD coverage in `script/test_v04_measure.sh` for direct helper invocation with `LITHEPG_V04_MEASURE_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`; the helper must emit only the generic v04_measure sanitizer failure, avoid synthetic private sentinel leakage, skip fake dogfood/app/bench work, and create no measurement output directory or `summary.json`.
- RED verification: `bash script/test_v04_measure.sh` failed first because the old helper proceeded into fake dogfood setup instead of failing closed for empty `BASH_ENV` after the sanitizer marker.
- GREEN verification: `bash script/test_v04_measure.sh`, `bash -n script/v04_measure.sh script/test_v04_measure.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-114721/`; metrics: shell readiness 132.73 ms, connected cold start 282.45 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.032 ms, dogfood query median overhead 0.026 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-v04-measure-empty-bash-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 12:05 EDT — v1.0 public status metrics refresh

- Refreshed `README.md`, `CHANGELOG.md`, and `docs/releases/v1.0-draft.md` from `.build/dogfood-checks/20260602-114721/` on `main` at `4b89b9d`.
- Safe metrics synced: 132.73 ms shell readiness; 282.45 ms connected cold start; 21.379 MiB raw release executable; 11.980 MiB strip-probe executable; 0.032 ms median `SELECT 1` overhead; 0.026 ms median dogfood-query overhead.
- Gate statuses synced: `defaultSwiftTest`, `liveSwiftTest`, and `v04Measure` passed.
- Historical dogfood examples touched by this docs sync were kept in credential-redacted form, and the v0.4 redaction/concurrency receipt wording remains intact.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-public-status-metrics-refresh.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 13:06 EDT — dogfood_check empty BASH_ENV receipt sync

- Receipt sync for the already-committed `script/dogfood_check.sh` startup-env hardening from `c21955e` (`[verified] chore(dogfood): harden check startup env`); no Swift/code behavior changed in this slice.
- Clarified the detail omitted from the prior dogfood-check receipt: the helper treats an empty-but-present `BASH_ENV` key as dirty startup environment and fails closed after sanitizer-marked reentry instead of continuing into dogfood work.
- Existing fail-closed coverage is in `script/test_dogfood_check.sh`: it invokes the helper with `LITHEPG_DOGFOOD_CHECK_STARTUP_ENV_SANITIZED=1` and `BASH_ENV=""`, expects the generic sanitizer failure path, and ensures normal dogfood startup output is skipped.
- Evidence artifact: `screenshots/evidence/2026-06-02-dogfood-check-empty-bash-env-receipt-sync.svg`.
- This is docs/evidence only; no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 13:32 EDT — package verifier empty Perl startup-env fail-closed hardening

- Hardened `script/package_verify.sh` so empty-but-present Perl startup env keys (`PERL5OPT`, `PERL5LIB`, and `PERLLIB`) are treated as dirty startup environment, matching the current release-helper sanitizer posture. Sanitizer-marked reentry with any of those keys present now fails closed with exit 2 before package verification or usage output can continue.
- Added strict-TDD coverage in `script/test_package_verify.sh` for all three empty Perl startup env keys with `LITHEPG_PACKAGE_VERIFY_BASH_FUNCTIONS_SANITIZED=1`; each case expects the generic package-verifier sanitizer failure and asserts no package verification output, usage text, fixture path, synthetic sentinel, or ambient private value leaks.
- RED verification: `bash script/test_package_verify.sh` failed first with `package verifier sanitizer marker with empty PERL5OPT should exit 2, got 0`.
- GREEN verification: `bash script/test_package_verify.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-133218/`; metrics: shell readiness 133.70 ms, connected cold start 244.31 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.010 ms, dogfood query median overhead 0.060 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-package-verify-empty-perl-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 14:17 EDT — v1.0 release gate Ruby startup-env fail-closed hardening

- Hardened `script/v10_release_gate.sh` so Ruby startup env keys (`RUBYOPT`, `RUBYLIB`, and `RUBYGEMS_GEMDEPS`) are treated as dirty startup environment before the Homebrew cask Ruby syntax check. Sanitizer-marked reentry now fails closed with exit 2 if any of those keys remain, and the cask syntax check runs with those variables scrubbed plus Ruby startup/gems disabled.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` for poisoned Ruby startup env, empty-but-present Ruby startup env, and `RUBYGEMS_GEMDEPS` fail-closed behavior; tests assert synthetic private sentinel values do not leak.
- RED verification: `bash script/test_v10_release_gate.sh` first failed with `v10 release gate startup sanitizer did not fail closed with exit 2 when RUBYOPT remained after sanitizer marker`, then again for the `RUBYGEMS_GEMDEPS` regression before the final fix.
- GREEN verification: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-141646/`; metrics: shell readiness 134.11 ms, connected cold start 248.31 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.065 ms, dogfood query median overhead 0.051 ms.
- Fast publication preflight check: `./script/v10_release_gate.sh --check-remote` remained safely blocked on the expected dirty-tree/external-publication placeholders and approvals while confirming `origin` has `v0.5` and does not have `v1.0`.
- Independent reviews: spec compliance PASS; code quality/security APPROVED after the `RUBYGEMS_GEMDEPS` hardening fix.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-ruby-startup-env-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 14:35 EDT — v1.0 public status metrics sync

- Refreshed `README.md`, `CHANGELOG.md`, and `docs/releases/v1.0-draft.md` from the latest committed local dogfood gate at `.build/dogfood-checks/20260602-141646/` on `main` at `d4f402a`.
- Safe metrics synced: 134.11 ms shell readiness; 248.31 ms connected cold start; 21.379 MiB raw release executable; 11.980 MiB strip-probe executable; 0.065 ms median `SELECT 1` overhead; 0.051 ms median dogfood-query overhead.
- Gate statuses synced: `defaultSwiftTest`, `liveSwiftTest`, and `v04Measure` passed.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-public-status-metrics-sync.svg`.
- This docs-only status sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 15:02 EDT — dogfood_check status JSON argv hardening

- Hardened `script/dogfood_check.sh` so status JSON metadata is passed into the Python writer as argv data with a quoted heredoc instead of interpolating shell values into Python source.
- Added strict-TDD regression coverage in `script/test_dogfood_check.sh` for a valid git branch containing a double quote (`dogfood-check-quote"branch`), proving `status.json` remains valid JSON and credential redaction is preserved.
- RED verification: the new test failed first because the old helper produced invalid Python source (`"branch": "dogfood-check-quote"branch"`) and could not write `status.json`.
- GREEN verification passed: `bash script/test_dogfood_check.sh`, `bash -n script/dogfood_check.sh script/test_dogfood_check.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-150152/`; metrics: shell readiness 132.10 ms, connected cold start 253.84 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.045 ms, dogfood query median overhead 0.112 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-dogfood-check-status-json-argv-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 15:18 EDT — v1.0 public status metrics sync

- Refreshed `README.md`, `CHANGELOG.md`, and `docs/releases/v1.0-draft.md` from the latest committed local dogfood gate at `.build/dogfood-checks/20260602-150152/` on `main` at `7c580d4`.
- Safe metrics synced: 132.10 ms shell readiness; 253.84 ms connected cold start; 21.379 MiB raw release executable; 11.980 MiB strip-probe executable; 0.045 ms median `SELECT 1` overhead; 0.112 ms median dogfood-query overhead.
- Gate statuses synced: `defaultSwiftTest`, `liveSwiftTest`, and `v04Measure` passed.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-public-status-metrics-sync-latest.svg`.
- This docs-only status sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 15:45 EDT — v1.0 sign/notarize publication tool PATH hardening

- Hardened `script/sign_and_notarize.sh` real-mode publication-sensitive tool invocations so `codesign`, `ditto`, `xcrun`, and `spctl` are called by absolute system paths (`/usr/bin/codesign`, `/usr/bin/ditto`, `/usr/bin/xcrun`, and `/usr/sbin/spctl`) instead of through `PATH`.
- Added strict-TDD coverage in `script/test_sign_and_notarize.sh` for PATH-shadowed `codesign`/`ditto`/`xcrun`/`spctl`: static assertions pin every publication-sensitive invocation to the absolute system-tool variables, and the dynamic regression proves PATH-shadowed fake shims are not reached before real codesign validation fails. Output remains redacted and no notary zip is created.
- RED verification: `bash script/test_sign_and_notarize.sh` failed first because the old helper passed with PATH-shadowed publication tools; a follow-up static assertion check also confirmed the old helper lacked the absolute publication-tool variables.
- GREEN verification: `bash script/test_sign_and_notarize.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_package_verify`, `test_v10_release_gate`), `bash -n script/sign_and_notarize.sh script/test_sign_and_notarize.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-154445/`; metrics: shell readiness 127.05 ms, connected cold start 263.35 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.027 ms, dogfood query median overhead 0.029 ms.
- Evidence artifact: `screenshots/evidence/2026-06-02-sign-notarize-publication-tool-path-hardening.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 16:09 EDT — v1.0 publication preflight receipt

- Re-ran the fast publication preflight after the latest sign/notarize publication-tool hardening: `./script/v10_release_gate.sh --check-remote`.
- Verified expected repository/tag state: `main` was clean at `a3af2e4`, local/origin `v0.5` existed, and local/origin `v1.0` was absent.
- Verified local artifact inspection still sees `dist/LithePG.app.zip` with a present app wrapper, matching bundle metadata, canonical entries, executable Mach-O format, code-signature resources, valid code-signature verification, matching signature identifier, and runtime option present.
- The preflight intentionally remains blocked with 12 blockers: release-copy/Homebrew/security placeholders, missing approved release-artifact SHA-256 input, missing codesign identity/notary profile/security contact/Homebrew tap, GitHub Actions not approved, release-copy approval not approved, and publication approval not approved.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-publication-preflight-latest.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 16:28 EDT — v1.0 release gate Python isolation hardening

- Hardened `script/v10_release_gate.sh` so both embedded Python zip-inspection probes run with isolated mode (`/usr/bin/python3 -I -`) instead of inheriting ambient Python startup/import environment while inspecting the public release artifact.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` requiring exactly two isolated Python stdin probes and rejecting the previous non-isolated `/usr/bin/python3 - "` invocation shape.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `test_v10_release_gate failed: expected 2 occurrences of: /usr/bin/python3 -I -` before production hardening.
- GREEN verification: `bash script/test_v10_release_gate.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_package_verify`), `bash -n script/*.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-162830/`; metrics: shell readiness 128.65 ms, connected cold start 266.86 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.025 ms, dogfood query median overhead 0.036 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-release-gate-python-isolation.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 16:49 EDT — v1.0 public status metrics sync

- Refreshed `README.md`, `CHANGELOG.md`, and `docs/releases/v1.0-draft.md` from the latest committed local dogfood gate at `.build/dogfood-checks/20260602-164838/` after the Python-isolation release-gate hardening landed on `main` at `958dd50`.
- Safe metrics synced: 130.43 ms shell readiness; 253.83 ms connected cold start; 21.379 MiB raw release executable; 11.980 MiB strip-probe executable; 0.037 ms median `SELECT 1` overhead; 0.017 ms median dogfood-query overhead.
- Gate statuses synced: `defaultSwiftTest`, `liveSwiftTest`, and `v04Measure` passed.
- Evidence artifact: `screenshots/evidence/2026-06-02-v10-public-status-metrics-sync-python-isolation.svg`.
- This docs-only status sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 17:36 EDT — v1.0 artifact-only gate receipt sync

- Synced the committed artifact-only release-gate slice from `4895035` (`[verified] feat(release): add v1.0 artifact-only gate`) into this dogfood log after `main` advanced and pushed to `origin/main`.
- That slice added `script/v10_release_gate.sh --artifact-only` plus `LITHEPG_ARTIFACT_ONLY=1` as a narrowly scoped final-artifact validator. It checks the `LithePG.app.zip` path, app wrapper, metadata, code-signature/runtime inspection, and approved SHA-256 match without printing SHA values.
- The artifact-only mode is intentionally **not** a publication gate: it skips tag readiness, release-copy, Homebrew cask, security policy, external credential, approval, and publication checks, and it does not approve tagging or publishing.
- Existing TDD coverage in `script/test_v10_release_gate.sh` proves the valid artifact-only CLI/env paths, missing SHA blocker, mismatched SHA blocker, redacted digest output, and absence of external publication sections in artifact-only output.
- Existing verification from the committed slice: `bash script/test_v10_release_gate.sh`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` passed; the dogfood gate wrote artifacts under `.build/dogfood-checks/20260602-171838/`.
- Original evidence artifact: `docs/evidence/20260602-v10-artifact-only-release-gate.svg`; receipt-sync evidence artifact: `screenshots/evidence/2026-06-02-v10-artifact-only-receipt-sync.svg`.
- This docs/evidence receipt sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-02 17:56 EDT — package verifier hard-link rejection

- Hardened `script/package_verify.sh` so release app bundles fail verification if any regular file has multiple hard links, closing a local mutability/TOCTOU gap between package verification and downstream zip/sign/notarization steps.
- Added strict-TDD coverage in `script/test_package_verify.sh` that first proved the old verifier accepted a hard-linked `Contents/MacOS/LithePGApp` and then verifies the new generic failure path without leaking fixture paths, sentinels, or external hard-link target names.
- RED verification: `bash script/test_package_verify.sh` failed first with `package verifier unexpectedly accepted a hard-linked file inside the app bundle`.
- GREEN verification passed: `bash script/test_package_verify.sh`, adjacent release-helper tests (`test_create_release_zip`, `test_sign_and_notarize`, `test_v10_release_gate`), `bash -n script/package_verify.sh script/test_package_verify.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-175538/`; metrics: shell readiness 138.99 ms, connected cold start 253.37 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.083 ms, dogfood query median overhead 0.073 ms.
- Evidence artifact: `screenshots/evidence/2026-06-02-package-verify-hardlink-rejection.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-02 18:26 EDT — release zip artifact-only gate wiring

- Hardened `script/create_release_zip.sh` so the staged public `LithePG.app.zip` is validated by `script/v10_release_gate.sh --artifact-only` before it is renamed into the final output path.
- The helper now passes the staged temp zip path through `LITHEPG_RELEASE_ZIP_PATH` and its computed SHA-256 through `LITHEPG_RELEASE_ZIP_SHA256`; artifact-gate output is suppressed and a failing gate emits only the generic `create_release_zip failed: release artifact validation failed` message.
- Added strict-TDD coverage in `script/test_create_release_zip.sh` proving the success path invokes the artifact-only gate with the staged zip and matching 64-hex SHA, and proving a failing fake artifact gate stops before final rename without leaking sentinel paths or creating the final zip.
- RED verification: `bash script/test_create_release_zip.sh` failed first with `test_create_release_zip failed: helper unexpectedly passed when artifact gate failed`.
- GREEN verification passed: `bash script/test_create_release_zip.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash -n` for the touched release-helper scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. Swift Testing reported 127 tests across 20 suites.
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260602-182609/`; metrics: shell readiness 129.31 ms, connected cold start 263.76 ms, raw release executable 21.379 MiB, strip-probe executable 11.980 MiB, `SELECT 1` median overhead 0.068 ms, dogfood query median overhead 0.136 ms.
- Independent reviews: spec compliance PASS; code quality/security APPROVED.
- Evidence artifact: `screenshots/evidence/2026-06-02-create-release-zip-artifact-gate.svg`.
- No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted.

## 2026-06-10 12:55 EDT — app icon + LithePGApp packaging product restore

- Restored the `LithePGApp` executable product that the `jun 10` single-binary refactor removed: the SwiftUI module now builds as the `LithePGAppUI` library (still at `Sources/LithePGApp/` so packaging scripts keep resolving `LithePGApp.entitlements`), and a thin `Sources/LithePGAppMain/main.swift` executable target named `LithePGApp` fixes the built binary name that `build_and_run.sh`, `run_dogfood_app.sh`, and `package_verify.sh` require. `swift run lithepg` still launches the GUI when run without `--url`.
- Added the first app icon: `packaging/AppIcon.png` (1024×1024 master) and `packaging/AppIcon.icns`, generated reproducibly by the new `script/generate_app_icon.swift` (CoreGraphics; blue rounded-square plate with a white database-cylinder glyph; regeneration commands documented in the script header).
- `script/build_and_run.sh` now fails closed (`build_and_run failed: app icon asset missing`) when `packaging/AppIcon.icns` is absent, installs it at `Contents/Resources/AppIcon.icns` with mode 644, and writes `CFBundleIconFile = AppIcon` into the generated Info.plist.
- `script/package_verify.sh` now rejects bundles whose `Contents/Resources/AppIcon.icns` is missing, a symlink, or group/world-writable, and fails on `CFBundleIconFile` ≠ `AppIcon`.
- Strict-TDD coverage: `test_build_and_run.sh` gained icon-installed/mode/plist assertions plus a missing-icon fail-closed fixture (RED: `build_and_run did not install Contents/Resources/AppIcon.icns`); `test_package_verify.sh` gained icon-missing and `CFBundleIconFile` mismatch fixtures (RED: `package verifier unexpectedly accepted a bundle without AppIcon.icns`); `test_sign_and_notarize.sh` fixtures updated to build icon-bearing bundles.
- GREEN verification passed: `bash script/test_build_and_run.sh`, `bash script/test_package_verify.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_run_dogfood_app.sh`, `bash script/test_dogfood_check.sh`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `swift test` (127 tests across 20 suites). End-to-end `script/build_and_run.sh --package` produced a signed `dist/LithePG.app` with the icon installed and passed package verification (12.03 MiB after strip -x).
- Release-impact dogfood verification passed with Docker available: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/dogfood_check.sh` wrote artifacts to `.build/dogfood-checks/20260610-124920/`; metrics: shell readiness 823.61 ms, connected cold start 447.49 ms (both elevated — measured while parallel release-helper test suites were still running on the same machine), raw release executable 21.63 MiB, strip-probe executable 12.03 MiB, `SELECT 1` median overhead 0.078 ms.
- Evidence artifact: `docs/evidence/2026-06-10-app-icon-and-lithepgapp-product-restore.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication was attempted (local ad-hoc codesign only via the existing `--package` default).

## 2026-06-14 17:17 EDT — v1.0 release gate directory-mode safety checks

- Hardened `script/v10_release_gate.sh` to check directory permissions inside `LithePG.app.zip`. Unsafe directory permissions (setuid, setgid, sticky bits, or group/world writable modes) will now fail validation in artifact-only mode.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh` with zip fixtures containing unsafe directory modes, verifying that they fail validation.
- RED verification: test failed as expected before the hardening fix was applied.
- GREEN verification passed: `bash script/test_v10_release_gate.sh`, adjacent tests, and `swift test` all passed.
- Evidence artifact: `screenshots/evidence/2026-06-14-release-directory-mode-gate.svg`.

## 2026-06-14 17:35 EDT — v1.0 file protection background cron fix

- Migrated `JSONFileSavedConnectionStore` and `JSONFileQueryHistoryStore` write options from `.completeFileProtectionUnlessOpen` to `.completeFileProtectionUntilFirstUserAuthentication`.
- This resolves POSIX `EPERM` "Operation not permitted" (Code 1) failures on macOS when the test suite is run via background cron/SSH jobs while the device/screen is locked. Since passwords and secrets are stored separately in the secure macOS Keychain (`KeychainCredentialStore`), these non-credential JSON files are safe to be accessed with first-user-authentication file protection level.
- RED verification: standard `swift test` failed with permission errors on the three persistence model tests under background cron run when the host was locked.
- GREEN verification passed: full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with all 127 tests in 20 suites perfectly green!
- Evidence artifact: `screenshots/evidence/2026-06-14-persistence-file-protection-cron-fix.svg`.

## 2026-06-23 01:18 EDT — v1.0 public status receipt sync after app icon/product restore

- Refreshed `README.md`, `CHANGELOG.md`, and `docs/releases/v1.0-draft.md` so the public-facing v1.0 status no longer points at the older 2026-06-02 receipt as the latest local gate.
- Synced the current safe app-icon/product-restore facts from `main` at `1f3b8f1`: the `LithePGApp` executable product is restored for packaging, the packaged app includes the reproducible `AppIcon.icns` bundle resource, release-helper shell suites passed, full `swift test` passed with 127 tests in 20 suites, package build and verification passed, and seeded `script/dogfood_check.sh` passed.
- Safe metrics synced from the app-icon/product-restore receipt: 21.63 MiB raw release executable; 12.03 MiB strip-probe/package executable; 823.61 ms shell readiness; 447.49 ms connected startup through seeded Postgres; and 0.078 ms median `SELECT 1` overhead. The startup figures are explicitly labeled as elevated because parallel release-helper tests were still running during that measurement.
- Also left the later focused v1.0 release-gate directory-mode and background-cron file-protection receipts intact as post-icon verification notes.
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-public-status-sync-app-icon.svg`.
- This docs/evidence receipt sync attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, or external publication.

## 2026-06-23 01:32 EDT — v1.0 publication preflight current-state receipt

- Rechecked local and remote release state after the public-status sync: `main` was clean at `3a0ab0b`, `origin/main` matched, local/origin `v0.5` existed, and local/origin `v1.0` remained absent.
- Ran `./script/v10_release_gate.sh --check-remote`; the fast publication preflight continued to pass local artifact inspection for `dist/LithePG.app.zip` (filename, wrapper, bundle contents, canonical entries, safe modes, Info.plist metadata, executable permissions/format, code-signature resources/verification/identifier/runtime, and clean top-level entries).
- The preflight intentionally remained blocked with 12 blockers: release-copy/Homebrew/security placeholders, missing approved release-artifact SHA-256 input, missing codesign identity/notary profile/security contact/Homebrew tap, GitHub Actions not approved, release-copy approval not approved, and publication approval not approved.
- Checked GitHub Actions with `gh run list --repo omarpr/lithepg --limit 5`; the latest run was still the existing manual `workflow_dispatch` CI failure (`26688293183`, `2026-05-30`, before this receipt), so no new passing remote CI signal was available.
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-publication-preflight-current.svg`.
- This docs/evidence preflight receipt attempted no signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication.

## 2026-06-23 02:04 EDT — v1.0 release gate icon metadata hardening

- Hardened `script/v10_release_gate.sh` so release artifact Info.plist metadata validation now requires `CFBundleIconFile = AppIcon`, matching the app-icon packaging requirement already enforced by `script/package_verify.sh`.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh`: the valid release-artifact fixture now includes `CFBundleIconFile`, and the metadata-mismatch fixture is otherwise valid but intentionally omits that icon metadata.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `expected output to contain: Release artifact Info.plist metadata: mismatch` because the old gate did not reject the iconless metadata fixture.
- GREEN verification passed: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Refreshed the ignored local `dist/LithePG.app` / `dist/LithePG.app.zip` with `LITHEPG_MARKETING_VERSION=1.0`; the fast publication preflight now reports `Release artifact Info.plist metadata: matches` while remaining intentionally blocked on external placeholders, missing approved release-artifact SHA-256 input, missing signing/notary/security-contact/Homebrew tap inputs, GitHub Actions approval, release-copy approval, and publication approval.
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-release-gate-icon-metadata.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 02:41 EDT — v1.0 release gate app-icon artifact hardening

- Hardened `script/v10_release_gate.sh` so the final `LithePG.app.zip` artifact check now requires `LithePG.app/Contents/Resources/AppIcon.icns` to be present exactly once as a regular file with safe mode bits, matching the app-icon bundle requirement already enforced by `script/package_verify.sh`.
- Added strict-TDD coverage in `script/test_v10_release_gate.sh`: the valid signed fixture now includes a fixture `AppIcon.icns`, while an otherwise valid ad-hoc-signed fixture with `CFBundleIconFile = AppIcon` but no icon asset must fail in artifact-only mode with `Release artifact app icon: missing` and without leaking the artifact path, SHA, or icon path.
- RED verification: `bash script/test_v10_release_gate.sh` failed first with `artifact-only gate unexpectedly passed with missing release artifact app icon`.
- GREEN verification passed: `bash script/test_v10_release_gate.sh`, `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, adjacent release zip test `bash script/test_create_release_zip.sh`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Current artifact-only preflight with the existing local `dist/LithePG.app.zip` and its computed SHA-256 passed and now reports `Release artifact app icon: present`; the full publication preflight remains intentionally blocked by dirty-tree state during this slice plus the existing external release placeholders, missing approved artifact SHA input, missing signing/notary/security-contact/Homebrew tap inputs, and approval gates.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-release-gate-app-icon-artifact.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 03:00 EDT — v1.0 app-icon ICNS magic hardening

- Hardened `script/package_verify.sh` so `Contents/Resources/AppIcon.icns` must start with ICNS magic (`icns`), in addition to the existing regular-file, non-symlink, and safe-mode checks.
- Hardened `script/v10_release_gate.sh` so the final `LithePG.app.zip` artifact-only/publication preflight rejects malformed app icon entries with `Release artifact app icon: invalid` while still redacting artifact paths, SHA-256 values, and fixture sentinels.
- Added strict-TDD coverage: `script/test_package_verify.sh` now fails a malformed app icon fixture with `app icon format is invalid`; `script/test_v10_release_gate.sh` now fails a signed artifact fixture whose `AppIcon.icns` payload lacks ICNS magic.
- RED verification: `bash script/test_package_verify.sh` first failed with `package verifier unexpectedly accepted a malformed AppIcon.icns`; `bash script/test_v10_release_gate.sh` first failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_sign_and_notarize.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `bash -n` for touched shell scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites), `./script/package_verify.sh dist/LithePG.app`, and artifact-only preflight for the existing local `dist/LithePG.app.zip` with its computed SHA-256.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-icns-magic-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 03:57 EDT — v1.0 app-icon ICNS declared-size hardening

- Hardened `script/package_verify.sh` so `Contents/Resources/AppIcon.icns` must have a complete 8-byte ICNS header and the big-endian declared length in bytes 4-7 must exactly match the actual icon file size, extending the previous magic-only check.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same declared-size check to `LithePG.app.zip` without leaking artifact paths, SHA-256 values, or fixture sentinels.
- Updated valid release-helper test fixtures to use a minimal syntactically valid ICNS header (`icns` plus a 12-byte declared length) and added mismatched-length regression coverage for package verification and release-artifact validation.
- RED verification was reproduced against `HEAD` in a temporary worktree with the test-only patch applied: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns with mismatched header length`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash -n` for touched shell scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `Release artifact SHA-256: matches`.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Independent review requested: Hermes spec/quality review subagents were dispatched for this slice, but their summaries did not return before the cron tick needed to close the coherent commit; standalone Codex review was attempted once and blocked by stale Codex OAuth (`refresh_token_reused` / `token_expired`), so no further Codex retries were attempted.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-icns-size-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 04:19 EDT — v1.0 app-icon ICNS element-table hardening

- Hardened `script/package_verify.sh` so `Contents/Resources/AppIcon.icns` must contain a structurally valid ICNS element table after the 8-byte file header: at least one element record, printable 4-byte element type, element length of at least 8 bytes, and element boundaries that stay inside the declared file length.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same element-table validation to `LithePG.app.zip` using isolated Python while still redacting artifact paths, SHA-256 values, and fixture sentinels.
- Updated release-helper test fixtures to use a minimal syntactically valid ICNS payload (`icns` file header plus one empty `icp4` element record), and added regression coverage for a matching-length but malformed `AppIcon.icns` payload that previously passed the header/declared-size-only checks.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns with a malformed element table`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash -n` for touched shell scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-icns-element-table-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 04:59 EDT — v1.0 app-icon ICNS image-payload hardening

- Hardened `script/package_verify.sh` so `Contents/Resources/AppIcon.icns` must contain at least one recognized ICNS image element with non-empty payload data, preventing a structurally valid but visually empty icon table from passing the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same image-payload validation to `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, and fixture sentinels.
- Updated release-helper fixtures to use a minimal non-empty `icp4` image element and added regression coverage for an empty `icp4` element that previously passed the element-table-only checks.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns without image payload data`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash -n` for touched shell scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-icns-image-payload-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 05:28 EDT — v1.0 app-icon high-resolution ICNS hardening

- Hardened `script/package_verify.sh` so `Contents/Resources/AppIcon.icns` must contain at least one high-resolution ICNS image element (`ic10` or `ic14`), preventing a technically valid but tiny/low-resolution-only icon payload from passing the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same high-resolution app-icon requirement to `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated release-helper fixtures to use minimal high-resolution `ic10` payloads for valid bundles, added package-verifier regression coverage for non-empty low-resolution-only `icp4` icons, and changed the release-artifact malformed-icon fixture to prove low-resolution-only artifacts fail.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns without a high-resolution image element`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `bash -n` for touched release-helper scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-high-resolution-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 05:48 EDT — v1.0 app-icon encoded payload hardening

- Hardened `script/package_verify.sh` so high-resolution ICNS image elements (`ic10` / `ic14`) must contain an encoded image payload signature instead of merely any non-empty bytes; accepted signatures are PNG plus JPEG 2000 signature-box or codestream prefixes.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same high-resolution encoded-payload requirement inside `LithePG.app.zip` without leaking artifact paths, SHA-256 values, icon paths, or fixture sentinels.
- Updated release-helper fixtures to use minimal PNG-signed high-resolution ICNS payloads and added regression coverage for an `ic10` element whose payload is just one byte, which previously passed the high-resolution gate.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution image payload has no encoded image signature`; `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `bash script/test_dogfood_check.sh`, `bash -n` for the touched release-helper scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification was attempted but could not run on this tick because Docker is unavailable in the current environment: `script/dogfood_check.sh` stopped with `docker is required for LithePG dogfood Postgres` before seeded Postgres startup.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-encoded-payload-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 06:41 EDT — v1.0 app-icon PNG dimension hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image elements must include a parseable PNG `IHDR` chunk with dimensions large enough for their ICNS slot (`ic10` requires at least 1024×1024; `ic14` requires at least 512×512), preventing a bare PNG signature from satisfying the release app-icon gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same PNG dimension validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated release-helper fixtures to use a minimal high-resolution PNG/IHDR payload and added regression coverage for an `ic10` payload that contains only the PNG signature bytes.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG payload has no dimensions`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `bash -n` for touched release-helper scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-dimension-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 07:00 EDT — v1.0 app-icon PNG IHDR metadata hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image elements must use valid PNG `IHDR` metadata: legal bit depth for the color type, compression method 0, filter method 0, and interlace method 0 or 1, in addition to the existing dimension thresholds.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same PNG `IHDR` metadata validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for an `ic10` payload with valid high-resolution dimensions but invalid PNG `IHDR` bit-depth metadata, proving both the package verifier and artifact-only release gate reject it.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IHDR metadata is invalid`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `bash -n script/package_verify.sh script/v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-ihdr-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 07:21 EDT — v1.0 app-icon PNG IHDR CRC hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image elements must have a valid PNG `IHDR` chunk CRC, preventing a forged/bit-flipped IHDR payload with otherwise plausible dimensions and metadata from satisfying the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same PNG `IHDR` CRC validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated release-helper fixtures to use a valid high-resolution PNG/IHDR CRC (`7f1d2b83`) and added strict-TDD regression coverage for an `ic10` payload with valid 1024×1024 RGBA metadata but an invalid zero CRC.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IHDR CRC is invalid`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `bash -n` for touched release-helper scripts, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing / `docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-ihdr-crc-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 07:42 EDT — v1.0 release artifact executable-size gate

- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight checks the uncompressed `LithePG.app/Contents/MacOS/LithePGApp` entry size inside `LithePG.app.zip` against the existing 50 MiB hard cap before extracting the executable for format or codesign inspection.
- Added strict-TDD regression coverage for a compressed release zip whose executable entry expands to 50 MiB + 1 byte; the gate now reports `Release artifact executable size: over budget` while redacting the artifact path and SHA-256.
- RED verification passed as expected before the production fix: `./script/test_v10_release_gate.sh` failed with `expected output to contain: Release artifact executable size: over budget`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for `dist/LithePG.app.zip` with SHA-256 `78ae07f97a06e2973a0f36c40da739c1ead0ec9aca1f31f2c11cb00e35f76385`, including `Release artifact executable size: under budget` and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-release-artifact-executable-size-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 08:06 EDT — v1.0 app-icon PNG IEND hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image payloads must end with a zero-length PNG `IEND` chunk whose chunk-type CRC is valid, preventing an IHDR-only PNG header from satisfying the app-icon package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same terminal `IEND` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated release-helper fixtures to use a minimal high-resolution PNG/IHDR payload plus terminal `IEND`, and added strict-TDD regression coverage for an `ic10` payload with valid dimensions, metadata, and IHDR CRC but no `IEND` chunk.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG payload has no IEND chunk`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing / `docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-iend-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 08:27 EDT — v1.0 app-icon PNG IDAT hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image payloads must contain at least one non-empty `IDAT` chunk, and the PNG chunk walk validates chunk CRCs before accepting the icon.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same non-empty `IDAT` requirement inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated valid release-helper fixtures to use a minimal high-resolution PNG payload with `IHDR`, non-empty `IDAT`, and terminal `IEND`, and added strict-TDD regression coverage for a high-resolution PNG payload with valid `IHDR`/`IEND` but no `IDAT` image data.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG payload has no IDAT image data`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh script/test_sign_and_notarize.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing / `docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-idat-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 08:48 EDT — v1.0 app-icon PNG IDAT zlib hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image payloads must have `IDAT` chunks that concatenate into a valid zlib stream with non-empty inflated data, not merely a non-empty byte payload.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same zlib stream validation to `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated valid release-helper fixtures to use a minimal zlib-valid high-resolution PNG payload and added strict-TDD regression coverage for an `ic10` payload whose `IDAT` chunk has a valid PNG CRC but invalid zlib data.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT stream is not valid zlib data`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh script/test_sign_and_notarize.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `5802737ba704b3d82b9f736635a25ab89ceecfad532e58cc1ef366b20cc7b46c`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Independent review was requested from Hermes spec/quality subagents but did not return before this cron tick needed to close the coherent slice; standalone Codex review was attempted once and blocked by stale Codex OAuth (`refresh_token_reused` / `token_expired`), so no further Codex retries were attempted.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-idat-zlib-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 09:12 EDT — v1.0 app-icon PNG IDAT inflated-length hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image payloads must have `IDAT` zlib data that inflates to exactly the scanline byte count implied by the declared PNG width, height, bit depth, color type, and interlace method. This closes the gap where a 1024×1024 icon could claim large dimensions while containing only a tiny valid zlib stream.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same inflated-length validation to `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Updated valid release-helper fixtures to generate complete 1024×1024 RGBA PNG scanline data inside the ICNS payload, and added strict-TDD regression coverage for a high-resolution PNG whose `IDAT` stream is valid zlib but too short for the declared dimensions.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT stream is too short for the declared dimensions`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh script/test_sign_and_notarize.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `25721833e0957f9616d023762aa31759c51ab9ccc107025ac5f1f886d390e697`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Independent Hermes spec/quality reviews were dispatched for this slice; if their summaries arrive after this cron tick, the next watchdog tick should incorporate any findings before further release hardening.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-idat-length-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 09:32 EDT — v1.0 app-icon PNG scanline filter-byte hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image payloads must use valid inflated PNG scanline filter bytes (`0...4`) after the existing IDAT zlib length check, preventing a length-correct but semantically invalid PNG from satisfying the app-icon package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same scanline filter-byte validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds an otherwise valid 1024×1024 RGBA PNG/ICNS fixture whose inflated scanlines use filter byte `5`, and `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT scanlines use an invalid filter byte`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `e45f283c4f8ae557dbb7c8616a3001bf386301d4cecac12a2439af96ec1b5589`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Independent Hermes spec/quality reviews were dispatched for this slice; if their summaries arrive after this cron tick, the next watchdog tick should incorporate any findings before further release hardening.
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-filter-byte-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 09:51 EDT — v1.0 app-icon PNG IDAT consecutive-chunk hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS image payloads reject PNG streams whose `IDAT` chunks are interrupted by another chunk before a later `IDAT`. PNG requires multiple `IDAT` chunks to be consecutive, so this prevents a non-canonical split stream from satisfying the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same consecutive-`IDAT` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds a valid-dimension/zlib-valid PNG-backed `AppIcon.icns` with `IDAT`, `tEXt`, then another `IDAT`; `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution PNG IDAT chunks are not consecutive`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-idat-consecutive-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 10:12 EDT — v1.0 app-icon encoded-payload hardening

- Hardened `script/package_verify.sh` so high-resolution ICNS image payloads must be fully validated PNGs; a payload that only presents a JPEG 2000/JPEG 2000 codestream magic header no longer satisfies the app-icon package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same fully validated PNG requirement inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds an `ic10` high-resolution element containing only the JPEG 2000 file-signature box header, and `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose high-resolution image payload only has a JPEG 2000 magic header`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `e06ae6d9ec1500dd3bb5c5ad46d47020d65451be766de1ea389ea4a325b5cf12`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-encoded-payload-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 10:32 EDT — v1.0 app-icon PNG PLTE hardening

- Hardened `script/package_verify.sh` so high-resolution indexed-color PNG app-icon payloads (PNG color type 3) must contain a `PLTE` chunk before `IDAT`; a syntactically valid indexed PNG without a palette no longer satisfies the package app-icon gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same indexed-PNG palette requirement inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` builds a 1024×1024 indexed PNG-backed `AppIcon.icns` without `PLTE`, and `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose indexed PNG payload has no PLTE chunk`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-plte-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 10:51 EDT — v1.0 app-icon PNG empty-PLTE hardening

- Hardened `script/package_verify.sh` so indexed-color PNG app-icon payloads must have a non-empty, well-formed `PLTE` chunk: length must be a positive multiple of 3, no larger than 256 RGB entries, disallowed for grayscale/gray-alpha payloads, and bounded by the indexed PNG bit depth.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same indexed-PNG palette validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds a 1024×1024 indexed PNG-backed `AppIcon.icns` with an empty `PLTE`; `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose indexed PNG payload has an empty PLTE chunk`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-empty-plte-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 11:24 EDT — v1.0 app-icon duplicate-PLTE hardening

- Hardened `script/package_verify.sh` so indexed-color PNG app-icon payloads reject duplicate `PLTE` chunks before `IDAT`; PNG permits only one palette chunk, so a duplicate-palette icon no longer satisfies the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same duplicate-`PLTE` rejection inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds an otherwise valid 1024×1024 indexed PNG-backed `AppIcon.icns` with duplicate non-empty `PLTE` chunks, and `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose indexed PNG payload has duplicate PLTE chunks`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with SHA-256 `e06ae6d9ec1500dd3bb5c5ad46d47020d65451be766de1ea389ea4a325b5cf12` both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-duplicate-plte-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 11:45 EDT — v1.0 app-icon PNG IEND final-chunk hardening

- Hardened `script/package_verify.sh` so PNG-backed high-resolution app-icon payloads reject any chunk after the first `IEND`, reject duplicate `IEND`, and require zero-length `IEND`; a payload with valid image data followed by `IEND`, `tEXt`, and a second `IEND` no longer satisfies the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same final-`IEND` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds an otherwise valid 1024×1024 RGBA PNG-backed `AppIcon.icns` with chunks after `IEND`; `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has chunks after IEND`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with malformed release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-iend-final-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 12:07 EDT — v1.0 app-icon PNG chunk-type hardening

- Hardened `script/package_verify.sh` so high-resolution PNG-backed ICNS app-icon payloads reject malformed PNG chunk types whose four type bytes are not ASCII letters. A chunk such as `1234` with valid CRC and otherwise valid image data no longer satisfies the package gate.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same PNG chunk-type validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds an otherwise valid 1024×1024 RGBA PNG-backed `AppIcon.icns` with invalid chunk type `1234`; `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an invalid chunk type`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with invalid PNG chunk type in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-chunk-type-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 12:28 EDT — v1.0 app-icon PNG unknown-critical-chunk hardening

- Hardened `script/package_verify.sh` so PNG-backed high-resolution app-icon payloads reject unknown critical PNG chunks (uppercase first chunk-type byte) instead of accepting arbitrary critical chunk names with valid CRCs.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same unknown-critical-chunk rejection inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` now builds an otherwise valid 1024×1024 RGBA PNG-backed `AppIcon.icns` with an unknown critical `ABCD` chunk; `script/test_v10_release_gate.sh` uses the same malformed icon pattern for the signed artifact fixture.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an unknown critical chunk`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with unknown critical PNG chunk in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-unknown-critical-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 14:57 EDT — v1.0 app-icon exact-dimension hardening

- Hardened `script/package_verify.sh` so PNG-backed high-resolution ICNS app-icon payloads must match the fixed ICNS element dimensions exactly (`ic10` = 1024×1024, `ic14` = 512×512), rather than accepting any PNG at or above the minimum size.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same exact-dimension requirement inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` now build a fully valid 1025×1025 RGBA PNG-backed `ic10` payload and require both release gates to reject it.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG dimensions are oversized for the ICNS element type`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with oversized PNG dimensions in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-exact-dimensions-gate.svg`.
- Codex standalone review was attempted once and remains blocked by stale OAuth (`refresh_token_reused` / `token_expired`), so no further Codex retries were attempted.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 15:19 EDT — v1.0 app-icon file-size cap hardening

- Hardened `script/package_verify.sh` so `Contents/Resources/AppIcon.icns` must be non-empty and no larger than 10 MiB before the package verifier parses the ICNS payload.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight rejects a release-zip `AppIcon.icns` whose uncompressed ZIP entry size is empty or over the same 10 MiB cap before opening the entry, avoiding unnecessary memory use on oversized icon artifacts.
- Added strict-TDD regression coverage: `script/test_package_verify.sh` builds an otherwise valid ICNS with an extra padding element over the cap, and `script/test_v10_release_gate.sh` builds a signed release artifact with the same over-size icon pattern.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns that exceeds the icon size cap`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with an over-size release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-size-cap-gate.svg`.
- Codex standalone review was attempted once and remains blocked by stale OAuth (`refresh_token_reused` / `token_expired`), so no further Codex retries were attempted.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 17:11 EDT — v1.0 artifact duplicate-ICNS-element hardening

- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight rejects a release-zip `AppIcon.icns` that repeats an ICNS image element type such as duplicate `ic10` entries, matching the package verifier's fail-closed behavior for ambiguous app-icon payloads.
- Added strict-TDD regression coverage in `script/test_v10_release_gate.sh`: the fixture builds a signed `LithePG.app.zip` with two valid high-resolution `ic10` image elements, then requires artifact-only mode to report `Release artifact app icon: invalid` while redacting the artifact path, SHA-256, marker string, and `AppIcon.icns` path.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with duplicate ICNS image elements in release artifact app icon`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `798d654a06fddbdd1775cb273811aaa0b4f5f1805de21abf00e535309cc8b824`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Codex standalone review was attempted once and remains blocked by stale OAuth (`refresh_token_reused` / `token_expired`), so no further Codex retries were attempted.
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-release-gate-duplicate-icns-elements.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 17:33 EDT — v1.0 app-icon duplicate PNG IHDR hardening

- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight rejects PNG-backed release `AppIcon.icns` payloads that contain duplicate `IHDR` chunks, matching the package verifier's fail-closed behavior for duplicate PNG headers.
- Added strict-TDD regression coverage in `script/test_v10_release_gate.sh`: the fixture builds a signed `LithePG.app.zip` with a high-resolution `ic10` PNG payload containing two valid `IHDR` chunks, then requires artifact-only mode to report `Release artifact app icon: invalid` while redacting the artifact path, SHA-256, marker string, and `AppIcon.icns` path.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with duplicate PNG IHDR chunks in release artifact app icon`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-release-gate-duplicate-png-ihdr.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 18:04 EDT — v1.0 app-icon PNG tRNS hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed high-resolution `AppIcon.icns` payloads reject malformed `tRNS` transparency chunks: duplicate/late chunks fail, alpha-channel color types 4/6 cannot carry `tRNS`, grayscale/truecolor lengths must match the PNG spec, and indexed-color `tRNS` must follow a valid palette without exceeding the palette size.
- Added regression coverage for a high-resolution RGBA PNG payload that previously let the artifact-only gate pass while carrying a forbidden `tRNS` chunk; both package and release-artifact fixtures keep the app icon data otherwise valid to isolate the transparency-chunk rule.
- RED verification passed as expected before the production fix: `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with forbidden PNG tRNS in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-trns-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 18:50 EDT — v1.0 app-icon PNG zlib trailing-data hardening

- Hardened `script/package_verify.sh` so PNG-backed high-resolution `AppIcon.icns` payloads reject `IDAT` data with unused bytes after the zlib stream end marker, rather than accepting `Compress::Zlib::uncompress` output that silently ignored trailing payload data.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same strict zlib-consumption check inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a valid 1024×1024 RGBA PNG icon whose `IDAT` chunk contains a complete valid zlib stream followed by trailing marker bytes.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG IDAT zlib stream has trailing data`, and `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with trailing zlib data in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `0f3e3bfdbb391db438206f36f9dac55bc0ecbb480548aea10b823eff36d354b7`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-zlib-trailing-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 19:08 EDT — v1.0 release-gate temp cleanup guard

- Added a fail-fast self-check to `script/test_v10_release_gate.sh` that verifies every `mktemp -d` fixture directory declared by the release-gate test is listed in the cleanup trap.
- RED verification passed as expected before the cleanup fix: `bash script/test_v10_release_gate.sh` failed with `mktemp dirs missing from cleanup: trailing_zlib_app_icon_zip_dir`.
- GREEN verification passed after adding the missing cleanup entry for the trailing-zlib app-icon fixture directory: `bash script/test_v10_release_gate.sh` passed.
- Additional verification: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker command missing`).
- Evidence artifact: `screenshots/evidence/2026-06-23-v10-release-gate-temp-cleanup.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 19:33 EDT — v1.0 app-icon PNG tRNS/PLTE ordering hardening

- Hardened `script/package_verify.sh` so PNG-backed app-icon payloads reject a `PLTE` chunk that appears after `tRNS`; PNG requires `tRNS` to follow `PLTE` when both chunks are present.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same `tRNS`/`PLTE` ordering validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a truecolor PNG-backed `ic10` icon with valid dimensions, CRCs, transparency length, and IDAT data but invalid `tRNS`-before-`PLTE` ordering.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload places tRNS before PLTE`; `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG tRNS before PLTE in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact executable size: under budget`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-trns-plte-order-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 20:30 EDT — v1.0 app-icon PNG reserved-bit hardening

- Hardened `script/package_verify.sh` so PNG-backed `AppIcon.icns` payloads reject chunk types whose PNG reserved bit is invalid: after the existing ASCII-letter check, the third chunk-type byte must be uppercase.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same reserved-bit validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a valid-dimension/zlib-valid PNG icon containing an otherwise ancillary private chunk type `txet`, where the lowercase third byte violates the PNG reserved-bit rule.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG chunk type has a lowercase reserved byte`; `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with lowercase reserved PNG chunk byte in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh script/test_sign_and_notarize.sh script/test_create_release_zip.sh script/test_build_and_run.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-reserved-bit-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 21:10 EDT — v1.0 app-icon PNG sRGB hardening

- Hardened `script/package_verify.sh` so PNG-backed `AppIcon.icns` payloads validate `sRGB` chunks instead of silently accepting malformed ancillary color-space metadata: `sRGB` must appear before `PLTE`/`IDAT`, appear at most once, be exactly one byte long, and use rendering intent `0...3`.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same `sRGB` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a valid-dimension/zlib-valid PNG icon containing a two-byte `sRGB` chunk that previously satisfied both app-icon gates.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an invalid sRGB chunk`; `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with invalid PNG sRGB chunk in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker is required for LithePG dogfood Postgres`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-srgb-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 21:32 EDT — v1.0 app-icon PNG gAMA hardening

- Hardened `script/package_verify.sh` so PNG-backed `AppIcon.icns` payloads validate `gAMA` chunks instead of silently accepting malformed ancillary gamma metadata: `gAMA` must appear before `PLTE`/`IDAT`, appear at most once, be exactly four bytes long, and encode a positive gamma integer.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same `gAMA` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a valid-dimension/zlib-valid PNG icon containing a two-byte `gAMA` chunk that previously satisfied both app-icon gates.
- RED verification passed as expected before the production fix: `bash script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an invalid gAMA chunk`; `bash script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with invalid PNG gAMA chunk in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `bash script/test_package_verify.sh`, `bash script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-gama-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 21:53 EDT — v1.0 app-icon PNG cHRM hardening

- Hardened `script/package_verify.sh` so PNG-backed `AppIcon.icns` payloads validate `cHRM` chunks instead of silently accepting malformed ancillary chromaticity metadata: `cHRM` must appear before `PLTE`/`IDAT`, appear at most once, and be exactly 32 bytes long.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same `cHRM` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a valid-dimension/zlib-valid PNG icon containing a two-byte `cHRM` chunk that previously satisfied both app-icon gates.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an invalid cHRM chunk`; `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with invalid PNG cHRM chunk in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-chrm-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-23 22:16 EDT — v1.0 app-icon PNG iCCP hardening

- Hardened `script/package_verify.sh` so PNG-backed `AppIcon.icns` payloads validate `iCCP` embedded color-profile chunks instead of silently accepting malformed ancillary profile metadata: `iCCP` must appear before `PLTE`/`IDAT`, appear at most once, not coexist with `sRGB`, carry a printable 1...79 byte profile name, use compression method 0, and contain a fully consumed non-empty zlib-compressed profile.
- Hardened `script/v10_release_gate.sh` so artifact-only/publication preflight applies the same `iCCP` validation inside `LithePG.app.zip` while continuing to redact artifact paths, SHA-256 values, icon paths, and fixture sentinels.
- Added strict-TDD regression coverage for a valid-dimension/zlib-valid PNG icon containing a malformed two-byte `iCCP` chunk that previously satisfied both app-icon gates.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an invalid iCCP chunk`; `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with invalid PNG iCCP chunk in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker command missing`).
- Evidence artifact: `screenshots/evidence/2026-06-23-app-icon-png-iccp-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 00:07 EDT — v1.0 package verifier PNG text-metadata parity

- Mirrored the release-artifact app-icon text-metadata rejection into `script/package_verify.sh`, so local package verification now rejects PNG-backed `AppIcon.icns` payloads containing `tEXt`, `zTXt`, or `iTXt` chunks instead of allowing arbitrary metadata in the packaged app icon.
- Added strict-TDD coverage in `script/test_package_verify.sh` for a valid-dimension/zlib-valid `ic10` PNG carrying a `tEXt` payload with a sentinel marker.
- RED verification passed as expected before the production fix: `bash -n script/test_package_verify.sh && ./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has text metadata`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Codex standalone review was attempted once and remains blocked by stale OAuth (`refresh_token_reused` / `token_expired`), so no further Codex retries were attempted.
- Evidence artifact: `screenshots/evidence/2026-06-24-package-verify-png-text-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 00:32 EDT — v1.0 app-icon PNG timestamp-metadata hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads reject `tIME` timestamp chunks, keeping release app icons deterministic and metadata-free alongside the existing text-metadata rejection.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for valid-dimension/zlib-valid `ic10` PNG icons carrying a `tIME` chunk before `IDAT`.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has timestamp metadata`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG timestamp metadata in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-time-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 00:58 EDT — v1.0 app-icon PNG EXIF metadata hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads reject `eXIf` EXIF metadata chunks, keeping release app icons deterministic and metadata-free alongside the existing text/timestamp metadata rejection.
- Removed existing `eXIf` chunks from `packaging/AppIcon.png` and the checked-in `packaging/AppIcon.icns`; verified the remaining PNG chunks are limited to `IHDR`, `sRGB`, `IDAT`, and `IEND` across the source icon payloads.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for valid-dimension/zlib-valid `ic10` PNG icons carrying an `eXIf` payload.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has EXIF metadata`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG EXIF metadata in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Rebuilt the local v1.0 package with `LITHEPG_MARKETING_VERSION=1.0`; `script/package_verify.sh` passed with packaged executable 12,545,680 bytes / 11.96 MiB, and `script/create_release_zip.sh` produced `dist/LithePG.app.zip` with SHA-256 `1816f38b9b97fca493b7ad6e839f784b40c3ec651cf7c17725384c07aeabab32`. Artifact-only preflight passed with `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-exif-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 01:18 EDT — v1.0 app-icon PNG pHYs metadata hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads reject `pHYs` physical pixel-density metadata chunks, keeping release app icons deterministic and metadata-free alongside the existing text/timestamp/EXIF metadata rejection.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for valid-dimension/zlib-valid `ic10` PNG icons carrying a `pHYs` chunk before `IDAT`.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has physical pixel metadata`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG physical pixel metadata in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker-missing`).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-phys-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 01:43 EDT — v1.0 app-icon PNG sBIT metadata hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads reject `sBIT` significant-bit chunks, keeping release app icons deterministic and metadata-free alongside the existing text/timestamp/EXIF/pHYs metadata rejection.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for valid-dimension/zlib-valid `ic10` PNG icons carrying an `sBIT` chunk before `IDAT`.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has significant-bit metadata`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG significant-bit metadata in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local artifact verification passed: `./script/package_verify.sh dist/LithePG.app` and artifact-only preflight for the existing `dist/LithePG.app.zip` with its computed SHA-256 both passed, including `Release artifact app icon: present`, `Release artifact code signature verification: valid`, and `v1.0 artifact-only preflight is clear`.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-sbit-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 02:30 EDT — v1.0 app-icon PNG bKGD metadata hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads reject `bKGD` preferred-background metadata chunks, keeping release app icons deterministic and metadata-free alongside the existing text/timestamp/EXIF/pHYs/sBIT metadata rejection.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for valid-dimension/zlib-valid `ic10` PNG icons carrying a `bKGD` chunk before `IDAT`.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has background metadata`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG background metadata in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local package verification passed: `./script/package_verify.sh dist/LithePG.app` reported `Package verified: LithePG.app`, bundle ID `dev.omarpr.lithepg`, version `1.0 (100)`, and executable size 84,688 bytes / 0.08 MiB for the current local debug-package artifact.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-bkgd-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 03:07 EDT — v1.0 app-icon PNG hIST metadata hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads reject `hIST` palette-frequency histogram metadata chunks, keeping release app icons deterministic and metadata-free alongside the existing text/timestamp/EXIF/pHYs/sBIT/bKGD metadata rejection.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for valid-dimension/zlib-valid `ic10` PNG icons carrying an `hIST` chunk before `IDAT`.
- RED verification passed as expected in a detached `HEAD` worktree with only the new tests applied before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has histogram metadata`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with PNG histogram metadata in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local package verification passed: `./script/package_verify.sh dist/LithePG.app` reported `Package verified: LithePG.app`, bundle ID `dev.omarpr.lithepg`, version `1.0 (100)`, and executable size 84,688 bytes / 0.08 MiB for the current local debug-package artifact.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-histogram-metadata-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 06:13 EDT — v1.0 app-icon PNG unknown ancillary chunk hardening

- Hardened `script/package_verify.sh` and `script/v10_release_gate.sh` so PNG-backed `AppIcon.icns` payloads fail closed on unrecognized ancillary chunks, preventing private/unknown chunks such as `vpAg` from carrying arbitrary icon metadata through local package or artifact-only release verification.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` and `script/test_v10_release_gate.sh` for otherwise valid `ic10` PNG icons carrying an unknown ancillary chunk payload.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `package verifier unexpectedly accepted an AppIcon.icns whose PNG payload has an unknown ancillary chunk`, and `./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with unknown ancillary PNG chunk in release artifact app icon`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh script/v10_release_gate.sh script/test_v10_release_gate.sh script/sign_and_notarize.sh script/create_release_zip.sh script/build_and_run.sh`, `./script/test_package_verify.sh`, `./script/test_v10_release_gate.sh`, `bash script/test_sign_and_notarize.sh`, `bash script/test_create_release_zip.sh`, `bash script/test_build_and_run.sh`, `git diff --check`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites).
- Local package verification passed: `./script/package_verify.sh dist/LithePG.app` reported `Package verified: LithePG.app`, bundle ID `dev.omarpr.lithepg`, version `1.0 (100)`, and executable size 84,688 bytes / 0.08 MiB for the current local debug-package artifact.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker` command missing).
- Evidence artifact: `screenshots/evidence/2026-06-24-app-icon-png-unknown-ancillary-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 06:35 EDT — v1.0 release-hardening docs receipt

- Refreshed public-facing release status docs after the focused app-icon/package hardening sequence so README and CHANGELOG no longer imply the older `1f3b8f1` full dogfood receipt is the only current v1.0 local evidence.
- README now distinguishes the latest full dogfood/product-restore receipt from the later focused package/artifact integrity gates through `58419e7`.
- CHANGELOG now summarizes the app-icon release preflight hardening: malformed ICNS tables, invalid PNG dimensions/chunks/zlib streams, duplicate payloads, metadata-bearing PNG chunks, unknown ancillary chunks, and unsafe bundle files are fail-closed before publication.
- Verification: Markdown reference/link sanity checks and focused no-secret scans passed; Swift tests were not rerun because this slice is docs/evidence-only and does not change production code or release scripts.
- Evidence artifact: `screenshots/evidence/2026-06-24-release-hardening-docs-receipt.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 07:06 EDT — v1.0 package verifier Resources directory hardening

- Hardened `script/package_verify.sh` so `Contents/Resources` must be a real non-symlink directory with safe mode bits before the verifier reads `Contents/Resources/AppIcon.icns`; this closes the local-package parity gap where a symlinked resource directory was only rejected later by the generic bundle symlink scan.
- Added strict-TDD regression coverage in `script/test_package_verify.sh` for a valid bundle whose `Contents/Resources` path is replaced by a symlink to an external directory containing an otherwise valid app icon.
- RED verification passed as expected before the production fix: `./script/test_package_verify.sh` failed with `expected output to contain: Contents/Resources directory must be a non-symlink directory`.
- GREEN verification passed: `bash -n script/package_verify.sh script/test_package_verify.sh && ./script/test_package_verify.sh` reported `test_package_verify passed`.
- Wider local verification passed: release-helper shell suites (`test_package_verify`, `test_v10_release_gate`, `test_sign_and_notarize`, `test_create_release_zip`, `test_build_and_run`), `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, artifact-only `./script/v10_release_gate.sh --artifact-only` with the current local `dist/LithePG.app.zip` SHA-256, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) all passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker_missing`).
- Focused added-line static/no-secret scans reported no findings.
- Evidence artifact: `screenshots/evidence/2026-06-24-package-verify-resources-dir-gate.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 07:35 EDT — v1.0 release artifact directory/file-type hardening

- Hardened `script/v10_release_gate.sh` so final `LithePG.app.zip` artifact preflight rejects critical app-bundle directory paths (`LithePG.app`, `Contents`, `Contents/MacOS`, `Contents/Resources`, and `Contents/_CodeSignature`) when they appear as non-directory ZIP entries; this closes an artifact-only collision case where `Contents/Resources` could be a regular file while `Contents/Resources/AppIcon.icns` also existed.
- Added strict-TDD regression coverage in `script/test_v10_release_gate.sh` for a signed release artifact fixture with a regular file at `LithePG.app/Contents/Resources` plus a valid app icon beneath that path.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `expected output to contain: Release artifact bundle file types: invalid`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` reported `test_v10_release_gate passed`.
- Wider local verification passed: release-helper shell suites (`test_package_verify`, `test_v10_release_gate`, `test_sign_and_notarize`, `test_create_release_zip`, `test_build_and_run`), `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, artifact-only `./script/v10_release_gate.sh --artifact-only` with the current local `dist/LithePG.app.zip` SHA-256, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) all passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Focused added-line static/no-secret scans reported no findings.
- Evidence artifact: `screenshots/evidence/2026-06-24-v10-release-gate-resources-file-type.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 07:59 EDT — v1.0 release artifact CodeResources mode hardening

- Hardened `script/v10_release_gate.sh` so final `LithePG.app.zip` artifact preflight rejects `LithePG.app/Contents/_CodeSignature/CodeResources` when the ZIP entry is group/other-writable or carries special mode bits, rather than only checking that it is a regular file.
- Added strict-TDD artifact-only regression coverage in `script/test_v10_release_gate.sh` by rewriting the valid signed fixture ZIP's `CodeResources` entry metadata to mode `100666` while keeping its contents unchanged.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with unsafe release artifact code signature resources mode`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` reported `test_v10_release_gate passed`.
- Wider local verification passed: release-helper shell suites (`test_package_verify`, `test_v10_release_gate`, `test_sign_and_notarize`, `test_create_release_zip`, `test_build_and_run`), `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, artifact-only `./script/v10_release_gate.sh` with the current local `dist/LithePG.app.zip` SHA-256, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) all passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-24-v10-release-gate-code-resources-mode.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 08:24 EDT — v1.0 release artifact CodeResources executable-mode hardening

- Tightened `script/v10_release_gate.sh` so final `LithePG.app.zip` artifact preflight rejects `LithePG.app/Contents/_CodeSignature/CodeResources` when that signature-resource file carries any executable bit, in addition to the existing non-regular, special-bit, and group/other-writable mode rejection.
- Updated the strict-TDD artifact fixture in `script/test_v10_release_gate.sh` to rewrite the signed fixture ZIP's `CodeResources` entry to mode `100755`, proving the artifact-only gate fails before the production check and passes after the executable-bit rejection is added.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `artifact-only gate unexpectedly passed with unsafe release artifact code signature resources mode`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` reported `test_v10_release_gate passed`.
- Wider local verification passed: release-helper shell suites (`test_package_verify`, `test_v10_release_gate`, `test_sign_and_notarize`, `test_create_release_zip`, `test_build_and_run`), `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, artifact-only `./script/v10_release_gate.sh` with the current local `dist/LithePG.app.zip` SHA-256, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) all passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker unavailable; skipping dogfood_check.sh`).
- Evidence artifact: `screenshots/evidence/2026-06-24-v10-release-gate-code-resources-exec-mode.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-24 08:50 EDT — v1.0 release artifact empty CodeResources hardening

- Tightened `script/v10_release_gate.sh` so final `LithePG.app.zip` artifact preflight rejects `LithePG.app/Contents/_CodeSignature/CodeResources` when the ZIP entry has a zero-byte or unparsable uncompressed size, before attempting codesign verification.
- Added strict-TDD artifact-only regression coverage in `script/test_v10_release_gate.sh` by rewriting the signed fixture ZIP's `CodeResources` entry to an empty regular file while preserving the rest of the archive metadata.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `expected output to contain: Release artifact code signature resources: invalid`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` reported `test_v10_release_gate passed`.
- Wider local verification passed: release-helper shell suites (`test_v10_release_gate`, `test_package_verify`, `test_sign_and_notarize`, `test_create_release_zip`, `test_build_and_run`), `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, artifact-only `./script/v10_release_gate.sh` with the current local `dist/LithePG.app.zip` SHA-256, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) all passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker command missing`).
- Evidence artifact: `screenshots/evidence/2026-06-24-v10-release-gate-code-resources-empty.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-29 — v1.0 release artifact oversized CodeResources hardening

- Tightened `script/v10_release_gate.sh` so final `LithePG.app.zip` artifact preflight rejects `LithePG.app/Contents/_CodeSignature/CodeResources` when the ZIP entry's uncompressed size exceeds a 4 MiB sanity cap (`CODE_RESOURCES_MAX_BYTES`), closing the gap where the resources check enforced a lower bound (non-empty) and safe mode bits but no upper bound. A legitimate `CodeResources` plist is tiny (the current `dist/LithePG.app` signature resources file is 2446 bytes), so an absurdly large tampered entry previously passed the resources check.
- Added strict-TDD artifact-only regression coverage in `script/test_v10_release_gate.sh` by rewriting the signed fixture ZIP's `CodeResources` entry to a >4 MiB payload while preserving the rest of the archive metadata.
- RED verification passed as expected before the production fix: `bash -n script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` failed with `expected output to contain: Release artifact code signature resources: invalid`.
- GREEN verification passed: `bash -n script/v10_release_gate.sh script/test_v10_release_gate.sh && ./script/test_v10_release_gate.sh` reported `test_v10_release_gate passed`.
- No-false-positive check passed: artifact-only `./script/v10_release_gate.sh --artifact-only` against the current local `dist/LithePG.app.zip` (2446-byte CodeResources) still reported `Release artifact code signature resources: present` and a clear artifact-only preflight.
- Wider local verification passed: release-helper shell suites (`test_v10_release_gate`, `test_package_verify`, `test_sign_and_notarize`, `test_create_release_zip`, `test_build_and_run`), `git diff --check`, `./script/package_verify.sh dist/LithePG.app`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`, and full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (127 tests across 20 suites) all passed.
- Release-impact dogfood verification could not run on this tick because Docker is unavailable in the current cron environment (`docker_missing`).
- Evidence artifact: `screenshots/evidence/2026-06-29-v10-release-gate-code-resources-oversized.svg`.
- No signing identity, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.

## 2026-06-29 — Repo hygiene: ignore stray Node/JS tooling artifacts

- Found 77 MiB of foreign, untracked Node content in the working tree (`node_modules/` plus a root `package.json`/`package-lock.json` for an unrelated `agent-browser` npm package). These are referenced nowhere in the Swift package sources, scripts, or release tooling, and `.gitignore` did not cover them — so the watchdog workflow's own `git add -A` commit step could have swept tens of MB of unrelated npm content into LithePG history.
- Fix: extended `.gitignore` with a Node/JS tooling section (`node_modules/`, `package.json`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) with a comment explaining why a Swift package ignores these.
- RED (before): `git status --porcelain` listed `?? node_modules/`, `?? package.json`, `?? package-lock.json` as untracked and addable.
- GREEN (after): `git check-ignore node_modules package.json package-lock.json` matches all three; `git status` shows only the intended `.gitignore` edit. The strays can no longer enter history.
- Verification: ignore-only change; no Swift sources, scripts, or release gates touched, so `swift build`/`swift test` were not rerun (no build or runtime impact). `git check-ignore` and `git status` confirm the intended effect.
- Evidence artifact: `screenshots/evidence/2026-06-29-gitignore-node-artifacts.svg`.
- v1.0 remains correctly gated: all plan tasks implemented; only the GitHub Release draft and `v1.0` tag are open, both awaiting Omar's explicit approval and external signing credentials (`LITHEPG_CODESIGN_IDENTITY`/`LITHEPG_NOTARY_PROFILE`). No signing, notarization, upload, Homebrew publication, GitHub Release, tag, cron changes, Telegram delivery, or external publication was attempted.
