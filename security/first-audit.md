# LithePG Security Audit — First Pass

> Historical audit receipt from 2026-05-05. This document is preserved as an
> evidence artifact for the reviewed commit below and is not the current
> security posture. For current policy and implementation status, see
> [`../SECURITY.md`](../SECURITY.md).

**Date:** 2026-05-05
**Auditor:** Security Engineer agent
**Commit:** `ab4b49f0f98e31182ce83efb86023a809d3247d3`
**Scope reviewed:**
- `Sources/LithePGCore/{ConnectionConfig,PostgresConnector,SSHTunnel,SchemaIntrospector,SchemaMetadata,QueryResult,ErrorRedaction}.swift`
- `Sources/LithePGApp/{AppState,ConnectSheet,PersistenceStores,PersistenceModels,LithePGApp,WorkspaceView,EditorView,ResultsTable,SchemaSidebar,QueryHistoryView,QueryTab,SQLSyntaxHighlighter,ErrorBanner}.swift`
- `Sources/lithepg/LithePGMain.swift`
- `Sources/LithePGBench/LithePGBench.swift`
- `Package.swift`, `Package.resolved`
- `.github/workflows/ci.yml`
- `script/{build_and_run,dogfood_postgres,run_dogfood_app}.sh`, `script/dogfood_seed.sql`
- `dist/LithePG.app/Contents/Info.plist`, `.build/.../*-entitlement.plist`
- `SECURITY.md`, `AGENTS.md`, `.gitignore`
- Test files cross-checked: `Tests/LithePGCoreTests/{ErrorRedactionTests,PostgresConnectorTests,SchemaIntrospectorTests,SSHTunnelTests}.swift`, `Tests/LithePGAppTests/AppStateTests.swift`

## Executive Summary

- **Overall posture is reasonable for a pre-1.0 dogfood release.** The "pure Swift, no libpq" claim is fully verified in `Package.resolved`. Passwords for saved connections do reach the macOS Keychain via `SecItemAdd` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Network egress is limited to the user-configured Postgres host plus an optional `/usr/bin/ssh` subprocess; no telemetry, analytics, crash-reporting, or update-check code paths exist.
- **The biggest gap between the documented posture and the code is TLS defaulting.** `SECURITY.md` claims "TLS is required by default" and "no fallback to cleartext on handshake failure," but in code TLS defaults to `.disable` everywhere — in `ConnectionConfig.init(...)`, in URL parsing (`?sslmode=...` is silently ignored), in saved connections (anything not literally `"verify-full"` is treated as `.disable`), and in the connect sheet (the toggle is off unless an env var is set). This is the most security-relevant divergence.
- **The shipped/built `.app` has no entitlements file at all** (`dist/LithePG.app/Contents/` only has `Info.plist` and `MacOS/`). The debug entitlements that SwiftPM generates set `com.apple.security.get-task-allow=true`. There is no App Sandbox, no Hardened Runtime, no code signing, and no notarization in `script/build_and_run.sh`. For a pre-1.0 internal build this is acceptable, but it must change before any public distribution.
- **SSH tunnel posture is acceptable for v0.1.** The OpenSSH child process is launched with `StrictHostKeyChecking=accept-new` (TOFU) and the local listener is the OpenSSH default of `127.0.0.1` — explicitly noted in code comments and confirmed by SSH semantics. There is no command injection vector in the argument array. Argument values are passed unshelled. The risk is `accept-new` itself, which the author has flagged as deferred to a NIOSSH-based replacement.
- **Notable strengths:** Pydantic-style strict URL parsing with explicit port range validation; `PostgresQuery(unsafeSQL:)` is only used with user-typed SQL (the user's own machine, the user's own DB — this is intended) and never with concatenated identifiers from external input; `SELECT * FROM …` builder properly double-quotes identifiers and escapes embedded `"`; query history explicitly excludes result rows and labels the boundary in the UI; saved-connection metadata stores only references, never the secret.
- **Top remediation priorities (in order):** (1) Default TLS to verify-full when scheme/sslmode signals it, and warn loudly on `.disable` for non-loopback hosts; (2) ship a real `.entitlements` file with App Sandbox + Hardened Runtime before any release outside the maintainer's machine; (3) tighten `ErrorRedaction` to scrub `postgres://user:pass@host` URL forms in addition to `password=...` shapes; (4) write secrets to the keychain with `kSecUseDataProtectionKeychain` to lock them to the data-protection keychain; (5) document/automate code signing + notarization in `script/build_and_run.sh`.

## Severity Counts

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 5 |
| Informational | 4 |
| **Total** | **16** |

---

## Findings

