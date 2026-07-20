# LithePG Tech Stack: Lean & AI-Era Proof

## 1. Core Philosophy
- **Measured Lean:** Target app binary size < 50 MiB, with a 30 MiB stretch goal. AI models ship separately.
- **Mac-First:** Native SwiftUI implementation, no Electron or heavy C-wrappers.
- **Local-First AI:** Privacy-centric SQL drafting that prefers Apple's on-device system model when available and falls back to deterministic schema-aware logic.

## 2. Persistence Layer
- **Local JSON metadata:** Saved connections and opt-in query history are stored under Application Support with restrictive directory/file permissions and file-protection write options.
- **Keychain:** Saved passwords and saved-connection integrity keys live in the macOS Keychain. JSON metadata stores references and HMAC tags, not passwords.
- **UserDefaults:** Appearance preference uses standard app defaults.
- **Rationale:** The current app keeps persistence simple, testable, and dependency-free while preserving credential separation. SwiftData remains a possible future migration only if it earns its complexity.

## 3. PostgreSQL Engine (The Driver)
- **PostgresNIO:** The active connection path.
- **Constraint:** Strictly avoid `libpq` and app-authored C shims to keep the binary lean and modern.
- **Features:** Async/await-facing app APIs, explicit TLS modes from Postgres URLs/UI configuration, optional OpenSSH tunnel handoff, schema introspection, and typed query results for the UI.
- **Neon compatibility (verified 2026-07-11):** The connector and CLI smoke utility passed live checks against a real Neon project (Postgres 17) over verified TLS, on both direct and pooled (`-pooler`) endpoints using the current `ep-*.c-N.<region>.aws.neon.tech` host shape with `channel_binding=require` present in the URL. The gated live app-layer suite (`POSTGRES_TEST_URL` + `swift test --filter 'live|Live'`) passed 6/6 against Neon: connect, query render, schema introspection, saved-connection flow, reconnect, and query history. The app can also invoke an installed `neon`/`neonctl` on demand to discover projects, branches and databases with JSON output and analytics disabled, importing only missing endpoints.
- **Vendored C boundary:** PostgresNIO's TLS path brings BoringSSL transitively through `swift-nio-ssl`; that is an accepted security/runtime dependency, not an app-authored C shim. The v0.2a editor deliberately uses native AppKit `NSTextView` after the Runestone spike failed on native macOS SPM, so v0.2a adds no tree-sitter or editor-side C dependency. Revisit the binary-size trade-off before introducing tree-sitter in v0.2b.

## 4. AI & Intelligence Layer
- **Local RAG (Retrieval-Augmented Generation):**
    - Local schema indexing powers lexical retrieval today; vector storage remains a future optimization.
- **Default inference runtime:** `OnDeviceAIQueryService` uses Apple's Foundation Models framework on macOS 26 when the Apple Intelligence system model is available. Guided generation produces a typed SQL draft, compact lexical retrieval supplies relevant schema and foreign-key context, and a local SQL gate rejects mutation, DDL, locking, `SELECT INTO`, malformed and multi-statement output. The framework is supplied by macOS and adds no model artifact to LithePG.
- **Fallback:** `DeterministicAIQueryService` remains the offline fallback on macOS 14–15 and whenever Apple Intelligence is unsupported, disabled, downloading or temporarily unavailable. It also receives a request if system-model generation fails.
- **Custom model scaffold:** The earlier `LocalModelAIQueryService` CoreML artifact validator remains available for experiments behind `LITHEPG_ENABLE_LOCAL_MODEL=1` and `LITHEPG_LOCAL_MODEL_PATH`, but it is not the app default and does not implement model-specific NL2SQL inference.
- **Model artifacts:** LithePG bundles and downloads no model artifact. macOS manages the Apple Intelligence system model; `LocalModelRegistry` only locates explicitly user-provided CoreML artifacts for the legacy experimental scaffold.
- **v0.5 adapter measurement (2026-05-25):** Baseline release `LithePGApp` before the adapter was 22,352,984 bytes / 21.317 MiB. After the CoreML scaffold it was 22,374,232 bytes / 21.338 MiB, a +21,248 byte / +0.020 MiB delta, with no bundled model and no new package dependency. The milestone measurement stayed under budget: raw binary 21.338 MiB, strip probe 11.959 MiB, shell readiness 121.11 ms, connected cold start 220.51 ms.
- **Privacy receipts:** AI context construction is test-covered to include only the user request and schema metadata, with credentials/raw connection URLs redacted or omitted and result rows excluded. Drafted SQL is inserted for human review and is never run automatically.
- **Schema Awareness:** Local schema metadata and foreign-key indexing support both retrieved system-model context and deterministic read-only drafts. Prompts, schema context and generated output remain in process and on device.

## 5. Build System
- **Swift Package Manager (SPM):** No `.xcodeproj` bloat.
- **Tooling:** Managed via `swift build` and integrated with Superset for agent-driven development.
