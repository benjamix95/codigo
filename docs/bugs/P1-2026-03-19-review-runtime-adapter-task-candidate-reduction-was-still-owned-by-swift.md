# P1 - La riduzione di prepareTaskCandidates nel review runtime adapter era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: dopo il porting di candidate builders e fix-stage planner, `ReviewRuntimeAdapter.prepareTaskCandidates(...)` continuava ancora a usare `tempState` Swift per costruire `candidates/promotedFindings/events`.
- Sintomo:
  - builder dei candidate invocati da Swift
  - verifica/promozione guidata dal layer Swift
  - callback `prepare_task_candidates` assemblato localmente nel runtime adapter
- Impatto: il runtime review manteneva ancora una source of truth Swift sul path di preparazione candidati del pipeline loop.
- Gravita': alta, perche' tocca verify/promote dei finding prima del fix stage.
- Steps to reproduce:
  1. Ispezionare [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift).
  2. Verificare che `prepareTaskCandidates(...)` costruisca ancora il callback tramite `tempState`.
  3. Notare che il core Rust non e' ancora il reducer canonico di questo path.
- Risultato attuale: `prepare_task_candidates` non e' ancora Rust-owned end-to-end.
- Risultato atteso: Swift deve limitarsi a inviare task/contesto al core Rust e ricevere il payload canonico del callback.
- Causa probabile: la tranche precedente ha portato in Rust builder e verifier, ma non ancora il reducer finale del callback.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - audit host execution
  - panel runtime
  - patch workflow end-to-end
  - worker host I/O
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `ReviewPipelineCoordinator+CandidateVerification`
- Test da aggiungere o aggiornare:
  - regression Rust sul reducer `prepare_task_candidates`
  - smoke XCTest provider/pipeline confinanti
- Strategia di fix minimo:
  - introdurre boundary Rust per `review_core_runtime_reduce_prepare_task_candidates`
  - spostare in Rust builder/verifier/promote reduce del callback
  - far fallire chiuso `ReviewRuntimeAdapter` se il reducer Rust non risponde
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_task_candidates::tests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review-runtime): route task candidate reduction through rust`

## Effetto osservato
- `prepareTaskCandidates` non costruisce piu' il payload canonico nel layer Swift.
- Il runtime adapter riceve dal core Rust `candidates`, `promotedFindings` ed `events` gia' ridotti.
