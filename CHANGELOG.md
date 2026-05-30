# Changelog

All notable release-history entries for LithePG are collected here for public readers. The historical notes below are summarized from the roadmap, milestone specs, and dogfood receipts; detailed verification evidence lives in [`docs/dogfood-log.md`](docs/dogfood-log.md).

LithePG follows outcome-named milestones with semantic-version tags. v1.0 remains unreleased until the public-launch gates are complete, including Apple Developer signing/notarization credentials and final distribution approval.

## [v1.0] — Unreleased — Public Launch

### Added

- Public-launch planning opened from the roadmap's v1.0 exit criteria: notarized macOS distribution, GitHub/Homebrew release path, public docs, governance templates, security reporting, and light/dark appearance support.
- Local package verification now checks the generated `dist/LithePG.app` bundle structure, executable permissions, bundle metadata, minimum macOS version, and the 50 MiB executable hard cap.
- A credential-gated signing/notarization wrapper is available for dry-run validation and future real distribution signing.
- [`docs/RELEASING.md`](docs/RELEASING.md) documents the local package gate, required signing/notary inputs, dry-run flow, and final v1.0 tag gate.

### Still blocked before release

- Real codesigning and notarization require Omar-controlled Apple Developer signing identity and notarytool keychain profile on the release machine.
- Homebrew publication needs an approved tap target.
- GitHub Release artifact creation, release-copy approval, and the `v1.0` tag remain gated on Omar's explicit public publication approval.
- Push/PR-triggered GitHub Actions may still require Omar-side account settings; local release receipts remain the fallback gate until CI triggers are confirmed.

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
