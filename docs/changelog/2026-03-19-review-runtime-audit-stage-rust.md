# 2026-03-19 - Review runtime audit stage reduction via Rust

## Modifiche
- aggiunti nel core Rust:
  - [runtime_audit_stage.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_pipeline/runtime_audit_stage.rs)
  - [review_runtime_audit_stage.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_runtime_audit_stage.rs)
- introdotto il boundary:
  - `review_core_runtime_reduce_audit_stage`
- [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift) delega ora al core Rust la riduzione di `runAuditStage`
- [ReviewPipelineCoordinator+Runtime.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Runtime.swift) espone ora un helper separato per raccogliere i `ReviewAuditToolResult` host-side senza ridurre localmente il callback
- aggiunta regression XCTest in [ReviewPipelineCoordinatorTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift) per verificare `audit snapshot`, `candidates` e `promotedFindings` dal callback runtime audit

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_audit_stage::tests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Runtime.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_runtime_audit_stage.rs,Native/RustCore/src/review_pipeline/mod.rs,Native/RustCore/src/review_pipeline/runtime_audit_stage.rs,Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift --format text`

## Esito
- anche il callback `run_audit_stage` non e' piu' source of truth Swift
- provider/pipeline smoke suite resta verde
- nessuna nuova violazione nel gate cutover Rust