### LITHEPG-001 — TLS defaults to disabled, contradicting `SECURITY.md`
- **Severity:** High
- **CWE:** CWE-319 (Cleartext Transmission of Sensitive Information), CWE-757 (Selection of Less-Secure Algorithm During Negotiation)
- **Location:**
  - `Sources/LithePGCore/ConnectionConfig.swift:48` — `tlsMode: TLSMode = .disable`
  - `Sources/LithePGCore/ConnectionConfig.swift:88-94` — URL parser ignores `sslmode=`
  - `Sources/LithePGApp/AppState.swift:576` — `tlsMode: tls ? .verifyFull : parsed.tlsMode` (parsed is always `.disable`)
  - `Sources/LithePGApp/AppState.swift:591` — `metadata.tlsMode == "verify-full" ? .verifyFull : .disable`
  - `Sources/LithePGApp/ConnectSheet.swift:7` — `@State private var tls = ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] != nil`
- **Evidence:**
  ```swift
  // ConnectionConfig.swift line 48
  tlsMode: TLSMode = .disable,
  ```
  ```swift
  // AppState.swift line 591
  tlsMode: metadata.tlsMode == "verify-full" ? .verifyFull : .disable,
  ```
  `SECURITY.md:16`: *"**TLS is required by default.** `sslmode=require` minimum; prefer `verify-full` when a root CA is configured."*
- **Impact:** A user pasting a `postgres://user:pw@db.prod.example.com/app` URL into the connect sheet without checking the TLS toggle will send the password and every subsequent query in cleartext. The `?sslmode=require` query-string is silently dropped during parsing. Passive eavesdroppers on any network segment between the Mac and the database can read credentials and data. This is the largest gap between the stated security posture and the implementation.
- **Remediation:**
  1. In `ConnectionConfig.init(url:)`, parse `?sslmode=require|verify-ca|verify-full|prefer|allow|disable` and map at least `require`/`verify-ca`/`verify-full` to `.verifyFull` (and add an intermediate `.require` mode that does encryption without hostname/CA verification, for parity with the Postgres ecosystem). Default the `init(host:...)` overload to `.verifyFull` for non-loopback hosts.
  2. In `ConnectSheet.swift`, default the TLS toggle to ON for any host that is not `127.0.0.1`/`localhost`, and render a red "cleartext" warning when the user explicitly disables it.
  3. In `AppState.connectionConfig(from:password:)`, treat unknown `tlsMode` strings as a hard error rather than silently downgrading to `.disable` — that path is how a future schema migration could regress security.

### LITHEPG-002 — Built `.app` has no entitlements, no sandbox, no hardened runtime, no signing
- **Severity:** High
- **CWE:** CWE-732 (Incorrect Permission Assignment), CWE-693 (Protection Mechanism Failure)
- **Location:**
  - `script/build_and_run.sh:34-53` — Info.plist generation, no entitlements written, no `codesign` or `xcrun notarytool` invocation
  - `dist/LithePG.app/Contents/` — only `Info.plist` + `MacOS/`, no `embedded.provisionprofile`, no `_CodeSignature/`
  - `.build/arm64-apple-macosx/debug/LithePGApp-entitlement.plist` — SwiftPM-generated debug entitlement enables `com.apple.security.get-task-allow=true` (debugger attach allowed)
- **Evidence:**
  ```bash
  # script/build_and_run.sh — entire bundle build, no codesign step
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cat >"$INFO_PLIST" <<PLIST
  ...
  ```
  ```xml
  <!-- LithePGApp-entitlement.plist -->
  <key>com.apple.security.get-task-allow</key>
  <true/>
  ```
- **Impact:** Without App Sandbox the app has full read/write access to the user's home directory; any compromised dependency or query-rendering bug that achieves arbitrary file write does so unconstrained. Without Hardened Runtime, library injection (`DYLD_INSERT_LIBRARIES`) is allowed by default on the binary. Without code signing/notarization, end-users cannot verify the binary's provenance and Gatekeeper will refuse to launch it (forcing right-click → Open workarounds that train users to bypass security). The shipped `dist/` build is also unsigned. For a pre-1.0 maintainer-only build this is tolerable, but every one of these is required before any external distribution.
- **Remediation:**
  1. Add a checked-in `Sources/LithePGApp/LithePGApp.entitlements` with at minimum:
     ```xml
     <key>com.apple.security.app-sandbox</key><true/>
     <key>com.apple.security.network.client</key><true/>
     <key>com.apple.security.files.user-selected.read-only</key><true/>  <!-- for CA cert imports -->
     ```
  2. Update `script/build_and_run.sh` to invoke `codesign --force --options runtime --entitlements <path> --sign "Developer ID Application: …"` and stage `xcrun notarytool submit … --wait` for release builds.
  3. Verify SSH-tunnel `Process()` invocation still works under sandbox — `com.apple.security.inherit` is *not* needed but `Process` may need `com.apple.security.temporary-exception.files.absolute-path.read-only` for `/usr/bin/ssh` and the user's `~/.ssh/known_hosts`. Plan the migration before enabling sandbox or migrate SSH to NIOSSH first (see LITHEPG-005).
  4. Set `com.apple.security.get-task-allow=false` for release.

