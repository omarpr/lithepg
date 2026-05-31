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
