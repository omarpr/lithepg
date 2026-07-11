# Changelog

All notable release-history entries for LithePG are collected here for public readers. The historical notes below are summarized from the roadmap, milestone specs, and dogfood receipts; detailed verification evidence lives in [`docs/dogfood-log.md`](docs/dogfood-log.md).

LithePG follows outcome-named milestones with semantic-version tags. v1.0 remains unreleased until the public-launch gates are complete, including Apple Developer signing/notarization credentials and final distribution approval.

## [v1.0] — Unreleased — Public Launch

### Added

- Public collaboration entry points: `CONTRIBUTING.md`, `GOVERNANCE.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue and PR templates with DCO sign-off guidance.
- Light, dark and system appearance preferences, with dark as the default.
- Results grid export and copy as CSV, TSV, JSON, GitHub-flavored Markdown and SQL INSERT statements. Only rows already fetched are serialized; nothing runs SQL or touches the network.
- EXPLAIN and EXPLAIN ANALYZE from the toolbar (`⌘E` / `⇧⌘E`) rendering the parsed plan as an indented tree with cost shares, ANALYZE timings and the costliest node flagged. Explain Analyze is labeled as executing the query.
- The sidebar's select action now inserts and runs the `SELECT ... LIMIT 100` in one click when connected.
- Result cells are clickable: click selects and `⌘C` copies, right-click copies the cell or row, double-click opens an editable detail popover for long or NULL values. Edits stay local because a query result cannot safely be written back without knowing its source table and key.
- Timestamps, dates, UUIDs and numeric values render readably in the grid instead of a raw byte-count placeholder.
- Query tabs can be renamed: double-click a tab or use its context menu.
- Cell clicking is instant: the per-cell editor popover became a single sheet and single-click selection no longer waits out the double-click interval. Grid fonts moved up to 13pt SF Mono with roomier rows.
- `script/dev_signing_setup.sh` creates a persistent local code-signing identity so Keychain "Always Allow" choices survive rebuilds; the packager picks it up automatically.
- Readability pass: results grid, sidebar rows, status text and badges moved from 10pt caption sizes to 11 to 12pt.
- EXPLAIN plan parsing (`QueryPlan`) and headless plan-tree presentation seams, ready for a v1.1 plan view.
- Schema graph (`⇧⌘G`): an in-app force-directed graph of tables and foreign keys with pan, zoom, drag, selection highlighting and a column inspector with PK/FK badges. Read-only, derived from already-loaded schema metadata; graphs past 300 tables use a static grid layout.
- Neon connection support: pasted Neon URLs are detected and surface endpoint, database, role and pooled or direct mode, with a suggested connection name. Verified live against real Neon endpoints (Postgres 17, direct and pooled, current host shape) by CLI smoke and the gated live app suite.
- Pasted connection strings are sanitized before parsing, so quoted strings, `psql '<url>'` commands, `DATABASE_URL=` lines and trailing newlines all work.
- Bare-executable runs (`swift run`, Xcode package schemes) now activate the app so windows accept keyboard input.
- Keychain resilience: entitlement-less builds fall back to the legacy login keychain instead of failing to save credentials; a gated suite (`LITHEPG_KEYCHAIN_TESTS=1`) covers real-keychain round trips.
- Release tooling: local package verification, artifact and icon hardening, `script/v10_release_gate.sh` preflight, `script/create_release_zip.sh`, a credential-gated signing/notarization wrapper and a Homebrew cask template under `packaging/homebrew/`.
- `CORE_TECHNOLOGIES.md` documents every core technology choice and why.

### Changed

- swift-nio updated to 2.101.2 for published advisories (GHSA-rj37-6j9x-74q6, GHSA-r3rc-9hpw-54v9, GHSA-cq87-8r7h-962v).
- User-facing copy reworked to read naturally (no em-dashes, no Oxford commas).
- CI runs on every push and PR again: build and tests on macOS, security scans (osv-scanner, gitleaks, semgrep) on Linux with pinned, checksum-verified scanner binaries.

### Verified

- 224 tests across 34 suites pass locally and in CI; live suites verified against seeded Docker Postgres and real Neon endpoints.
- Full git history (412 commits) scanned for secrets with gitleaks plus manual pattern sweeps: clean, no rewrite needed before open-sourcing.
- Binary and speed budgets hold: ~21.7 MiB release executable (50 MiB cap, 30 MiB stretch), sub-500 ms connected startup, sub-5 ms query overhead. Receipts in `docs/dogfood-log.md`.

### Still blocked before release

- Apple Developer signing identity and notarytool profile on the release machine.
- An approved public security-reporting contact to replace the placeholder policy.
- An approved Homebrew tap target.
- Release-copy approval, resolved draft placeholders and the `v1.0` tag, all gated on explicit publication approval.

## [v0.5] — 2026-05-28 — AI-Ready

### Added

- Local-first Ask-in-English workflow that drafts SQL into the active editor for human review; generated SQL is never auto-run.
- Schema indexing and deterministic local drafting coverage for simple single-table prompts and two-table joins using foreign-key metadata.
- CoreML adapter and local model registry scaffolding behind explicit opt-in configuration; no model artifact is bundled with the app.
- Ask UI shortcut (`⇧⌘K`) and app-state flow for draft insertion, unavailable-model handling, and production-connection safety context.

### Verified

- Default Swift test gate and seeded dogfood check passed before the tag.
- The v0.5 receipt kept the app under the lean/fast budgets: 21.338 MiB raw release executable / 11.959 MiB stripped packaged executable, 138.14 ms shell readiness, and 222.00 ms connected startup through seeded local Postgres.
- AI privacy posture was documented: prompts, schemas, query results, credentials, and history stay on-device; external model artifacts are user-provided and opt-in.

## [v0.4] — 2026-05-24 — Lean & Fast

### Added

- Repeatable measurement harness for release binary size, app startup readiness, and query-path overhead versus `psql` on the local seeded baseline.
- Dogfood stability gate (`script/dogfood_check.sh`) that runs default tests, live dogfood coverage, and measurement checks.
- Release app packaging path that creates `dist/LithePG.app` and strips the copied executable for distribution-size measurement.
- Startup readiness instrumentation and query-overhead receipts for the app's persistent connection path.

### Changed

- Binary budget was revised to a 50 MiB hard cap with a 30 MiB stretch goal after the pure-Swift GUI and PostgresNIO baseline made the original smaller target unrealistic.
- Security hardening tightened `sslmode=` handling, credential redaction for Postgres URLs, data-protection Keychain usage, and cleartext warnings for non-loopback connections.

### Verified

- Seven-day zero-crash dogfood window elapsed without crash entries.
- Final v0.4 receipt passed local stability checks with shell readiness at 125.67 ms, connected startup at 158.86 ms, release binary at 20.98 MiB raw / 11.79 MiB stripped, and query overhead well below the 5 ms target.

## [v0.3] — 2026-05-04 — Dogfood-Ready

### Added

- Saved-connection metadata persistence with secrets routed through a Keychain-facing credential-store abstraction.
- Connect-from-saved flow with display names, environment labels, and production warning banner for production-tagged connections.
- Opt-in query history that records SQL text, connection/environment metadata, timing, status, and success flag without storing result rows.
- Safe delete flow for saved connections that removes local metadata and credential references without touching databases.

### Changed

- Results pane layout was polished so sparse result sets fill the allocated table area more clearly.
- Dogfood protocol moved from setup receipts into active daily-driver tracking for missing features or switches to other tools.

### Verified

- Default Swift tests and live dogfood slices covered saved connections, credential separation, production environment tracking, schema refresh/reconnect, and query-history capture against seeded local Postgres.

## [v0.2] — 2026-05-03 — Query Experience

### Added

- SwiftUI macOS app shell with a connect sheet, persistent connection lifecycle, editable SQL workspace, and result rendering.
- Query editor behavior for run/cancel shortcuts, inline errors with redaction, and reconnect affordance on connection-level failures.
- Results grid polish: clearer row/command/empty states, tab-separated copy output, duplicate-column tolerance, truncation handling, and client-side paging for the rendered row cap.
- Read-only schema sidebar with schemas, tables/views, columns, explicit refresh, and a safe schema-to-query helper that inserts quoted `SELECT ... LIMIT 100` statements without auto-running them.
- Multi-tab query workspace with preserved buffers/results and documented keyboard navigation.

### Changed

- The attempted Runestone editor dependency was abandoned after native macOS SPM builds resolved an iOS/UIKit-only path; v0.2 continued with native AppKit/SwiftUI editor integration.
- The v0.1 CLI stayed available as a smoke utility while the app became the primary query surface.

### Verified

- Default Swift tests and live schema/AppState smokes passed during the milestone.
- Release binary observations stayed under the later 50 MiB hard cap.

## [v0.1] — 2026-04-18 — Walking Skeleton

### Added

- Initial pure-Swift PostgreSQL connection skeleton with the `lithepg` CLI and `PostgresNIO`-based core.
- Plain loopback Postgres connection smoke for `SELECT 1`.
- TLS `verify-full` path with a pinned CA for local/self-signed verification.
- SSH tunnel path through the system `ssh` binary as the initial escape hatch for bastion-style access.

### Verified

- `SELECT 1` succeeded over plain loopback, TLS verify-full, and SSH-tunneled paths.
- Dependency inspection showed no `libpq` linkage and no LithePG-authored C shims.

[v1.0]: docs/superpowers/specs/2026-05-28-v1.0-public-launch-design.md
[v0.5]: https://github.com/omarpr/lithepg/tree/v0.5
[v0.4]: https://github.com/omarpr/lithepg/tree/v0.4
[v0.3]: https://github.com/omarpr/lithepg/tree/v0.3
[v0.2]: https://github.com/omarpr/lithepg/tree/v0.2
[v0.1]: https://github.com/omarpr/lithepg/tree/v0.1
