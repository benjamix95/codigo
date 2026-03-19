# 2026-03-19 - Review runtime task candidate reduction via Rust

## Modifiche
- aggiunti nel core Rust:
  - [runtime_task_candidates.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_pipeline/runtime_task_candidates.rs)
  - [review_runtime_task_candidates.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_runtime_task_candidates.rs)
- introdotto il boundary:
  - `review_core_runtime_reduce_prepare_task_candidates`
- [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift) delega ora al core Rust anche la riduzione di `prepareTaskCandidates`

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_task_candidates::tests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_runtime_task_candidates.rs,Native/RustCore/src/review_pipeline/mod.rs,Native/RustCore/src/review_pipeline/runtime_task_candidates.rs --format text`

## Esito
- anche il reducer `prepare_task_candidates` non e' piu' source of truth Swift
- provider/pipeline smoke suite resta verde
- nessuna nuova violazione nel gate cutover Rust
