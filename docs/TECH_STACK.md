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
    - Local vector storage for schema indexing (using `pgvector` on the server or a local SQLite/vector shim).
- **Inference:** - **CoreML / MLX:** Running quantized models (like Llama 3 or Phi-3) directly on the Mac's GPU/ANE for NL2SQL tasks.
- **Schema Awareness:** Automatic "semantic mapping" of tables to allow natural language joins (e.g., "Join users to their latest invoices").

## 5. Build System
- **Swift Package Manager (SPM):** No `.xcodeproj` bloat.
- **Tooling:** Managed via `swift build` and integrated with Superset for agent-driven development.
