# 2026-03-19 - Review fix-stage planner e worker event bridge via Rust

## Modifiche
- aggiunti nel core Rust:
  - [fix_stage.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_pipeline/fix_stage.rs)
  - [review_fix_stage.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_fix_stage.rs)
- introdotti i boundary:
  - `review_core_fix_stage_plan`
  - `review_core_fix_stage_bridge_event`
- [ReviewPipelineCoordinator+FixStage.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+FixStage.swift) ora delega a Rust:
  - batching non-overlap dei `ReviewTask`
  - mapping `resolvedScope/againstRef -> ReviewScope`
  - shape dei payload worker bridged da `PipelineUIEvent`
- Swift mantiene solo:
  - lock acquisition/release
  - costruzione `PipelineJob`/`TaskNode`
  - esecuzione del job tramite `PipelineFacade`
- aggiunte regressioni in [ReviewPipelineCoordinatorTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift) per:
  - piano batch fix-stage Rust
  - payload bridged di `task_failed`

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::fix_stage::tests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+FixStage.swift,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_fix_stage.rs,Native/RustCore/src/review_pipeline/mod.rs,Native/RustCore/src/review_pipeline/fix_stage.rs,Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift --format text`

## Esito
- il fix-stage review non decide piu' in Swift come raggruppare i task o come serializzare gli eventi worker
- le suite confinanti provider/pipeline restano verdi
- nessuna nuova violazione nel gate cutover Rust
