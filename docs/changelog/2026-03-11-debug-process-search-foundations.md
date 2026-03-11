# 2026-03-11 — Debug/process/search foundations

## Obiettivo

Primo incremento concreto del piano di hardening:

- consolidare l'esecuzione native debug fuori dal `DebugStore`
- introdurre un layer condiviso minimo per subprocess e timeout
- preparare il boundary ufficiale del motore semantic search con backend Swift e stub Rust

## Modifiche

### Debug

- aggiunti `DebugExecutionCoordinator` e `DebugExecutionCoordinatorModels`
- introdotte metriche tipizzate:
  - `DebugStageMetrics`
  - `DebugLifecycleMetrics`
- `NativeDebugSessionState` ora trasporta:
  - `payloadVersion`
  - snapshot metrico dell'ultima esecuzione
- `DebugStore+NativeService` non chiama più direttamente `DebugService` per `start/stop/step/refresh/sync`, ma passa dal coordinator
- `DebugService` usa il wrapper `DebugAdapterRecovery` per le operazioni core della sessione native

### Process orchestration

- aggiunto `ProcessSupervisor` con API condivise:
  - `spawn`
  - `collectOutput`
  - `terminate`
  - `runCollectingSync`
- migrati i call site iniziali:
  - `PathFinder.findUsingInteractiveShell`
  - `ManagedPostgresService.runProcess`
- gestito esplicitamente il timeout del processo senza leggere `terminationStatus` mentre il processo è ancora attivo

### Search backend boundary

- introdotti:
  - `SearchEngineBackendKind`
  - `SearchQueryInput`
  - `SearchHitOutput`
  - `IndexStatsOutput`
  - `SemanticIndexSearchSnapshot`
  - `SearchEngineBackend`
- aggiunti backend:
  - `SwiftSearchEngineBackend`
  - `RustSearchEngineBackend` con fallback esplicito al backend Swift
- `SemanticIndex` ora seleziona il backend via environment flag `SOLOCODE_SEMANTIC_SEARCH_BACKEND`
- `SemanticIndex.search(...)` usa il boundary backend invece della logica inline

## Test eseguiti

- `SoloCodeAppTests/DebugServiceFlowTests`
- `SoloCodeAppTests/DebugStoreTests`
- `CoderEngineTests/PathFinderTests`
- `CoderEngineTests/ProcessSupervisorTests`
- `CoderEngineTests/SearchEngineBackendTests`
- `CoderEngineTests/CodebaseIndexIncrementalTests`
- `CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
- `CoderEngineTests/SemanticSearchBenchmarkTests/testSemanticSearchBenchmarkSynthetic10kFiles`

## Note

- Nessuna parte Apple-specific del debug nativo è stata spostata fuori da Swift.
- Il backend Rust è preparato come boundary/stub e non è ancora collegato a una crate compilata.
- I file nuovi e toccati restano entro il vincolo operativo di dimensione del repository.
