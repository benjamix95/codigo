# 2026-03-27 — Indexing incrementale e review hot path

## Bug Fix Record
- Categoria: B
- Bug: `CodebaseIndex.incrementalUpdate()` ricostruiva sempre l'albero completo del workspace anche per semplici edit di contenuto.
- Sintomo:
  - rebuild ricorsivo di `fileTrees` / `allFileNodes`
  - allocazioni e traversal completi anche senza add/remove file
- Impatto: overhead CPU e allocazioni evitabili nel path incrementale.
- Gravita': alta.
- Steps to reproduce:
  1. indicizzare un workspace gia' noto;
  2. modificare il contenuto di un solo file;
  3. osservare che `incrementalUpdate()` passa ancora da rebuild globale.
- Risultato attuale: aggiornamento incrementale con lavoro strutturale troppo ampio.
- Risultato atteso: scan leggero dei soli source node e rebuild completo solo quando serve.
- Causa probabile: l'update incrementale riusava lo stesso path del rebuild del tree.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/**`
- Non-scope:
  - ranking search
  - semantic/vector logic
- Moduli confinanti da verificare:
  - `CodebaseIndexIncrementalTests`
  - benchmark smoke indexing
- Test da aggiungere o aggiornare:
  - regressione su reindex del solo file modificato
- Strategia di fix minimo:
  - inventario incrementale leggero per i source file
  - rebuild tree completo solo su cambi strutturali
- Verifica post-fix:
  - `CoderEngineTests/CodebaseIndexIncrementalTests`
  - `scripts/benchmark_indexing_pre_post.sh --phase post --tag perf-fixes-20260327 --runs 4 --warmup 1 --files 180`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`

## Bug Fix Record
- Categoria: B
- Bug: il pipeline incrementale riparsava tutti i file tramite `SymbolExtractor.indexFileWithContent(...)`, anche invariati.
- Sintomo:
  - read+decode+regex su ogni file sorgente ad ogni `incrementalUpdate()`
  - nessuna prova automatica che i file invariati venissero saltati
- Impatto: costo superfluo sul path piu' frequente dell'indice.
- Gravita': alta.
- Steps to reproduce:
  1. indicizzare due file;
  2. modificare solo il primo;
  3. osservare che anche il secondo entra nel path di parse completo.
- Risultato attuale: reparse indiscriminato.
- Risultato atteso: hash leggero per gli invariati e parse completo solo sui file realmente cambiati.
- Causa probabile: `analyzeIncrementalBatch(...)` usava sempre `indexFileWithContent(...)` come detector di cambiamento.
- Scope consentito:
  - `SymbolExtractor`
  - pipeline incrementale index
- Non-scope:
  - estrazione simboli multi-language
- Moduli confinanti da verificare:
  - test hash invariance
  - test delete/remove semantic chunk
- Test da aggiungere o aggiornare:
  - regressione `testIncrementalUpdateReindexesOnlyChangedFiles`
- Strategia di fix minimo:
  - fast-path con hash raw del contenuto per i file invariati a metadata costante
  - hook di test per verificare i parse effettivi
- Verifica post-fix:
  - `CoderEngineTests/CodebaseIndexIncrementalTests`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`

## Bug Fix Record
- Categoria: B
- Bug: `TaskActivityStore.scheduleCodeReviewSnapshotIngest(...)` lasciava la derivazione review nel path UI principale.
- Sintomo:
  - coalescing eseguito sul main actor
  - ingest di snapshot review con lavoro non banale prima dell'applicazione UI
- Impatto: rischio di blocco breve ma visibile durante burst di snapshot.
- Gravita': alta.
- Steps to reproduce:
  1. ricevere piu' snapshot review ravvicinati;
  2. osservare che la derivazione avviene ancora nel path di ingest UI.
- Risultato attuale: derivazione e applicazione troppo vicine al main actor.
- Risultato atteso: derivazione precomputata fuori main e applicazione finale sola sul main actor.
- Causa probabile: assenza di una coda dedicata per la derivazione coalescita.
- Scope consentito:
  - `TaskActivityStore`
  - `TaskActivityStore+CodeReview`
- Non-scope:
  - semantica della snapshot review
- Moduli confinanti da verificare:
  - `TaskActivityStoreScopedActivitiesTests`
  - `ReviewPanelFindingsHistoryTests`
- Test da aggiungere o aggiornare:
  - smoke sul deferred ingest
- Strategia di fix minimo:
  - coda dedicata per la derivazione
  - reuse del `pipelineJobState` gia' derivato
- Verifica post-fix:
  - `SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingsSessionSyncService.sync(...)` ricostruiva envelope completi ripetuti e faceva lookup patch `O(n*m)`.
- Sintomo:
  - sync ripetuti sulla stessa mutation sequence
  - `snapshot.patches.first(where:)` per ogni finding
- Impatto: CPU e allocazioni superflue nel path review.
- Gravita': alta.
- Steps to reproduce:
  1. rieseguire la risoluzione verified findings sullo stesso snapshot;
  2. osservare envelope ricreati integralmente.
