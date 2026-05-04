# SECURITY.md

## Threat Model
LithePG is a local macOS client that connects to user-owned PostgreSQL databases and runs AI inference locally. Primary assets to protect:
1. **Database credentials** (host, user, password, client certs).
2. **Query history and saved connections** (may contain sensitive schema or data fragments).
3. **Transport integrity** (connections to remote Postgres servers).
4. **User privacy** (no off-device analytics or LLM calls).

## Credential Storage
- **All secrets live in the macOS Keychain.** Never in SwiftData, plist, or on-disk files.
- Each connection references a Keychain item by identifier; the app never persists the password itself.
- Client certificates and SSH keys are referenced by path or Keychain handle, never copied.

## Transport Security
- **TLS is required by default.** `sslmode=require` minimum; prefer `verify-full` when a root CA is configured.
- Disabling TLS requires explicit opt-in per connection with a visible UI warning.
- No fallback to cleartext on handshake failure.

## Local Data at Rest
- SwiftData store lives under the app's sandbox container.
- Query history is opt-in and can be cleared at any time.
- No credentials, query results, or schema snapshots are written outside the sandbox.

## AI & Privacy
- **All inference is on-device** (CoreML / MLX).
- No prompts, schemas, query text, or results are transmitted to any external service.
- No telemetry. No crash reporting without explicit user opt-in.
- If a future feature requires network AI, it must be opt-in, clearly labeled, and off by default.

## Dependency Posture
- Minimize third-party dependencies (app binary target <50 MiB; AI models ship separately).
- No `libpq` or other C dependencies — reduces CVE exposure surface.
- Dependencies are pinned via `Package.resolved`; review updates before bumping.

## Reporting Vulnerabilities
Email security reports to the maintainer listed in `AGENTS.md`. Please do not open public issues for security-sensitive findings. Expect acknowledgement within 72 hours.

## Out of Scope
- Protection against a compromised macOS host (root-level malware).
- Protection of the remote PostgreSQL server itself — users are responsible for server-side hardening.
