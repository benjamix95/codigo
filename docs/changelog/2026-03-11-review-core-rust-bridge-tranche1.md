# 2026-03-11 — Review core Rust bridge, fallback hardening e benchmark tranche 1

## Modifiche
- esteso `Native/RustCore` con entrypoint FFI review-core:
  - `review_core_verify_candidates`
  - `review_core_sync_verified_findings`
  - `review_core_run_audit`
  - `review_core_reduce_panel_state`
  - `review_core_version`
- aggiunti moduli Rust isolati per:
  - candidate verification
  - identity/dedup
  - projection sync verified findings
  - reducer merge storico
  - audit scanner locale
- riusato il loader nativo Swift esistente introducendo `ReviewCoreBridge` come boundary unico per i servizi review
- migrati dietro bridge con fallback Swift:
  - `ReviewCandidateVerificationService`
  - `VerifiedFindingsSessionSyncService`
  - `CodeReviewAuditService`
  - merge storico del review panel
- mantenuto il comportamento UI compatibile e confinato:
  - nessun refactor delle view SwiftUI
  - nessuna migrazione di Git/patch workflow
- corretto il path inline review della pipeline per evitare race nei test/payload:
  - `PipelineIntegrationService+VerifiedFindingsReview` ora ingestisce subito la snapshot review sintetica
- aggiunta pipeline benchmark review-core:
  - `scripts/benchmark_review_pipeline_pre_post.sh`
  - benchmark engine in `ValidationPerformanceTests`
  - benchmark app/store in `ReviewPanelFindingsHistoryTests`
- salvati report benchmark in `docs/benchmarks/review-core/`

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/FindingIdentityServiceTests -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testReviewPanelStoreSmokeBenchmark`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase pre --tag review-core-tranche1`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag review-core-tranche1`

## Note operative
- `cargo` e `rustc` sono stati installati localmente via `rustup`.
- il build phase Xcode del crate Rust e' stato reso non bloccante: se il sandbox impedisce l'accesso al crate, il target torna in fallback Swift invece di rompere build/test.
- il benchmark `post` al momento non dimostra ancora `rust_review_core_loaded=true`; il bug e' tracciato separatamente.
