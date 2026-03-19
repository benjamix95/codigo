# 2026-03-19 - Review provider parsing e diagnostics via Rust

## Modifiche
- aggiunti nel core Rust i boundary:
  - `review_core_provider_plan_step`
  - `review_core_provider_reduce_event`
- introdotto [provider.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_pipeline/provider.rs) per servire:
  - parse prompt/scope/ref
  - validazione e normalizzazione `AGAINST`
  - task extraction (`parse_tasks_json`, `extract_review_tasks_json`, `parse_review_tasks`)
  - classificazione `issues/clean/inconclusive`
- allineata la logica Rust ai contratti Swift esistenti:
  - bare JSON array extraction
  - deduplica/trimming file
  - fallback `review-{index}` per id duplicati
  - clean-vs-issue classification senza false positive su frasi tipo `no critical issues`
- `CodeReviewMultiSwarmProvider+Scope.swift`, `...+Parsing.swift` e `...+Diagnostics.swift` ora fanno solo bridge al core Rust
- `ReviewTask` in [CodeReviewMultiSwarmProvider.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/CodeReviewMultiSwarmProvider.swift) e' ora `Codable` per il marshalling FFI
- i test provider/pipeline usano il resolver condiviso del dylib review core

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/CodeReviewMultiSwarmProvider.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/CodeReviewMultiSwarmProvider+Diagnostics.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/Parsing/CodeReviewMultiSwarmProvider+Parsing.swift,Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/Scope/CodeReviewMultiSwarmProvider+Scope.swift,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_provider.rs,Native/RustCore/src/review_pipeline/mod.rs,Native/RustCore/src/review_pipeline/provider.rs,Native/RustCore/src/review_pipeline/scope.rs,Native/RustCore/src/review_pipeline/tasks.rs,Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+Parsing.swift,Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift --format text`

## Esito
- il provider runtime resta host I/O Swift, ma parsing e diagnostica non sono piu' source of truth Swift
- `CodeReviewMultiSwarmProviderTests` e `ReviewPipelineCoordinatorTests` sono verdi sul boundary Rust aggiornato
- nessuna nuova violazione nel gate cutover Rust
