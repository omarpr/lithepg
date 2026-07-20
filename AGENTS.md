# AGENTS.md: Working in LithePG

Repository guidance for coding agents and automated development tools.

## Project context

LithePG is a lean, Mac-native PostgreSQL client with local-first AI. See
`docs/TECH_STACK.md` for the architecture and dependency boundaries.

## Build and test

- Build: `swift build`
- Run the CLI smoke utility: `swift run lithepg`
- Test: `swift test`
- Release build: `swift build -c release`
- Package the app: `./script/build_and_run.sh --package`
- Verify a package: `./script/package_verify.sh dist/LithePG.app`

Compile and run the relevant tests before reporting implementation work as
complete. Live Postgres, TLS, SSH, Keychain, Neon and model tests are gated by
environment variables and skip when their explicit test resources are absent.

## Code conventions

- Use Swift 6.2+ with strict concurrency.
- Prefer `async`/`await` over completion handlers.
- Prefer value types; use actors for shared mutable state.
- Use SwiftUI for UI. Bridge to AppKit only when necessary for native macOS
  behavior, and keep the bridge narrowly scoped.
- Do not add `libpq` or app-authored C shims. Keep the accepted
  PostgresNIO/BoringSSL boundary documented in `docs/TECH_STACK.md`.
- Keep the app Mac-first. Do not add Electron or cross-platform UI layers.
- Do not add dependencies without discussing the binary-size impact. The hard
  executable cap is 50 MiB, with a 30 MiB stretch target.
- Keep Swift Package Manager as the build system; do not add an `.xcodeproj`.

## Security and privacy

- Never commit credentials, tokens, production connection strings, real schema
  data or real query results.
- Store saved database credentials in Keychain, never plaintext metadata.
- Keep prompts, schema context, generated SQL and query results on-device.
- Preserve secure TLS defaults and redact credentials from user-facing errors,
  logs and diagnostics.
- Test fixtures and screenshots must use clearly synthetic data.

## Workflow

- Inspect existing work before editing and preserve unrelated user changes.
- Plan non-trivial work before implementation.
- Keep changes focused and update tests with behavior changes.
- Update `docs/` when architecture, security posture or the release workflow
  changes.
- Use isolated worktrees when parallel agents are explicitly orchestrated.
- If asked to commit, keep each commit coherent and exclude unrelated worktree
  changes. Push only when explicitly requested.

## Repository layout

- `Sources/LithePGCore/` — connector, schema, AI drafting, export and shared
  logic.
- `Sources/LithePGApp/` — SwiftUI UI, app state, persistence and view models.
- `Sources/LithePGAppMain/` — packaged app launcher.
- `Sources/lithepg/` — CLI smoke utility.
- `Tests/` — Swift Testing and environment-gated integration suites.
- `script/` — package, release and focused test helpers.
- `docs/` — architecture, security, release and historical design documents.
- `webapp/` — promotional website and Fly.io deployment configuration.
