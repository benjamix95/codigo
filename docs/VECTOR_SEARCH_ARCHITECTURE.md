# Vector Search & Instant Grep — Architettura Tecnica

## Panoramica

SoloCode implementa un sistema di ricerca ibrido a 4 fonti che combina:

1. **BM25 Lexical Search** (pre-esistente) — indice invertito con ranking Okapi BM25
2. **Vector Search** (nuovo) — embedding 384-dim via CoreML + pgvector cosine similarity
3. **Symbol Index** (pre-esistente) — lookup diretto per nome simbolo
4. **Instant Grep** (nuovo) — trigram index con bloom filters in Rust

I risultati delle 4 fonti vengono fusi tramite **Reciprocal Rank Fusion (RRF)**.

---

## 1. Vector Database (pgvector)

### Stack tecnologico
- **Database**: PostgreSQL embedded (già presente in SoloCode via `ManagedPostgresService`)
- **Estensione**: pgvector per tipo `vector(384)` e operatore cosine distance `<=>`
- **Indice**: HNSW (Hierarchical Navigable Small World) per query sub-10ms

### Schema (`PersistenceSchema+VectorSearch.swift`)

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE semantic_embeddings (
    chunk_id     TEXT PRIMARY KEY,        -- "filePath:startLine:endLine"
    file_path    TEXT NOT NULL,
    content_hash BIGINT NOT NULL,         -- per incremental re-index
    embedding    vector(384) NOT NULL,    -- all-MiniLM-L6-v2 output
    scope        TEXT,                    -- "MyClass > myFunc"
    kind         TEXT,                    -- function, class, struct...
    start_line   INTEGER,
    end_line     INTEGER,
    language     TEXT,
    symbol_names TEXT[],
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
);

-- HNSW index: m=16, ef_construction=64
CREATE INDEX idx_se_embedding_hnsw
    ON semantic_embeddings
    USING hnsw (embedding vector_cosine_ops);
```

### Operazioni CRUD (`PostgresPersistenceStore+VectorSearch.swift`)
- `upsertEmbedding()` — singolo insert/update
- `upsertEmbeddingsBatch()` — batch transazionale (BEGIN/COMMIT)
- `deleteEmbeddingsForFile()` — rimozione per file path
- `vectorSearch(queryEmbedding:, limit:, threshold:)` — cosine similarity top-K
- `embeddedChunkRecords(forFile:)` — lookup content hash per incremental
- `isVectorSearchAvailable()` — verifica pgvector installato

---

## 2. Embedding Pipeline

### Modello
- **all-MiniLM-L6-v2** — 384 dimensioni, ~80MB
- Ottimizzato per sentence-level semantic similarity
- Funziona completamente offline, privacy totale

### Architettura a 3 livelli

```
         ┌─────────────────────┐
         │  EmbeddingService   │  (actor unificato)
         │  embed() / batch()  │
         └────────┬────────────┘
                  │
          ┌───────┴───────┐
          ▼               ▼
  ┌──────────────┐  ┌──────────────┐
  │ CoreML       │  │ Rust ONNX    │
  │ Backend      │  │ Backend      │
  │ (ANE/GPU)    │  │ (fallback)   │
  └──────────────┘  └──────────────┘
```

#### CoreMLEmbeddingBackend (`CoreMLEmbeddingBackend.swift`)
- Carica `.mlmodelc` dal bundle app
- `computeUnits = .all` → preferisce ANE, fallback GPU/CPU
- Input: `input_ids` + `attention_mask` da WordPieceTokenizer
- Output: mean pooling + L2 normalization → vettore 384-dim

#### WordPieceTokenizer (`WordPieceTokenizer.swift`)
- Tokenizer BERT-compatible
- `[CLS]` + tokens + `[SEP]` + padding fino a 512
- Greedy longest-match WordPiece splitting
- Carica `vocab.txt` (~30K token) dal bundle

#### RustEmbeddingBackend (`RustEmbeddingBackend.swift`)
- Fallback se CoreML non disponibile
- Chiama `solocode_embed_text` FFI su `libsolocode_rust_core.dylib`
- Rust side: `embedding.rs` con hash-based pseudo-embedding (placeholder per ONNX Runtime)

### Background Indexing (`EmbeddingIndexingPipeline.swift`)
- Actor con coda asincrona
- Batch di 32 chunk per chiamata (ottimale per GPU/ANE)
- Progress tracking: `progress`, `active`, `remaining`
- Cancellazione supportata
- Incremental: salta chunk con content_hash invariato

### Flusso di indicizzazione

```
File modificato (FileWatcher FSEvents)
    │
    ▼
