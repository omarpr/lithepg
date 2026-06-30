# Neon Connection Polish Design

**Status:** Approved for implementation planning

## Goal

Make Neon Console connection strings feel first-class in LithePG's existing connect flow without adding Neon API tokens, account linking, browser automation, or external network calls.

## Scope

This is a paste-from-Neon polish slice:

- Detect Neon-hosted Postgres connection strings when users paste them into the existing `ConnectSheet` URL mode.
- Keep TLS verification enabled for Neon hosts.
- Show a compact provider hint so users know LithePG recognized the connection string.
- Suggest a useful saved-connection name when "Save this connection" is enabled and the user has not already typed a custom name.

Out of scope:

- Listing Neon projects, branches, roles, or databases through the Neon API.
- Storing Neon API tokens or Console session information.
- Opening Neon Console URLs from saved connections.
- Persisting provider-specific metadata in `SavedConnectionMetadata`.
- Changing the actual Postgres connection protocol beyond the existing URL/TLS handling.

## Current Context

The app already accepts pasted Postgres URLs in `ConnectSheet`, parses them through `ConnectionConfig(url:)`, defaults non-loopback hosts to `verifyFull`, stores saved connection metadata in local JSON, and stores passwords in Keychain. This feature should reuse those paths.

Neon connection strings copied from Neon Console are standard Postgres URLs whose hosts are under Neon-owned domains, commonly `*.neon.tech`, with compute endpoint identifiers that begin with `ep-`. Pooled hosts may include `-pooler`. Neon requires SSL/TLS for client connections, so LithePG should preserve verified TLS for these URLs.

## Design

### NeonConnectionProfile

Add a small pure helper in `Sources/LithePGCore/` so URL/provider detection is reusable and testable without SwiftUI:

```swift
struct NeonConnectionProfile: Equatable {
  let host: String
  let endpointID: String?
  let database: String
  let username: String
  let isPooled: Bool
  let suggestedName: String

  static func detect(url: String) -> NeonConnectionProfile?
}
```

Detection rules:

- Parse with `ConnectionConfig(url:)` so malformed URLs and unsupported schemes follow existing behavior.
- Match only Neon hosts under `neon.tech` or a subdomain ending in `.neon.tech`.
- Treat hosts containing `-pooler.` or an endpoint label ending in `-pooler` as pooled.
- Extract an endpoint ID from the first host label when it starts with `ep-`; if extraction fails, detection can still succeed from the Neon domain.
- Use `Neon - <database>` as the default suggested name when a database is available.
- Use `Neon - <endpointID>` only if the database name is empty, which should be rare because `ConnectionConfig` requires a database.

The helper must not retain or expose passwords. Tests should assert that profile output contains host, database, username, endpoint/pooler hints, and suggested name, but no password.

### ConnectSheet Integration

In URL mode:

- Recompute the Neon profile whenever the URL field changes.
- If a profile exists, show a compact hint below the URL field:
  - Title: `Neon connection detected`
  - Detail: database, username, and whether the URL appears pooled.
- Keep the existing TLS toggle on for Neon URLs. If a pasted Neon URL includes `sslmode=disable`, the app may still reflect the parsed cleartext mode as today, but the UI should surface the existing cleartext warning for remote hosts.
- When "Save this connection" is enabled and the connection-name field is empty or still contains the previous auto-suggested value, set it to `profile.suggestedName`.
- If the user edits the connection name manually, stop overwriting it.

This avoids new persistence fields and avoids changing existing saved-connection integrity signatures.

## Data Flow

1. User copies a Neon Postgres connection string from Neon Console.
2. User pastes it into LithePG's URL connection field.
3. `ConnectSheet` calls `NeonConnectionProfile.detect(url:)`.
4. If detection succeeds, UI shows the Neon hint and suggests a save name.
5. On connect or save, the existing `AppState.connect(url:...)` and `AppState.saveConnection(url:...)` paths run unchanged.

## Error Handling

- Malformed URLs show the existing parse/connect errors.
- Non-Neon Postgres URLs receive no provider hint.
- Unknown Neon hostname variants should fail open as generic Postgres rather than blocking connection attempts.
- Detection must never print, log, render, or persist passwords.

## Testing

Add focused Swift tests:

- Neon host detection for standard compute endpoint URLs.
- Pooled host detection for `-pooler` URLs.
- Non-Neon Postgres URLs return `nil`.
- Malformed URLs return `nil` rather than throwing through the UI helper.
- Suggested names use the database name.
- Profile output does not include the password.
- Connect sheet presentation helper, if extracted, applies the auto-name only while the name is user-unmodified.

No live Neon database, Neon account, Neon API token, or network access is required for tests.

## Documentation

Update README or a short connect-flow note only if the UI copy is not self-explanatory. The feature should be obvious in-app when a Neon URL is pasted.
