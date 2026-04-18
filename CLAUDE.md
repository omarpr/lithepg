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
- No `libpq`. No C shims. Pure Swift only (see `docs/TECH_STACK.md` §3).
- No Electron, no cross-platform abstractions. Mac-first.
- SwiftUI for all UI. No AppKit unless bridging is unavoidable — justify in a comment if used.
- Prefer `struct` over `class`; use `actor` for shared mutable state.

## Non-Goals / Do Not
- Do not add dependencies without discussing — binary size target is <15MB.
- Do not introduce `.xcodeproj`. SPM only.
- Do not send user data off-device. AI inference runs locally (CoreML/MLX).
- Do not store credentials in plaintext. Use Keychain (see `docs/SECURITY.md`).
- Do not disable TLS defaults.

## Workflow
- Use Superset worktrees for parallel UI/logic work (see `AGENTS.md`).
- PLAN before ACT on non-trivial changes.
- Update `docs/` when architecture or security posture changes.

## File Layout
- `Sources/lithepg/` — app code.
- `docs/` — architecture, roadmap, security, tech stack.
- `AGENTS.md`, `CLAUDE.md` — agent/tooling entry points (root).
