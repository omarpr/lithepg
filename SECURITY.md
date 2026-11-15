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
- Saved connections with passwords reference a Keychain item by identifier; passwordless connections omit that reference. The app persists connection metadata only.
- Saved-connection metadata is HMAC-signed with a per-connection key stored in the credential store. LithePG refuses to load unsigned or tampered saved-connection metadata so a local file edit cannot silently redirect a saved password to another host.
- Client certificates and SSH keys are referenced by path or by the user's system SSH/Keychain configuration; they are not copied into LithePG-owned storage.
- `POSTGRES_URL` and `LITHEPG_STARTUP_URL` are intended for CI and automated testing. Environment variables can be visible to same-user processes and terminal logs; saved connections are the recommended path for regular use.

## Transport Security
- **Verified TLS is the default for remote hosts.** A connection without an `sslmode` uses `verify-full` (certificate chain and hostname checked) for any host that is not loopback, and `disable` for `localhost`, `127.0.0.0/8`, `::1` and `*.localhost`.
- Postgres URL `sslmode=` values map to four modes, and unknown values are rejected rather than guessed:
  - `verify-full` and `verify-ca` use verified TLS. `verify-ca` is held to the stricter `verify-full` bar. Verified connections never fall back to cleartext.
  - `require` always encrypts but does not check the server certificate, as in libpq, so it does not stop an active machine in the middle.
  - `prefer` and `allow` try TLS without checking the certificate and fall back to cleartext if the server refuses TLS. PostgresNIO has no cleartext-first ordering, so `allow` behaves like `prefer`.
  - `disable` sends everything, including the password exchange, in cleartext.
- These weaker modes are only ever used when the URL or the user asks for them. The connect sheet warns when a remote host would use `disable` or `prefer`, and the TLS picker explains that `require` skips certificate checks. Imported Neon connections are saved as `verify-full` even when Neon's URL asks for `require`.
- A saved connection with an unrecognized TLS label fails to load instead of falling back to a weaker mode.
- SSH tunnels use OpenSSH with `StrictHostKeyChecking=yes`; users must pre-trust bastion host keys in `known_hosts` instead of relying on trust-on-first-use. The forward listens only on 127.0.0.1, ssh runs in batch mode and SSH users or hosts that start with `-` are refused so they cannot be read as ssh options. In the app, SSH tunnels are available only with TLS off, so traffic between the bastion and the database is not encrypted by LithePG.

## Local Data at Rest
- Saved connection metadata and opt-in query history are stored as local JSON files under Application Support.
- Query history is opt-in and can be cleared at any time.
- Credentials and query results are not written to LithePG-owned JSON files.
- Release bundles are signed with a Developer ID, use Hardened Runtime and are notarized by Apple. LithePG is not sandboxed, because it runs the system OpenSSH and a user-installed Neon CLI. Moving to the App Sandbox with helper processes remains a long-term goal.
- Neon discovery runs only after the user presses Scan. It invokes the installed CLI with JSON output, color disabled and Neon analytics disabled. CLI-generated URLs stay in process memory long enough to split metadata from passwords; passwords are sent to Keychain and are never logged or persisted in JSON.
- Test connection uses the entered credentials only for a temporary `SELECT 1` probe. It closes the temporary connection immediately, saves no metadata or password and redacts credentials from reported failures.

## AI & Privacy
- **All inference runs on-device.** Ask in English uses only Apple's `SystemLanguageModel.default` through the Foundation Models framework on macOS 26 with Apple Intelligence. When that model is unavailable, drafting is disabled with recovery guidance and no other drafter is substituted.
- LithePG bundles no model and downloads none. macOS manages the system model.
- A local gate admits only a single `SELECT` or `WITH` statement and rejects mutation, DDL, locking clauses, `SELECT INTO` and multiple statements. It is a keyword check, so a draft can still call a side-effecting function (for example `pg_terminate_backend`); review drafts before running them, especially on Production connections.
- No prompts, schemas, query text or results are transmitted to any external service.
- AI context construction is intentionally narrow: it may include the natural-language request and schema metadata, but it excludes raw connection URLs and query result rows and redacts credential-shaped substrings before any model adapter receives context.
- Generated SQL is a draft for user review. LithePG inserts drafts into the editor but does not execute them automatically.
- No telemetry. No crash reporting without explicit user opt-in.
- If a future feature requires network AI, it must be opt-in, clearly labeled and off by default.

## Dependency Posture
- Minimize third-party dependencies (app binary target <50 MiB; AI models ship separately).
- No `libpq` and no app-authored C shims. PostgresNIO's TLS path carries its documented SwiftNIO/BoringSSL dependency boundary.
- Dependencies are pinned via `Package.resolved`; automatic security alert monitoring (Dependabot) is configured to flag transient vulnerabilities within the NIO/BoringSSL boundaries before bumps.

## Reporting Vulnerabilities

Please do **not** open public GitHub issues, discussions, PR comments or pastebin-style links for security-sensitive findings.

The public vulnerability-reporting contact is **omarpr@gmail.com**. LithePG's target is to acknowledge vulnerability reports within **72 hours** and to follow up with triage status, remediation expectations or a request for safely redacted reproduction details.

Safe-reporting guidance:

- Redact credentials, tokens, certificates, cookies, private keys and any password-bearing connection strings.
- Use synthetic schemas, synthetic table names and minimal repro steps instead of production schemas or customer data.
- Do not include full database URLs, bastion hostnames, internal IP ranges, raw query-result dumps, logs with secrets or screenshots that reveal private data.
- Describe impact, affected version/commit, platform and sanitized steps to reproduce.
- If a finding involves AI context construction, include only synthetic prompts/schema snippets. LithePG's privacy invariant remains: no telemetry, no cloud AI calls and no prompt/schema/query/result transmission off-device.

## Out of Scope
- Protection against a compromised macOS host (root-level malware).
- Protection of the remote PostgreSQL server itself. Users are responsible for server-side hardening.
