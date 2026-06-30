# Contributing to LithePG

Thanks for your interest in LithePG. This project is **maintainer-led** with an
opinionated, deliberately narrow scope. Please read this guide,
[`GOVERNANCE.md`](GOVERNANCE.md), the [Code of Conduct](CODE_OF_CONDUCT.md), and
the security posture in [`docs/SECURITY.md`](docs/SECURITY.md) before opening a
pull request.

## Before You Write Code

- **Bugs:** open an issue, or send a PR directly for small, obvious fixes.
- **Roadmap work:** pick up items already on the roadmap (`docs/superpowers/`).
  Comment on the issue first so we don't duplicate effort.
- **New features / non-trivial changes:** open an issue or discussion **before**
  writing code. PRs that skip this step may be closed without review.
- **Out-of-scope proposals:** changes that push LithePG toward cross-platform
  support, non-Postgres databases, cloud AI, team/collab features, or a plugin
  API will be closed with a link to the roadmap non-goals. It's not personal —
  just scope discipline.

## Project Invariants (Non-Negotiable)

These are load-bearing. A change that violates one will not be merged:

- **Mac-native only.** SwiftUI for all UI; AppKit only where bridging is
  unavoidable (justify in a comment). No Electron, no cross-platform layers.
- **Pure app code.** No `libpq` and no app-authored C shims. PostgresNIO is the connection path; its accepted TLS dependency boundary is documented in `docs/TECH_STACK.md`.
- **Local-first AI.** Inference runs on-device (CoreML/MLX). No user data —
  prompts, schemas, results, credentials, history — leaves the machine. No
  bundled model artifacts.
- **Lean.** Binary-size and startup-time budgets are real targets, not
  aspirations (see `docs/TECH_STACK.md`). New dependencies must be discussed
  first; the app binary target is <50 MiB hard cap, with a 30 MiB stretch goal.
- **Secure by default.** Credentials go through the Keychain; never plaintext.
  Don't weaken TLS defaults (`docs/SECURITY.md`).
- **SPM only.** No `.xcodeproj`.

## Development Setup

Requires macOS with the Xcode toolchain (Swift 6.2+, strict concurrency on).

```sh
swift build              # build
swift run lithepg        # run the CLI smoke utility
swift test               # run the test suite
swift build -c release   # release build
```

Packaging and gates:

```sh
./script/build_and_run.sh --package   # produce dist/LithePG.app
./script/package_verify.sh dist/LithePG.app
./script/dogfood_check.sh             # full stability gate (needs Docker/Postgres)
```

Always confirm `swift build` and `swift test` pass before opening a PR unless the
change is docs/templates only. For release-impacting changes, also run the
package verifier and dogfood gate when the local prerequisites are available.

## Coding Conventions

- Swift 6.2+, strict concurrency. Prefer `async/await` over completion handlers.
- Prefer `struct` over `class`; use `actor` for shared mutable state.
- SwiftUI for UI. Keep changes focused — no drive-by reformatting.
- Update `docs/` when you change architecture, release workflow, or security
  posture.

## Tests and Examples

- New behavior needs tests. We use Swift Testing.
- Code changes follow TDD where practical: write the failing test first.
- Never commit real schemas, query results, credentials, connection strings,
  tokens, certificates, screenshots, or production data into tests, fixtures,
  docs, issues, or PRs.
- Use seeded, dummy, redacted, or synthetic examples. Replace passwords/tokens
  with `***`, and reduce query output to the smallest fake rows needed to explain
  the behavior.

## Commit Sign-Off (DCO)

All commits must be signed off under the
[Developer Certificate of Origin](https://developercertificate.org/):

```sh
git commit -s -m "your message"
```

The sign-off certifies you have the right to contribute the code under the
project's MIT license. There is no separate CLA. The same policy is documented in
[`GOVERNANCE.md`](GOVERNANCE.md#sign-off-dco).

Use clear, conventional commit subjects (for example, `feat(app): ...`,
`fix(core): ...`, `docs(readme): ...`).

## Pull Requests

- Keep PRs small and single-purpose.
- Fill out the PR template, including how you verified the change.
- Include signed-off commits (`git commit -s`).
- Strip any credentials, connection strings, query-result dumps, private schemas,
  or real customer/user data from examples.
- Re-check the local-first privacy invariant: prompts, schemas, results,
  credentials, and history must not leave the user's machine.
- Expect review from the project lead, who has final say on acceptance.

## Reporting Security Issues

Please do **not** open public issues for security vulnerabilities. See
[`docs/SECURITY.md`](docs/SECURITY.md) for current security posture and reporting
guidance. If a private GitHub vulnerability-reporting/advisory channel is enabled
for the repository, use that path for sensitive reports.

## Code of Conduct

By participating you agree to abide by the
[Code of Conduct](CODE_OF_CONDUCT.md).
