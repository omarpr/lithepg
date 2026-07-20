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
- `SchemaIntrospector`, `SchemaIndex` and `AIQueryService` implementations provide local schema awareness and deterministic/local SQL drafting.
- `ResultExporter` serializes already-fetched results to CSV, JSON or Markdown without network calls or SQL execution.
- All public I/O APIs are `async`; shared mutable services are `actor`s where needed.

### Driver
- `PostgresNIO` is the connection path. LithePG does not link `libpq` and does not carry app-authored C shims.
- Exposes typed `QueryResult` values to the app and caps materialized rows at the UI safety limit.
- Owns TLS configuration and the effective host/port after optional SSH tunnel resolution.

### Persistence
- Saved connection metadata and opt-in query history are local JSON files under Application Support, written with restrictive POSIX permissions and file-protection options.
- Passwords and saved-connection integrity keys live in the macOS Keychain. See `SECURITY.md`.
- Appearance preference is stored in `UserDefaults`.

### Inference
- Default SQL drafting prefers Apple's on-device Foundation Models system model on supported macOS 26 Macs, with guided output, bounded schema retrieval and a read-only SQL safety gate. It makes no network AI calls.
- The deterministic schema-aware drafter is the fallback when the system model is unavailable or generation fails. A separate CoreML artifact-validation scaffold remains disabled by default for user-provided experiments.
- Schema awareness uses local metadata/indexing; vector storage remains a future optimization.

## Key Invariants
- **No credentials in JSON, UserDefaults, screenshots, logs or query history.** Ever.
- **No network calls from the AI layer.** Inference is local-only.
- **UI never imports `PostgresNIO` directly.** Services mediate.
- **Services never import SwiftUI.** Keeps them testable and reusable.

## Concurrency Model
- `async/await` end-to-end.
- Long-running queries run on the driver's event loop; results bridge to the main actor for UI updates.
- Cancellation propagates from UI task cancellation through the service layer to the driver.

## Testing Strategy
- **Unit tests:** Core models/services, app-state workflow, persistence stores, presentation helpers, exporter behavior and redaction.
- **Integration tests:** Real PostgreSQL/TLS/SSH/model-artifact paths are env-gated and auto-skip when prerequisites are absent.
- **UI tests:** Minimal smoke coverage; most behavior is covered through view model and presentation-helper tests.