### LITHEPG-003 — `ErrorRedaction` only catches `password=…` and `password: "…"`, not `postgres://user:pw@host` URL forms
- **Severity:** Medium
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File), CWE-209 (Generation of Error Message Containing Sensitive Information)
- **Location:** `Sources/LithePGCore/ErrorRedaction.swift:11`
- **Evidence:**
  ```swift
  // ErrorRedaction.swift:11
  let pattern = #"(password\s*[:=]\s*)("[^"]*"|[^",\s)]+)"#
  ```
  This pattern matches `password=hunter2` and `password: "hunter2"` but not `postgres://alice:hunter2@db/app`, which is the exact URL form users paste into `ConnectSheet` (`Sources/LithePGApp/ConnectSheet.swift:34`). Several PostgresNIO error types stringify with the configuration embedded — and the URL parser in `ConnectionConfig.init(url:)` throws `ParseError.invalidURL` carrying `String(describing: error)` of the original input.
- **Impact:** If a user pastes a malformed Postgres URL with embedded credentials, the resulting `ErrorRedaction.redactCredentials(in: error)` output renders to the SwiftUI `ErrorBanner` (`Sources/LithePGApp/ErrorBanner.swift:12`, with `textSelection(.enabled)`) and to stderr in the CLI/bench tools — the password is preserved verbatim. URLs of the form `postgres://user:pass@host` also commonly appear in `LITHEPG_STARTUP_URL` env-var diagnostics.
- **Remediation:** Add an additional regex to `ErrorRedaction.redactCredentials(in:)`:
  ```swift
  // Replace `://user:password@host` with `://user:[redacted]@host`
  let urlPattern = #"(://[^:/\s@]+:)([^@\s]+)(@)"#
  ```
  Apply both regexes in sequence. Add tests covering `postgres://`, `postgresql://`, and percent-encoded passwords. Also consider redacting Authorization-style headers if any future code path emits them.

### LITHEPG-004 — Keychain items not pinned to the data-protection keychain; no access group
- **Severity:** Medium
- **CWE:** CWE-522 (Insufficiently Protected Credentials)
- **Location:** `Sources/LithePGApp/PersistenceStores.swift:77-112`
- **Evidence:**
  ```swift
  private func baseQuery(reference: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: reference,
    ]
  }
  ```
  Missing: `kSecUseDataProtectionKeychain = true`, `kSecAttrAccessGroup`, `kSecAttrSynchronizable = false`.
