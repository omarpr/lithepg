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
