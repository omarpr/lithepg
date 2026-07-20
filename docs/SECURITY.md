# SECURITY.md

## Threat Model
LithePG is a local macOS client that connects to user-owned PostgreSQL databases and runs AI inference locally. Primary assets to protect:
1. **Database credentials** (host, user, password, client certs).
2. **Query history and saved connections** (may contain sensitive schema or data fragments).
3. **Transport integrity** (connections to remote Postgres servers).
4. **User privacy** (no off-device analytics or LLM calls).

## Credential Storage
- **All saved passwords live in the macOS Keychain.** Never in local JSON files, plist files, UserDefaults, logs, screenshots or query history.
- Keychain writes use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and the data-protection keychain flag when available. Reads retain a legacy fallback for pre-migration saved passwords.
- Entitlement-less builds (unsigned dev builds and plain `swift test` runners) cannot use the data-protection keychain at all (`errSecMissingEntitlement`, -34018). Saves in those builds fall back to the legacy login keychain with the same accessibility attribute rather than failing, and reads/deletes treat the data-protection keychain as absent. Signed/notarized builds keep the hardened data-protection path. Covered by the `LITHEPG_KEYCHAIN_TESTS=1` gated suite.
- Each saved connection references a Keychain item by identifier; the app persists connection metadata only.
- Saved-connection metadata is HMAC-signed with a per-connection key stored in the credential store. LithePG refuses to load unsigned or tampered saved-connection metadata so a local file edit cannot silently redirect a saved password to another host.
- Client certificates and SSH keys are referenced by path or by the user's system SSH/Keychain configuration; they are not copied into LithePG-owned storage.
- `POSTGRES_URL` and `LITHEPG_STARTUP_URL` are intended for CI and dogfood automation. Environment variables can be visible to same-user processes and terminal logs; saved connections are the recommended path for regular use.

## Transport Security
- Postgres URL `sslmode=` is honored. `require`, `verify-ca` and `verify-full` map to LithePG's verified TLS path; `disable`, `allow` and `prefer` remain cleartext until LithePG adds a distinct opportunistic/no-verify TLS mode.
- Explicit TLS connections do not fall back to cleartext on handshake failure.
- SSH tunnels use OpenSSH with `StrictHostKeyChecking=yes`; users must pre-trust bastion host keys in `known_hosts` instead of relying on trust-on-first-use.
- Current pre-1.0 builds still permit cleartext for localhost/dogfood and explicit `sslmode=disable`; remote cleartext warnings and richer TLS modes remain tracked hardening work.

## Local Data at Rest
- Saved connection metadata and opt-in query history are stored as local JSON files under Application Support.
- Query history is opt-in and can be cleared at any time.
- Credentials and query results are not written to LithePG-owned JSON files.
- Release bundles use Hardened Runtime and remain unsandboxed so explicit user-initiated integrations can execute OpenSSH and a user-installed Neon CLI. Public distribution still requires Developer ID signing and notarization.
- Neon discovery runs only after the user presses Scan. It invokes the installed CLI with JSON output, color disabled and Neon analytics disabled. CLI-generated URLs stay in process memory long enough to split metadata from passwords; passwords are sent to Keychain and are never logged or persisted in JSON.
- Test connection uses the entered credentials only for a temporary `SELECT 1` probe. It closes the temporary connection immediately, saves no metadata or password and redacts credentials from reported failures.

## AI & Privacy
- **All inference runs on-device.** On macOS 26, `OnDeviceAIQueryService` uses Apple's Foundation Models framework when the Apple Intelligence system model is available; otherwise it falls back to the deterministic local drafter.
- System-model input contains only a redacted user request plus a bounded subset of local schema and foreign-key metadata. Guided output is accepted only when every reported relation exists in the loaded schema.
- Generated output passes a second local gate that allows one read-only `SELECT`/read-only CTE and rejects mutation, DDL, administrative commands, `SELECT INTO`, row-locking clauses, malformed quoting/comments and multiple statements.
- The built-in deterministic fallback supports a documented read-only subset: relation listing, counts, projected columns, ordering, limits and known foreign-key joins.
- LithePG bundles and downloads no model artifact. macOS manages the system model. `LocalModelAIQueryService` remains a non-default, gated CoreML artifact-validation scaffold for user-provided experiments.
- No prompts, schemas, query text or results are transmitted to any external service.
- AI context construction is intentionally narrow: it may include the natural-language request and schema metadata, but it excludes raw connection URLs and query result rows and redacts credential-shaped substrings before any model adapter receives context.
- Generated SQL is a draft for user review. LithePG inserts drafts into the editor but does not execute them automatically.
- No telemetry. No crash reporting without explicit user opt-in.
- If a future feature requires network AI, it must be opt-in, clearly labeled and off by default.

## Dependency Posture
- Minimize third-party dependencies (app binary target <50 MiB; AI models ship separately).
- No `libpq` and no app-authored C shims. PostgresNIO's TLS path carries its documented SwiftNIO/BoringSSL dependency boundary.
- Dependencies are pinned via `Package.resolved`; review updates before bumping.

## Reporting Vulnerabilities

Please do **not** open public GitHub issues, discussions, PR comments or pastebin-style links for security-sensitive findings.

The public vulnerability-reporting contact is **pending Omar approval**. Until an approved contact is published, use `[security contact pending]` as the documented placeholder and treat the missing public contact as a release blocker for public v1.0 distribution. Do not invent or scrape a maintainer email address.

Once the public security contact is published, LithePG's target is to acknowledge vulnerability reports within **72 hours** and to follow up with triage status, remediation expectations or a request for safely redacted reproduction details.

Safe-reporting guidance:

- Redact credentials, tokens, certificates, cookies, private keys and any password-bearing connection strings.
- Use synthetic schemas, synthetic table names and minimal repro steps instead of production schemas or customer data.
- Do not include full database URLs, bastion hostnames, internal IP ranges, raw query-result dumps, logs with secrets or screenshots that reveal private data.
- Describe impact, affected version/commit, platform and sanitized steps to reproduce.
- If a finding involves AI context construction, include only synthetic prompts/schema snippets. LithePG's privacy invariant remains: no telemetry, no cloud AI calls and no prompt/schema/query/result transmission off-device.

## Out of Scope
- Protection against a compromised macOS host (root-level malware).
- Protection of the remote PostgreSQL server itself. Users are responsible for server-side hardening.
