# LithePG Roadmap — Design Spec

**Date:** 2026-04-18
**Status:** Approved design; implementation planning pending.

## 1. Context

LithePG is a lean, Mac-native PostgreSQL client with local-first AI. The tech stack, architecture, and security posture are already documented in `docs/TECH_STACK.md`, `docs/ARCHITECTURE.md`, and `SECURITY.md`. This spec defines *what we build, in what order, and how we know we're done*.

## 2. Target User

**Primary:** Backend engineers at small/mid teams who need a daily driver for real work — password + TLS connections, SSH tunnels, multiple environments (dev/staging/prod), saved queries, query history.

Not primarily aimed at indie hackers, data analysts, or DBAs — though those audiences may be served incidentally.

## 3. Success Criteria

- **Primary (bar A — dogfood):** The maintainer uses LithePG as the daily Postgres client for 2 consecutive weeks without reaching for another tool.
- **Secondary (bar B — technical):** App binary <50 MiB hard cap with <30 MiB stretch, cold start <500ms, query-path overhead <5ms vs `psql` on a localhost baseline, zero crashes in 7 days of daily dogfooding.
- **Deferred:** Community/adoption metrics (stars, downloads) — not a v1.0 gate.

## 4. Non-Goals

**Hard non-goals (forever-no):**
- Non-Postgres databases (MySQL, SQLite, etc.).
- Windows / Linux builds.
- Cloud sync, shared connection libraries, team collaboration features.
- Network / cloud AI inference — on-device only, always (reinforces `SECURITY.md`).
- Plugin / extension API.

**Deferred to post-v1.0 (reconsider later):**
- Visual schema designer / ERD editor (read-only schema views only in MVP).
- DBA / admin tooling (role management, vacuum controls, replication dashboards).

## 5. Roadmap Structure

**Hybrid — outcome-named milestones with semantic-version tags.** Outcomes define *why* a milestone exists; version tags make git tags and changelogs trivial.

**Sequencing principle — risk-first.** Front-load the thesis-critical unknowns (pure-Swift driver, TLS, SSH tunneling) in v0.1. UX polish comes *after* the stack is proven. The "no `libpq`" bet either pays off early or we learn early.

**No date commitments.** Milestones ship when exit criteria pass. One milestone in flight at a time.

## 6. Milestones

### v0.1 — Walking Skeleton *(prove the thesis)*
Minimal, even ugly, UI — but the full risky stack works end-to-end.

**Exit criteria:**
- Connect to local Postgres (no TLS, loopback).
- Connect to remote Postgres with TLS `verify-full`.
- Connect to remote Postgres via SSH tunnel.
- Run `SELECT 1` successfully on each of the three paths.
- Pure Swift implementation — no `libpq`, no C dependencies.

### v0.2 — Query Experience *(make it nice to use)*
**Exit criteria:**
- SwiftUI query editor with syntax highlighting.
- Results grid with pagination.
- Schema tree (databases → schemas → tables/views → columns).
- Multi-tab query workspace.
- Keyboard-first navigation (documented shortcuts).
- Binary-size measurement added to CI.

### v0.3 — Dogfood-Ready *(daily-driver gate)*
**Exit criteria:**
- Saved connections persisted (metadata in SwiftData, secrets in Keychain).
- Query history persisted (SwiftData, opt-in, clearable).
- Multi-environment switching with visible prod warnings (e.g., red banner when connected to an env tagged "production").
- **Primary success bar A triggered:** 2 consecutive weeks of daily use as the sole Postgres client.
- Dogfood log (`docs/dogfood-log.md`) started and maintained through v0.4.

