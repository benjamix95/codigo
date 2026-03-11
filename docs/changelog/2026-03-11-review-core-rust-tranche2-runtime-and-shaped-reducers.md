# 2026-03-11 — Review core Rust tranche 2: runtime loader, reducers VerifiedFindings e shaping storico

## Modifiche
- esteso `Native/RustCore` con nuovi entrypoint:
  - `review_core_build_projection`
  - `review_core_replay_verified_findings`
  - `review_core_evaluate_security_gate`
  - `review_core_shape_historical_findings`
- aggiunti moduli Rust:
  - `review_projection`
  - `review_replay`
  - `review_security_gate`
  - `review_history`
- aggiornato il loader in `RustSearchFFIClient`:
  - stato diagnostico `ReviewCoreLoadedState`
  - path candidati piu' robusti
  - retry reale dopo failure
  - reset controllato per i test
- `ReviewCoreBridge` ora espone anche `loadedState()`
- migrati dietro bridge con fallback Swift:
  - `VerifiedFindingsProjectionBuilder`
  - `VerifiedFindingsReplayService`
  - `VerifiedFindingsSecurityGateService`
  - `HistoricalFindingsQueryService`
- `TaskActivityStore+VerifiedFindings` include ora nel payload diagnostica del review-core loader
- aggiunti test Swift mirati:
  - loader review-core
  - parity replay
  - parity security gate
  - shaping storico
  - benchmark engine aggiornato con metriche `projection_build`, `security_gate`, `historical_shape`
- irrobustito `scripts/benchmark_review_pipeline_pre_post.sh`:
  - phase marker file `tmp/review-core-benchmark-phase.txt`
  - sovrascrittura sempre dei JSON benchmark
  - summary esteso con tutte le metriche della tranche 2

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SearchEngineBackendTests/testReviewCoreBridgeLoadedStateReturnsVersionWhenLibraryPathIsForced -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests/testReplayServiceMatchesRustBridgeWhenLibraryIsAvailable -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests/testGateMatchesRustBridgeWhenLibraryIsAvailable -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests/testHistoricalFindingsShapeWithRustWhenLibraryIsAvailable -only-testing:CoderEngineTests/ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests -only-testing:CoderEngineTests/SearchEngineBackendTests -only-testing:CoderEngineTests/ValidationPerformanceTests`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase pre --tag review-core-tranche2`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag review-core-tranche2`

## Esito benchmark
- il `post` ora dimostra `rust_review_core_loaded=true`
- il `pre` resta fallback Swift e fornisce baseline comparabile
- il delta attuale mostra:
  - miglioramento su `verify_candidate`, `verified_sync`, `projection_build`, `security_gate`, `audit_suite_duration`
  - regressione su `historical_shape` e `history_load` da tenere sotto osservazione nella tranche successiva
