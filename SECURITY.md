# Security Policy

LithePG's full security posture and vulnerability-reporting guidance lives in [`docs/SECURITY.md`](docs/SECURITY.md).

## Reporting Vulnerabilities

Please do **not** open public GitHub issues, discussions, PR comments, or pastebin-style links for security-sensitive findings.

The public security contact is **pending Omar approval**. Until an approved contact is published, `[security contact pending]` is the placeholder reporting path and the missing public contact remains a blocker for public v1.0 distribution. Do not invent or scrape a maintainer email address.

Once the public contact is published, LithePG targets acknowledgement of vulnerability reports within **72 hours**.

When preparing a report, redact credentials, tokens, certificates, private keys, full connection URLs, private schemas, raw query-result dumps, internal hostnames/IP ranges, and screenshots containing private data. Use synthetic schemas/data and minimal reproduction steps whenever possible.

LithePG's local-first privacy invariant remains in scope for security reports: no telemetry, no cloud AI calls, and no prompt/schema/query/result transmission off-device.
