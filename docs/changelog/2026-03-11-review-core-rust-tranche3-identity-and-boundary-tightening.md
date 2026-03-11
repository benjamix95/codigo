# 2026-03-11 — Review core Rust tranche 3: identity dedup unificata e chiusura del perimetro utile

## Modifiche
- aggiunto l'entrypoint Rust `review_core_find_duplicate` in `Native/RustCore/src/ffi.rs`
- estesa la logica identity in `Native/RustCore/src/review_identity.rs` con:
  - ricerca del duplicato tramite gli stessi bucket della sync
  - tie-break coerente tra exact-match e best-match approssimato
- aggiornato `FindingIdentityService` per delegare al `ReviewCoreBridge` il path `findDuplicate(candidate:existing:)`
- reso `VerifiedFindingIdentityMatch` serializzabile (`Codable`) per evitare adapter ridondanti nel boundary FFI
- aggiunto test di parity Swift/Rust in `FindingIdentityServiceTests`
- rigenerati i benchmark `pre/post` della tranche 3:
  - `review-core-tranche3-pre-engine.json`
  - `review-core-tranche3-post-engine.json`
  - `review-core-tranche3-pre-app.json`
  - `review-core-tranche3-post-app.json`
  - `review-core-tranche3-summary.md`

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SearchEngineBackendTests/testReviewCoreBridgeLoadedStateReturnsVersionWhenLibraryPathIsForced -only-testing:CoderEngineTests/VerifiedFindings/FindingIdentityServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase pre --tag review-core-tranche3`
- `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag review-core-tranche3`

## Esito benchmark
- il `post` conferma ancora `rust_review_core_loaded=true`
- il bridge Rust migliora `verify_candidate_p95_ms` e mantiene il beneficio sul path audit
- `projection_build`, `security_gate`, `historical_shape` e parte della sync restano piu' lenti del fallback Swift per overhead FFI/JSON
- per questo la migrazione si ferma qui sui path pure-compute residui utili; non e' opportuno spingere in Rust l'orchestrazione Swift o i reducer app-side non dimostrati come hot path
