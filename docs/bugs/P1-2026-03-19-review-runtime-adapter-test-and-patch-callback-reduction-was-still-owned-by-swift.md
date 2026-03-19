# P1 - La riduzione callback di test e patch preparation nel review runtime adapter era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: `ReviewRuntimeAdapter` continuava ancora a costruire localmente in Swift il payload canonico dei callback `runTests` e `prepareVerifiedPatches`.
- Sintomo:
  - `runTests(sessionId:)` derivava ancora `events`, `testStatus` e `detail`
  - `prepareVerifiedPatches(step:sessionId:)` calcolava ancora in Swift il delta tra snapshot corrente e snapshot aggiornato
- Impatto: il review runtime non era ancora Rust-owned sui callback terminali che alimentano la state machine della pipeline.
- Gravita': alta, perche' tocca stato test, gating terminale e pubblicazione patch-ready.
- Steps to reproduce:
  1. Ispezionare [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift).
  2. Verificare che i callback `runTests` e `prepareVerifiedPatches` costruiscano ancora localmente il payload `ReviewPipelineRustCallbackResult`.
  3. Notare che il core Rust non riceve ancora la responsabilita' canonica di questi due reducer.
- Risultato attuale: riduzione callback ancora Swift locale per test e patch preparation.
- Risultato atteso: Swift deve essere solo host I/O; il payload di callback deve essere derivato dal core Rust.
- Causa probabile: questi due path erano rimasti in Swift per velocizzare la prima tranche del pipeline cutover.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineRustModels.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - audit host execution
  - panel runtime
  - patch workflow end-to-end
  - provider host I/O
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `ReviewPipelineRustDriver`
- Test da aggiungere o aggiornare:
  - regression Rust per reducer `run_tests`
  - regression Rust per reducer `prepare_verified_patches`
  - smoke XCTest su suite provider/pipeline confinanti
- Strategia di fix minimo:
  - introdurre boundary Rust per `review_core_runtime_reduce_tests`
  - introdurre boundary Rust per `review_core_runtime_reduce_prepare_verified_patches`
  - rendere `ReviewPipelineRustCallbackResult` `Codable`
  - far fallire chiuso il bridge Swift se il reducer Rust non risponde
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_callbacks::tests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review-runtime): route callback reduction through rust`

## Effetto osservato
- `runTests` e `prepareVerifiedPatches` non costruiscono piu' il payload canonico nel layer Swift.
- La riduzione del callback passa ora dal core Rust e il bridge Swift resta fail-closed se il reducer non e' disponibile.
