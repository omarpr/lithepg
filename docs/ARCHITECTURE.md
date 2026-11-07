# ARCHITECTURE.md

High-level module boundaries and data flow for LithePG. Implementation details live in the code; this file explains why the boundaries exist.

## Layers

```
┌─────────────────────────────────────────────┐
│  App Layer (SwiftUI + AppState)             │
│  - Views, navigation, query workflow        │
└───────────────┬─────────────────────────────┘
                │  (async/await, @Observable)
┌───────────────▼─────────────────────────────┐
│  Core Services                              │
│  - PostgresConnector                        │
│  - SchemaIntrospector                       │
│  - AIQueryService implementations           │
│  - ResultExporter                           │
└───────┬───────────────────┬─────────────────┘
        │                   │
┌───────▼──────┐   ┌────────▼─────────────────┐
│  Driver      │   │  Persistence             │
│  PostgresNIO │   │  Local JSON metadata     │
│  (no libpq)  │   │  Keychain (secrets)      │
└──────────────┘   └──────────────────────────┘
        │
┌───────▼──────────────────────────────────────┐
│  Inference (local)                           │
│  Deterministic draft service; optional       │
│  user-provided CoreML artifacts              │
└──────────────────────────────────────────────┘
```

## Layer Responsibilities

### App Layer
- SwiftUI views plus `AppState` for the left connection navigator, schema, query, saved-connection, query-history, appearance and Ask-in-English workflow state.
- `NeonCLIScanner` discovers a user-installed Homebrew CLI, requests machine-readable projects/branches/databases only after a button press and returns connection URLs directly to the credential-separating persistence flow.
- `PostgresConnectionTester` opens a temporary connector, runs `SELECT 1` and shuts it down without changing workspace connection or persistence state.
- UI code talks to the driver through `PostgresConnector` and to credentials through persistence protocols; views do not touch Keychain APIs directly.
- Presentation helpers stay headless-testable where practical, for example results pagination/copy/export formatting.

### Core Services
- `PostgresConnector` owns the live Postgres connection lifecycle, query execution, TLS configuration, SSH tunnel handoff and result materialization.
- `SchemaIntrospector`, `SchemaIndex` and the production `OnDeviceAIQueryService` provide local schema awareness and Apple on-device SQL drafting.
- `ResultExporter` serializes already-fetched results to CSV, JSON or Markdown without network calls or SQL execution.
- `ResultEditing` writes an edited result cell back to its table. It traces result columns to their source table and attribute with `PostgresConnector.describeResultColumns` (the original query wrapped as `SELECT * FROM (...) LIMIT 0`, so no rows are produced), reads the primary key and column types from the catalog, and builds one parameterized `UPDATE` that matches the full primary key and, where the displayed value round-trips exactly, the original value. Computed columns, views, generated and identity columns, tables without a primary key and results missing the key stay read-only.
- `SQLStatementSplitter` and `SQLCompletionIndex` give the editor statement-at-caret execution and schema-aware autocomplete without any server round trip.
- All public I/O APIs are `async`; shared mutable services are `actor`s where needed.

### Driver
- `PostgresNIO` is the connection path. LithePG does not link `libpq` and does not carry app-authored C shims.
- Exposes typed `QueryResult` values to the app and caps materialized rows at the UI safety limit.
- Owns TLS configuration and the effective host/port after optional SSH tunnel resolution.
- Always requests `client_encoding=UTF8`. PostgresNIO (through 1.33.2) never completes a query sent on a channel the server already closed, so the connector checks for a closed channel before each query and fails pending work when the channel closes; `AppState` watches the close future to report a lost connection while idle.

### Persistence
- Saved connection metadata and opt-in query history are local JSON files under Application Support, written with restrictive POSIX permissions and file-protection options.
- Passwords and saved-connection integrity keys live in the macOS Keychain. See `SECURITY.md`.
- Appearance preference is stored in `UserDefaults`.

### Inference
- Default SQL drafting exclusively uses Apple's lightweight `SystemLanguageModel.default` on supported macOS 26 Macs, with guided output, bounded schema retrieval and a read-only SQL safety gate. It makes no network AI calls.
- Ask in English is disabled with recovery guidance when Apple's model is unavailable; no alternate drafter is substituted. The deterministic service remains test/reference code only. A separate CoreML artifact-validation scaffold remains disabled by default for user-provided experiments.
- Schema awareness uses local metadata/indexing; vector storage remains a future optimization.

## Key Invariants
- **No credentials in JSON, UserDefaults, screenshots, logs or query history.** Ever.
- **No network calls from the AI layer.** Inference is local-only.
- **UI never imports `PostgresNIO` directly.** Services mediate.
- **Services never import SwiftUI.** Keeps them testable and reusable.
- **The app never writes data the user did not confirm.** Result edits show the exact `UPDATE` and run only after an explicit confirmation; AI drafts are never run automatically.

## Concurrency Model
- `async/await` end-to-end.
- Long-running queries run on the driver's event loop; results bridge to the main actor for UI updates.
- Cancellation propagates from UI task cancellation through the service layer to the driver.

## Testing Strategy
- **Unit tests:** Core models/services, app-state workflow, persistence stores, presentation helpers, exporter behavior and redaction.
- **Integration tests:** Real PostgreSQL/TLS/SSH/model-artifact paths are env-gated and auto-skip when prerequisites are absent.
- **UI tests:** Minimal smoke coverage; most behavior is covered through view model and presentation-helper tests.
