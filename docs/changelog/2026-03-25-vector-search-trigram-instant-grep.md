# Changelog: Vector Database, Semantic Search Reale, Instant Grep Trigram

**Data**: 2026-03-25

## Contesto

Implementazione completa di un vero vector database (pgvector), embedding locali (CoreML), e instant grep con trigram index in Rust. La semantic search precedente usava solo BM25 lessicale — ora è stata potenziata con ricerca vettoriale reale.

---

## Fase A — pgvector Schema + Persistence

### File nuovi
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+VectorSearch.swift`
  - `CREATE EXTENSION IF NOT EXISTS vector`
  - Tabella `semantic_embeddings` con `vector(384)` e indice HNSW
  - Indici su file_path e content_hash

- `Engine/CoderEngine/Sources/PersistenceCore/VectorSearchModels.swift`
  - `VectorSearchHit`, `EmbeddingRecord`, `EmbeddingUpsertPayload`

- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VectorSearch.swift`
  - CRUD: upsert (singolo e batch), delete, vectorSearch, embeddedChunkRecords
  - Operatore `<=>` per cosine distance
  - Batch upsert transazionale

### File modificati
- `PersistenceSchema.swift` — version 2 → 3, aggiunto `vectorSearchSQL`

---

## Fase B — CoreML Embedding Pipeline

### File nuovi
- `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/WordPieceTokenizer.swift`
  - Tokenizer BERT-compatible con [CLS]/[SEP], padding, truncation 512

- `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/CoreMLEmbeddingBackend.swift`
  - CoreML actor per all-MiniLM-L6-v2 (384 dim)
  - Mean pooling + L2 normalization
  - BERTInputProvider per MLModel

- `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/EmbeddingServiceModels.swift`
  - `EmbeddingBackendKind`, `EmbeddingResult`, `EmbeddingBatchResult`

- `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/RustEmbeddingBackend.swift`
  - Fallback FFI a Rust per embedding

- `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/EmbeddingService.swift`
  - Actor unificato: CoreML → Rust fallback

- `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/EmbeddingIndexingPipeline.swift`
  - Background pipeline, batch 32, progress reporting, cancellation

### File nuovi Rust
- `Native/RustCore/src/embedding.rs` — ONNX embedding con hash-based pseudo-embedding fallback
- `Native/RustCore/src/ffi/embedding.rs` — FFI `solocode_embed_text`

### File modificati
- `Native/RustCore/src/lib.rs` — aggiunto `pub mod embedding; pub mod trigram;`
- `Native/RustCore/src/ffi/mod.rs` — aggiunto `mod embedding;`

---

## Fase C — Vector Search Backend + Hybrid Fusion

### File nuovi
- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/VectorSearchEngineBackend.swift`
  - Backend pgvector per cosine similarity search

- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift`
  - Compone BM25 + Vector con RRF, embedding query parallelo

- `Engine/.../Hybrid/UnifiedToolRuntime+SemanticHybridVectorSource.swift`
  - Raccolta hit vettoriali per la hybrid fusion

### File modificati
- `SearchEngineBackend.swift` — aggiunto `.vector` e `.hybrid` kind, metodo `vectorSearch` opzionale nel protocol, factory aggiornata
- `UnifiedToolRuntime+SemanticHybridModels.swift` — aggiunto case `.vectorIndex`
- `UnifiedToolRuntime+SemanticHybridFusion.swift` — pesi: semantic=0.8, vector=1.2, symbol=0.8, grep=0.45
- `UnifiedToolRuntime+SemanticHybridSources.swift` — vector source parallela con `async let`

---

## Fase D — Trigram Instant Grep (Rust)

### File nuovi Rust (`Native/RustCore/src/trigram/`)
- `mod.rs` — dichiarazione modulo
- `index.rs` — `TrigramIndex` con posting lists e incremental update
- `bloom.rs` — BloomFilter 2KB/file, 3 hash functions, ~1% false positive
- `persistence.rs` — formato binario "TRGM" con header + file entries + posting lists + bloom
- `search.rs` — trigram candidate filtering + regex verification
- `ffi.rs` — `solocode_trigram_index_build`, `solocode_trigram_search`, `solocode_trigram_update`

### File nuovi Swift (`TrigramSearch/`)
- `TrigramSearchModels.swift` — `TrigramSearchHit`, `TrigramSearchResult`, FFI JSON models
- `TrigramSearchFFIBridge.swift` — ponte FFI Swift → Rust
- `TrigramSearchService.swift` — actor per build/search/update

### File modificati
- `UnifiedToolRuntime+SearchGrep.swift` — pre-filter trigram prima di ripgrep

---

## Fase E — Integrazione + Settings UI

### File nuovi
- `Engine/CoderEngine/Sources/CodebaseIndex/Core/CodebaseIndex+VectorPipeline.swift`
  - `generateEmbeddingsForChunks`, `removeEmbeddingsForFile`, progress tracking

- `Engine/CoderEngine/Sources/CodebaseIndex/Core/CodebaseIndex+TrigramPipeline.swift`
  - `buildTrigramIndex`, `updateTrigramIndex`, `trigramSearch`

### File modificati
- `SettingsView+CodebaseIndex.swift` — sezioni "Vector Search (beta)" e "Instant Grep Index (beta)"
- `SettingsContainers.swift` — `vectorSearchEnabled`, `trigramIndexEnabled` AppStorage

---

## Feature Flags

| Flag | Default | Descrizione |
|------|---------|-------------|
| `SOLOCODE_ENABLE_VECTOR_SEARCH` | OFF | Abilita pgvector + CoreML embedding |
| `SOLOCODE_ENABLE_TRIGRAM_INDEX` | OFF | Abilita trigram instant grep |

---

## Inventario

- **25 file nuovi** (17 Swift + 8 Rust)
- **10 file modificati**
- **~2800 righe totali** aggiunte
- Tutti i file rispettano il limite di 300 righe
- BM25 esistente **intatto** — zero regressioni con feature flags OFF
