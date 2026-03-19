# 2026-03-19 - Review runtime adapter callback reduction via Rust

## Modifiche
- aggiunti nel core Rust:
  - [runtime_callbacks.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_pipeline/runtime_callbacks.rs)
  - [review_runtime_callbacks.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_runtime_callbacks.rs)
- introdotti i boundary:
  - `review_core_runtime_reduce_tests`
  - `review_core_runtime_reduce_prepare_verified_patches`
- [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift) delega ora al core Rust:
  - la riduzione di `runTests`
  - la riduzione del delta `prepareVerifiedPatches`
- [ReviewPipelineRustModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineRustModels.swift) rende `ReviewPipelineRustCallbackResult` `Codable` per il round-trip FFI

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_callbacks::tests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineRustModels.swift,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_runtime_callbacks.rs,Native/RustCore/src/review_pipeline/mod.rs,Native/RustCore/src/review_pipeline/runtime_callbacks.rs --format text`

## Esito
- i reducer runtime dei callback `runTests` e `prepareVerifiedPatches` non sono piu' source of truth Swift
- le suite provider/pipeline restano verdi
- nessuna nuova violazione nel gate cutover Rust
