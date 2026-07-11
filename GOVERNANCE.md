# Governance

LithePG is **maintainer-led**. This document covers how decisions get made and
what contributors can expect.

## Project lead

- **Omar Gerardo Soto-Fortuño**, project lead and maintainer.
- The project lead has final say on scope, roadmap, vision, release timing and
  acceptance of contributions.
- Direction disagreements are settled by the project lead. There is no community
  vote on scope or features.

## Scope and vision

LithePG's opinionated scope lives in `docs/superpowers/specs/` (roadmap) and
`docs/TECH_STACK.md`. Core commitments:

- Mac-native (macOS only).
- PostgreSQL only.
- Pure app code: no `libpq`, no app-authored C shims.
- Local-first AI: on-device inference only.
- Lean: binary-size and startup-time targets are load-bearing, not aspirational.

The roadmap non-goals are non-negotiable. Pull requests that push LithePG toward
cross-platform support, non-Postgres databases, cloud AI, team features or a
plugin API will not be accepted.

## Contribution model

- **Bugs:** issues and PRs welcome any time.
- **Roadmap work:** pick up items already on the roadmap. Coordinate in the issue
  first to avoid duplicate effort.
- **New features or non-trivial changes:** open a discussion or issue **before
  writing code**. PRs that skip this may be closed without review.
- **Out-of-scope proposals:** closed with a link to the roadmap non-goals.
  Nothing personal, just scope discipline.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the concrete workflow, coding
conventions, local verification commands, no-secrets guidance and PR
expectations.

## Sign-off (DCO)

Every commit must be signed off under the
[Developer Certificate of Origin](https://developercertificate.org/):

```sh
git commit -s -m "your message"
```

The sign-off states that you have the right to contribute the code under the
project's license (MIT). There is no separate Contributor License Agreement. See
[`CONTRIBUTING.md`](CONTRIBUTING.md#commit-sign-off-dco) for the workflow.

## Code of conduct

Contributors and maintainers follow the project's
[Code of Conduct](CODE_OF_CONDUCT.md). The project lead handles enforcement
through the maintainer-led process described there.

## Succession

If the project lead becomes unavailable long-term, maintainership may pass to a
trusted contributor named in a future update to this document. Until then LithePG
has a single, intentional point of decision.

## Changes to this document

Governance changes require a pull request and are at the project lead's
discretion.
