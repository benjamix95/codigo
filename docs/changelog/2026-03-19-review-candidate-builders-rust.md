# 2026-03-19 - Review candidate builders via Rust

## Modifiche
- aggiunti nel core Rust:
  - [candidates.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_pipeline/candidates.rs)
  - [review_candidates.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_candidates.rs)
- introdotti i boundary:
  - `review_core_candidate_from_finding`
  - `review_core_candidate_from_review_task`
- [ReviewPipelineCoordinator+CandidateVerification.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift) ora usa il core Rust sia per il candidate da finding sia per il candidate da review task
- [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift) e [ReviewPipelineCoordinator+Rounds.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Rounds.swift) sono fail-closed se il builder Rust non risponde
- completato il payload `Codable` di [CodeReviewFinding.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Session/CodeReviewFinding.swift) con:
  - `verificationReport`
  - `verifiedAt`
  - `verificationMethod`
  - `falsePositiveReason`
  - `patchArtifactId`
- aggiunte regressioni in [ReviewPipelineCoordinatorTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift) per i due builder Rust

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::candidates::tests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Rounds.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Session/CodeReviewFinding.swift,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_candidates.rs,Native/RustCore/src/review_pipeline/mod.rs,Native/RustCore/src/review_pipeline/candidates.rs,Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift --format text`

## Esito
- la costruzione canonica dei review candidate non e' piu' owned da Swift
- le suite provider/pipeline restano verdi
- nessuna nuova violazione nel gate cutover Rust
