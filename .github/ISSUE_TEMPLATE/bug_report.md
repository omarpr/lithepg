---
name: Bug report
about: Report a reproducible problem in LithePG
title: "fix: "
labels: bug
assignees: ""
---

<!--
Thanks for reporting a bug. Use redacted, seeded, or synthetic examples only.

Do NOT paste passwords, tokens, full connection URLs, private schemas, real
query-result dumps, certificates, or real customer/user data.

If this is a security vulnerability, do not open a public issue. See
`docs/SECURITY.md` and use GitHub private vulnerability reporting/advisory
channels if enabled for this repository.
-->

## Summary

<!-- What happened? What did you expect instead? -->


## Reproduction steps

<!-- Provide the smallest safe reproduction using sanitized inputs. -->

1.
2.
3.

## Environment

- macOS version:
- LithePG version/commit:
- Install/run method:

## Sanitized connection/query details

<!--
Redact credentials and private data. Use fake hostnames/schemas/rows where
possible.

Example shape:
postgres://user:***@db.example.invalid:5432/example?sslmode=require
SELECT 1 AS example;
-->

```text

```

## Relevant logs or screenshots

<!-- Paste only short, redacted excerpts. No real query-result dumps, private schemas, secrets, or full connection URLs. -->

```text

```

## Privacy check

- [ ] I removed passwords, tokens, full connection URLs, private schemas, certificates, and real query-result dumps.
- [ ] Any examples above are redacted, seeded, or synthetic.
- [ ] This is not a security vulnerability report that should be handled privately.
