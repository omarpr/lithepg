# CLAUDE.md: Working in LithePG

Instructions for Claude Code when operating in this repository.

## Project Context
LithePG is a lean, Mac-native PostgreSQL client with local-first AI. See `docs/TECH_STACK.md` for the stack and `AGENTS.md` for the dev squad.

## Build & Test
- **Build:** `swift build`
- **Run:** `swift run lithepg`
- **Test:** `swift test`
- **Release build:** `swift build -c release`

Always verify changes compile with `swift build` before reporting work complete.

## Code Conventions
- **Swift 6.2+**, strict concurrency on.
- Prefer `async/await` over completion handlers.
- No `libpq`. No app-authored C shims. Keep the accepted PostgresNIO/TLS dependency boundary documented in `docs/TECH_STACK.md` §3.
- No Electron, no cross-platform abstractions. Mac-first.
- SwiftUI for all UI. No AppKit unless bridging is unavoidable — justify in a comment if used.
- Prefer `struct` over `class`; use `actor` for shared mutable state.

## Non-Goals / Do Not
- Do not add dependencies without discussing — app binary size target is <50 MiB hard cap, with a 30 MiB stretch goal.
- Do not introduce `.xcodeproj`. SPM only.
- Do not send user data off-device. AI inference runs locally (CoreML/MLX).
- Do not store credentials in plaintext. Use Keychain (see `docs/SECURITY.md`).
- Do not disable TLS defaults.

## Workflow
- Use Superset worktrees for parallel UI/logic work (see `AGENTS.md`).
- PLAN before ACT on non-trivial changes.
- Update `docs/` when architecture or security posture changes.

## File Layout
- `Sources/LithePGCore/` — connector, schema, AI drafting, export, and shared core logic.
- `Sources/LithePGApp/` — SwiftUI app UI, app state, persistence stores, and view models.
- `Sources/LithePGAppMain/` — thin packaged app launcher.
- `Sources/lithepg/` — CLI smoke utility.
- `docs/` — architecture, roadmap, security, release, tech stack, and evidence.
- `AGENTS.md`, `CLAUDE.md` — agent/tooling entry points (root).
