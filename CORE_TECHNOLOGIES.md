# Core Technologies

This document lists the technologies LithePG is built on, what each one was chosen for and why the choice matters. The deeper rationale and measurements live in [`docs/TECH_STACK.md`](docs/TECH_STACK.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Language and Runtime

### Swift 6.2 with strict concurrency
All app code is Swift with strict concurrency checking on. Data races are caught at compile time instead of in production. Shared mutable state lives in actors such as `PostgresConnector` and `KeychainCredentialStore`, and the UI layer is isolated to the main actor. This matters because a database client holds live connections, credentials and background queries at the same time, which is exactly where race bugs hide.

### async/await everywhere
Connection, query, schema introspection and AI drafting APIs are all async functions. No completion handlers, no callback pyramids. The result is code a reviewer can read top to bottom, which keeps the security sensitive paths auditable.

## User Interface

### SwiftUI, Mac first
The entire UI is SwiftUI. There is no Electron, no web view and no cross platform abstraction layer. A native app starts faster, uses less memory and respects macOS conventions such as appearance, keyboard shortcuts and accessibility for free. The measured connected cold start is under half a second and the shipped binary is around 12 MiB stripped, which no embedded browser runtime can match.

### One deliberate AppKit exception
The SQL editor uses an AppKit `NSTextView` behind `NSViewRepresentable` because the native text stack outperforms every SwiftUI text editor for large documents and precise syntax highlighting. This is the single documented bridge and it adds no third party editor dependency.

## Database Engine

### PostgresNIO instead of libpq
The wire protocol is spoken by [PostgresNIO](https://github.com/vapor/postgres-nio), a pure Swift driver from the Vapor project. Avoiding `libpq` means no app authored C shims, a leaner binary and a driver that exposes idiomatic async Swift APIs with typed rows. The accepted C boundary is BoringSSL, which arrives transitively through `swift-nio-ssl` and is treated as a vetted security dependency rather than app code.

### TLS that fails closed
Remote hosts default to full certificate verification and loopback hosts default to plain TCP. A pasted URL with `sslmode=require` is upgraded to verified TLS rather than silently downgraded to unverified encryption. Internal certificate authorities are supported through an explicit pinned root, which replaces the trust store instead of quietly widening it. Connectivity is verified end to end against live Neon endpoints, both direct and pooled, including the current host shape with a proxy cell segment and `channel_binding` parameters.

### Neon aware connection handling
Pasting a Neon connection string is recognized by `NeonConnectionProfile`, which surfaces the endpoint, database, role and pooled or direct mode in the connect sheet and suggests a connection name. Detection is read only and never stores or echoes the password.

### SSH tunnels through the system client
SSH tunneling shells out to the macOS bundled `ssh` binary rather than embedding an SSH library. Users keep their existing `~/.ssh` configuration, keys and known hosts. This is documented tech debt with a clear upgrade path if a native library earns its place.

## Credentials and Persistence

### macOS Keychain for secrets
Passwords never touch disk in plaintext. They are stored in the data protection Keychain, scoped to this device and readable only after first unlock. Saved connection metadata is plain JSON under Application Support with restrictive permissions, and an HMAC integrity key in the Keychain signs that metadata so tampering is detected on load.

### Boring, testable persistence
Saved connections and opt in query history are JSON files behind small store protocols. Tests inject in memory stores. No ORM and no database for the app state itself, because a few kilobytes of metadata do not justify one. SwiftData remains a possible future migration only if it earns its complexity.

## Local First AI

### Deterministic drafting by default
Ask in English drafting runs entirely on device. The default engine is deterministic Swift that uses the indexed schema and foreign key metadata to draft single table queries and two table joins. Drafted SQL is inserted into the editor for human review and is never executed automatically.

### CoreML for optional models
The optional model adapter is built on CoreML because it ships with the macOS SDK, adds zero package dependencies and keeps model artifacts external and user provided. Nothing is bundled and nothing is downloaded. MLX stays on the roadmap for when a concrete model justifies the runtime cost. Privacy receipts are test covered: prompts contain only the user request and schema metadata, never credentials, connection URLs or result rows.

## Build and Distribution

### Swift Package Manager only
There is no `.xcodeproj`. The whole app builds with `swift build` and tests run with `swift test`, so any contributor with Xcode command line tools can build from a clean checkout. Packaging scripts assemble the app bundle, verify its structure, icon and permissions and enforce the size budget.

### Hard budgets, measured continuously
The binary has a 50 MiB hard cap with a 30 MiB stretch goal, currently about 21.6 MiB raw and 12 MiB stripped. Startup, query overhead and size are measured by `LithePGBench` and recorded in dogfood receipts before every milestone. Budgets are enforced by scripts, not by good intentions.

## Testing

### Swift Testing with gated live suites
Unit tests cover every file in `LithePGCore` and the headless presentation seams of the app layer, 185 tests across 26 suites. Live integration tests are gated behind `POSTGRES_TEST_URL` and run against a seeded local Postgres in Docker or against a real Neon database. Keychain round trips are gated behind `LITHEPG_KEYCHAIN_TESTS`. Secret hygiene is enforced with history wide scanning before any public release.
