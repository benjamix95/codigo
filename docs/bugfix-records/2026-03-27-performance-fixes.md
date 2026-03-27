# Performance Fix Record

Data: 2026-03-27
Workspace: `/Users/benjaminstoica/SoloCode`
Riferimento audit: `/Users/benjaminstoica/SoloCode/docs/bugs/2026-03-27-performance-bottlenecks-audit.md`

## Stato Per Priorita'

### P1 - Sync review-core snapshot completo

- Stato: fixato
- Perimetro:
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/Sync/VerifiedFindingsSessionSyncService.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/Sync/VerifiedFindingsSessionSyncService+BridgeOptimization.swift`
- Strategia:
  - introdotto fast-path locale per payload piccoli o quando il bridge Rust non e' conveniente
  - mantenuta la semantica di duplicate detection gia' usata dal fallback Swift
  - preservato il path Rust come opzione per payload piu' grandi o se forzato via env
- Verifica:
  - benchmark review-core post-fix: `verified_sync_p95_ms = 1.70`
  - benchmark review-core pre-fix osservato in audit: `verified_sync_p95_ms = 10.15`
- Esito:
  - miglioramento netto del principale collo di bottiglia confermato da benchmark

### P1 - Multi-pass contenuti nel codebase indexing

- Stato: mitigato senza regressione strutturale sui path riaperti/cached
- Perimetro:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/CodebaseIndex+WorkspaceIndexing.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/Support/CodebaseIndex+FullIndexContentCache.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/MerkleTree+IndexedSnapshot.swift`
- Strategia:
  - aggiunti helper per riusare contenuti e Merkle prebuilt solo quando conviene davvero
  - limitato il fast-path ai casi di hydration/cache o set piccoli
  - evitato di trattenere il contenuto di tutti i file nel cold full-build grande, dove il costo di memoria superava il beneficio
- Verifica:
  - nuovo test: `CodebaseIndexFullIndexOptimizationTests`
  - benchmark smoke cold full-build: banda sostanzialmente piatta, `full_median_ms = 459`, `full_p95_ms = 469`
- Esito:
  - il collo di bottiglia dei reopen/index cached e dei path con hydration e' ridotto nel codice
  - il benchmark smoke cold-start non mostra ancora un guadagno netto; resta area da ottimizzare ulteriormente

### P2 - Prima semantic search bloccata da full reindex inline

- Stato: fixato
- Perimetro:
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Index/Search/Semantic/UnifiedToolRuntime+IndexSemantic.swift`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Index/Search/Semantic/UnifiedToolRuntime+SemanticSearchPreparation.swift`
- Strategia:
  - spostato il reindex freddo fuori dal path sincrono della ricerca
  - introdotto warmup in background dell’indice
  - quando l’indice non e' pronto, la ricerca risponde via fallback testo invece di bloccare
- Verifica:
  - test: `UnifiedToolRuntimeTests/testSemanticSearchUsesTextFallbackWhileIndexWarmsInBackground`
- Esito:
  - la prima `semantic_search` non resta piu' agganciata al full reindex inline

### P2 - WorkspaceScanner rilancia processi git ripetuti

- Stato: fixato
- Perimetro:
  - `Engine/CoderEngine/Sources/Workspace/WorkspaceScanner.swift`
  - `Engine/CoderEngine/Sources/Workspace/WorkspaceScanner+GitCache.swift`
- Strategia:
  - introdotta cache TTL breve per `git status`, `git diff --cached` e `git ls-files`
  - aggiunto command runner testabile per verificare che il processo non venga rilanciato inutilmente
- Verifica:
  - test: `WorkspaceScannerTests/testListUncommittedSourceFilesCachesRepeatedGitStatusCalls`
- Esito:
  - ridotto l’overhead dei process spawn ripetuti nei round review

### P2 - Script Rust sempre rilanciati in build/test

- Stato: mitigato
- Perimetro:
  - `scripts/build_rust_search_backend.sh`
  - `scripts/build_rust_mcp_server.sh`
  - `scripts/build_rust_mcp_lifecycle_backend.sh`
- Strategia:
  - aggiunto fast-exit basato su stamp e freshness dei sorgenti crate/script
  - se artifact e stamp sono gia' aggiornati, gli script escono subito senza ricompilare/copiare
- Verifica:
  - log di build post-fix con messaggi:
    - `[rust-search] artifact gia' aggiornato, skip build`
    - `[rust-mcp] artifact gia' aggiornato, skip build`
    - `[rust-mcp-lifecycle] artifact gia' aggiornato, skip build`
- Esito:
  - il `.pbxproj` continua a invocare le phase, ma il lavoro reale degli script Rust viene saltato quando non serve

## Verifica Finale

- test mirati eseguiti:
  - `xcodebuild test -quiet -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodebaseIndexFullIndexOptimizationTests -only-testing:CoderEngineTests/MerkleTreeTests -only-testing:CoderEngineTests/WorkspaceScannerTests -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testSemanticSearchUsesTextFallbackWhileIndexWarmsInBackground -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testSemanticSearchReindexesWhenWorkspacePathsChange -only-testing:CoderEngineTests/ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
- benchmark review-core post-fix:
  - `docs/benchmarks/review-core/perf-fixes-20260327-post-engine.json`
- benchmark indexing post-fix:
  - `docs/benchmarks/indexing-hardening/perf-fixes-20260327-post.json`
