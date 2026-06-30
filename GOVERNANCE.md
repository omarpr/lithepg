# Governance

LithePG is **maintainer-led**. This document defines how decisions get made and what contributors can expect.

## Project Lead

- **Omar Gerardo Soto-Fortuño** — project lead and maintainer.
- The project lead has final say on scope, roadmap, vision, release timing, and acceptance of contributions.
- Disagreements on direction are resolved by the project lead. There is no community vote on scope or features.

## Scope & Vision

LithePG has an opinionated scope documented in `docs/superpowers/specs/` (roadmap) and `docs/TECH_STACK.md`. Core commitments:

- Mac-native (macOS only).
- PostgreSQL only.
- Pure app code, no `libpq`, no app-authored C shims.
- Local-first AI — on-device inference only.
- Lean — binary-size and startup-time targets are load-bearing, not aspirational.

The non-goals listed in the roadmap are non-negotiable. Pull requests that push LithePG toward cross-platform support, non-Postgres databases, cloud AI, team/collab features, or a plugin API will not be accepted.

## Contribution Model

- **Bugs:** issues and PRs welcome at any time.
- **Roadmap work:** pick up items already on the roadmap. Coordinate in the issue first to avoid duplicate effort.
- **New features / non-trivial changes:** open a discussion or issue **before writing code**. PRs that skip this step may be closed without review.
- **Out-of-scope proposals:** will be closed with a link to the roadmap non-goals. Not personal — just scope discipline.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the concrete workflow, coding conventions, local verification commands, no-secrets guidance, and PR expectations.

## Sign-Off (DCO)

All commits must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/):

```sh
git commit -s -m "your message"
```

The sign-off is a lightweight statement that you have the right to contribute the code under this project's license (MIT). LithePG does not require a separate Contributor License Agreement. See [`CONTRIBUTING.md`](CONTRIBUTING.md#commit-sign-off-dco) for the contributor-facing DCO workflow.

## Code of Conduct

Contributors and maintainers are expected to follow the project's [Code of Conduct](CODE_OF_CONDUCT.md). Enforcement is handled by the project lead through the maintainer-led process described there.

## Succession

If the project lead becomes unavailable long-term, maintainership may be transferred to a trusted contributor named in a future update to this document. Until then, LithePG has a single point of decision — that is intentional.

## Changes to This Document

Changes to governance require a pull request and are at the discretion of the project lead.
