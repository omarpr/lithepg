# SECURITY.md

## Threat Model
LithePG is a local macOS client that connects to user-owned PostgreSQL databases and runs AI inference locally. Primary assets to protect:
1. **Database credentials** (host, user, password, client certs).
2. **Query history and saved connections** (may contain sensitive schema or data fragments).
3. **Transport integrity** (connections to remote Postgres servers).
4. **User privacy** (no off-device analytics or LLM calls).

## Credential Storage
- **All saved passwords live in the macOS Keychain.** Never in local JSON files, plist files, UserDefaults, logs, screenshots, or query history.
- Keychain writes use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and the data-protection keychain flag when available. Reads retain a legacy fallback for pre-migration saved passwords.
- Each saved connection references a Keychain item by identifier; the app persists connection metadata only.
- Saved-connection metadata is HMAC-signed with a per-connection key stored in the credential store. LithePG refuses to load unsigned or tampered saved-connection metadata so a local file edit cannot silently redirect a saved password to another host.
- Client certificates and SSH keys are referenced by path or by the user's system SSH/Keychain configuration; they are not copied into LithePG-owned storage.
- `POSTGRES_URL` and `LITHEPG_STARTUP_URL` are intended for CI and dogfood automation. Environment variables can be visible to same-user processes and terminal logs; saved connections are the recommended path for regular use.

## Transport Security
- Postgres URL `sslmode=` is honored. `require`, `verify-ca`, and `verify-full` map to LithePG's verified TLS path; `disable`, `allow`, and `prefer` remain cleartext until LithePG adds a distinct opportunistic/no-verify TLS mode.
- Explicit TLS connections do not fall back to cleartext on handshake failure.
- SSH tunnels use OpenSSH with `StrictHostKeyChecking=yes`; users must pre-trust bastion host keys in `known_hosts` instead of relying on trust-on-first-use.
- Current pre-1.0 builds still permit cleartext for localhost/dogfood and explicit `sslmode=disable`; remote cleartext warnings and richer TLS modes remain tracked hardening work.

## Local Data at Rest
- Saved connection metadata and opt-in query history are stored as local JSON files under Application Support in current pre-sandbox builds.
- Query history is opt-in and can be cleared at any time.
- Credentials and query results are not written to LithePG-owned JSON files.
- Public distribution must add App Sandbox, Hardened Runtime, signing, and notarization before broad release.

## AI & Privacy
- **All inference is intended to run on-device.** v0.5's first adapter scaffold uses CoreML because it is provided by the macOS SDK and adds no package dependency; MLX remains a future measured option.
- v0.5 ships deterministic/local NL2SQL scaffolding plus a gated `LocalModelAIQueryService`. The adapter is disabled by default and requires both `LITHEPG_ENABLE_LOCAL_MODEL=1` and `LITHEPG_LOCAL_MODEL_PATH` before it will attempt to load a user-provided CoreML artifact.
- Model artifacts are separate from the app binary, are expected under LithePG's Application Support model directory by default, and are never downloaded by the app.
- No prompts, schemas, query text, or results are transmitted to any external service.
- AI context construction is intentionally narrow: it may include the natural-language request and schema metadata, but it excludes raw connection URLs and query result rows and redacts credential-shaped substrings before any model adapter receives context.
- Generated SQL is a draft for user review. LithePG inserts drafts into the editor but does not execute them automatically.
- No telemetry. No crash reporting without explicit user opt-in.
- If a future feature requires network AI, it must be opt-in, clearly labeled, and off by default.

## Dependency Posture
- Minimize third-party dependencies (app binary target <50 MiB; AI models ship separately).
- No `libpq` and no app-authored C shims. PostgresNIO's TLS path carries its documented SwiftNIO/BoringSSL dependency boundary.
- Dependencies are pinned via `Package.resolved`; review updates before bumping.

## Reporting Vulnerabilities

Please do **not** open public GitHub issues, discussions, PR comments, or pastebin-style links for security-sensitive findings.

The public vulnerability-reporting contact is **pending Omar approval**. Until an approved contact is published, use `[security contact pending]` as the documented placeholder and treat the missing public contact as a release blocker for public v1.0 distribution. Do not invent or scrape a maintainer email address.

Once the public security contact is published, LithePG's target is to acknowledge vulnerability reports within **72 hours** and to follow up with triage status, remediation expectations, or a request for safely redacted reproduction details.

Safe-reporting guidance:

- Redact credentials, tokens, certificates, cookies, private keys, and any password-bearing connection strings.
- Use synthetic schemas, synthetic table names, and minimal repro steps instead of production schemas or customer data.
- Do not include full database URLs, bastion hostnames, internal IP ranges, raw query-result dumps, logs with secrets, or screenshots that reveal private data.
- Describe impact, affected version/commit, platform, and sanitized steps to reproduce.
- If a finding involves AI context construction, include only synthetic prompts/schema snippets. LithePG's privacy invariant remains: no telemetry, no cloud AI calls, and no prompt/schema/query/result transmission off-device.

## Out of Scope
- Protection against a compromised macOS host (root-level malware).
- Protection of the remote PostgreSQL server itself — users are responsible for server-side hardening.
