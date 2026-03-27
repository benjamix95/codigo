# Audit Colli Di Bottiglia Performance

Data: 2026-03-27
Workspace: `/Users/benjaminstoica/SoloCode`
Obiettivo: individuare colli di bottiglia reali o ad alto rischio che riducono le performance runtime o la reattivita' del workflow.

## Metodo

- benchmark eseguiti:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testReviewPanelStoreSmokeBenchmark`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
- benchmark storici consultati:
  - `docs/benchmarks/indexing-hardening/PERF-AUDIT-20260327-post.json`
  - `docs/benchmarks/review-core/PERF-AUDIT-20260327-post-engine.json`
  - `docs/benchmarks/review-core/PERF-AUDIT-20260327-post-app.json`
- review statica dei path caldi:
  - `Engine/CoderEngine/Sources/CodebaseIndex/**`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/**`
  - `Engine/CoderEngine/Sources/Workspace/WorkspaceScanner.swift`
  - `Solo Code.xcodeproj/project.pbxproj`

## Sintesi Rapida

- Hotspot confermato: `verified_sync_p95_ms` nel review-core. Benchmark corrente: `10.15 ms`.
- Hotspot secondario: `historical_shape_p95_ms` a `4.37 ms`; non e' il primo problema da attaccare.
- UI review panel: non risulta il collo di bottiglia principale. Benchmark corrente: `main_thread_block_time_ms = 1.43 ms`.
- Indexing full-workspace: resta il problema strutturale piu' evidente sul codice, con piu' passaggi completi sul filesystem e rilettura dei file.
- Workflow build/test: quattro script phase sono `alwaysOutOfDate = 1`, quindi ogni build/test rilancia step Rust e strip xattr anche quando niente e' cambiato.

## Bug Fix Record

### P1 - Full indexing con triplo I/O sugli stessi file

- Categoria: B - Importante ma non bloccante
- Bug: il full indexing del codebase rilegge e rielabora gli stessi file piu' volte nello stesso ciclo.
- Sintomo: il cold start dell'indice e la prima ricerca semantica possono costare molto piu' del necessario.
- Impatto: latenza percepibile su apertura workspace, prima `semantic_search`, rebuild completi e benchmark indexing.
- Gravita': alta
- Steps to reproduce:
  - eseguire il benchmark indexing smoke
  - osservare che `indexWorkspace` ricostruisce albero file, estrae simboli, ricostruisce semantic index e Merkle tree in passaggi separati
  - confrontare con `docs/benchmarks/indexing-hardening/PERF-AUDIT-20260327-post.json` che riporta `full_median_ms = 445` e `full_p95_ms = 452` su dataset da 180 file
- Risultato attuale:
  - `CodebaseIndex.indexWorkspace` ricostruisce l'albero completo del workspace
  - `SymbolExtractor.indexFile` legge ogni file per simboli
  - `SemanticIndex.buildIndex` rilegge ogni file per chunking
  - `MerkleTree.build` rilegge gli stessi file per hashing SHA-256
- Risultato atteso:
  - un solo passaggio contenutistico per file nel path full-index, con riuso del contenuto gia' letto per simboli, semantic chunks e hashing.
- Causa probabile:
  - il path full indexing usa `SymbolExtractor.indexFile` invece di `indexFileWithContent`
  - la semantic phase e il Merkle tree non consumano un contenuto/cache condiviso dal passaggio precedente
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/CodebaseIndex+WorkspaceIndexing.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SymbolExtractor.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/MerkleTree.swift`
- Non-scope:
  - ranking BM25
  - UI della search
  - provider LLM
- Moduli confinanti da verificare:
  - incremental indexing
  - persistence del semantic index
  - calcolo simhash e invalidazione cache
- Test da aggiungere o aggiornare:
  - benchmark di regressione che verifichi riduzione del numero di read per file nel full index
  - smoke benchmark su `CodebaseIndexIndexingBenchmarkSmokeTests`
- Strategia di fix minimo:
  - portare il full index a usare `indexFileWithContent`
  - passare una `contentCache` reale a `SemanticIndex.buildIndex`
  - evitare la seconda/terza lettura dove l'hash puo' essere derivato dal contenuto gia' in memoria
- Verifica post-fix:
  - ricontrollare `full_median_ms`, `full_p95_ms`, tempo della prima `semantic_search`
- Commit previsto:
  - `fix(indexing): reuse file content across full index pipeline`

### P1 - Sync review-core ancora dominato da serializzazione snapshot completa

- Categoria: B - Importante ma non bloccante
- Bug: il sync dei verified findings passa ogni volta l'intero snapshot attraverso il bridge Swift/Rust, e il costo resta il piu' alto del benchmark review-core.
- Sintomo: review-core benchmark corrente con `verified_sync_p95_ms = 10.15 ms`, nettamente sopra `verify_candidate_p95_ms = 0.14 ms`, `projection_build_p95_ms = 1.00 ms`, `security_gate_p95_ms = 2.14 ms`.
- Impatto: overhead ripetuto nelle sessioni review che accumulano findings/eventi; peggiora la reattivita' dei loop di review e update status.
- Gravita': alta
- Steps to reproduce:
  - eseguire `ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark`
  - osservare il payload `REVIEW_ENGINE_BENCHMARK`
- Risultato attuale:
  - `VerifiedFindingsSessionSyncService.sync` serializza findings + trace log con `JSONEncoder`
  - Rust ordina, deduplica e ricostruisce projection
  - Swift ricostruisce poi il canonical snapshot completo e, in altri path, puo' ricalcolare projection/security gate
- Risultato atteso:
  - sync incrementale o almeno payload piu' stretto, con minore churn di encoding/decoding per ogni mutation.
- Causa probabile:
  - bridge FFI ancora coarse-grained
  - ogni invalidazione della cache richiede round-trip completo del set findings
  - `ReviewCoreBridge.call` alloca encoder a ogni chiamata e trasporta payload completo
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/Sync/VerifiedFindingsSessionSyncService.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/ReviewCoreBridge.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift`
  - `Native/RustCore/src/review_sync.rs`
  - `Native/RustCore/src/review_projection.rs`
- Non-scope:
  - UI rendering panel
  - persistence Postgres
- Moduli confinanti da verificare:
  - `VerifiedFindingsProjectionBuilder`
  - `VerifiedFindingsSecurityGateService`
  - compatibilita' schema JSON Swift/Rust
- Test da aggiungere o aggiornare:
  - benchmark regressione su `verified_sync_p95_ms`
  - test che assicuri nessuna perdita di duplicate detection su sync incrementale
- Strategia di fix minimo:
  - introdurre fast-path incrementale per mutation semplici
  - ridurre il payload al delta o a una forma canonica piu' compatta
  - riusare encoder/decoder o buffer condivisi nelle call piu' frequenti
- Verifica post-fix:
  - benchmark review-core con target primario su `verified_sync_p95_ms`
- Commit previsto:
  - `fix(review-core): reduce full snapshot sync overhead`

### P2 - Prima semantic search puo' bloccare sul full reindex inline

- Categoria: B - Importante ma non bloccante
- Bug: la prima `semantic_search` puo' eseguire un `indexWorkspace` completo inline se l'indice e' idle/error o se i path richiesti non coincidono con quelli gia' indicizzati.
- Sintomo: la ricerca semantica a freddo eredita la latenza del full indexing invece di degradare gradualmente o partire in background.
- Impatto: UX peggiore sul primo comando search dopo apertura workspace o cambio root.
- Gravita': media
- Steps to reproduce:
  - aprire workspace senza indice pronto
  - invocare `semantic_search`
  - osservare che `ensureSemanticIndexReadyIfNeeded` richiama `index.indexWorkspace(...)`
- Risultato attuale:
  - `UnifiedToolRuntime.executeSemanticSearch` attende la preparazione completa dell'indice
- Risultato atteso:
  - prima risposta piu' rapida, con fallback controllato o warmup in background
- Causa probabile:
  - strategia di readiness sincrona sul path di ricerca
- Scope consentito:
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Index/Search/Semantic/UnifiedToolRuntime+IndexSemantic.swift`
  - eventuali fallback search sources gia' presenti
- Non-scope:
  - ranking dei risultati
  - algoritmi FFI Rust
- Moduli confinanti da verificare:
  - grep fallback
  - symbol index fallback
  - status reporting dell'indice
- Test da aggiungere o aggiornare:
  - benchmark cold-start semantic search
  - test che assicuri fallback senza blocchi lunghi
- Strategia di fix minimo:
  - warmup asincrono anticipato
  - fallback a grep/symbol index quando l'indice non e' ancora pronto
- Verifica post-fix:
  - tempo della prima `semantic_search`
- Commit previsto:
  - `fix(search): avoid blocking semantic search on cold full reindex`

### P2 - WorkspaceScanner rilancia processi git in piu' punti del loop review

- Categoria: B - Importante ma non bloccante
- Bug: il review pipeline richiama scansioni git (`git status`, `git diff`, `git ls-files`) in piu' punti senza memoizzazione per round/sessione.
- Sintomo: overhead da process spawn e I/O sul git index, soprattutto in repo grandi o con working tree sporco.
- Impatto: peggiora la latenza del loop review/re-review e dei resolver scope.
- Gravita': media
- Steps to reproduce:
  - eseguire round di review multipli con repo grande o molti file modificati
  - osservare chiamate ripetute a `WorkspaceScanner.listUncommittedSourceFiles(...)`
- Risultato attuale:
  - `WorkspaceScanner` esegue processi shell sincroni per ogni richiesta
  - diversi call site nel review pipeline chiedono la stessa informazione nello stesso flusso
- Risultato atteso:
  - una snapshot git per round o una cache breve con invalidazione esplicita
- Causa probabile:
  - assenza di memoizzazione nel boundary pipeline
- Scope consentito:
  - `Engine/CoderEngine/Sources/Workspace/WorkspaceScanner.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Rounds.swift`
  - call site review-core che consumano scope file
- Non-scope:
  - logica git UI lato app
- Moduli confinanti da verificare:
  - scope resolution
  - bug hunter scope
  - runtime adapter review-core
- Test da aggiungere o aggiornare:
  - unit test su cache TTL/snapshot per round
  - smoke test con repo sporco e multi-round review
- Strategia di fix minimo:
  - introdurre cache per round/sessione
  - evitare process spawn ripetuti a parita' di input
- Verifica post-fix:
  - riduzione chiamate git per round
  - misure sul loop review end-to-end
- Commit previsto:
  - `fix(workspace): cache git scope scans during review rounds`

### P2 - Build/test pipeline rallentata da shell script Xcode sempre out-of-date

- Categoria: D - Miglioramento travestito da bug, ma con impatto pratico alto sul ciclo di sviluppo
- Bug: le shell build phase Rust e `xattr` sono marcate `alwaysOutOfDate = 1`, quindi vengono rieseguite ad ogni build/test.
- Sintomo: ogni `xcodebuild test` rilancia step Rust e strip xattr, anche senza cambiamenti.
- Impatto: rallentamento costante di build locali, test mirati e benchmark.
- Gravita': media
- Steps to reproduce:
  - eseguire qualunque `xcodebuild test`
  - osservare i warning `Run script build phase ... will be run during every build`
- Risultato attuale:
  - quattro shell phase vengono sempre eseguite
- Risultato atteso:
  - esecuzione solo se cambiano input/output rilevanti
- Causa probabile:
  - `alwaysOutOfDate = 1` nel `project.pbxproj`
- Scope consentito:
  - `Solo Code.xcodeproj/project.pbxproj`
  - script build Rust correlati
- Non-scope:
  - logica runtime dell'app
- Moduli confinanti da verificare:
  - packaging del bundle
  - path degli artifact Rust
- Test da aggiungere o aggiornare:
  - nessun test funzionale; serve validazione build incrementale
- Strategia di fix minimo:
  - dichiarare input/output reali delle phase
  - rimuovere `alwaysOutOfDate` dove non indispensabile
- Verifica post-fix:
  - confronto tempi di build incrementale
- Commit previsto:
  - `fix(build): stop rerunning rust and xattr phases on every build`

## Non Hotspot Primario Confermato

- `ReviewPanelFindingsHistoryTests/testReviewPanelStoreSmokeBenchmark`
  - `snapshot_ingest_p95_ms = 0.116`
  - `history_load_p95_ms = 0.555`
  - `main_thread_block_time_ms = 1.427`
- Conclusione: la UI del review panel, allo stato attuale, non e' il primo bersaglio.

## Priorita' Operativa Consigliata

1. Full indexing: eliminare il multi-pass sui file.
2. Review-core sync: ridurre round-trip e payload completi Swift/Rust.
3. Semantic search cold-start: evitare reindex inline bloccante.
4. Cache delle query git nel review loop.
5. Solo dopo: ottimizzazione build phases Xcode.
