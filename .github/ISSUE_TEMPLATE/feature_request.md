---
name: Feature request
about: Propose a focused change that fits LithePG's scope
title: "feat: "
labels: enhancement
assignees: ""
---

<!--
LithePG is maintainer-led and intentionally narrow: Mac-native, PostgreSQL-only,
Swift app code with no libpq, local-first AI, lean, and secure by default. Please read
`CONTRIBUTING.md` and `GOVERNANCE.md` before proposing non-trivial work.

Use redacted, seeded, or synthetic examples only. Do NOT paste passwords, tokens,
full connection URLs, private schemas, real query-result dumps, certificates, or
real customer/user data.

Security vulnerabilities should not be opened publicly; see `docs/SECURITY.md`
and use GitHub private vulnerability reporting/advisory channels if enabled for
this repository.
-->

## Problem or workflow

<!-- What user problem does this solve? -->


## Proposed solution

<!-- Describe the smallest useful change. -->


## Scope fit

<!-- Which project invariant does this touch: Mac-native UI, PostgreSQL query workflow, local-first AI, security/credentials, lean performance/packaging, or docs/release workflow? -->


## Sanitized examples

<!-- Optional fake schema/query/UI examples. Keep them small and synthetic. -->

```sql
-- Example fake schema only; replace or delete.
CREATE TABLE demo_customers (id integer primary key, name text);
```

## Guardrails

- [ ] This does not require cloud AI, telemetry, or sending prompts/schemas/results/credentials/history off-device.
- [ ] This does not require cross-platform support, non-Postgres databases, or a plugin API.
- [ ] I removed passwords, tokens, full connection URLs, private schemas, certificates, and real query-result dumps.
