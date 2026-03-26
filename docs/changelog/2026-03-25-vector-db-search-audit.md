# Changelog — 2026-03-25: Audit Vector DB, Semantic Search, Instant Grep

## Analisi eseguita

Audit completo del sistema di ricerca: Vector DB (SemanticIndex), MCP server search tools, Instant Grep UI.

## Componenti analizzati

### SemanticIndex (Swift actor)
- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex.swift` — Core BM25 index
- `SemanticIndex+Search.swift` — Search con backend strategy pattern
- `SemanticIndex+Build.swift` — Full build e incremental update
- `SemanticIndex+Persistence.swift` — JSONL persistence con metadata validation
- `SemanticIndex+IndexManagement.swift` — Chunk add/remove, inverted index
- `SemanticIndex+ChunkBudget.swift` — LRU eviction (max 50K chunk)

### Search Engine Backends
- `SearchEngineBackend.swift` — Protocol + Factory
- `SwiftSearchEngineBackend.swift` — BM25 puro in Swift con bonuses
- `RustSearchEngineBackend.swift` — FFI bridge verso dylib Rust con fallback Swift
- `HybridSearchEngineBackend.swift` — RRF fusion (lexical + vector)
- `RustSearchFFIClient.swift` — dlopen/dlsym FFI client

### MCP Server Rust
- `Native/CoderideMCPServerRust/src/search_tools.rs` — 8 tool di ricerca
- `Native/CoderideMCPServerRust/src/diagnostics_tools.rs` — semantic_search
- `Native/CoderideMCPServerRust/src/catalog.rs` — Tool catalog

### Instant Grep
- `App/.../TaskActivityPanel+InstantGrep.swift` — UI cards
- `App/.../EventNormalizer/Search/EventNormalizerSearch.swift` — Normalizzazione

### UnifiedToolRuntime
- `UnifiedToolRuntime+IndexSemantic.swift` — Hybrid search orchestration

## Bug trovati

### P0 — Critici (4)
1. `coderide_semantic_search` è un grep mascherato, non usa SemanticIndex
2. `coderide_semantic_search` fallisce — rg non nel PATH del MCP server
3. 6/8 tool di ricerca MCP non funzionanti (tutti quelli che dipendono da rg)
4. `coderide_codebase_search` non usa l'indice codebase reale

### P1 — Importanti (3)
5. HybridSearchEngineBackend: DispatchSemaphore deadlock risk
6. SemanticIndex: full persist O(n) su ogni aggiornamento incrementale
7. MCP grep e semantic_search ignorano parametri di filtro dichiarati nello schema

### P2 — Minori (2)
8. find_symbol copre solo keyword Swift, non multi-linguaggio
9. file_outline parsing troppo primitivo

## Cosa funziona bene
- SemanticIndex in-process (BM25 + AST chunking + Merkle tree) è ben progettato
- LRU eviction con chunk budget è corretto
- Persistence con metadata validation (version, schema, fingerprint) è robusta
- Hybrid search con RRF fusion è architetturalmente solido
- Instant Grep UI è corretto e funzionale
- RustSearchFFIClient con dylib probing multi-path è resiliente

## Documenti bug creati
- `docs/bugs/P0-2026-03-25-vector-db-search-tools-broken.md`
- `docs/bugs/P1-2026-03-25-hybrid-search-semaphore-deadlock-risk.md`
- `docs/bugs/P1-2026-03-25-semantic-index-full-persist-on-every-update.md`
- `docs/bugs/P1-2026-03-25-mcp-grep-ignores-filter-params.md`
- `docs/bugs/P2-2026-03-25-find-symbol-file-outline-incomplete.md`
