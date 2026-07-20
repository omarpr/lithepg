# Contributing to LithePG

Thanks for your interest in LithePG. This project is **maintainer-led** with a
deliberately narrow scope. Before opening a pull request, please read this guide,
[`GOVERNANCE.md`](GOVERNANCE.md), the [Code of Conduct](CODE_OF_CONDUCT.md) and
the security posture in [`docs/SECURITY.md`](docs/SECURITY.md).

## Before you write code

- **Bugs:** open an issue, or send a small, obvious fix straight as a PR.
- **Roadmap work:** pick up items already on the roadmap (`docs/superpowers/`).
  Comment on the issue first so we don't double up.
- **New features or non-trivial changes:** open an issue or discussion **before**
  writing code. PRs that skip this may be closed without review.
- **Out-of-scope proposals:** anything that pushes LithePG toward cross-platform
  support, non-Postgres databases, cloud AI, team features or a plugin API gets
  closed with a link to the roadmap non-goals. Nothing personal, just scope
  discipline.

## Project invariants (non-negotiable)

A change that breaks one of these will not merge:

- **Mac-native only.** SwiftUI for all UI; AppKit only where bridging is
  unavoidable (justify it in a comment). No Electron, no cross-platform layers.
- **Pure app code.** No `libpq` and no app-authored C shims. PostgresNIO is the
  connection path; its accepted TLS dependency boundary is documented in
  `docs/TECH_STACK.md`.
- **Local-first AI.** Inference runs on-device (CoreML/MLX). No user data leaves
  the machine: not prompts, schemas, results, credentials or history. No bundled
  model artifacts.
- **Lean.** Binary-size and startup-time budgets are real targets (see
  `docs/TECH_STACK.md`). Discuss new dependencies first. The app binary has a
  <50 MiB hard cap and a 30 MiB stretch goal.
- **Secure by default.** Credentials go through the Keychain, never plaintext.
  Don't weaken TLS defaults (`docs/SECURITY.md`).
- **SPM only.** No `.xcodeproj`.

## Development setup

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
```

Confirm `swift build` and `swift test` pass before opening a PR (docs- or
templates-only changes excepted). For release-impacting changes, also run the
package verifier.

## Coding conventions

- Swift 6.2+, strict concurrency. Prefer `async/await` over completion handlers.
- Prefer `struct` over `class`; use `actor` for shared mutable state.
- SwiftUI for UI. Keep changes focused, with no drive-by reformatting.
- Update `docs/` when you change architecture, release workflow or security
  posture.

## Tests and examples

- New behavior needs tests. We use Swift Testing.
- Follow TDD where practical: write the failing test first.
- Never commit real schemas, query results, credentials, connection strings,
  tokens, certificates, screenshots or production data into tests, fixtures,
  docs, issues or PRs.
- Use seeded, dummy or synthetic examples. Replace passwords and tokens with
  `***`, and cut query output to the smallest fake rows that explain the
  behavior.

## Commit sign-off (DCO)

Every commit must be signed off under the
[Developer Certificate of Origin](https://developercertificate.org/):

```sh
git commit -s -m "your message"
```

The sign-off certifies you have the right to contribute the code under the
project's MIT license. There is no separate CLA. The same policy lives in
[`GOVERNANCE.md`](GOVERNANCE.md#sign-off-dco).

Use clear, conventional commit subjects (for example `feat(app): ...`,
`fix(core): ...`, `docs(readme): ...`).

## Pull requests

- Keep PRs small and single-purpose.
- Fill out the PR template, including how you verified the change.
- Sign off your commits (`git commit -s`).
- Keep secrets and real data out of examples, and re-check that nothing
  user-side (prompts, schemas, results, credentials, history) leaves the machine.
- Expect review from the project lead, who has the final say on acceptance.

## Reporting security issues

Please do **not** open public issues for security vulnerabilities. See
[`docs/SECURITY.md`](docs/SECURITY.md) for the current posture and reporting
guidance, and use the repository's private GitHub advisory channel for sensitive
reports if it is enabled.

## Code of conduct

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