- Risultato attuale: niente cache locale e mapping patch non indicizzato.
- Risultato atteso: envelope cached per mutation sequence e lookup patch `O(1)`.
- Causa probabile: assenza di cache e preindicizzazione patch per finding.
- Scope consentito:
  - `VerifiedFindingsSessionSyncService`
- Non-scope:
  - modello dati verified findings
- Moduli confinanti da verificare:
  - `ValidationPerformanceTests`
  - `TaskActivityStoreScopedActivitiesTests`
- Test da aggiungere o aggiornare:
  - copertura indiretta su cache envelope fresca per mutation
- Strategia di fix minimo:
  - cache bounded per envelope
  - dizionario `patchesByFindingId`
- Verifica post-fix:
  - `SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests`
  - `CoderEngineTests/ValidationPerformanceTests`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`

## Bug Fix Record
- Categoria: B
- Bug: projection verified findings e security gate passavano spesso da FFI Rust anche quando il costo locale Swift era inferiore.
- Sintomo:
  - `projection_build_p95_ms` e `security_gate_p95_ms` fortemente aumentati con il bridge Rust
  - doppio lavoro tra bridge e reducer locale
- Impatto: regressione concreta sul throughput review.
- Gravita': alta.
- Steps to reproduce:
  1. eseguire `ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark`;
  2. confrontare `projection_build_p95_ms` e `security_gate_p95_ms` sul path bridged.
- Risultato attuale: uso eager del bridge anche su dataset UI-size.
- Risultato atteso: builder locale cached di default, Rust solo on-demand esplicito.
- Causa probabile: fallback Swift dietro al bridge invece che davanti.
- Scope consentito:
  - `VerifiedFindingsProjectionBuilder`
  - `SecurityWorkflowService`
- Non-scope:
  - contract FFI review core
- Moduli confinanti da verificare:
  - `ValidationPerformanceTests`
  - query/gate review MCP harness
- Test da aggiungere o aggiornare:
  - benchmark smoke review core
- Strategia di fix minimo:
  - projection local builder cached
  - security gate local cached
  - opt-in env per riabilitare il path Rust hot
- Verifica post-fix:
  - `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag perf-fixes-20260327`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`

## Bug Fix Record
- Categoria: B
- Bug: il panel history scalava male perche' shape/merge passavano ancora da reducer Rust o rieseguivano fallback completi senza cache.
- Sintomo:
  - derivazione fallback su tutti gli snapshot
  - sorting e merge ripetuti della history
- Impatto: history refresh costoso su dataset reali.
- Gravita': media-alta.
- Steps to reproduce:
  1. aprire il tab history con piu' snapshot;
  2. eseguire refresh multipli;
  3. osservare shape e merge ripetuti.
- Risultato attuale: nessuna cache locale del fallback e dipendenza eccessiva dal bridge.
- Risultato atteso: reducer locale per merge/shape e cache per chiave di refresh.
- Causa probabile: il fallback history non era memoizzato e il merge locale non esisteva.
- Scope consentito:
  - `CodeReviewPanelStore+History`
  - reducer locale history
- Non-scope:
  - query DB persisted findings
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTests`
- Test da aggiungere o aggiornare:
  - merge locale
  - shape locale timeline ordering
- Strategia di fix minimo:
  - reducer Swift per merge/shape
  - cache fallback per refresh key
- Verifica post-fix:
  - `SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`

## Bug Fix Record
- Categoria: B
- Bug: lo script `scripts/benchmark_indexing_pre_post.sh` era rotto rispetto alla struttura reale del repo e non produceva artefatti JSON con `xcodebuild`.
- Sintomo:
  - `swift test` lanciato in path inesistente
  - con `xcodebuild` il JSON non veniva scritto perche' la config non arrivava al test
- Impatto: pipeline di misura inutilizzabile, con rischio di regressioni non osservate.
- Gravita': alta.
- Steps to reproduce:
  1. eseguire lo script benchmark indexing dal root;
  2. osservare il fallimento o l'assenza di `post.json`.
- Risultato attuale: benchmark non affidabile.
- Risultato atteso: script funzionante end-to-end con config parametrica e JSON esportato.
- Causa probabile: drift tra layout repo e harness del benchmark.
- Scope consentito:
  - `scripts/benchmark_indexing_pre_post.sh`
  - `CodebaseIndexIndexingBenchmarkSmokeTests`
- Non-scope:
  - benchmark review core
- Moduli confinanti da verificare:
  - `docs/benchmarks/indexing-hardening/*`
- Test da aggiungere o aggiornare:
  - smoke benchmark xcodebuild con config file temporaneo
- Strategia di fix minimo:
  - script su `xcodebuild`
  - file config temporaneo letto dal test
  - fallback log→JSON
- Verifica post-fix:
  - `scripts/benchmark_indexing_pre_post.sh --phase post --tag perf-fixes-20260327 --runs 4 --warmup 1 --files 180`
- Commit previsto: `fix(perf): cut indexing and review hot-path overhead`