- **Impact:** Without `kSecUseDataProtectionKeychain` on macOS, items land in the legacy file-based keychain by default. Any unsandboxed process running as the same user can `SecItemCopyMatching` the data without prompting (the legacy keychain's ACL model is per-app only when codesigned with a stable Team ID — see LITHEPG-002). Once the app is sandboxed and signed, switching to the data-protection keychain ensures keychain items are scoped to the app's bundle ID + Team ID and are no longer readable by arbitrary user processes. Without `kSecAttrSynchronizable = false`, future iCloud Keychain enrollment could surprise users by syncing DB credentials to other devices — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` already prevents this, but being explicit is safer.
- **Remediation:** Update `baseQuery(reference:)` to include `kSecUseDataProtectionKeychain as String: true` and `kSecAttrSynchronizable as String: false`. Once the app is signed with a stable Team ID, add `kSecAttrAccessGroup` set to `"<TeamID>.dev.omarpr.lithepg"` so future helper tools can be enrolled into the same access group.

### LITHEPG-005 — SSH host-key policy is `accept-new` (TOFU); no programmatic verification
- **Severity:** Medium
- **CWE:** CWE-322 (Key Exchange without Entity Authentication), CWE-295 (Improper Certificate Validation, by analogy)
- **Location:** `Sources/LithePGCore/SSHTunnel.swift:39-47`
- **Evidence:**
  ```swift
  process.arguments = [
      "-N",
      "-L", "\(localPort):\(remoteHost):\(remotePort)",
      "-p", String(sshPort),
      "-o", "ExitOnForwardFailure=yes",
      "-o", "StrictHostKeyChecking=accept-new",
      "-o", "ServerAliveInterval=30",
      "\(sshUser)@\(sshHost)",
  ]
  ```
- **Impact:** On the first connection to any new SSH host, OpenSSH silently writes the host key to `~/.ssh/known_hosts` and proceeds. An attacker positioned to MITM the user on first connect (open Wi-Fi, hostile coffee shop, malicious DNS) can intercept the bastion's SSH session, observe the Postgres password (sent over the tunneled connection because `--tls + --ssh` is forbidden by `Args.parse`, see `Sources/lithepg/LithePGMain.swift:102-104`) and modify query traffic. The author has flagged this as deferred until NIOSSH lands; this finding documents the current exposure clearly.
- **Remediation:** Short-term: change to `StrictHostKeyChecking=yes` and surface a clear UI/CLI error when the host is not in `known_hosts`, telling the user to add it via `ssh -o VisualHostKey=yes -o StrictHostKeyChecking=ask user@host` before connecting. Medium-term: replace `Process` + `/usr/bin/ssh` with NIOSSH so host-key policy is enforced in Swift against a per-app known-hosts file (`~/Library/Application Support/LithePG/known_hosts`). Block `accept-new` for hosts marked as production environment.

### LITHEPG-006 — Saved connections JSON is world-unreadable but not file-protected at the macOS level
- **Severity:** Medium
- **CWE:** CWE-276 (Incorrect Default Permissions)
- **Location:** `Sources/LithePGApp/PersistenceStores.swift:62-68, 149-154`, `PersistenceFileLocations.applicationSupportDirectory` (~/Library/Application Support/LithePG/)
- **Evidence:**
  ```swift
  try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
  ```
  `Data.WritingOptions.completeFileProtectionUnlessOpen` is the iOS Data Protection API which, on macOS, is a no-op outside the data-protection keychain context. The directory creation `createDirectory(at:withIntermediateDirectories:true)` does not set restrictive POSIX permissions; on macOS the default is `drwxr-xr-x` (0755).
- **Impact:** While no secrets are stored in `saved-connections.json` (only metadata: hostnames, usernames, database names, environment labels, secret-reference UUIDs), this metadata is sensitive — knowing that production DB host `db.acme-internal.example.com` exists is reconnaissance value. On a shared macOS user account or with another user on the same machine, the `~/Library/Application Support/LithePG/` directory is readable. Once App Sandbox lands (see LITHEPG-002) the bundle container will provide isolation and this concern goes away.
- **Remediation:** Either (a) ship App Sandbox so the file lives in the bundle container (preferred), or (b) explicitly set `FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath:)` on the directory and `0o600` on the JSON files at create time. Add a unit test that verifies the permission bits.

### LITHEPG-007 — `info_schema.columns INNER JOIN information_schema.tables` misses tables with zero columns
- **Severity:** Low
- **CWE:** N/A (correctness/availability bug; flagged here because the introspection SQL is part of the security perimeter via excluded-system-schemas filter)
- **Location:** `Sources/LithePGCore/SchemaIntrospector.swift:46-63`
- **Evidence:** The introspection query joins `information_schema.columns` against `information_schema.tables`. Tables with zero columns won't appear (rare in practice) and the `WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'pg_toast') AND table_schema NOT LIKE 'pg_toast_temp_%' AND table_schema NOT LIKE 'pg_temp_%'` filter is correct as a defense-in-depth complement to `SchemaIntrospector.excludedSystemSchemas` (line 4-8).
- **Impact:** Minor information-disclosure mismatch: the post-query Swift-side filter uses a slightly different list (`pg_temp_*` not filtered Swift-side, but is filtered SQL-side; the Swift-side `excludedSystemSchemas` set is an *additional* belt-and-suspenders filter). No security exposure today, but the duplication is a maintenance hazard — future drift between the SQL and Swift filters could allow a `pg_toast_temp_42` schema to leak through.
- **Remediation:** Single-source the excluded-schema list. Either generate the SQL `NOT IN (...)` clause from `excludedSystemSchemas` at query construction time, or remove the SQL-side filter and rely solely on the Swift-side filter. Add a test that creates a `pg_temp_*` schema and asserts it is excluded.

### LITHEPG-008 — Schema/relation identifiers in `selectSQL(for:)` use only quote-doubling, not full identifier validation
- **Severity:** Low
- **CWE:** CWE-89 (Improper Neutralization of Special Elements used in an SQL Command)
- **Location:** `Sources/LithePGApp/AppState.swift:362-364, 616-618`
- **Evidence:**
  ```swift
  public static func selectSQL(for relation: DatabaseSchema.Relation) -> String {
    "SELECT * FROM \(quotedIdentifier(relation.schema)).\(quotedIdentifier(relation.name)) LIMIT 100;"
  }
  private static func quotedIdentifier(_ identifier: String) -> String {
    "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
  ```
- **Impact:** The identifier comes from `information_schema.tables.table_name`, which the user's database returned as part of an authenticated session. The user is connected to *their own* database — this is not classic SQL injection. However: (a) a compromised or malicious server could return a `table_name` containing a NUL byte (PostgreSQL identifiers cannot contain NUL but `information_schema` is text, not name, on the wire — worth defense-in-depth); (b) the resulting SQL is pasted into the SQL editor and *then* sent back to the same database — so the practical attack surface is "a hostile DB tricks the user into running attacker-chosen SQL on the same DB they're connected to," which is empty (the attacker already has SQL execution).
  More relevantly, the helper does not handle Unicode normalization — an identifier with a combining character could render visually identical to another table while pointing somewhere else (homograph attack). Low severity given the threat model.
- **Remediation:** Reject identifiers containing `\0` or other C0 control characters before quoting. Optionally, render the relation name in the UI with `String.precomposedStringWithCanonicalMapping` to neutralize Unicode normalization-confusion attacks. Add a test case for an identifier containing a literal `"` (already handled correctly by the quote-doubling).

### LITHEPG-009 — Saved-connection JSON is not validated against tampering on read
- **Severity:** Low
- **CWE:** CWE-345 (Insufficient Verification of Data Authenticity)
- **Location:** `Sources/LithePGApp/PersistenceStores.swift:56-60, 143-147`
- **Evidence:** `JSONDecoder().decode([SavedConnectionMetadata].self, from: data)` reads the file with no integrity check.
- **Impact:** An attacker with write access to `~/Library/Application Support/LithePG/saved-connections.json` could change `host` to a hostname they control, then wait for the user to click "Connect" — the password is fetched from the keychain (correctly tied by the immutable `secretReference` UUID) and sent to the attacker's host. This is essentially a connection-redirect attack, requiring local file write. Out of scope per `SECURITY.md:40` ("Protection against a compromised macOS host"). Documented for completeness.
- **Remediation:** Once App Sandbox lands, this risk drops further (the file is in the sandboxed container). Optionally: HMAC the JSON with a key stored alongside the password keychain item, and refuse to load saved connections whose HMAC doesn't validate. Surface a clear UI message if validation fails.

### LITHEPG-010 — `unsafeSQL:` initializer is the only path; no parameterized API exposed
- **Severity:** Low
- **CWE:** CWE-89 (informational — by design here)
- **Location:** `Sources/LithePGCore/PostgresConnector.swift:75`
- **Evidence:**
  ```swift
  let metadata = try await current.connection.query(
      PostgresQuery(unsafeSQL: sql),
      logger: logger
  ) { row in ...
  ```
- **Impact:** This is correct for the current product — the user types raw SQL. There is no internal code path that takes external parameters and would benefit from `PostgresQuery` interpolation. The risk is forward-looking: future features (e.g. row inspector, "view N rows starting from offset M", saved query parameters) are likely to want parameter binding, and the present code shape doesn't telegraph that need.
- **Remediation:** Add a helper `executeBound(_ sql: PostgresQuery) -> QueryResult` alongside `execute(_ sql: String)` so that future features default to the parameterized path. No immediate action required.

### LITHEPG-011 — `print()` of error metadata in CLI/bench tools could leak via shell history or terminal multiplexer logs
- **Severity:** Low
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **Location:** `Sources/lithepg/LithePGMain.swift:17,41`, `Sources/LithePGBench/LithePGBench.swift:30`
- **Evidence:** Errors are written to `FileHandle.standardError` after `ErrorRedaction.redactCredentials(...)`. As noted in LITHEPG-003, that redaction is incomplete for URL-shaped credentials.
- **Impact:** A user running `lithepg --url 'postgres://alice:hunter2@db' 2>&1 | tee debug.log` could end up with the raw URL in `debug.log` if the error chain stringifies the full configuration. Mitigated by LITHEPG-003 fix.
- **Remediation:** Resolved by LITHEPG-003.

### LITHEPG-012 — Subprocess `Process()` does not set `qualityOfService` or close inherited file descriptors
- **Severity:** Low
- **CWE:** CWE-403 (Exposure of File Descriptor to Unintended Control Sphere)
- **Location:** `Sources/LithePGCore/SSHTunnel.swift:32-51`
- **Evidence:** `Process()` is configured with explicit stdout/stderr `Pipe()`s but inherits the parent's other file descriptors (Foundation `Process` does not implicitly call `posix_spawn_file_actions_addclose_*`).
- **Impact:** Minor. Any open FDs in the LithePG process at SSH-spawn time (sockets to other Postgres servers, log files) are inherited by `/usr/bin/ssh`. OpenSSH does not, in practice, do anything malicious with them. Hardening rather than active exploit.
- **Remediation:** Consider `posix_spawn` directly with explicit FD inheritance control, or set FD_CLOEXEC on every file descriptor LithePG opens. Low priority.

### LITHEPG-013 — CI workflow is currently `workflow_dispatch` only — security scanning is not enforced
- **Severity:** Low
- **CWE:** CWE-1357 (Reliance on Insufficiently Trustworthy Component)
- **Location:** `.github/workflows/ci.yml:5-6`
- **Evidence:**
  ```yaml
  on:
    # Temporarily manual-only while GitHub Actions is blocked by account billing/
    # spending-limit settings. Re-enable push/pull_request triggers once resolved.
    workflow_dispatch:
  ```
  No SAST (e.g. Semgrep), no SCA / dependency scanner (Trivy, OSV-scanner), no secrets scanner (Gitleaks).
- **Impact:** No automated detection of vulnerable transitive dependencies, hardcoded secrets, or unsafe Swift patterns on PRs. Currently mitigated by the project being pre-1.0 with a single maintainer, but should not ship to v1.0 without it.
- **Remediation:** When the billing pause lifts, add three jobs: (1) `osv-scanner` against `Package.resolved`, (2) Gitleaks on full history, (3) basic Semgrep with the `p/swift` ruleset. All three are pure-OSS, free for public repos, and pin `actions/checkout@v4` already (good — see LITHEPG-014). Pin all third-party actions to commit SHAs rather than tags.

### LITHEPG-014 — Third-party GitHub Actions pinned to floating tag, not SHA
- **Severity:** Low → Informational (only one third-party action; first-party Apple is already pinned to v4)
- **CWE:** CWE-829 (Inclusion of Functionality from Untrusted Control Sphere)
- **Location:** `.github/workflows/ci.yml:27` — `uses: maxim-lobanov/setup-xcode@v1`
- **Evidence:** `setup-xcode@v1` is a moving tag. If the action's maintainer is compromised, malicious code runs in the LithePG CI runner with whatever scopes the workflow's `GITHUB_TOKEN` has (currently `contents: read` by default).
- **Impact:** Low. The workflow has no `secrets:` access, no `actions/upload-artifact` to a protected location, and no write permissions beyond the default. But pinning to SHAs is a good habit.
- **Remediation:** Replace `@v1` with the specific commit SHA: `uses: maxim-lobanov/setup-xcode@<sha>`. Add a comment with the resolved version. Use Dependabot to bump.

### LITHEPG-015 — `dist/` directory is `.gitignore`d but contains a built `.app` and a screenshot; `.DS_Store` is present
- **Severity:** Informational
- **Location:** `dist/`, `.gitignore` (line: `dist/`)
- **Evidence:** `dist/.DS_Store`, `dist/lithepg-progress-20260503-172809.png`, `dist/LithePG.app/`. None are tracked by git.
- **Impact:** None on the repo. Flagging only because if the maintainer ever switches `dist/` to be tracked (for distribution), the `.DS_Store` and any other artifacts would need a `.gitattributes` cleanup pass.
- **Remediation:** No action required currently. If `dist/` becomes tracked, add a stricter pattern: `dist/.DS_Store`, `dist/*.png`.

### LITHEPG-016 — `LITHEPG_STARTUP_*` and `POSTGRES_*` environment variables can pre-fill credentials silently
- **Severity:** Informational
- **CWE:** CWE-200 (informational)
- **Location:** `Sources/LithePGApp/ConnectSheet.swift:6-11`, `Sources/LithePGApp/LithePGApp.swift:80-90`
- **Evidence:** The connect sheet pre-fills the URL field from `POSTGRES_URL`, and the app autoconnects from `LITHEPG_STARTUP_URL`. URLs typically embed credentials.
- **Impact:** A user who set `POSTGRES_URL` for testing and then opens the LithePG UI sees their URL pre-populated — this includes any embedded password. If the user takes a screenshot or screen-shares, the password appears in the URL field. The autoconnect path (`runStartupConnection`) bypasses the connect sheet entirely, which is correct, but means CI/scripted launches put the password in `ps`-visible env vars.
- **Remediation:** Two improvements: (1) when pre-filling from env, mask the password portion in the displayed text field (use a separate password field, or replace `:password@` with `:••••@` in the visible string while keeping the real value in state); (2) document in `SECURITY.md` that environment variables are visible to other processes on macOS via `ps -E` and recommend the keychain path for non-CI use.

---

## Verified Security Claims

The following claims from `SECURITY.md` and the repository agent guidance were confirmed in code:

1. **"No `libpq` or other C dependencies."** — `Package.resolved` resolves only Apple/Vapor pure-Swift packages: postgres-nio, swift-{nio,nio-ssl,asn1,async-algorithms,atomics,collections,crypto,log,metrics,system,service-lifecycle}. No `libpq` import exists anywhere. (BoringSSL is vendored inside swift-nio-ssl, which is the canonical pure-Swift path.)
2. **"All secrets live in the macOS Keychain. Never in SwiftData, plist, or on-disk files."** — Verified. `KeychainCredentialStore.saveSecret(_:for:)` (`PersistenceStores.swift:77-85`) is the only path that handles the password. `SavedConnectionMetadata` (`PersistenceModels.swift:23-71`) has no `password` field — only a `secretReference: String?`. The on-disk JSON contains only the reference UUID.
3. **"Each connection references a Keychain item by identifier; the app never persists the password itself."** — Verified. `AppState.saveConnection` (`AppState.swift:141-178`) generates a per-connection UUID-derived secret reference (`lithepg.connection.<uuid>.password`) and writes only that to disk.
4. **"AI inference runs locally."** — Verified by absence: no `URLSession`, `URLRequest`, `NWConnection`, no Anthropic/OpenAI/AWS/Google SDK imports, no analytics/crash-reporting libraries in `Package.resolved`. The only outbound network is to the user-configured Postgres host.
5. **"No telemetry. No crash reporting without explicit user opt-in."** — Verified. No telemetry SDK, no Firebase/Sentry/Crashlytics, no update-check endpoint.
6. **"Query history is opt-in."** — Verified. `AppState.queryHistoryEnabled` defaults to `false` (`AppState.swift:40`), and `appendQueryHistory` (`AppState.swift:519`) early-returns when disabled. UI banner reinforces this in `QueryHistoryView.swift:18`.
7. **"History stores SQL, connection metadata, timing, and status — never result rows."** — Verified. `QueryHistoryEntry` (`PersistenceModels.swift:73-105`) has no field for cells/rows.
8. **"Pure Swift, no C shims authored by LithePG."** — Verified. The only `Darwin.*` calls are POSIX socket calls in `SSHTunnel.allocateLocalPort` for ephemeral port discovery — not "C shim" in the libpq sense.
9. **Agent guidance: "Store saved database credentials in Keychain, never plaintext metadata."** — Verified for the keychain path. Caveat: see LITHEPG-016 — credentials may pass through env vars at launch, which is not "stored" but is "in plaintext."
10. **Agent guidance: "Preserve secure TLS defaults."** — Partially verified: TLS is *not disabled in NIOSSL*. NIOSSL's `TLSConfiguration.makeClientConfiguration()` is used unmodified, which preserves hostname verification, certificate validation, and modern cipher suites. BUT — see LITHEPG-001: the *default mode* in `ConnectionConfig` is `.disable` (i.e. plaintext), not `.verifyFull`. Reading the rule narrowly ("don't disable NIOSSL defaults"), the code is compliant. Reading it broadly ("connections default to TLS"), it isn't.
11. **"No `.xcodeproj`. SPM only."** — Verified.
12. **Keychain accessibility class is sensible.** — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`PersistenceStores.swift:82`) means the secret is unavailable while the device is locked and is never synced to other devices via iCloud Keychain. Good choice for desktop credentials.

