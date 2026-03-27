# 2026-03-27 — Indexing incrementale e review hot path

## Modifiche

- `CodebaseIndex.incrementalUpdate()` ora usa un inventario incrementale leggero dei source node e ricostruisce `fileTrees` solo quando rileva cambi strutturali, non per semplici edit di contenuto.
- `analyzeIncrementalBatch(...)` evita il parse completo dei file invariati: usa un controllo hash raw e lascia `SymbolExtractor.indexFileWithContent(...)` solo ai file realmente cambiati.
- aggiunta regressione `CodebaseIndexIncrementalTests.testIncrementalUpdateReindexesOnlyChangedFiles`.
- `TaskActivityStore.scheduleCodeReviewSnapshotIngest(...)` pre-deriva lo stato review su una coda dedicata `userInitiated` e applica sul main actor solo il risultato finale.
- `TaskActivityStore+CodeReview.ingestCodeReviewSnapshot(...)` riusa il `pipelineJobState` gia' derivato invece di ricostruirlo nel trace debug.
- `VerifiedFindingsSessionSyncService.sync(...)` ora cachea gli envelope per mutation sequence e indicizza le patch per finding prima del mapping.
- `ReviewCoreBridge.call(...)` passa il payload encoded come `Data` al client FFI evitando il round-trip `Data -> String -> cString`.
- `VerifiedFindingsProjectionBuilder` usa di default un local builder cached; il path Rust resta riattivabile con `SOLOCODE_REVIEW_CORE_USE_RUST_PROJECTION=1`.
- `SecurityWorkflowService.evaluate(...)` usa di default il gate locale cached; il path Rust resta riattivabile con `SOLOCODE_REVIEW_CORE_USE_RUST_SECURITY_GATE=1`.
- il panel history usa un reducer Swift locale per `merge` e `shape`, con cache del fallback per `refreshKey`, invece di dipendere dal bridge per ogni refresh.
- aggiunti test app-side per `ReviewPanelHistoricalFindingsLocalReducer`.
- ottimizzati `review_projection.rs` e `review_sync.rs` nel core Rust per ridurre allocazioni/cloni nel path `sync + projection`.
- `scripts/benchmark_indexing_pre_post.sh` e `CodebaseIndexIndexingBenchmarkSmokeTests` ora funzionano end-to-end con `xcodebuild`: config temporanea su file e fallback log→JSON.

## Benchmark osservati

- review core engine, run post-fix `perf-fixes-20260327`:
  - `projection_build_p95_ms`: `0.97`
  - `security_gate_p95_ms`: `2.00`
  - `verified_sync_p95_ms`: `11.34`
  - fonte: `docs/benchmarks/review-core/perf-fixes-20260327-post-engine.json`
- review panel app, run post-fix `perf-fixes-20260327`:
  - `snapshot_ingest_p95_ms`: `0.079`
  - `history_load_p95_ms`: `0.581`
  - `main_thread_block_time_ms`: `1.04`
  - fonte: `docs/benchmarks/review-core/perf-fixes-20260327-post-app.json`
- indexing smoke, run post-fix `perf-fixes-20260327`:
  - `full_median_ms`: `439`
  - `incremental_median_ms`: `10`
  - `incremental_p95_ms`: `11`
  - fonte: `docs/benchmarks/indexing-hardening/perf-fixes-20260327-post.json`

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodebaseIndexIncrementalTests -only-testing:CoderEngineTests/ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag perf-fixes-20260327`
- `scripts/benchmark_indexing_pre_post.sh --phase post --tag perf-fixes-20260327 --runs 4 --warmup 1 --files 180`