CodebaseIndex.indexSingleFile()
    │
    ├── SemanticChunker.chunk() → [SemanticChunk]
    │       (AST-aware, max 3000 chars, symbol boundaries)
    │
    ├── SemanticIndex.buildIndex() → BM25 inverted index
    │
    └── EmbeddingIndexingPipeline.submit(chunks)
            │
            ├── Controlla content_hash vs pgvector
            │   (skip se invariato)
            │
            ├── EmbeddingService.embedBatch(contextualizedText)
            │       CoreML → 384-dim vector
            │
            └── PostgresPersistenceStore.upsertEmbeddingsBatch()
                    INSERT INTO semantic_embeddings ... ON CONFLICT DO UPDATE
```

---

## 3. Hybrid Search (4 fonti + RRF)

### Flusso di ricerca

```
Query utente: "authentication error handling"
    │
    ▼
collectHybridSearchHits()
    │
    ├── async let: collectSemanticIndexHits()     [BM25]
    ├── async let: collectVectorIndexHits()       [pgvector]
    ├── async let: collectSymbolIndexHits()       [symbol lookup]
    └── await:     collectGrepFallbackHits()      [ripgrep]
    │
    ▼
fuseHybridSearchResults()  [Reciprocal Rank Fusion]
    │
    ▼
Top-K risultati ordinati per score fuso
```

### Reciprocal Rank Fusion (RRF)

Per ogni risultato da ogni fonte:

```
RRF_score = weight / (K + rank)
```

| Fonte | Peso | Nudge |
|-------|------|-------|
| Vector Index | 1.2 | 0.010 |
| Semantic Index (BM25) | 0.8 | 0.008 |
| Symbol Index | 0.8 | 0.004 |
| Grep Fallback | 0.45 | 0.004 |

- **K = 50** (smoothing factor)
- Deduplicazione per chiave `filePath:lineStart`
- Confidence filtering: drop risultati < `min_confidence` (default 0.45)
- Sorting: fusedScore > confidence > semantic contribution > first-seen order

### Vector Source (`UnifiedToolRuntime+SemanticHybridVectorSource.swift`)

1. Verifica feature flag `SOLOCODE_ENABLE_VECTOR_SEARCH=1`
2. Embed query text → 384-dim vector
3. `PostgresPersistenceStore.vectorSearch()` → top-K per cosine similarity
4. Mappa risultati a `HybridSourceHit` con source `.vectorIndex`

---

## 4. Instant Grep (Trigram Index)

### Concetto

Il trigram index elimina il 95%+ dei file prima di eseguire la regex, riducendo il tempo di grep da secondi a millisecondi.

### Come funziona

```
Indice: per ogni file, estrai tutti i trigrammi (3-char subsequence)

