# P1 - La riduzione dei callback runtime review per test e patch preparation era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: dopo il porting di sessione, provider parsing, fix-stage planner e candidate builders, `ReviewRuntimeAdapter` continuava ancora a ridurre localmente in Swift i callback `runTests` e `prepareVerifiedPatches`.
- Sintomo:
  - `runTests(sessionId:)` costruiva ancora in Swift `events`, `testStatus` e `detail`
  - `prepareVerifiedPatches(step:sessionId:)` calcolava ancora in Swift il delta eventi e il payload `findings/patches/events`
- Impatto: il runtime review non era ancora Rust-owned sulla riduzione dei callback finali piu' sensibili del pipeline loop.
- Gravita': alta, perche' tocca stato test, terminal gating del pipeline e delta patch-ready esposti al runtime review.
- Steps to reproduce:
  1. Ispezionare `ReviewRuntimeAdapter.runTests(...)`.
  2. Ispezionare `ReviewRuntimeAdapter.prepareVerifiedPatches(...)`.
  3. Verificare che entrambi ricostruiscano ancora il callback payload nel layer Swift.
- Risultato attuale: il core Rust non e' ancora la source of truth della riduzione callback per test e patch preparation.
- Risultato atteso: Swift deve limitarsi all’host I/O; la riduzione del risultato runtime deve essere calcolata nel core Rust.
- Causa probabile: i callback erano stati lasciati in Swift per sbloccare prima il cutover state machine del pipeline.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineRustModels.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - audit execution host
  - panel runtime
  - patch workflow end-to-end
  - provider host I/O
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `ReviewPipelineRustDriver`
- Test da aggiungere o aggiornare:
  - regression Rust per `run_tests` reducer
  - regression Rust per `prepare_verified_patches` reducer
  - smoke XCTest su provider/pipeline suites confinanti
- Strategia di fix minimo:
  - introdurre boundary Rust per riduzione test result
  - introdurre boundary Rust per riduzione patch-preparation delta
  - rendere `ReviewPipelineRustCallbackResult` decodificabile per il bridge FFI
  - far fallire chiuso `ReviewRuntimeAdapter` se il reducer Rust non risponde
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_callbacks::tests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review-runtime): route callback reduction through rust`

## Effetto osservato
- `runTests` e `prepareVerifiedPatches` non riducono piu' il callback payload nel layer Swift.
- Il bridge Swift si limita a ricevere il payload canonico dal core Rust e a fallire chiuso se il reducer non e' disponibile.
