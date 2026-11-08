# Changelog

All notable release-history entries for LithePG are collected here for public readers. The historical notes below are summarized from the roadmap and milestone specs.

LithePG follows [Semantic Versioning](https://semver.org/). The `v1.0.0` tag marks the source release; signed and notarized binary publication is tracked separately because it requires Apple Developer credentials and final distribution approval.

## [Unreleased]

## [v1.0.12] — 2026-11-08

### Added

- Filter results: click the filter icon (or press ⌘F) and type to show only rows containing that text in any column, ignoring case and accents, across every page. The bar shows how many rows match, and copy and export use the filtered rows. Esc or the clear button brings everything back.
- Keyboard shortcuts can be changed in **Settings → Keyboard**. Click a command's shortcut and press the new keys; Delete removes it, Esc cancels and each row (or Restore Defaults) brings back the default. Shortcuts must include ⌘ or ⌃ so typing is never affected, and ones used by macOS or text editing (such as ⌘C or ⌘Q) or already taken by another command are refused with the reason. Settings now has General and Keyboard tabs.

### Changed

- The toolbar no longer repeats the tab bar's new-tab and close-tab buttons; ⌘T and ⌘W still work. Run is a labeled accent button, and the other toolbar icons show full contrast when usable, so they no longer look disabled.
- The results bar drops the "Table" label, which did nothing, and keeps its controls together at the right. Filter, Copy and Export now have text labels, Copy and Export show an arrow for their format menus, and Copy reads "Copied" with a checkmark for a moment after copying instead of staying checked.
- The README lists what LithePG does today, grouped by connections, writing SQL, results and the schema, and no longer describes releases as unnotarized previews.
- A `Makefile` gives the common tasks short names: `make test`, `make run`, `make app`, `make install`, `make web-deploy` and `make release`, which runs the local release wrapper.

### Fixed

- A cell that cannot be edited now says so at the top of the editor, in a "Read-only" notice with the reason (for example, that the query needs the table's primary key), instead of a small gray caption under a dimmed text box that looked like a broken editor.
- Neon scan errors open in a dialog with OK and a button that copies the fix, such as the sign-in command, instead of red text that could spill over the sidebar. The sign-in advice names the command the installed CLI recommends (`neon login` in Neon CLI 8).
- Scan Neon CLI explains failures and what to do next instead of showing raw CLI errors. An expired or missing Neon sign-in, Node.js not found, no network, rate limiting and a CLI that never finishes (now stopped after 60 seconds) each get a plain message, and these stop the scan rather than being counted as skipped resources.
- Scanning works with a sign-in saved by older Neon CLI versions in `~/.config/neonctl`. Neon CLI 8 tried to refresh it through the missing `~/.config/neon` folder and failed with "ENOENT ... .refresh-*.lock".
- Scanning works when LithePG is opened from the Dock and the Neon CLI was installed with npm, nvm or Volta. The CLI now runs with its own Node.js on the PATH, and LithePG also looks for it in those install folders.
- A Neon CLI that writes a lot of error output no longer hangs the scan.

### Commits since `v1.0.11`

- fix(neon): explain scan failures and survive Dock launches (`d0c2ace`)
- chore: add a Makefile with make release (`e69267d`)
- feat(neon): show scan errors in a dialog with a copyable fix (`9ca0a5a`)
- docs(readme): use the current website screenshot (`72a2137`)
- feat(settings): let users change keyboard shortcuts (`d354fbe`)
- docs(readme): bring the feature list up to date (`c867d1e`)
- feat(ui): working results filter and a clearer toolbar (`d7478c1`)
- feat(results): label the Filter, Copy and Export controls (`5551a16`)
- fix(results): make read-only cells explain themselves up front (`95f1fc8`)

## [v1.0.11] — 2026-11-07

### Added

- Edit query results in place. Double-click a cell (or use the View and edit action in VoiceOver), change the value or set it to NULL, and review the exact UPDATE before it runs; production connections get an extra warning. The change is written with a single UPDATE that matches the row by its full primary key, and the grid then shows the value PostgreSQL stored. Cells that cannot be written say why: columns computed by the query, views, generated and identity columns, tables without a primary key, or results that leave the key out. If the row changed since the results loaded, nothing is written and LithePG says so instead of overwriting the other change.
- SQL autocomplete in the editor. Suggestions appear under the cursor after two letters, or right after a `.`, and Esc opens them on demand. They cover SQL keywords (matching the case you type, so `sele` offers `select` and `SELE` offers `SELECT`), common functions, schemas, tables, views and columns. Columns come from the tables the current statement names, `alias.` narrows the list to that table, and each column shows its type. Up and Down move through the list, Tab or Return inserts the suggestion and Esc closes it. Names that need quoting are inserted quoted.
- With several statements in the editor, Run and Explain now execute only the statement under the cursor, or the selected SQL when there is a selection. The statement that will run gets a light tint. Semicolons inside strings, comments and `$$` function bodies do not split a statement. Each query tab remembers its own cursor.

### Fixed

- Numeric values keep their scale in results: a `numeric(10,2)` value of 9480.00 now shows as `9480.00` instead of `9480`, and `NaN` and `Infinity` display correctly. Values match PostgreSQL's own text output.
- Saving in the cell editor used to change only the value on screen, which looked like an edit that then vanished on refresh. Saving now writes to the database after confirmation, and cells that cannot be written are clearly read-only.
- A connection dropped by the server or network (an idle timeout, a Neon suspend, a restart) no longer leaves every query stuck on Running until the app is restarted. LithePG notices the drop right away, shows "Connection lost" in the header with a Reconnect button and keeps your results, schema and editor text.
- Reconnect now works for saved connections, not only for connections opened from a URL.
- Accented and other non-ASCII text (José, Muñoz, ¿qué?) no longer shows as replacement characters on databases that use LATIN1, WIN1252 or another non-UTF-8 encoding. LithePG now always asks the server for UTF-8, which also stops text written from LithePG being stored with the wrong bytes on those databases. SQL_ASCII databases, which do no conversion, fall back to Latin-1 for text that is not valid UTF-8.
- The results grid sits flush against its pane instead of leaving a gap above the header and left of the row numbers.
- The SQL editor no longer re-highlights the whole document on unrelated interface updates, which made longer scripts lag.

### Security

- Updated swift-nio-ssl to 2.37.6 for GHSA-xfxg-9975-pc2j (critical: an out-of-bounds read when checking certificate names, reachable from a TLS client) and swift-crypto to 5.1.1 for GHSA-8q93-f6xh-4f6f (critical: a double free when RSA public key parsing fails). swift-nio and postgres-nio also moved to their latest patch releases.
- Updated the website build tooling (vite, postcss and source-map-js) to clear its open advisories. The website is not part of the app.

### Changed

- The website describes autocomplete, running the statement under the cursor and one-click reconnect, links to this changelog, and no longer claims a local drafting fallback that was removed in v1.0.3. Build-from-source instructions now state the Swift 6.4 requirement for packaged builds, and the hero install command no longer gets cut off on wide screens. The hero shows a new screenshot of the current build.
- Release changelog preparation now turns these Unreleased notes into the release section and lists the commit subjects below them.

### Commits since `v1.0.10`

- chore(deps): pick up security fixes in swift-nio-ssl and swift-crypto (`cac9f49`)
- fix(ui): sit the results grid flush against the pane (`6b5850d`)
- fix(core): always ask the server for UTF-8 text (`a0c6a0d`)
- fix: report dropped connections and let saved connections reconnect (`6f4a66a`)
- feat(editor): run the statement under the cursor (`d18f6a6`)
- chore(webapp): update vite, postcss and source-map-js for open advisories (`254f5d5`)
- docs(changelog): describe the unreleased fixes and carry curated notes into releases (`bf223d1`)
- feat(editor): autocomplete keywords, tables and columns (`66ae5e4`)
- docs(webapp): refresh feature copy and fix the hero layout (`766dd53`)
- feat(results): write edited cells back to the database after confirmation (`2485d1e`)
- docs(webapp): show the current build in the hero screenshot (`e08dea0`)
- fix(core): show numeric values with their full scale (`0b15919`)
- docs(changelog): note the numeric display fix (`47fe4d5`)
- docs(webapp): retake the hero screenshot (`e53c755`)

## [v1.0.10] — 2026-08-11

### Changes since `v1.0.9`

- fix(release): bundle Swift compatibility shims into the app (`3d7a52a`)

## [v1.0.9] — 2026-08-06

### Changes since `v1.0.8`

- fix(release): audit Homebrew cask by name (`77b0675`)
- fix(release): scope audit to tap checks (`e85dcd5`)
- fix(core): stop the deadline sleeper aborting the app (`98651a9`)
- fix(release): require Swift 6.4 for release builds (`0b5f78c`)

## [v1.0.8] — 2026-08-05

### Changes since `v1.0.7-preview.1`

- fix: bound connection attempts so a stalled server cannot hang the app (`05f569b`)
- chore(webapp): pin the Fly deploy to a single machine (`5a276c6`)
- Preparing to release signed+notarized LithePG. (`a66d6dd`)
- fix parser (`820a8b6`)
- more fixes for notarized release (`a89a67b`)
- Add prepare_release_changelog.sh (`0bd0668`)

## [v1.0.3] — 2026-07-20

### Added

- Saved connections can be edited in place from the connection sheet or navigator, including their name, environment, endpoint, TLS/SSH options and password.
- Saved-connection lists are collapsible and paginated in groups of five, keeping the connection sheet and left navigator compact even with many databases.
- Result-table columns can be resized with the mouse while preserving a usable minimum width.
- Appearance settings now include a preference for whether the connection window opens automatically at launch. The connection view can always be dismissed or used to quit LithePG without first connecting.
- Ask in English now uses Apple's lightweight on-device `SystemLanguageModel.default` with bounded schema context, guided output and the existing read-only SQL safety gate.

### Changed

- Enabling “Save this connection” changes the primary action to **Save & Connect** without disabling it. A blank optional connection name receives a deterministic `host · database` name.
- Required connection fields now carry a visible `*` indicator and legend. Conditional requirements such as the SSH target also participate in submit validation.
- Ask in English depends exclusively on Apple's local model. If Apple Intelligence is disabled, unsupported, still preparing or temporarily unavailable, drafting stays disabled and an information card explains the relevant recovery step; LithePG no longer substitutes its basic deterministic drafter.
- The Ask panel can be opened while disconnected so its schema and model requirements are visible instead of hiding the guidance behind a disabled toolbar action.
- Query tabs expose a clearer close action and the connection navigator keeps Add Connection readily available outside the initial connection window.
- Release tooling now supports versioned unsigned Homebrew preview casks and validates versioned ZIP artifacts before publication. The website and release copy use the latest cask installation path rather than a version-specific install command.

### Fixed

- Opening the app and browsing saved connections no longer reads every per-connection Keychain integrity item. Integrity validation is deferred until a connection is used and successful Keychain reads are cached for the current app session, preventing cascades of repeated authorization dialogs while preserving tamper checks before credentials or network access.
- Passwordless PostgreSQL connections can be saved, reopened and edited without incorrectly reporting a missing credential-store password.
- PostgreSQL failures now surface useful, credential-redacted server diagnostics instead of the generic `PSQLError` privacy description.
- Neon CLI scans reject interactive or malformed output with actionable authentication guidance instead of exposing a raw JSON decoding error.

### Security

- Repository publication checks now fail closed, CI security tools are pinned or checksum-verified, CodeQL scanning is configured and release artifacts are rebuilt with source-path privacy checks.

### Verified

- The complete local Swift gate passes 277 tests across 41 suites. Environment-gated Apple-model, Keychain, SSH, UI and live-Postgres integration tests remain opt-in.

## [v1.0.0] — 2026-07-19 — Source Release

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
- Readability pass: results grid, sidebar rows, status text and badges moved from 10pt caption sizes to 11 to 12pt.
- EXPLAIN plan parsing (`QueryPlan`) and headless plan-tree presentation seams, ready for a v1.1 plan view.
- Schema graph (`⇧⌘G`): an in-app force-directed graph of tables and foreign keys with pan, zoom, drag, selection highlighting and a column inspector with PK/FK badges. Read-only, derived from already-loaded schema metadata; graphs past 300 tables use a static grid layout.
- Neon connection support: pasted Neon URLs are detected and surface endpoint, database, role and pooled or direct mode, with a suggested connection name. Verified live against real Neon endpoints (Postgres 17, direct and pooled, current host shape) by CLI smoke and the gated live app suite.
- A left-side connection navigator switches among saved databases without returning to the connect sheet. An optional, explicit Neon CLI scanner discovers project/branch databases and imports only missing endpoints; its button remains disabled when the CLI is unavailable.
- The connection form can run a temporary `SELECT 1` probe before connecting or saving, with explicit success feedback and credential-redacted failures.
- The built-in English-to-SQL drafter now covers generic counts, column projection, ordering and limits in addition to relation listing and known joins, rejects mutation prompts and labels its deterministic limitations directly in the UI.
- Pasted connection strings are sanitized before parsing, so quoted strings, `psql '<url>'` commands, `DATABASE_URL=` lines and trailing newlines all work.
- Bare-executable runs (`swift run`, Xcode package schemes) now activate the app so windows accept keyboard input.
- Keychain resilience: entitlement-less builds fall back to the legacy login keychain instead of failing to save credentials; a gated suite (`LITHEPG_KEYCHAIN_TESTS=1`) covers real-keychain round trips.
- Release tooling: local package verification, artifact and icon hardening, `script/v10_release_gate.sh` preflight, `script/create_release_zip.sh`, a credential-gated signing/notarization wrapper and a Homebrew cask template under `packaging/homebrew/`.
- `CORE_TECHNOLOGIES.md` documents every core technology choice and why.
- A native About window shows the website, main developer and bundle-derived semantic version/build number.

### Changed

- swift-nio updated to 2.101.2 for published advisories (GHSA-rj37-6j9x-74q6, GHSA-r3rc-9hpw-54v9, GHSA-cq87-8r7h-962v).
- User-facing copy reworked to read naturally (no em-dashes, no Oxford commas).
- CI runs on every push and PR again: build and tests on macOS, security scans (osv-scanner, gitleaks, semgrep) on Linux with pinned, checksum-verified scanner binaries.

### Verified

- 252 tests across 40 suites pass locally; live suites were separately verified against seeded Docker Postgres and real Neon endpoints.
- Full patch-bearing git history (446 commits) scanned for secrets with gitleaks plus manual pattern sweeps: no credentials or secrets found.
- Binary and speed budgets hold: ~21.7 MiB release executable (50 MiB cap, 30 MiB stretch), sub-500 ms connected startup, sub-5 ms query overhead.

### Still blocked before public binary distribution

- Apple Developer signing identity and notarytool profile on the release machine.
- An approved public security-reporting contact to replace the placeholder policy.
- An approved Homebrew tap target.
- Release-copy approval and resolved draft placeholders, both gated on explicit publication approval.

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
- A milestone stability gate that ran default tests, live database coverage and measurement checks.
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

[v1.0.12]: https://github.com/omarpr/lithepg/compare/v1.0.11...v1.0.12
[v1.0.11]: https://github.com/omarpr/lithepg/compare/v1.0.10...v1.0.11
[v1.0.10]: https://github.com/omarpr/lithepg/compare/v1.0.9...v1.0.10
[v1.0.9]: https://github.com/omarpr/lithepg/compare/v1.0.8...v1.0.9
[v1.0.8]: https://github.com/omarpr/lithepg/compare/v1.0.7-preview.1...v1.0.8
[v1.0.3]: https://github.com/omarpr/lithepg/compare/v1.0.0...v1.0.3
[v1.0.0]: https://github.com/omarpr/lithepg/tree/v1.0.0
[v0.5]: https://github.com/omarpr/lithepg/tree/v0.5
[v0.4]: https://github.com/omarpr/lithepg/tree/v0.4
[v0.3]: https://github.com/omarpr/lithepg/tree/v0.3
[v0.2]: https://github.com/omarpr/lithepg/tree/v0.2
[v0.1]: https://github.com/omarpr/lithepg/tree/v0.1
