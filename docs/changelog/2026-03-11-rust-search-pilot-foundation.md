# 2026-03-11 — Rust search pilot foundation

## Obiettivo

Portare il primo uso reale di Rust nel motore search/index senza toccare il core del debug nativo LLDB.

## Modifiche

### Rust

- aggiunta crate `Native/RustCore` con nome `solocode_rust_core`
- crate configurata come:
  - `staticlib`
  - `cdylib`
- C ABI esportato:
  - `solocode_search_backend_version()`
  - `solocode_semantic_search(...)`
  - `solocode_semantic_tokenize(...)`
  - `solocode_free_buffer(...)`

### Build

- aggiunto script `scripts/build_rust_search_backend.sh`
- aggiunta build phase Xcode su target `CoderEngine`
- la build phase è best-effort:
  - se `cargo` o `rustc` non esistono, logga skip e non rompe build/test
  - se presenti, compila la crate e copia gli artifact in `Native/RustCore/build/lib` e in `BUILT_PRODUCTS_DIR/solocode_rust`

### Swift boundary / FFI

- aggiunti:
  - `RustSearchFFIClient`
  - `RustSearchFFIModels`
  - `SearchBackendMetrics`
- `SearchEngineBackend` ora restituisce una response con:
  - hit
  - metriche backend
- `RustSearchEngineBackend` usa il client FFI quando la libreria è disponibile
- fallback esplicito al backend Swift se la libreria Rust manca o fallisce decode/call

### Metriche

- aggiunto `IndexingMetricsSnapshot`
- aggiunto `ProcessLifecycleMetrics`
- aggiunto `DebugSessionMetrics`
- `SemanticIndex` conserva `lastSearchMetrics`
- `CodebaseIndex` espone `metricsSnapshot()`

### Non-scope confermato

- nessuna migrazione Rust di:
  - `DebugService`
  - `LLDBPersistentSession`
  - `LLDBDAPDebugAdapter`
  - `DebugNativePipeline*`
  - `DebugStore`

## Test

- `SoloCodeAppTests/DebugServiceFlowTests`
- `SoloCodeAppTests/DebugStoreTests`
- `CoderEngineTests/PathFinderTests`
- `CoderEngineTests/ProcessSupervisorTests`
- `CoderEngineTests/SearchEngineBackendTests`
- `CoderEngineTests/IndexingMetricsSnapshotTests`
- `CoderEngineTests/CodebaseIndexIncrementalTests`

## Note

- In questa sessione `cargo` non è disponibile, quindi il backend Rust reale non è stato eseguito end-to-end nella build locale.
- Il progetto resta compilabile e testabile con fallback Swift completo.