File "a.swift": "func handleSearch()"
  Trigrammi: fun, unc, nc_, c_h, _ha, han, and, ndl, dle, leS, eSe, Sea, ear, arc, rch, ch(, h()

Query: "handleSearch"
  Trigrammi query: han, and, ndl, dle, leS, eSe, Sea, ear, arc, rch

Intersezione posting lists → solo file che contengono TUTTI i trigrammi
  → file candidati (pochi)
  → regex verification solo su quei file
```

### Architettura Rust (`Native/RustCore/src/trigram/`)

| Modulo | Descrizione |
|--------|-------------|
| `index.rs` | `TrigramIndex` con posting lists, build, query, incremental update |
| `bloom.rs` | BloomFilter 2KB/file, 3 hash functions, ~1% false positive rate |
| `persistence.rs` | Formato binario "TRGM" con header + file entries + posting lists + bloom |
| `search.rs` | Candidate filtering + regex verification pass |
| `ffi.rs` | FFI: `solocode_trigram_index_build`, `solocode_trigram_search`, `solocode_trigram_update` |

### Bloom Filter

Ogni file ha un bloom filter da 2KB (16384 bit, 3 hash functions):
- `insert(trigram)` — setta 3 bit
- `may_contain(trigram)` — controlla 3 bit
- `may_contain_all(trigrams)` — short-circuit al primo miss
- False positive rate: ~1% a 500 trigrammi/file
- False negative: **impossibile** (garanzia zero missed results)

### Integrazione Grep (`UnifiedToolRuntime+SearchGrep.swift`)

```
Query grep ricevuta
    │
    ├── SOLOCODE_ENABLE_TRIGRAM_INDEX == "1"?
    │       │
    │       ├── Sì → trigramSearch(pattern) via FFI
    │       │       │
    │       │       ├── Risultati? → return formattati (fast path)
    │       │       └── Vuoto? → fallthrough a ripgrep
    │       │
    │       └── No → skip
    │
    └── ripgrep standard (/usr/bin/env rg ...)
            │
            └── grep POSIX fallback (se rg non installato)
```

### Performance target
- **Build**: <30s per 50K file
- **Query**: <15ms (vs 16s raw ripgrep su repo grandi)
- **Update incrementale**: <1ms per file singolo

---

## 5. Feature Flags

| Flag ambiente | Default | Effetto |
|---------------|---------|---------|
| `SOLOCODE_ENABLE_VECTOR_SEARCH` | `0` (OFF) | Abilita pgvector + CoreML embedding pipeline |
| `SOLOCODE_ENABLE_TRIGRAM_INDEX` | `0` (OFF) | Abilita trigram instant grep |
| `SOLOCODE_SEMANTIC_SEARCH_BACKEND` | `rust` | Backend BM25: `swift` o `rust` |

### Degradazione graceful

- Se pgvector non installato → tabella non creata, vector search disabilitato, BM25 funziona
- Se CoreML model non trovato → Rust fallback, poi hash pseudo-embedding
- Se trigram index non pronto → grep standard via ripgrep
- Se Rust dylib non caricato → Swift BM25 backend

---

## 6. Settings UI

In **Settings > Codebase Index**:

- **Vector Search (beta)** — toggle per abilitare pgvector + embeddings
- **Instant Grep Index (beta)** — toggle per abilitare trigram index

---

## 7. Mappa dei file

### Persistence Layer
```
PersistenceCore/
├── PersistenceSchema.swift              (version 3)
├── PersistenceSchema+VectorSearch.swift  (pgvector DDL)
├── PostgresPersistenceStore+VectorSearch.swift (CRUD)
└── VectorSearchModels.swift              (VectorSearchHit, EmbeddingRecord, etc.)
```

### Embedding Pipeline
```
CodebaseIndex/Embeddings/
├── WordPieceTokenizer.swift       (BERT tokenizer)
├── CoreMLEmbeddingBackend.swift   (CoreML inference)
├── RustEmbeddingBackend.swift     (FFI fallback)
├── EmbeddingService.swift         (unified actor)
├── EmbeddingServiceModels.swift   (types)
└── EmbeddingIndexingPipeline.swift (background queue)
```

### Search Backends
```
CodebaseIndex/Indexing/
├── SearchEngineBackend.swift            (protocol + factory)
├── VectorSearchEngineBackend.swift      (pgvector backend)
├── HybridSearchEngineBackend.swift      (BM25 + vector RRF)
└── TrigramSearch/
    ├── TrigramSearchService.swift       (actor)
    ├── TrigramSearchFFIBridge.swift     (Rust FFI)
    └── TrigramSearchModels.swift        (types)
```

### Hybrid Fusion
```
UnifiedToolRuntime/.../Hybrid/
├── UnifiedToolRuntime+SemanticHybridModels.swift   (+vectorIndex case)
├── UnifiedToolRuntime+SemanticHybridFusion.swift   (RRF weights)
├── UnifiedToolRuntime+SemanticHybridSources.swift  (async let vector)
└── UnifiedToolRuntime+SemanticHybridVectorSource.swift (vector collection)
```

### Rust Trigram
```
Native/RustCore/src/
├── embedding.rs           (ONNX fallback)
├── ffi/embedding.rs       (FFI entry)
└── trigram/
    ├── mod.rs
    ├── index.rs           (TrigramIndex)
    ├── bloom.rs           (BloomFilter)
    ├── persistence.rs     (binary format)
    ├── search.rs          (grep execution)
    └── ffi.rs             (FFI entry points)
```

### Integration
```
CodebaseIndex/Core/
├── CodebaseIndex+VectorPipeline.swift   (embedding integration)
└── CodebaseIndex+TrigramPipeline.swift  (trigram integration)
```
