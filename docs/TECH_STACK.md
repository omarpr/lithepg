# LithePG Tech Stack: Lean & AI-Era Proof

## 1. Core Philosophy
- **Zero-Bloat:** Target binary size < 15MB.
- **Mac-First:** Native SwiftUI implementation, no Electron or heavy C-wrappers.
- **Local-First AI:** Privacy-centric intelligence leveraging the Apple Neural Engine (ANE).

## 2. Persistence Layer
- **SwiftData:** The primary choice for local app state, query history, and saved connections.
- **Rationale:** Native to macOS, leverages M-series hardware, and handles schema migrations automatically with zero configuration.

## 3. PostgreSQL Engine (The Driver)
- **PostgresNIO / PostgresClientKit:** Pure Swift implementations.
- **Constraint:** Strictly avoid `libpq` (the legacy C library) to ensure the binary remains lean and modern.
- **Features:** High-performance async/await support, SSL/TLS by default, and type-safe query results.

## 4. AI & Intelligence Layer
- **Local RAG (Retrieval-Augmented Generation):**
    - Local vector storage for schema indexing (using `pgvector` on the server or a local SQLite/vector shim).
- **Inference:** - **CoreML / MLX:** Running quantized models (like Llama 3 or Phi-3) directly on the Mac's GPU/ANE for NL2SQL tasks.
- **Schema Awareness:** Automatic "semantic mapping" of tables to allow natural language joins (e.g., "Join users to their latest invoices").

## 5. Build System
- **Swift Package Manager (SPM):** No `.xcodeproj` bloat.
- **Tooling:** Managed via `swift build` and integrated with Superset for agent-driven development.
