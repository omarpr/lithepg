# ARCHITECTURE.md

High-level module boundaries and data flow for LithePG. Implementation details live in the code; this file explains *why* the boundaries exist.

## Layers

```
┌─────────────────────────────────────────────┐
│  UI Layer (SwiftUI)                         │
│  - Views, view models, navigation           │
└───────────────┬─────────────────────────────┘
                │  (async/await, @Observable)
┌───────────────▼─────────────────────────────┐
│  Services Layer                             │
│  - ConnectionManager                        │
│  - QueryRunner                              │
│  - SchemaIntrospector                       │
│  - AIService (NL2SQL, semantic mapping)     │
└───────┬───────────────────┬─────────────────┘
        │                   │
┌───────▼──────┐   ┌────────▼─────────────────┐
│  Driver      │   │  Persistence             │
│  PostgresNIO │   │  SwiftData (app state)   │
│  (pure Swift)│   │  Keychain (secrets)      │
└──────────────┘   └──────────────────────────┘
        │
┌───────▼──────────────────────────────────────┐
│  Inference (local)                           │
│  CoreML / MLX — quantized models on ANE/GPU  │
└──────────────────────────────────────────────┘
```

## Layer Responsibilities

### UI Layer
- SwiftUI views, `@Observable` view models, navigation state.
- Never touches the driver or Keychain directly — always through Services.
- No business logic beyond presentation.

### Services Layer
- The only layer that orchestrates driver + persistence + AI.
- All public APIs are `async` and cancellation-aware.
- Stateless where possible; stateful services are `actor`s.

### Driver
- `PostgresNIO` (or `PostgresClientKit`) — pure Swift, no `libpq`.
- Exposes typed query results and streaming row cursors.
- Owns connection pooling and TLS configuration.

### Persistence
- **SwiftData** for saved connections (without secrets), query history, workspace state.
- **Keychain** for all credentials. See `SECURITY.md`.

### Inference
- Local models only. See `TECH_STACK.md` §4.
- Used for NL2SQL and schema semantic mapping.
- Schema embeddings cached locally (vector shim or SQLite).

## Key Invariants
- **No credentials in SwiftData.** Ever.
- **No network calls from the AI layer.** Inference is local-only.
- **UI never imports `PostgresNIO` directly.** Services mediate.
- **Services never import SwiftUI.** Keeps them testable and reusable.

## Concurrency Model
- `async/await` end-to-end.
- Long-running queries run on the driver's event loop; results bridge to the main actor for UI updates.
- Cancellation propagates from UI (task cancellation) through the service layer to the driver.

## Testing Strategy
- **Unit tests:** Services layer with a mocked driver protocol.
- **Integration tests:** Real PostgreSQL in Docker; hit a real database per `feedback_testing.md` principles if/when we adopt that rule.
- **UI tests:** Minimal; focus on view model behavior via unit tests instead.