### v0.4 — Lean & Fast *(hit the thesis)*
**Exit criteria:**
- App binary size <50 MiB hard cap, with <30 MiB as a stretch goal.
- Cold start <500ms (measured on maintainer's primary machine).
- Query-path overhead <5ms vs `psql` on a localhost baseline (simple `SELECT` benchmarks).
- Zero crashes in 7 days of daily dogfooding.
- Dogfood log items from v0.3 triaged: fixed, deferred (with rationale), or converted to v1.1+ backlog.
- **Secondary success bar B met.**

### v0.5 — AI-Ready *(the differentiator)*
**Exit criteria:**
- Local schema introspection → on-device vector index.
- On-device NL2SQL via CoreML or MLX (quantized model, e.g., Phi-3 class or smaller).
- Command palette "Ask in English" produces runnable SQL for:
  - Simple single-table queries.
  - 2-table joins using foreign-key relationships.
- AI model shipped as a separate download, not bundled in the app binary.
- No prompts, schemas, or results leave the device.

### v1.0 — Public Launch
**Exit criteria:**
- Codesigned + notarized macOS build.
- Distribution: GitHub Releases + Homebrew cask.
- `README.md` with screenshots, quick-start, and install instructions.
- `CHANGELOG.md` covering v0.1 → v1.0.
- `SECURITY.md` vulnerability-reporting path live (email + response-time commitment).
- Light + dark theme support; default = dark.
- Governance & contribution artifacts in place: `GOVERNANCE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, DCO sign-off policy, and issue/PR templates under `.github/`.

## 7. Deferred to v1.1+

**Progress note (2026-07-19):** The read-only schema graph, EXPLAIN/EXPLAIN ANALYZE plan tree and JSON/TSV/Markdown/SQL export formats have since shipped on `main` while v1.0 distribution remains externally gated. The original backlog below is retained as the approved roadmap record; remaining slices are narrowed in parentheses.

- Read-only ERD / schema visualization. *(Implemented as the schema graph.)*
- Light DBA helpers: `EXPLAIN (ANALYZE, BUFFERS)` visualization, index suggestions, table/column stats viewer. Read-only, no mutation UI. *(EXPLAIN visualization implemented; index suggestions and statistics remain.)*
- Advanced AI: multi-table joins beyond 2, query optimization suggestions, natural-language schema search across large schemas.
- Export formats beyond CSV (JSON, Parquet, Excel). *(JSON plus TSV, Markdown and SQL implemented; Parquet and Excel remain.)*
- Full theming / appearance customization (beyond light/dark).
- Sparkle auto-updater.

## 8. Key Risks & Mitigations

| # | Risk | When we find out | Mitigation |
|---|------|------------------|------------|
| 1 | `PostgresNIO` missing a feature we need (e.g., `COPY`, `LISTEN/NOTIFY`, specific auth edge case, `gssapi`). | v0.1 exit | v0.1 validates auth + TLS + basic query only. If a gap appears: contribute upstream, work around, or re-evaluate `PostgresClientKit`. |
| 2 | SSH tunneling in pure Swift (NIOSSH) is too low-level or painful. | v0.1 exit | Escape hatch: shell out to the system `ssh` binary for tunneling in v0.1. Document as tech debt; revisit in v0.4 or v1.1. |
| 3 | Binary size creeps past the lean desktop budget once AI ships. | v0.4 + v0.5 | Ship AI model as a separate download. Measure binary size in CI from v0.2 onward. Warn above 30 MiB and fail above 50 MiB. |
| 4 | On-device NL2SQL quality is poor on real backend-engineer schemas (long names, unusual FK conventions). | v0.5 | v0.5 exit criteria already scope to simple queries + 2-table joins. Advanced cases explicitly deferred to v1.1+. |
| 5 | Dogfood bar A fails — maintainer keeps reaching for another tool at v0.3. | v0.3 dogfood window | Treat it as data, not failure. Log every switch in `docs/dogfood-log.md`, fix the gap, extend v0.3. Do not skip to v0.4 with an unresolved dogfood log. |

## 9. Working Norms

**Definition of done (every milestone):**
- All exit criteria met and demonstrable.
- `swift build` and `swift test` pass.
- Binary size recorded (from v0.2 onward).
- Changelog entry written.
- Git-tagged release (`v0.1`, `v0.2`, …).

**Dogfood protocol (v0.3 onward):**
- LithePG is the maintainer's default Postgres client on the primary machine.
- Maintain `docs/dogfood-log.md`. Every switch to another tool gets an entry: date, what was missing, severity. That log drives the v0.4/v1.0 punch list.

**Release cadence:**
- No calendar commitments. Milestones ship when exit criteria pass.
- One milestone in flight at a time. No parallel prototyping of later milestones.

**Spec / plan discipline:**
- Each milestone gets its own design spec (brainstorming) → implementation plan (writing-plans) → execution.
- This roadmap is the umbrella, not a substitute for per-milestone specs.

**Roadmap revision triggers:**
- A risk from §8 materializes → revisit the affected milestone.
- Dogfood log reveals a missing capability → promote to current milestone or next.
- Otherwise, the roadmap is not edited.

## 10. Open Questions

None at design approval. Per-milestone specs will surface implementation-level questions as each milestone begins.

## 11. Next Step

Invoke `superpowers:writing-plans` to produce the implementation plan for **v0.1 — Walking Skeleton**. Later milestones get their own brainstorm → spec → plan cycle when v0.1 ships.