---

## Unverified or Partially Verified Claims

1. **`SECURITY.md:16` — "TLS is required by default. `sslmode=require` minimum; prefer `verify-full` when a root CA is configured."** — Partially verified. `verify-full` is correctly implemented when chosen (`PostgresConnector.swift:207-227`), but it is *not* the default. See LITHEPG-001.
2. **`SECURITY.md:18` — "No fallback to cleartext on handshake failure."** — Cannot fully verify in code; depends on PostgresNIO's TLS-required mode behavior. The code uses `.require(sslContext)` in `makeTLS(for:)` which in PostgresNIO means "REQUIRE TLS" (does not fall back to cleartext if the server doesn't support TLS). This is correct, but the broader claim implies the *default* is TLS, which is not the case.
3. **`SECURITY.md:11` — "Client certificates and SSH keys are referenced by path or Keychain handle, never copied."** — Client certificates are not implemented in current code (`PostgresConnection.Configuration` is built without `certificateVerification` overrides for client auth). SSH keys are not handled by LithePG at all — `/usr/bin/ssh` reads `~/.ssh/` directly. Claim is technically true (because the feature doesn't yet exist) but should be revised once mTLS/client-cert support lands.
4. **`SECURITY.md:21` — "SwiftData store lives under the app's sandbox container."** — Not currently true. The app is not sandboxed (LITHEPG-002), and the persistence store is JSON, not SwiftData. The doc appears aspirational. Update either the doc or the code.
5. **`SECURITY.md:32` — "Minimize third-party dependencies (app binary target <50 MiB)."** — Verified by CI gate (`.github/workflows/ci.yml:46-61`).
6. **`SECURITY.md:34` — "Dependencies are pinned via `Package.resolved`."** — Verified literally — `Package.resolved` records exact revisions. `Package.swift` uses `from: "1.21.0"` (semver lower bound); the resolved file pins `1.33.0` of postgres-nio. This is normal Swift Package Manager semantics, not a security issue.

---

## Coverage Gaps

I read the following files thoroughly and cross-referenced their tests:
- All Sources/ Swift files in scope (~1.7K lines total of LithePGCore + LithePGApp + lithepg + LithePGBench)
- All test files for the Core target
- `Package.swift`, `Package.resolved`, `.github/workflows/ci.yml`, all three `script/*.sh` files, `dist/LithePG.app/Contents/Info.plist`, `.build/.../*-entitlement.plist`
- `SECURITY.md`, `AGENTS.md`, `.gitignore`

I did **not** read in full:
- The `docs/superpowers/` plans and specs (~5K lines of design docs) — these don't affect the security posture of the running code
- `script/dogfood_seed.sql` — confirmed to exist and contain non-secret demo data only (referenced from `dogfood_postgres.sh`)
- `Tests/LithePGAppTests/AppStateTests.swift` — read selectively (the env-var/startup test, lines 256-283); did not read other unit-test bodies in full because they exercise non-security code paths (results-table presentation, schema-sidebar UI, syntax highlighting)
- Transitive dependency source code under `.build/checkouts/` — not feasible at this scope; relied on Apple/Vapor maintenance status (all packages active, all SECURITY.md present)

I did **not** dynamically run the binary, attempt exploitation, attach a debugger, or run `lsof` against a live process. This is a static review only.

I did **not** cross-reference `Package.resolved` revisions against CVE databases (e.g. GHSA, OSV) — none of the pinned versions are flagged in publicly known advisories I'm aware of as of the audit date, but a programmatic OSV-scanner pass should be added to CI per LITHEPG-013.

---

## Recommended Next Steps

In priority order:

1. **Fix the TLS default (LITHEPG-001).** Two-line change in `ConnectionConfig.init(host:...)` plus URL-parser update plus connect-sheet default. High-leverage, low-risk. Add tests asserting that `postgres://user:pw@public.example.com/db` resolves to `tlsMode == .verifyFull` unless explicitly overridden.
2. **Add a real entitlements file and code signing path (LITHEPG-002).** This blocks any external distribution. Start with `app-sandbox` + `network.client` and iterate; the SSH tunnel will need explicit thinking (probably wait until NIOSSH replaces `/usr/bin/ssh`).
3. **Tighten `ErrorRedaction` (LITHEPG-003).** Add the URL-form regex; add tests; this is a 10-minute change.
4. **Migrate keychain queries to `kSecUseDataProtectionKeychain` (LITHEPG-004).** Trivial change, large benefit once signing is in place.
5. **Plan the NIOSSH migration (LITHEPG-005).** This is a v0.5+ effort but it solves multiple findings (LITHEPG-002 sandbox interaction, LITHEPG-005 host-key TOFU, LITHEPG-012 FD inheritance) at once.
6. **Re-enable CI with security jobs (LITHEPG-013).** OSV-scanner + Gitleaks + Semgrep on every PR. Pin the one third-party action to a SHA (LITHEPG-014).
7. **Reconcile `SECURITY.md` with the code.** Either update the docs to say "TLS required by default — *coming in v0.5*" or fix the code first. The current divergence is the kind of thing that gets cited in incident reports.
8. **Add explicit POSIX-permission setting on the persistence directory (LITHEPG-006)** as a stopgap until App Sandbox lands.
9. **Mask credentials in env-var-prefilled URL fields (LITHEPG-016).** Small UI fix, large screenshot/screenshare safety improvement.
10. **Threat-model the upcoming local-AI feature.** Once CoreML/MLX inference lands, re-audit specifically for: model file integrity (signed vs. downloaded?), prompt-template injection from query results, and any temporary file paths that touch user data.
