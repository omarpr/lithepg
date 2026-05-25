# LithePG Tech Stack: Lean & AI-Era Proof

## 1. Core Philosophy
- **Measured Lean:** Target app binary size < 50 MiB, with a 30 MiB stretch goal. AI models ship separately.
- **Mac-First:** Native SwiftUI implementation, no Electron or heavy C-wrappers.
- **Local-First AI:** Privacy-centric intelligence leveraging the Apple Neural Engine (ANE).

## 2. Persistence Layer
- **SwiftData:** The primary choice for local app state, query history, and saved connections.
- **Rationale:** Native to macOS, leverages M-series hardware, and handles schema migrations automatically with zero configuration.

## 3. PostgreSQL Engine (The Driver)
- **PostgresNIO / PostgresClientKit:** Pure Swift implementations.
- **Constraint:** Strictly avoid `libpq` (the legacy C library) to ensure the binary remains lean and modern.
- **Features:** High-performance async/await support, SSL/TLS by default, and type-safe query results.
- **Vendored C boundary:** PostgresNIO's TLS path brings BoringSSL transitively through `swift-nio-ssl`; that is an accepted security/runtime dependency, not an app-authored C shim. The v0.2a editor deliberately uses native AppKit `NSTextView` after the Runestone spike failed on native macOS SPM, so v0.2a adds no tree-sitter or editor-side C dependency. Revisit the binary-size trade-off before introducing tree-sitter in v0.2b.

## 4. AI & Intelligence Layer
- **Local RAG (Retrieval-Augmented Generation):**
    - Local schema indexing powers lexical retrieval today; vector storage remains a future optimization.
- **Inference runtime decision:** v0.5 chooses a minimal **CoreML** adapter scaffold first. CoreML is available from the macOS SDK, requires no new Swift package dependency, and keeps model artifacts external. MLX remains a future option after a model candidate justifies the package/runtime cost.
- **Model adapter:** `LocalModelAIQueryService` sits behind `AIQueryService` and is disabled by default. It is explicitly gated by `LITHEPG_ENABLE_LOCAL_MODEL=1` plus `LITHEPG_LOCAL_MODEL_PATH`; default tests cover unavailable/missing behavior, while real CoreML artifact loading is env-gated so CI stays deterministic.
- **Model artifacts:** Artifacts are never bundled in the app binary. `LocalModelRegistry` only locates user-provided artifacts under Application Support (or explicit test/config overrides) and reports unavailable/missing states; it does not download models.
- **v0.5 adapter measurement (2026-05-25):** Baseline release `LithePGApp` before the adapter was 22,352,984 bytes / 21.317 MiB. After the CoreML scaffold it was 22,374,232 bytes / 21.338 MiB, a +21,248 byte / +0.020 MiB delta, with no bundled model and no new package dependency. `./script/v04_measure.sh` stayed under budget: raw binary 21.338 MiB, strip probe 11.959 MiB, shell readiness 121.11 ms, connected cold start 220.51 ms.
- **Privacy receipts:** AI context construction is test-covered to include only the user request and schema metadata, with credentials/raw connection URLs redacted or omitted and result rows excluded. Drafted SQL is inserted for human review and is never run automatically.
- **Schema Awareness:** Automatic "semantic mapping" of tables to allow natural language joins (e.g., "Join users to their latest invoices").

## 5. Build System
- **Swift Package Manager (SPM):** No `.xcodeproj` bloat.
- **Tooling:** Managed via `swift build` and integrated with Superset for agent-driven development.
