# Changelog — 2026-03-25: Vector Index UserDefaults Bridge & Embedding Progress

## Summary

Collegamento del flag `vector_search_enabled` da UserDefaults (Settings UI) al Engine,
integrazione del progress dell'embedding vettoriale nel progress bar di indexing,
ampliamento delle directory escluse, e semplificazione delle descrizioni Settings.

## Changes

### 1. IndexFeatureFlags — Centralizzazione feature flags
**File:** `Engine/CoderEngine/Sources/CodebaseIndex/Core/IndexFeatureFlags.swift` (NEW)

- Nuovo enum `IndexFeatureFlags` che legge da `UserDefaults` con fallback env var
- `vectorSearchEnabled`: legge `vector_search_enabled` (default: `true`)
- `trigramIndexEnabled`: legge `trigram_index_enabled` (default: `true`)
- `respectGitignore`: legge `codebase_index_respect_gitignore` (default: `true`)
- Env var override: `SOLOCODE_ENABLE_VECTOR_SEARCH=0/1` per test/CI

### 2. Rimozione env var hardcoded
**Files modificati:**
- `CodebaseIndex+VectorPipeline.swift` — 2 occorrenze sostituite con `IndexFeatureFlags.vectorSearchEnabled`
- `SearchEngineBackend.swift` — 1 occorrenza sostituita
- `UnifiedToolRuntime+SemanticHybridVectorSource.swift` — 1 occorrenza sostituita

**Impatto:** Il toggle "Vector Search" nelle Settings ora controlla effettivamente il pipeline vettoriale.

### 3. Embedding progress integrato nel _indexingProgress
**File:** `CodebaseIndex+WorkspaceIndexing.swift`

- Progress total ora include 2 fasi extra se vector è attivo (semantic + embedding)
- Dopo il build del semantic index, viene lanciato `generateEmbeddingsForChunks()`
- Progress polling dell'embedding pipeline con aggiornamento UI in tempo reale
- La barra di progresso nella sidebar e nelle Settings ora riflette il vero stato dell'embedding

### 4. SemanticIndex.allChunks()
**File:** `SemanticIndex+Search.swift`

- Nuovo metodo `allChunks() -> [SemanticChunk]` per esporre tutti i chunk all'embedding pipeline

### 5. ExcludedDirectories ampliato
**File:** `ExcludedDirectories.swift`

Aggiunte directory per:
- Python: `.tox`, `.eggs`, `*.egg-info`, `site-packages`
- Ruby: `bundle`, `.bundle`
- Go: `go_modules`
- Java: `.m2`, `.mvn`
- .NET: `packages`, `bin`, `obj`
- Docker: `.docker`
- Terraform: `.terragrunt-cache`
- JS: `.parcel-cache`, `.turbo`, `bower_components`, `.pnpm-store`

### 6. Settings UI — Hint semplificato
**File:** `SettingsView+CodebaseIndex.swift`

- Vector Search hint semplificato: rimosso riferimento tecnico a CoreML/MiniLM/384dim
- Nuovo testo: "Semantic code search powered by local embeddings. Everything runs on-device — no data leaves your machine."

## Tests

### Nuovi test (tutti passati):
- `IndexFeatureFlagsTests` — 6 test: default true, lettura UserDefaults, env override
- `ExcludedDirectoriesTests` — 11 test: verifica tutte le nuove directory escluse
- `SemanticIndexTests.testAllChunksReturnsAllIndexedChunks` — verifica count coerente con status
- `SemanticIndexTests.testAllChunksEmptyOnFreshIndex` — verifica stato iniziale vuoto

### Test pre-esistenti falliti (NON regressioni):
- `testBuildIndexReadsNonUTF8ContentWithFallbackEncoding` — falliva già prima
- `testPersistAndReload` — falliva già prima
- `testSearchByExactSymbolName` — crash index out of range pre-esistente
- Vari test synonym/NL — fallimenti pre-esistenti del search backend
